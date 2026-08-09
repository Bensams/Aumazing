"""Re-roll phrases the model delivered with a pause in the middle.

`repair_consistency.py` polices *who* is speaking. This polices *how*: a phrase
recorded as one utterance is supposed to run its two words together, and the
model does that most of the time -- but not every time. Measured over the 540
colour+shape phrases as first generated:

    inner gap   median 0.10 s   p75 0.18   p90 0.27   max 0.87
    duration    median 1.78 s   p75 2.04   p90 2.28   max 3.19

The median is genuinely fluent: 0.10 s between "purple" and "circle" is the
closure of the /k/, not a pause. The tail is not -- 30% of clips sit above
0.15 s, and a 0.87 s hole in the middle of a two-word phrase is worse than the
concatenation this was meant to replace.

"Inner gap" is the longest *contiguous* run of near-silence strictly inside the
speech, measured on 10 ms RMS frames at -45 dB. Contiguous matters: summing all
quiet frames counts every stop consonant and unvoiced fricative, which makes a
perfectly fluent phrase look broken.

The remedy is the one that already works for voice drift -- regenerate and keep
the better take. Nothing else is available: the pause is the model re-rolling
its own delivery, and no field in the request suppresses it.

    python repair_delivery.py --report-only
    python repair_delivery.py --attempts 3
"""
import argparse
import os
import sys
import threading
import warnings
from concurrent.futures import ThreadPoolExecutor

import numpy as np
import soundfile as sf

import voice_lib as VL
import voices as VOX
from kie_client import KieClient, KieError
from repair_consistency import load_texts, regenerate

warnings.filterwarnings('ignore')

FRAME_MS = 10.0
SILENCE_DB = -45.0
# p75 of the first run. Above this a listener hears a pause rather than a
# consonant; below it, re-rolling mostly buys noise.
DEFAULT_TOLERANCE = 0.18
# A phrase that is merely slow is not broken, so duration only breaks ties.
DURATION_WEIGHT = 0.15
TARGET_DURATION = 1.8

_lock = threading.Lock()


def measure(y, sr):
    """(inner_gap_seconds, speech_duration_seconds), or None if silent."""
    n = max(1, int(sr * FRAME_MS / 1000))
    m = (len(y) // n) * n
    if m < n:
        return None
    r = np.sqrt((np.asarray(y[:m], dtype=np.float32).reshape(-1, n) ** 2)
                .mean(axis=1))
    if r.max() <= 0:
        return None
    th = r.max() * (10 ** (SILENCE_DB / 20.0))
    idx = np.flatnonzero(r > th)
    if len(idx) < 2:
        return None
    quiet = r[idx[0]:idx[-1] + 1] <= th
    best = cur = 0
    for v in quiet:
        cur = cur + 1 if v else 0
        if cur > best:
            best = cur
    return best * FRAME_MS / 1000.0, (idx[-1] - idx[0] + 1) * FRAME_MS / 1000.0


def score(gap, duration):
    return gap + DURATION_WEIGHT * max(0.0, duration - TARGET_DURATION)


def read(path):
    y, sr = sf.read(path, dtype='float32', always_2d=True)
    return y.mean(axis=1), sr


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--root', default=os.path.join('out', 'kie', 'gemini'))
    ap.add_argument('--category', default='phrases',
                    help='cue folder to police (default: phrases)')
    ap.add_argument('--tolerance', type=float, default=DEFAULT_TOLERANCE)
    ap.add_argument('--attempts', type=int, default=3)
    ap.add_argument('--timeout', type=float, default=300.0)
    ap.add_argument('--workers', type=int, default=10)
    ap.add_argument('--report-only', action='store_true')
    args = ap.parse_args()

    texts = load_texts()
    client = None if args.report_only else KieClient()
    selection = VOX.resolve('gemini')

    jobs, scanned = [], 0
    for lang in VOX.LANGUAGES:
        for tier, key, voice, _label, _pitch in selection:
            pack = os.path.join(args.root, lang, '%s_%s' % (tier, key))
            folder = os.path.join(pack, args.category)
            if not os.path.isdir(folder):
                continue
            flagged = []
            for name in sorted(os.listdir(folder)):
                if not name.lower().endswith('.wav'):
                    continue
                path = os.path.join(folder, name)
                m = measure(*read(path))
                if m is None:
                    continue
                scanned += 1
                gap, dur = m
                if gap > args.tolerance:
                    flagged.append((path, gap, dur, score(gap, dur)))
            if flagged:
                print('%-4s %-12s %3d/%3d over %.2fs  worst %.2fs'
                      % (lang, '%s/%s' % (tier, key), len(flagged),
                         len(os.listdir(folder)), args.tolerance,
                         max(f[1] for f in flagged)))
                jobs += [(lang, tier, key, voice) + f for f in flagged]

    print('\n%d clip(s) scanned, %d over tolerance' % (scanned, len(jobs)))
    if args.report_only or not jobs:
        return 0

    fixed = [0]

    def repair(job):
        lang, tier, key, voice, path, gap, dur, best = job
        rel = os.path.relpath(path, os.path.join(
            args.root, lang, '%s_%s' % (tier, key)))
        entry = texts.get((lang, rel))
        if entry is None:
            return
        text, emotion = entry
        best_audio, best_gap = None, gap
        for _ in range(args.attempts):
            try:
                x, sr = regenerate(client, lang, tier, key, voice, text,
                                   emotion, args.timeout)
            except KieError:
                continue
            y = VL.pad_and_fade(x, sr)
            if y is None:
                continue
            y = VL.normalize(y)
            m = measure(y, sr)
            if m is None:
                continue
            s = score(*m)
            if s < best:
                best, best_gap, best_audio = s, m[0], y
        if best_audio is not None:
            VL.save_16bit(path, best_audio, VL.TARGET_SR)
            with _lock:
                fixed[0] += 1
                print('  fixed %-38s gap %.2f -> %.2f s'
                      % (rel.replace(os.sep, '/'), gap, best_gap), flush=True)

    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        list(pool.map(repair, jobs))

    print('\nimproved %d of %d flagged clip(s)' % (fixed[0], len(jobs)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
