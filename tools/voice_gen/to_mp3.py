"""Transcode a voice-over tree from WAV to MP3, preserving structure.

The generated library is 24 kHz mono 16-bit WAV -- about 48 KB per second,
which is fine on disk and far too much to ship 48 voice packs of. MP3 at the
default level is roughly 8x smaller with no audible loss on speech.

Only the container changes: sample rate, channel count and the lead/tail
padding are already correct from generation and are passed through untouched.

  python to_mp3.py --src out/kie/gemini --dst out/kie/gemini_mp3
  python to_mp3.py --src ../../packages/shared_audio/assets/audio/voice_over \
      --dst out/live_mp3 --level 0.5

Level runs 0.0 (largest, best) to 0.9 (smallest). 0.5 keeps consonants crisp,
which matters more here than the last few megabytes -- these cues are single
words a child is being asked to discriminate.
"""
import argparse
import os
import sys
from concurrent.futures import ThreadPoolExecutor

import numpy as np
import soundfile as sf

DEFAULT_LEVEL = 0.5


def convert(src, dst, level):
    x, sr = sf.read(src, dtype='float32', always_2d=True)
    x = x.mean(axis=1)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    with sf.SoundFile(dst, 'w', samplerate=sr, channels=1, format='MP3',
                      compression_level=level) as f:
        f.write(x)
    return os.path.getsize(src), os.path.getsize(dst)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--src', required=True)
    ap.add_argument('--dst', required=True)
    ap.add_argument('--level', type=float, default=DEFAULT_LEVEL,
                    help='0.0 best/largest .. 0.9 smallest (default %.1f)' % DEFAULT_LEVEL)
    ap.add_argument('--workers', type=int, default=8)
    ap.add_argument('--force', action='store_true')
    args = ap.parse_args()

    if not os.path.isdir(args.src):
        sys.exit('Not a directory: %s' % args.src)

    jobs = []
    for root, _dirs, files in os.walk(args.src):
        for name in files:
            if not name.lower().endswith('.wav'):
                continue
            src = os.path.join(root, name)
            rel = os.path.relpath(src, args.src)
            dst = os.path.join(args.dst, os.path.splitext(rel)[0] + '.mp3')
            if os.path.exists(dst) and not args.force:
                continue
            jobs.append((src, dst))

    if not jobs:
        print('Nothing to convert (use --force to redo).')
        return 0
    print('Converting %d file(s) at level %.1f ...' % (len(jobs), args.level))

    totals = [0, 0]
    failures = []

    def work(job):
        src, dst = job
        try:
            a, b = convert(src, dst, args.level)
            totals[0] += a
            totals[1] += b
        except Exception as exc:
            failures.append((src, '%s: %s' % (type(exc).__name__, exc)))

    with ThreadPoolExecutor(max_workers=max(1, args.workers)) as pool:
        list(pool.map(work, jobs))

    mb = lambda n: n / (1024.0 * 1024.0)
    print('wav %.1f MB -> mp3 %.1f MB  (%.1fx smaller)'
          % (mb(totals[0]), mb(totals[1]),
             totals[0] / max(totals[1], 1)))
    print('Wrote %d file(s) to %s' % (len(jobs) - len(failures), args.dst))
    if failures:
        print('%d failed:' % len(failures))
        for src, err in failures[:10]:
            print('  %s  %s' % (src, err))
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
