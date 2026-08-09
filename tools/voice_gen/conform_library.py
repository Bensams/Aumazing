"""Strip the dead air that makes composed phrases drag.

A composed phrase ("Tap the" + "Yellow" + "Star", or the naming feedback
"Yellow" + "Star") plays as separate clips back to back. Every millisecond of
silence baked into the end of one clip and the start of the next lands in the
middle of the phrase, so a child hears a long, unexplained pause between two
words that should run together.

Two separate faults put it there:

  1. `tl` was never conformed at all -- ~1.0 s of trailing silence per clip,
     straight from whatever produced it.
  2. Every generated pack *was* conformed, and the trim did nothing, because
     `voice_lib.THRESH_DB` is -60 dB. That is 0.1% of peak: the model's own
     noise floor and the MP3 encoder's ringing both sit above it, so
     `speech_bounds` reported speech starting at 0.03 s when the first audible
     sound was at 0.33 s. The clip looked already-tight and was left alone.

Measured across the shipped library, before this pass:

     pack               lead (med)   tail (med)
     tl                    0.21 s       0.86 s
     generated packs       0.30 s       0.35 s
     ceb_lexianne          0.02 s       0.02 s   <- human-edited, the target

So a `tl` word boundary carried ~1.3 s of silence and a generated one ~0.7 s,
against the 0.06 s the library contract now asks for (20 ms lead + 40 ms tail).

This pass re-detects speech with a **10 ms RMS window at -45 dB relative to
peak** and re-pads to `voice_lib`'s LEAD_PAD_MS / TAIL_PAD_MS. -45 dB was
chosen by measurement, not feel: the detected span is stable between -45 and
-40 dB and only starts eating real speech at -35 dB, where long phrases like
"Great job!" lose 120 ms off the end.

It does **not** renormalise. Loudness is left exactly as found, so this is a
silence edit and nothing else -- which keeps it safe to run on the three
default packs, whose audio is the only copy in existence.

Order matters. Conform the WAV masters, then re-derive the MP3s, so the
generated packs never take a second generation of lossy encoding:

    python conform_library.py --root out/kie/gemini
    python to_mp3.py --src out/kie/gemini --dst out/mp3 --force
    python install_packs.py
    python conform_library.py --assets          # en / tl / ceb, in place
    python check_library.py

`--assets` backs up every file it changes on the first run, because the default
packs cannot be regenerated. Backups go to `out/asset_backup/`, deliberately
*outside* the asset tree -- Flutter bundles every file in a declared asset
directory, so a .bak sitting beside its clip would ship inside the app.
`--restore` puts them back.
"""
import argparse
import os
import shutil
import sys

import numpy as np
import soundfile as sf

import voice_lib as VL

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
ASSET_ROOT = os.path.join(REPO, 'packages', 'shared_audio', 'assets', 'audio',
                          'voice_over')
# Backups live OUTSIDE the asset tree on purpose. Flutter bundles every file in
# a declared asset directory, so a .bak sitting next to its clip would ship
# inside the app -- doubling the voice-over payload with dead weight.
BACKUP_ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                           'out', 'asset_backup')

# Relative to peak RMS. See the module docstring for why not -60 (the existing
# voice_lib value, which never fires) and why not -35 (which clips word tails).
TRIM_DB = -45.0
FRAME_MS = 10.0

# Human-recorded and already tighter than the contract; also irreplaceable.
SKIP_PACKS = {'ceb_lexianne'}

REGISTRY = os.path.join(REPO, 'packages', 'shared_audio', 'lib', 'src',
                        'voice_pack.dart')


def registered_folders():
    """Asset folders the app actually ships, from voice_pack.dart.

    Deregistered folders can linger on disk long after they stop being built
    into the app. The padding contract exists to keep composed phrases fluent,
    which is only meaningful for audio a child can hear, so this pass -- and in
    particular `--check`, which gates commits -- ignores anything unregistered
    rather than reporting failures nobody can act on.
    """
    import re
    try:
        text = open(REGISTRY, encoding='utf-8').read()
    except OSError:
        return None
    return set(re.findall(r"assetFolder: '([^']+)'", text)) or None


def rms_bounds(y, sr, db=TRIM_DB, frame_ms=FRAME_MS):
    """(start, end) sample indices of audible speech, or None.

    Frame RMS rather than sample peak: a single stray sample above threshold
    is what let the old detector mistake the noise floor for a word onset.
    One frame of slack on each side keeps soft onsets and released consonants.
    """
    n = max(1, int(sr * frame_ms / 1000))
    m = (len(y) // n) * n
    if m < n:
        return None
    frames = y[:m].reshape(-1, n)
    r = np.sqrt((frames ** 2).mean(axis=1))
    if r.max() <= 0:
        return None
    idx = np.flatnonzero(r > r.max() * (10 ** (db / 20.0)))
    if not len(idx):
        return None
    return max(0, (idx[0] - 1)) * n, min(len(y), (idx[-1] + 2) * n)


def backup_path(path):
    return os.path.join(BACKUP_ROOT, os.path.relpath(path, ASSET_ROOT))


def conform(path, dry_run, backup):
    """Re-trim one clip. Returns (lead_before, tail_before, saved_seconds)."""
    y, sr = sf.read(path, dtype='float32', always_2d=True)
    mono = y.mean(axis=1)
    b = rms_bounds(mono, sr)
    if b is None:
        return None
    start, end = b
    lead_before, tail_before = start / sr, (len(mono) - end) / sr

    lead = int(sr * VL.LEAD_PAD_MS / 1000)
    tail = int(sr * VL.TAIL_PAD_MS / 1000)
    # Only excess silence is a defect. A clip trimmed *tighter* than the
    # contract -- the human-recorded ones are, at ~20 ms -- is left exactly as
    # it is: padding it back up would add the very silence this pass exists to
    # remove, and would make re-running the tool churn files forever.
    slack = int(sr * FRAME_MS / 1000)
    if start <= lead + slack and (len(mono) - end) <= tail + slack:
        return None

    keep = y[start:end]
    pad_l = np.zeros((lead, y.shape[1]), np.float32)
    pad_t = np.zeros((tail, y.shape[1]), np.float32)
    out = np.concatenate([pad_l, keep, pad_t], axis=0)

    fi = min(int(sr * VL.FADE_IN_MS / 1000), len(out) // 2)
    fo = min(int(sr * VL.FADE_OUT_MS / 1000), len(out) // 2)
    if fi:
        out[:fi] *= np.linspace(0, 1, fi, dtype=np.float32)[:, None]
    if fo:
        out[-fo:] *= np.linspace(1, 0, fo, dtype=np.float32)[:, None]

    saved = (len(mono) - len(out)) / sr
    if not dry_run:
        if backup:
            bak = backup_path(path)
            if not os.path.exists(bak):
                os.makedirs(os.path.dirname(bak), exist_ok=True)
                shutil.copy2(path, bak)
        if out.shape[1] == 1:
            out = out[:, 0]
        sf.write(path, out, sr, subtype='PCM_16')
    return lead_before, tail_before, saved


def walk(root, exts):
    """(path, pack) for every clip under root.

    The two trees nest differently -- the shipped assets are
    `<pack>/<category>/<file>` and a generation output is
    `<lang>/<tier>_<voice>/<category>/<file>` -- so the pack name is whatever
    sits above the category folder, at whatever depth that lands.
    """
    for dirpath, _dirs, files in os.walk(root):
        rel = os.path.relpath(dirpath, root)
        if rel == '.':
            continue
        parts = rel.split(os.sep)
        if len(parts) < 2:
            continue  # a pack folder itself; clips live one level deeper
        pack = os.sep.join(parts[:-1])
        for name in sorted(files):
            if name.lower().endswith(exts):
                yield os.path.join(dirpath, name), pack


def restore(_root):
    if not os.path.isdir(BACKUP_ROOT):
        print('no backups at %s' % BACKUP_ROOT)
        return 0
    n = 0
    for dirpath, _dirs, files in os.walk(BACKUP_ROOT):
        for name in sorted(files):
            src = os.path.join(dirpath, name)
            shutil.move(src, os.path.join(
                ASSET_ROOT, os.path.relpath(src, BACKUP_ROOT)))
            n += 1
    print('restored %d file(s) from %s' % (n, BACKUP_ROOT))
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--root', help='a generation output tree of WAV masters, '
                                   'e.g. out/kie/gemini')
    ap.add_argument('--assets', action='store_true',
                    help='conform the shipped packs in packages/shared_audio '
                         '(WAV only -- run install_packs.py for the MP3 ones)')
    ap.add_argument('--include-skipped', action='store_true',
                    help='also conform %s' % ', '.join(sorted(SKIP_PACKS)))
    ap.add_argument('--restore', action='store_true',
                    help='undo --assets from the .bak files')
    ap.add_argument('--dry-run', action='store_true')
    ap.add_argument('--check', action='store_true',
                    help='report only, and exit non-zero if any clip is out '
                         'of contract -- use this to gate a commit')
    args = ap.parse_args()
    if args.check:
        args.dry_run = True

    if args.restore:
        return restore(ASSET_ROOT)
    if not args.root and not args.assets:
        ap.error('pass --root DIR or --assets')

    root = ASSET_ROOT if args.assets else args.root
    if not os.path.isdir(root):
        sys.exit('no such directory: %s' % root)

    # Only the shipped packs are held to the contract; see registered_folders.
    shipped = registered_folders() if args.assets else None

    changed = skipped = unregistered = 0
    saved_total = 0.0
    per_pack = {}
    for path, pack in walk(root, ('.wav',)):
        if pack in SKIP_PACKS and not args.include_skipped:
            skipped += 1
            continue
        if shipped is not None and pack not in shipped:
            unregistered += 1
            continue
        r = conform(path, args.dry_run, backup=args.assets)
        if r is None:
            continue
        _lead, _tail, saved = r
        changed += 1
        saved_total += saved
        acc = per_pack.setdefault(pack, [0, 0.0])
        acc[0] += 1
        acc[1] += saved

    for pack in sorted(per_pack):
        n, s = per_pack[pack]
        print('  %-20s %4d clip(s)  %6.1f s of silence removed  '
              '(%.2f s/clip)' % (pack, n, s, s / n))
    print('\n%s %d clip(s), %.1f s of dead air removed%s'
          % ('would conform' if args.dry_run else 'conformed', changed,
             saved_total, ', %d skipped' % skipped if skipped else ''))
    if changed and not args.dry_run and args.assets:
        print('originals backed up to %s -- `--restore` undoes this'
              % os.path.relpath(BACKUP_ROOT, os.getcwd()))
    if args.check and changed:
        print('\nFAIL: %d clip(s) carry more silence than the contract '
              'allows.\nComposed phrases play these back to back, so this '
              'lands as a pause mid-phrase.\nRun without --check to fix.'
              % changed)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
