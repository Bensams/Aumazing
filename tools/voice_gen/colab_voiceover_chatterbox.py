"""
Chatterbox TTS batch voice-over generator — Google Colab (free T4 GPU)
========================================================================

SETUP — run this in a Colab cell BEFORE the generation cell:

    !pip install chatterbox-tts soundfile numpy soxr

    # Chatterbox pulls its own torch/torchaudio pins, which can conflict
    # with the torch build Colab preinstalls. If pip reports a dependency
    # conflict, or `import torch` errors after install, go to
    # Runtime > Restart session (NOT "Disconnect and delete runtime" —
    # that also wipes /content) and just re-run the generation cell below.
    # No need to reinstall after a restart.
    #
    # soxr is optional (higher-quality resampling for CSV/carrier mode);
    # a lower-quality linear fallback is used automatically if missing.
    #
    # KNOWN ISSUE: if importing chatterbox fails with
    #   "RuntimeError: operator torchvision::nms does not exist"
    # it means the chatterbox-tts install pulled in a torch build that no
    # longer matches Colab's preinstalled torchvision. Chatterbox is
    # audio-only and doesn't need torchvision, so just remove it:
    #   !pip uninstall -y torchvision
    # then re-run the generation cell (no restart needed).

USAGE — upload your reference clip and script (via the Colab file browser,
or google.colab.files.upload()), then from a cell:

    !python colab_voiceover_chatterbox.py /content/reference.wav /content/script.txt \
        --out /content/drive/MyDrive/voiceover_out

    # --out on Google Drive is strongly recommended (see below).

SCRIPT FILE FORMAT — two supported, chosen by file extension:

  .txt  Plain text, one VO line per line. Blank lines and lines starting
        with "#" are skipped. A line with multiple sentences is split on
        sentence-ending punctuation, so each sentence becomes its own clip.
        Output files: out/<stem>/<stem>_0001.wav, _0002.wav, ...

  .csv  Same manifest format as the local generate.py/lines.csv workflow:
            path,text,carrier,exaggeration,cfg_weight,emotion
        - path: output file (without .wav), may include subfolders, e.g.
          "colors/Gold" -> out/<stem>/colors/Gold.wav
        - text: what gets spoken
        - carrier: "yes" wraps short/single-word text in a carrier phrase
          ("Okay. {text}. Ready.") and extracts the middle segment by
          silence detection, so bare one-word prompts don't come out
          clipped or mis-toned. Requires voice_lib.py (see below).
        - exaggeration, cfg_weight: per-row overrides of the --exaggeration
          / --cfg-weight CLI defaults; leave blank to use the CLI default.
        - emotion: optional friendly preset (excited, happy, gentle, calm,
          serious, silly, surprised, sleepy) that fills in exaggeration/
          cfg_weight for you -- see EMOTION_PRESETS below. Explicit values
          in the exaggeration/cfg_weight columns always win over this.
          Chatterbox has no real emotion classifier; these presets are
          just reasonable starting points for --exaggeration/--cfg-weight,
          not a guarantee -- audition and hand-tune per line as needed.
        CSV mode requires voice_lib.py to be present alongside this script
        (upload it the same way you uploaded this file) — it does the
        resample/carrier-split/pad/normalize steps.

EXPRESSIVENESS FOR KIDS' CONTENT
-----------------------------------
Chatterbox has no discrete "emotion" input -- expressiveness is entirely
the --exaggeration / --cfg-weight knobs (or the emotion column above) plus
the character of the reference clip itself:

  - Raise the default: try --exaggeration 0.7 instead of 0.5 for an
    overall more animated read, and use the emotion/exaggeration column
    to dial individual lines up (excited reveal) or down (gentle aside).
  - Lower --cfg-weight a bit (0.3-0.4) for more delivery freedom; going
    too low can drift from the cloned voice's identity, so audition it.
  - Punctuation drives prosody -- "Wow!!" and "wow." read very
    differently. Write the script the way you want it performed.
  - The reference clip's own delivery carries through. A flat, deadpan
    reference recording tends to produce flat output regardless of these
    settings -- record the reference itself with some warmth/energy if
    the target is an expressive kids' character voice.

SESSION LIMITS — READ THIS BEFORE A LONG BATCH
------------------------------------------------
Free-tier Colab disconnects idle sessions (~90 min idle, ~12h hard cap)
without warning, and reclaims the T4 immediately. If that happens
mid-run:

  1. Point --out at a mounted Google Drive folder, e.g.:
         from google.colab import drive
         drive.mount('/content/drive')
     Per-line WAVs are written to disk as they finish, so anything
     generated before the disconnect survives even though the VM doesn't.
     /content itself is wiped on disconnect — Drive is not.
  2. Reconnect the runtime, re-run the install cell, then re-run the
     EXACT SAME command. This script skips any line whose output WAV
     already exists under --out, so it resumes instead of starting over.
     Pass --overwrite to force a full regeneration instead.
  3. The concatenated "full take" WAV is (re)built at the very end of
     each run from whatever per-line files exist on disk at that moment,
     so a resumed run's full take includes lines from the interrupted
     run too — you don't lose earlier progress.
"""
import argparse
import csv
import os
import re
import sys
import time

import numpy as np

# The target word sits between two throwaway words so the model has
# prosodic context on both sides. Periods encourage it to insert real
# pauses, which is what makes silence-based extraction reliable.
CARRIER = "Okay. {text}. Ready."
CARRIER_INDEX = 1      # segment to keep
CARRIER_SEGMENTS = 3   # expected voiced segment count

# (exaggeration, cfg_weight) starting points for the CSV "emotion" column.
# Chatterbox has no real emotion classifier -- these are just reasonable
# defaults to audition and hand-tune per line, not a guarantee.
EMOTION_PRESETS = {
    'neutral':   (0.5, 0.5),
    'calm':      (0.3, 0.6),
    'gentle':    (0.35, 0.55),
    'happy':     (0.7, 0.4),
    'excited':   (0.85, 0.3),
    'silly':     (0.9, 0.3),
    'surprised': (0.85, 0.35),
    'serious':   (0.4, 0.6),
    'sleepy':    (0.25, 0.65),
}


def fmt_elapsed(seconds):
    seconds = max(0.0, seconds)
    h, rem = divmod(int(seconds), 3600)
    m, s = divmod(rem, 60)
    if h:
        return f'{h}h{m:02d}m{s:02d}s'
    if m:
        return f'{m}m{s:02d}s'
    return f'{seconds:.1f}s'


def truncate(text, n=55):
    return text if len(text) <= n else text[:n - 1] + '…'


def load_units_txt(script_path):
    with open(script_path, encoding='utf-8-sig') as f:
        raw = f.read()
    if not raw.strip():
        raise ValueError(f'Script file is empty: {script_path}')

    units = []
    for raw_line in raw.splitlines():
        line = raw_line.strip()
        if not line or line.startswith('#'):
            continue
        for sentence in re.split(r'(?<=[.!?])\s+', line):
            sentence = sentence.strip()
            if sentence:
                units.append(sentence)

    if not units:
        raise ValueError(
            f'No speakable lines found in script (only blanks/comments): {script_path}'
        )
    return [
        {'rel': f'{i + 1:04d}', 'text': t, 'carrier': False, 'exaggeration': None, 'cfg_weight': None}
        for i, t in enumerate(units)
    ]


def load_units_csv(script_path):
    with open(script_path, encoding='utf-8-sig', newline='') as f:
        rows = list(csv.DictReader(f))

    units = []
    for n, row in enumerate(rows, 2):  # row 1 is the header
        rel = (row.get('path') or '').strip()
        if rel.lower().endswith('.wav'):
            rel = rel[:-4]  # lines.csv includes .wav in path; avoid writing "name.wav.wav"
        text = (row.get('text') or '').strip()
        if not rel or not text:
            print(f'  (row {n}: missing path/text, skipped)')
            continue
        exag = (row.get('exaggeration') or '').strip()
        cfgw = (row.get('cfg_weight') or '').strip()
        emotion = (row.get('emotion') or '').strip().lower()

        preset_exag = preset_cfgw = None
        if emotion:
            preset = EMOTION_PRESETS.get(emotion)
            if preset is None:
                print(f'  (row {n}: unknown emotion "{emotion}", ignoring -- '
                      f'known: {", ".join(sorted(EMOTION_PRESETS))})')
            else:
                preset_exag, preset_cfgw = preset

        units.append({
            'rel': rel,
            'text': text,
            'carrier': (row.get('carrier') or '').strip().lower() == 'yes',
            'exaggeration': float(exag) if exag else preset_exag,
            'cfg_weight': float(cfgw) if cfgw else preset_cfgw,
        })

    if not units:
        raise ValueError(
            f'No usable rows in CSV (need non-empty "path" and "text" columns): {script_path}'
        )
    return units


def load_units(script_path):
    """Returns (units, mode) where mode is 'csv' or 'txt'.

    Raises FileNotFoundError if the path doesn't exist, ValueError if the
    file has no usable content.
    """
    if not os.path.isfile(script_path):
        raise FileNotFoundError(script_path)
    if script_path.lower().endswith('.csv'):
        return load_units_csv(script_path), 'csv'
    return load_units_txt(script_path), 'txt'


def to_numpy(wav):
    """Chatterbox returns a torch tensor; accept a numpy array too."""
    if hasattr(wav, 'detach'):
        wav = wav.detach().cpu().numpy()
    wav = np.asarray(wav, dtype=np.float32)
    if wav.ndim > 1:
        wav = wav.squeeze()
        if wav.ndim > 1:
            wav = wav.mean(axis=0)
    return wav


def build_full_take(paths, out_root, stem, gap_seconds, sr):
    """Concatenate whatever per-line WAVs exist on disk, in order."""
    import soundfile as sf

    existing = [p for p in paths if os.path.isfile(p)]
    if not existing:
        print('No per-line files on disk yet -- skipping full-take concatenation.')
        return None

    gap = np.zeros(int(gap_seconds * sr), dtype=np.float32)
    chunks = []
    for p in existing:
        data, file_sr = sf.read(p, dtype='float32')
        if file_sr != sr:
            sys.exit(
                f'Sample rate mismatch in {p} ({file_sr} vs {sr}); '
                'was --out reused across a different model/run? Use --overwrite or a clean --out.'
            )
        chunks.append(data)
        chunks.append(gap)
    full = np.concatenate(chunks[:-1])

    full_path = os.path.join(out_root, f'{stem}_full.wav')
    sf.write(full_path, full, sr, subtype='PCM_16')
    return full_path


def parse_args():
    ap = argparse.ArgumentParser(
        description='Chatterbox TTS batch voice-over generator (Colab / T4 GPU).'
    )
    ap.add_argument('ref_audio', help='Reference voice clip to clone (WAV/MP3, ~10-30s)')
    ap.add_argument('script_file', help='.txt (one line per VO line) or .csv (path,text,carrier,exaggeration,cfg_weight)')
    ap.add_argument(
        '--out', default='out',
        help='Output directory root (default: ./out). Use a mounted Drive path for long batches.',
    )
    ap.add_argument('--device', default=None, help='cuda | cpu (default: cuda if available)')
    ap.add_argument('--exaggeration', type=float, default=0.5, help='Emotional intensity, 0-1 (CSV rows can override)')
    ap.add_argument('--cfg-weight', type=float, default=0.5, help='Adherence to the reference voice (CSV rows can override)')
    ap.add_argument(
        '--no-carrier', action='store_true',
        help="Ignore the CSV 'carrier' column; always generate bare text",
    )
    ap.add_argument(
        '--gap', type=float, default=0.35,
        help='Silence in seconds inserted between lines in the concatenated full take',
    )
    ap.add_argument(
        '--overwrite', action='store_true',
        help='Regenerate lines even if their WAV already exists (default: skip/resume)',
    )
    return ap.parse_args()


def main():
    t_script_start = time.time()
    args = parse_args()

    # --- Validate inputs up front, before paying for a model load -------
    try:
        if not os.path.isfile(args.ref_audio):
            raise FileNotFoundError(args.ref_audio)
        units, mode = load_units(args.script_file)
    except FileNotFoundError as e:
        sys.exit(f'File not found: {e}')
    except ValueError as e:
        sys.exit(f'Malformed script file: {e}')

    voice_lib = None
    if mode == 'csv':
        try:
            import voice_lib as voice_lib
        except ImportError as e:
            sys.exit(
                'Script file is a CSV, which needs voice_lib.py for carrier-phrase '
                'extraction and audio post-processing. Upload voice_lib.py into the '
                f'same folder as this script (same way you uploaded this file) and retry.\n'
                f'  (underlying error: {e})'
            )

    try:
        import torch
    except ImportError as e:
        sys.exit(f'torch is not importable ({e}). Run the install cell (see the top of this file) first.')

    device = args.device or ('cuda' if torch.cuda.is_available() else 'cpu')
    if device == 'cuda' and not torch.cuda.is_available():
        print('CUDA requested but not available -- falling back to CPU (this will be slow).')
        device = 'cpu'

    try:
        oom_error = torch.cuda.OutOfMemoryError
    except AttributeError:
        oom_error = RuntimeError  # older torch: OOM surfaces as a plain RuntimeError

    stem = os.path.splitext(os.path.basename(args.script_file))[0]
    out_dir = os.path.join(args.out, stem)
    os.makedirs(out_dir, exist_ok=True)

    if mode == 'csv':
        paths = [os.path.join(out_dir, u['rel'] + '.wav') for u in units]
    else:
        paths = [os.path.join(out_dir, f"{stem}_{u['rel']}.wav") for u in units]

    already_done = sum(os.path.isfile(p) for p in paths) if not args.overwrite else 0
    if already_done:
        print(
            f'Resuming: {already_done}/{len(units)} lines already exist in {out_dir}, '
            'will be skipped. Pass --overwrite to regenerate everything.'
        )

    # --- Load model -------------------------------------------------------
    print(f'Loading Chatterbox on {device} (first run downloads model weights)...')
    t_load_start = time.time()
    try:
        from chatterbox.tts import ChatterboxTTS
        model = ChatterboxTTS.from_pretrained(device=device)
    except oom_error:
        sys.exit(
            'CUDA out of memory while loading the model. Free the GPU '
            '(Runtime > Restart session) and try again with --device cpu if it recurs.'
        )
    except ImportError as e:
        sys.exit(
            f'chatterbox-tts is not importable ({e}).\n'
            'If you already ran the install cell, this is usually a dependency version '
            'conflict rather than a missing package -- run:\n'
            '  !python -c "from chatterbox.tts import ChatterboxTTS"\n'
            'in a Colab cell to see the full traceback, then fix/reinstall that specific '
            'package (Runtime > Restart session first if numpy/torch was involved).'
        )
    load_time = time.time() - t_load_start
    model_sr = getattr(model, 'sr', 24000)
    out_sr = voice_lib.TARGET_SR if mode == 'csv' else model_sr
    print(f'Model ready in {fmt_elapsed(load_time)} (sr={model_sr}). Generating {len(units)} lines.\n')

    # --- Per-line generation ----------------------------------------------
    import soundfile as sf

    failed = []
    ok_count = 0
    t_gen_start = time.time()
    interrupted = False
    try:
        for i, (unit, path) in enumerate(zip(units, paths), 1):
            line_t0 = time.time()
            if os.path.isfile(path) and not args.overwrite:
                ok_count += 1
                print(f'[{i:3d}/{len(units)}] {truncate(unit["text"]):<56} SKIP (exists)  '
                      f'elapsed {fmt_elapsed(time.time() - t_gen_start)}')
                continue

            try:
                use_carrier = mode == 'csv' and unit['carrier'] and not args.no_carrier
                prompt = CARRIER.format(text=unit['text'].rstrip('.!?')) if use_carrier else unit['text']
                exaggeration = unit['exaggeration'] if unit['exaggeration'] is not None else args.exaggeration
                cfg_weight = unit['cfg_weight'] if unit['cfg_weight'] is not None else args.cfg_weight

                wav = model.generate(
                    prompt,
                    audio_prompt_path=args.ref_audio,
                    exaggeration=exaggeration,
                    cfg_weight=cfg_weight,
                )
                x = to_numpy(wav)
                if x.size == 0:
                    raise RuntimeError('model produced no audio')

                note = ''
                if mode == 'csv':
                    x = voice_lib.resample(x, model_sr, voice_lib.TARGET_SR)
                    if use_carrier:
                        segs, th = voice_lib.split_carrier(x, out_sr, expected=CARRIER_SEGMENTS)
                        if segs is not None:
                            s, e = segs[CARRIER_INDEX]
                            x = x[s:e + 1]
                        else:
                            note = f'carrier did not split into {CARRIER_SEGMENTS} segments -- saved unextracted'
                    y = voice_lib.pad_and_fade(x, out_sr)
                    if y is None:
                        raise RuntimeError('no signal generated')
                    y = voice_lib.normalize(y)
                    os.makedirs(os.path.dirname(path), exist_ok=True)
                    voice_lib.save_16bit(path, y, out_sr)
                else:
                    os.makedirs(os.path.dirname(path), exist_ok=True)
                    sf.write(path, x, out_sr, subtype='PCM_16')

                ok_count += 1
                suffix = f'  ({note})' if note else ''
                print(f'[{i:3d}/{len(units)}] {truncate(unit["text"]):<56} '
                      f'{time.time() - line_t0:5.2f}s  elapsed {fmt_elapsed(time.time() - t_gen_start)}{suffix}')
                if note:
                    failed.append((i, unit['text'], note))

            except oom_error as e:
                if oom_error is RuntimeError and 'out of memory' not in str(e).lower():
                    raise
                print(f'[{i:3d}/{len(units)}] {truncate(unit["text"]):<56} CUDA OUT OF MEMORY -- skipped')
                failed.append((i, unit['text'], 'CUDA out of memory'))
                if device == 'cuda':
                    torch.cuda.empty_cache()
                continue

            except Exception as e:
                print(f'[{i:3d}/{len(units)}] {truncate(unit["text"]):<56} FAILED: {e}')
                failed.append((i, unit['text'], str(e)))
                continue

    except KeyboardInterrupt:
        interrupted = True
        print('\nInterrupted -- building a full take from lines generated so far.')

    gen_time = time.time() - t_gen_start

    # --- Concatenate whatever exists on disk -------------------------------
    full_path = build_full_take(paths, out_dir, stem, args.gap, out_sr)

    # --- Summary ------------------------------------------------------------
    total_time = time.time() - t_script_start
    print('\n' + '=' * 60)
    print('SUMMARY' + (' (interrupted)' if interrupted else ''))
    print(f'  Model load time : {fmt_elapsed(load_time)}')
    print(f'  Generation time : {fmt_elapsed(gen_time)}')
    print(f'  Total runtime   : {fmt_elapsed(total_time)}')
    print(f'  Lines OK        : {ok_count}/{len(units)}')
    if failed:
        print(f'  Flagged/failed  : {len(failed)}')
        for i, text, reason in failed:
            print(f'    [{i:3d}] {truncate(text, 45)} -- {reason}')
        print('  Re-run the same command to retry missing/failed lines (existing ones are skipped).')
    print(f'  Per-line WAVs   : {out_dir}')
    print(f'  Full take       : {full_path or "not created"}')
    print('=' * 60)

    if interrupted:
        sys.exit(130)


if __name__ == '__main__':
    main()
