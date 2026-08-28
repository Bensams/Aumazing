"""Generate voice-over clips with Chatterbox, cloned from a reference recording.

Writes to an output directory -- it never touches the live asset folder, so you
can audition results next to the existing library before adopting them.

Short clips ("Yellow", "Star") are generated inside a carrier phrase and then
extracted, because zero-shot TTS delivers bare one-word prompts poorly. The
extraction is verified: if the carrier does not split into the expected number
of voiced segments, the line is FLAGGED rather than silently mis-cut.

Usage:
  python generate.py --ref my_voice.wav --manifest lines.csv --out out/en
  python generate.py --ref my_voice.wav --manifest lines.csv --out out/en \
      --only colors/Gold,colors/Pink,colors/Magenta,colors/Teal,shapes/Heart
"""
import argparse
import csv
import os
import sys

import numpy as np

import voice_lib as VL

# The target word sits between two throwaway words so the model has prosodic
# context on both sides. Periods encourage it to insert real pauses, which is
# what makes silence-based extraction reliable.
CARRIER = "Okay. {text}. Ready."
CARRIER_INDEX = 1      # segment to keep
CARRIER_SEGMENTS = 3   # expected voiced segment count


def to_numpy(wav):
    """Chatterbox returns a torch tensor; accept ndarray too."""
    if hasattr(wav, 'detach'):
        wav = wav.detach().cpu().numpy()
    wav = np.asarray(wav, dtype=np.float32)
    if wav.ndim > 1:
        wav = wav.squeeze()
        if wav.ndim > 1:
            wav = wav.mean(axis=0)
    return wav


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--ref', required=True, help='reference recording of the voice to clone (10-20s, clean)')
    ap.add_argument('--manifest', default='lines.csv')
    ap.add_argument('--out', required=True)
    ap.add_argument('--only', help='comma-separated path prefixes to generate (without .wav)')
    ap.add_argument('--no-carrier', action='store_true', help='ignore the carrier column; generate bare text')
    ap.add_argument('--device', default='cpu')
    args = ap.parse_args()

    if not os.path.exists(args.ref):
        sys.exit('Reference audio not found: %s' % args.ref)

    with open(args.manifest, encoding='utf-8') as f:
        rows = list(csv.DictReader(f))
    if args.only:
        wanted = [s.strip() for s in args.only.split(',')]
        rows = [r for r in rows if any(r['path'].startswith(w) for w in wanted)]
    if not rows:
        sys.exit('No lines matched.')

    print('Loading Chatterbox on %s (first run downloads model weights)...' % args.device)
    from chatterbox.tts import ChatterboxTTS
    model = ChatterboxTTS.from_pretrained(device=args.device)
    model_sr = getattr(model, 'sr', 24000)
    print('Model ready (sr=%d). Generating %d lines.\n' % (model_sr, len(rows)))

    flagged = []
    for i, row in enumerate(rows, 1):
        rel, text = row['path'], row['text']
        use_carrier = (row.get('carrier') == 'yes') and not args.no_carrier
        prompt = CARRIER.format(text=text.rstrip('.!?')) if use_carrier else text

        wav = model.generate(
            prompt,
            audio_prompt_path=args.ref,
            exaggeration=float(row.get('exaggeration', 0.5)),
            cfg_weight=float(row.get('cfg_weight', 0.5)),
        )
        x = VL.resample(to_numpy(wav), model_sr, VL.TARGET_SR)
        sr = VL.TARGET_SR

        note = ''
        if use_carrier:
            segs, th = VL.split_carrier(x, sr, expected=CARRIER_SEGMENTS)
            if segs is not None:
                s, e = segs[CARRIER_INDEX]
                x = x[s:e + 1]
                if th != VL.SPLIT_THRESH_SWEEP[0]:
                    note = '(split at %g dB)' % th
            else:
                note = 'carrier did not split into %d segments at any ' \
                       'threshold - NOT extracted' % CARRIER_SEGMENTS
                flagged.append((rel, note))

        y = VL.pad_and_fade(x, sr)
        if y is None:
            flagged.append((rel, 'no signal generated'))
            continue
        y = VL.normalize(y)

        dst = os.path.join(args.out, rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        VL.save_16bit(dst, y, sr)

        d = VL.describe(y, sr)
        print('[%3d/%d] %-34s %5.2fs (speech %.2fs) %s' % (
            i, len(rows), rel, d['total'], d['speech'], note))

    print('\nWrote %d files to %s' % (len(rows) - len([f for f in flagged if 'no signal' in f[1]]), args.out))
    if flagged:
        print('\n%d line(s) need a look:' % len(flagged))
        for rel, note in flagged:
            print('  %-34s %s' % (rel, note))
        print('\nFor carrier-split failures, retry that line with --no-carrier,')
        print('or edit its text in the manifest and regenerate just that path with --only.')
    else:
        print('No warnings. Audition the output before copying it into the asset folder.')


if __name__ == '__main__':
    main()
