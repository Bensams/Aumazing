"""Tighten speaker consistency within each voice pack.

Gemini's `voice_name` is a prior, not a locked speaker embedding: every call
re-rolls the voice inside that description, so a pack generated clip-by-clip
drifts. Measured on the first run, one "voice" spanned 157-389 Hz. Temperature
does not control this (0.2 was measurably worse than 1.0), and KIE renders only
the first entry of `dialogue_turns`, so batching a pack into one call is not
available either.

What is left is rejection sampling. For each pack:

  1. Build a voice centre from the clips already generated -- the median F0 and
     the median MFCC vector, both robust to the outliers we are hunting.
  2. Score every clip against that centre.
  3. Regenerate the worst offenders, up to --attempts times each, keeping
     whichever rendition scores best. A clip is only replaced if the new take
     actually beats the old one.

This narrows the spread, it does not eliminate it -- the underlying model still
re-rolls. Expect the tail to come in, not vanish.

  python repair_consistency.py --root out/kie/gemini --report-only
  python repair_consistency.py --root out/kie/gemini --attempts 3
"""
import argparse
import io
import os
import sys
import warnings
from concurrent.futures import ThreadPoolExecutor

import numpy as np
import soundfile as sf

import voice_lib as VL
import voices as VOX
from kie_client import KieClient, KieError

warnings.filterwarnings('ignore')

# Weight of timbre vs pitch when scoring. Pitch is the more audible giveaway
# for "that is a different person", so it carries most of the score.
W_PITCH, W_TIMBRE = 1.0, 0.5
# A clip beyond this score is treated as an outlier worth spending calls on.
# Scores are in units of median-absolute-deviation from the pack centre, so
# this is "more than three deviations out". Measured on the 18-pack run, the
# median clip scores ~1.6 and 3.0 selects the worst ~13% -- the takes that
# actually read as a different person, not the ordinary spread.
DEFAULT_TOLERANCE = 3.0


def _features(y, sr):
    """(median F0, mean MFCC) for one clip, or None if it has no voiced part."""
    import librosa
    y, _ = librosa.effects.trim(y, top_db=35)
    if len(y) < 2048:
        return None
    f0 = librosa.yin(y, fmin=70, fmax=500, sr=sr)
    f0 = f0[(f0 > 70) & (f0 < 500)]
    if not len(f0):
        return None
    mfcc = librosa.feature.mfcc(y=y, sr=sr, n_mfcc=13).mean(axis=1)
    return float(np.median(f0)), mfcc


def features_of(path):
    y, sr = VL.load(path)
    return _features(np.asarray(y, dtype=np.float32), sr)


def score(feat, centre, pitch_scale):
    """Distance from the pack's voice centre; 0 is a perfect match."""
    f0, mfcc = feat
    cf0, cm = centre
    pitch = abs(f0 - cf0) / max(pitch_scale, 1e-6)
    timbre = 1 - float(np.dot(mfcc, cm) /
                       (np.linalg.norm(mfcc) * np.linalg.norm(cm) + 1e-12))
    return W_PITCH * pitch + W_TIMBRE * (timbre * 100)


def pack_centre(feats):
    """Median F0 and median MFCC -- robust to the outliers being measured."""
    f0s = np.array([f[0] for f in feats])
    mfccs = np.stack([f[1] for f in feats])
    # Median absolute deviation gives a spread that outliers cannot inflate.
    mad = float(np.median(np.abs(f0s - np.median(f0s)))) or float(f0s.std()) or 1.0
    return (float(np.median(f0s)), np.median(mfccs, axis=0)), mad


def scan(pack_dir):
    """[(path, feature, score)] plus the pack's centre and pitch scale."""
    paths = []
    for root, _dirs, files in os.walk(pack_dir):
        for name in sorted(files):
            if name.lower().endswith('.wav'):
                paths.append(os.path.join(root, name))
    feats, kept = [], []
    for p in paths:
        f = features_of(p)
        if f is not None:
            feats.append(f)
            kept.append(p)
    if len(feats) < 5:
        return [], None, None
    centre, mad = pack_centre(feats)
    return ([(p, f, score(f, centre, mad)) for p, f in zip(kept, feats)],
            centre, mad)


def regenerate(client, lang, tier, key, voice, text, emotion, timeout):
    """One fresh rendition, returned as (float32 audio, sr) at TARGET_SR."""
    inputs = VOX.build_input('gemini', lang, voice, text, tier,
                             emotion=emotion, key=key)
    raw, _url = client.synthesize(VOX.GEMINI_MODEL, inputs, timeout=timeout,
                                  task_retries=1)
    x, sr = sf.read(io.BytesIO(raw), dtype='float32', always_2d=True)
    x = VL.resample(np.asarray(x).mean(axis=1), sr, VL.TARGET_SR)
    return x, VL.TARGET_SR


def load_texts():
    """(lang, relpath.wav) -> (text, emotion) from the manifests."""
    import csv
    out = {}
    for lang, cfg in VOX.LANGUAGES.items():
        with open(cfg['manifest'], encoding='utf-8') as f:
            for row in csv.DictReader(f):
                rel = (row.get('path') or '').strip()
                if not rel:
                    continue
                if not rel.lower().endswith('.wav'):
                    rel += '.wav'
                out[(lang, rel.replace('/', os.sep))] = (
                    (row.get('text') or '').strip(),
                    (row.get('emotion') or '').strip())
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--root', default=os.path.join('out', 'kie', 'gemini'))
    ap.add_argument('--attempts', type=int, default=3,
                    help='regeneration tries per outlier clip')
    ap.add_argument('--tolerance', type=float, default=DEFAULT_TOLERANCE)
    ap.add_argument('--max-per-pack', type=int, default=25,
                    help='cap on outliers repaired per pack, worst first')
    ap.add_argument('--timeout', type=float, default=300.0)
    ap.add_argument('--workers', type=int, default=12)
    ap.add_argument('--voices', help='limit to these voice keys, e.g. man,boy')
    ap.add_argument('--only', help='repair only clips whose path starts with '
                                   'one of these prefixes, e.g. letters/,items/'
                                   ' -- the pack centre is still built from the '
                                   'whole pack, so the filter narrows what is '
                                   'spent on, not what it is measured against')
    ap.add_argument('--report-only', action='store_true')
    args = ap.parse_args()

    only = ([p.strip().replace('/', os.sep) for p in args.only.split(',')]
            if args.only else None)

    texts = load_texts()
    keys = [k.strip() for k in args.voices.split(',')] if args.voices else None
    selection = VOX.resolve('gemini', keys=keys)
    client = None if args.report_only else KieClient()

    grand = [0, 0]
    for lang in VOX.LANGUAGES:
        for tier, key, voice, _label, _pitch in selection:
            pack_dir = os.path.join(args.root, lang, '%s_%s' % (tier, key))
            if not os.path.isdir(pack_dir):
                continue
            rows, centre, mad = scan(pack_dir)
            if not rows:
                continue
            scores = np.array([r[2] for r in rows])
            f0s = np.array([r[1][0] for r in rows])
            flagged = [r for r in rows if r[2] > args.tolerance]
            if only:
                flagged = [r for r in flagged
                           if os.path.relpath(r[0], pack_dir).startswith(
                               tuple(only))]
            outliers = sorted(flagged, key=lambda r: -r[2])[:args.max_per_pack]
            print('%-4s %-12s n=%3d  centre=%3.0f Hz  spread=%3.0f Hz  '
                  'median score=%.2f  outliers=%d'
                  % (lang, '%s/%s' % (tier, key), len(rows), centre[0],
                     f0s.std(), float(np.median(scores)), len(outliers)))
            grand[0] += len(rows)
            grand[1] += len(outliers)
            if args.report_only or not outliers:
                continue

            # Attempts for one clip stay sequential (each is compared against
            # the best so far), but clips are repaired in parallel -- 250
            # outliers x 3 tries is hours of round trips otherwise.
            results = []

            def repair(item):
                path, _feat, old = item
                rel = os.path.relpath(path, pack_dir)
                entry = texts.get((lang, rel))
                if entry is None:
                    return None
                text, emotion = entry
                best, best_audio = old, None
                for _ in range(args.attempts):
                    try:
                        x, sr = regenerate(client, lang, tier, key, voice,
                                           text, emotion, args.timeout)
                    except KieError:
                        continue
                    y = VL.pad_and_fade(x, sr)
                    if y is None:
                        continue
                    y = VL.normalize(y)
                    f = _features(y, sr)
                    if f is None:
                        continue
                    s = score(f, centre, mad)
                    if s < best:
                        best, best_audio = s, y
                if best_audio is None:
                    return None
                VL.save_16bit(path, best_audio, VL.TARGET_SR)
                return old, best

            with ThreadPoolExecutor(max_workers=args.workers) as pool:
                results = [r for r in pool.map(repair, outliers) if r]

            if results:
                before = np.mean([r[0] for r in results])
                after = np.mean([r[1] for r in results])
                print('     repaired %d/%d  score %.2f -> %.2f'
                      % (len(results), len(outliers), before, after))
            else:
                print('     repaired 0/%d' % len(outliers))

    print('\n%d clip(s) scanned, %d flagged as outliers%s'
          % (grand[0], grand[1], ' (report only)' if args.report_only else ''))
    return 0


if __name__ == '__main__':
    sys.exit(main())
