"""Generate the voice-over library through the KIE API using ElevenLabs models.

Covers all three languages the app ships -- English, Filipino/Tagalog and
Bisaya/Cebuano -- across three age tiers (adult / young / child), so the app
can offer the user a choice of narrator.

Two backends: `gemini` (default, google/gemini-3-1-flash-tts) and `elevenlabs`.
Unlike the local Chatterbox path in generate.py, neither clones a reference
recording, and both speak Filipino and Cebuano properly -- the manifests
already hold translated text.

Output keeps the library contract (24 kHz mono 16-bit PCM WAV, ~30 ms lead /
~80 ms tail) and lands under out/kie/<backend>/<lang>/<tier>_<voice>/ -- the
live asset folder is never touched.

  # what would run, no API calls, no key needed
  python generate_kie.py --lang all --dry-run

  # audition every voice on a few lines first
  python generate_kie.py --lang en --preview

  # one language, one tier
  python generate_kie.py --lang ceb --tier child

  # the whole thing
  python generate_kie.py --lang all --yes
"""
import argparse
import csv
import json
import os
import sys
import threading
from concurrent.futures import ThreadPoolExecutor

import numpy as np

import voice_lib as VL
import voices as VOX
from kie_client import KieClient, KieError, RateLimiter, decode_audio

# Lines used by --preview: short, long, calm and celebratory, so a single
# listen tells you whether a voice suits the library.
PREVIEW_PATHS = (
    'colors/Blue',
    'core_praise',
    'instruction/LetsBegin',
    'attention_and_regulation/TakeABreath',
    'turn_taking/YourTurn',
)
PREVIEW_PER_GROUP = 1

# Above this many clips, require --yes. Every clip is a paid API call.
CONFIRM_THRESHOLD = 200

_print_lock = threading.Lock()


def log(msg):
    with _print_lock:
        print(msg, flush=True)


def load_manifest(cfg, only=None, limit=None):
    """Rows as (relpath.wav, text, emotion, short) for one language."""
    path = cfg['manifest']
    if not os.path.exists(path):
        raise SystemExit('Manifest not found: %s' % path)
    rows = []
    with open(path, encoding='utf-8') as f:
        for row in csv.DictReader(f):
            rel = (row.get('path') or '').strip()
            text = (row.get('text') or '').strip()
            if not rel or not text:
                continue
            if not rel.lower().endswith('.wav'):
                rel += '.wav'
            if only and not any(rel.startswith(p) for p in only):
                continue
            # The English manifest marks short lines explicitly; the
            # translated ones do not, so fall back to counting words.
            carrier = (row.get('carrier') or '').strip().lower()
            short = carrier == 'yes' if carrier else len(text.split()) <= 2
            rows.append((rel, text, (row.get('emotion') or '').strip(), short))
    if limit:
        rows = rows[:limit]
    return rows


def preview_rows(rows):
    """A handful of representative lines, one per PREVIEW_PATHS prefix."""
    picked, seen = [], {}
    for rel, text, emotion, short in rows:
        for pref in PREVIEW_PATHS:
            if rel.startswith(pref) and seen.get(pref, 0) < PREVIEW_PER_GROUP:
                seen[pref] = seen.get(pref, 0) + 1
                picked.append((rel, text, emotion, short))
                break
    return picked or rows[:len(PREVIEW_PATHS)]


def postprocess(raw, pitch_semitones=0.0):
    """Decode API audio and conform it to the library's WAV contract."""
    x, sr = decode_audio(raw)
    if pitch_semitones:
        import librosa
        x = librosa.effects.pitch_shift(y=x, sr=sr, n_steps=pitch_semitones)
    x = VL.resample(np.asarray(x, dtype=np.float32), sr, VL.TARGET_SR)
    y = VL.pad_and_fade(x, VL.TARGET_SR)
    if y is None:
        return None
    return VL.normalize(y)


def write_reference(out_root, backend, langs):
    """Record which voice produced each folder, next to the audio itself.

    Folder names carry the tier and a short key ("adult_sulafat"); this maps
    them back to the actual voice id, its character, and the age profile that
    was sent, so the output is still readable months later without diffing
    voices.py against a git history.
    """
    sel = VOX.resolve(backend)
    root = os.path.join(out_root, backend)
    os.makedirs(root, exist_ok=True)

    data = {'backend': backend,
            'model': VOX.model_for(backend, langs[0]),
            'languages': {l: VOX.LANGUAGES[l]['label'] for l in langs},
            'voices': []}
    for tier, key, voice, label, pitch in sel:
        entry = {'folder': '%s_%s' % (tier, key), 'tier': tier, 'key': key,
                 'voice_id': voice, 'character': label}
        if backend == 'gemini':
            entry['audio_profile'] = VOX.GEMINI_TIER_PROFILE[tier]
        elif pitch:
            entry['pitch_semitones'] = pitch
        data['voices'].append(entry)

    with open(os.path.join(root, 'voices.json'), 'w', encoding='utf-8') as f:
        json.dump(data, f, indent=2, ensure_ascii=False)

    lines = ['# Voice reference', '',
             'Which voice produced each folder. Generated by `generate_kie.py`.', '',
             '- backend: `%s`' % backend,
             '- model: `%s`' % data['model'],
             '- languages: %s' % ', '.join('`%s` (%s)' % (l, VOX.LANGUAGES[l]['label'])
                                           for l in langs),
             '',
             'Layout: `<lang>/<folder>/<category>/<line>.wav`', '',
             '| folder | tier | voice id | character |',
             '|---|---|---|---|']
    for v in data['voices']:
        lines.append('| `%s` | %s | **%s** | %s |'
                     % (v['folder'], v['tier'], v['voice_id'], v['character']))
    if backend == 'gemini':
        lines += ['', '## Age profile sent per tier', '',
                  'On Gemini the age comes from `audio_profile`; `voice_id` only',
                  'selects the timbre.', '',
                  '| tier | audio_profile |', '|---|---|']
        for tier in VOX.TIERS:
            lines.append('| %s | %s |' % (tier, VOX.GEMINI_TIER_PROFILE[tier]))
    lines.append('')
    with open(os.path.join(root, 'VOICES.md'), 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines))
    return root


def build_jobs(args, selection):
    """Every (lang, tier, key, voice, pitch, rel, text, emotion, short, dst)."""
    jobs, skipped = [], 0
    for lang in args.langs:
        cfg = VOX.LANGUAGES[lang]
        rows = load_manifest(cfg, only=args.only, limit=args.limit)
        if args.preview:
            rows = preview_rows(rows)
        if not rows:
            log('No lines matched for %s.' % lang)
            continue
        for tier, key, voice, _label, pitch in selection:
            if args.no_pitch:
                pitch = 0.0
            voice_dir = os.path.join(args.out, args.backend, cfg['out'],
                                     '%s_%s' % (tier, key))
            for rel, text, emotion, short in rows:
                dst = os.path.join(voice_dir, rel)
                if os.path.exists(dst) and not args.force:
                    skipped += 1
                    continue
                jobs.append(dict(lang=lang, tier=tier, key=key, voice=voice,
                                 pitch=pitch, rel=rel, text=text, emotion=emotion,
                                 short=short, dst=dst))
    return jobs, skipped


def run_job(client, job, backend, timeout, task_retries=2):
    """Synthesize one line. Returns None on success, an error string otherwise."""
    lang = job['lang']
    model = VOX.model_for(backend, lang)

    prev_t = next_t = None
    if backend == 'elevenlabs' and job['short'] and model == VOX.MODEL_V2:
        prev_t, next_t = VOX.ELEVEN_LANG[lang]['carrier']

    inputs = VOX.build_input(backend, lang, job['voice'], job['text'], job['tier'],
                             previous_text=prev_t, next_text=next_t,
                             emotion=job['emotion'], key=job['key'])
    raw, _url = client.synthesize(model, inputs, timeout=timeout,
                                  task_retries=task_retries)
    y = postprocess(raw, job['pitch'])
    if y is None:
        return 'decoded to silence'
    os.makedirs(os.path.dirname(job['dst']), exist_ok=True)
    VL.save_16bit(job['dst'], y, VL.TARGET_SR)
    return None


def main():
    ap = argparse.ArgumentParser(
        description='Generate voice-over clips via the KIE API (ElevenLabs models).')
    ap.add_argument('--backend', default='gemini', choices=VOX.BACKENDS,
                    help='gemini (default) or elevenlabs')
    ap.add_argument('--lang', default='all',
                    help='en, tl, ceb, or all (comma-separated). tl = Filipino, ceb = Bisaya')
    ap.add_argument('--tier', help='adult, young, child (comma-separated). Default: all')
    ap.add_argument('--voices', help='specific voice keys, comma-separated (see --list-voices)')
    ap.add_argument('--only', help='comma-separated path prefixes to generate')
    ap.add_argument('--out', default=os.path.join('out', 'kie'))
    ap.add_argument('--api-key', default=None, help='defaults to $KIE_API_KEY')
    ap.add_argument('--workers', type=int, default=4)
    ap.add_argument('--timeout', type=float, default=300.0, help='per-clip seconds')
    ap.add_argument('--task-retries', type=int, default=2,
                    help='retries when a task is accepted but fails upstream')
    ap.add_argument('--limit', type=int, help='first N manifest lines only')
    ap.add_argument('--preview', action='store_true',
                    help='a few representative lines per voice, for auditioning')
    ap.add_argument('--force', action='store_true', help='regenerate existing files')
    ap.add_argument('--no-pitch', action='store_true',
                    help='skip the elevenlabs child-tier pitch shift (gemini never uses it)')
    ap.add_argument('--dry-run', action='store_true', help='plan only, no API calls')
    ap.add_argument('--list-voices', action='store_true')
    ap.add_argument('--write-reference', action='store_true',
                    help='write VOICES.md / voices.json into the output dir and exit')
    ap.add_argument('--yes', action='store_true',
                    help='proceed without confirmation for large runs')
    args = ap.parse_args()

    if args.list_voices:
        print('backend: %s' % args.backend)
        for tier, key, voice, label, pitch in VOX.resolve(args.backend):
            print('  %-6s %-14s %-24s %s%s' % (
                tier, key, voice, label,
                '  (+%.1f st)' % pitch if pitch else ''))
        if args.backend == 'gemini':
            print('\nAge comes from the audio_profile sent per tier:')
            for tier in VOX.TIERS:
                print('  %-6s %s' % (tier, VOX.GEMINI_TIER_PROFILE[tier]))
        return 0

    args.langs = (list(VOX.LANGUAGES) if args.lang == 'all'
                  else [s.strip() for s in args.lang.split(',') if s.strip()])
    for lang in args.langs:
        if lang not in VOX.LANGUAGES:
            sys.exit('Unknown language %r (have: %s)'
                     % (lang, ', '.join(VOX.LANGUAGES)))
    args.only = [s.strip() for s in args.only.split(',')] if args.only else None

    if args.write_reference:
        print('Wrote VOICES.md and voices.json to %s'
              % os.path.abspath(write_reference(args.out, args.backend, args.langs)))
        return 0

    tiers = [s.strip() for s in args.tier.split(',')] if args.tier else None
    keys = [s.strip() for s in args.voices.split(',')] if args.voices else None
    try:
        selection = VOX.resolve(args.backend, tiers, keys)
    except KeyError as exc:
        sys.exit(exc.args[0])

    jobs, skipped = build_jobs(args, selection)

    print('Backend:   %s' % args.backend)
    print('Languages: %s' % ', '.join(
        '%s (%s, %s)' % (l, VOX.LANGUAGES[l]['label'],
                         VOX.model_for(args.backend, l).split('/')[-1])
        for l in args.langs))
    print('Voices:    %d  (%s)' % (
        len(selection), ', '.join('%s/%s' % (t, k) for t, k, _, _, _ in selection)))
    print('To render: %d clip(s)%s' % (
        len(jobs), '  (%d already present, skipped)' % skipped if skipped else ''))
    print('Output:    %s' % os.path.abspath(args.out))

    if args.dry_run:
        for job in jobs[:15]:
            print('  %-4s %-14s %-38s %s' % (
                job['lang'], '%s/%s' % (job['tier'], job['key']), job['rel'],
                job['text'][:40]))
        if len(jobs) > 15:
            print('  ... and %d more' % (len(jobs) - 15))
        return 0

    if not jobs:
        print('\nNothing to do.')
        write_reference(args.out, args.backend, args.langs)
        return 0
    if len(jobs) > CONFIRM_THRESHOLD and not args.yes:
        sys.exit('\n%d clips is a large paid run. Re-run with --yes to confirm, '
                 'or narrow it with --preview / --tier / --lang / --only.' % len(jobs))

    try:
        client = KieClient(api_key=args.api_key, limiter=RateLimiter())
    except KieError as exc:
        sys.exit(str(exc))

    print('')
    done, failures = [0], []

    def worker(job):
        label = '%s %s/%s %s' % (job['lang'], job['tier'], job['key'], job['rel'])
        try:
            err = run_job(client, job, args.backend, args.timeout, args.task_retries)
        except KieError as exc:
            err = str(exc)
        except Exception as exc:  # keep one bad line from killing the batch
            err = '%s: %s' % (type(exc).__name__, exc)
        with _print_lock:
            done[0] += 1
            n = done[0]
        if err:
            failures.append((label, err))
            log('[%3d/%d] FAIL %s -- %s' % (n, len(jobs), label, err))
        else:
            log('[%3d/%d] ok   %s' % (n, len(jobs), label))

    with ThreadPoolExecutor(max_workers=max(1, args.workers)) as pool:
        list(pool.map(worker, jobs))

    write_reference(args.out, args.backend, args.langs)
    print('\nWrote %d of %d clip(s) to %s'
          % (len(jobs) - len(failures), len(jobs), os.path.abspath(args.out)))

    if failures:
        report = os.path.join(args.out, 'failures.json')
        os.makedirs(args.out, exist_ok=True)
        with open(report, 'w', encoding='utf-8') as f:
            json.dump([{'clip': c, 'error': e} for c, e in failures], f, indent=2)
        print('%d failed; details in %s' % (len(failures), report))
        print('Re-run the same command to retry only the missing files.')
        return 1

    print('Audition the output before copying it into the asset folder.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
