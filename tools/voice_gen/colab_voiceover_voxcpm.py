"""
VoxCPM2 batch voice-over generator — Google Colab (free T4 GPU)
========================================================================
Same job as colab_voiceover_chatterbox.py, but using VoxCPM2 (OpenBMB,
Apache-2.0), which additionally covers Tagalog. It does NOT cover
Cebuano/Bisaya -- see the language note below.

SETUP — run this in a Colab cell BEFORE the generation cell:

    !pip install voxcpm soundfile numpy

    # Requirements per the VoxCPM2 docs: Python >=3.10,<3.13 (Colab's
    # default 3.12 is fine), PyTorch >=2.5.0, CUDA >=12.0, ~8GB VRAM
    # (the free T4 has 16GB, so it fits, but close other GPU-heavy cells
    # first if you hit CUDA OOM). from_pretrained() auto-downloads the
    # model from Hugging Face on first run.
    #
    # If pip reports a dependency conflict, or imports fail afterward,
    # Runtime > Restart session (NOT "Disconnect and delete runtime")
    # and re-run the generation cell -- no need to reinstall.
    #
    # KNOWN ISSUE: VoxCPM2 torch.compile()s part of itself on load. The T4
    # doesn't support bf16 compilation (you'll see repeated warnings about
    # this -- harmless, skipped automatically), but on some torch/einops
    # version pairs the Dynamo tracer crashes outright while compiling
    # (e.g. "torch._dynamo.exc.Unsupported: call_method ... isalnum"),
    # hard-aborting the model load -- torch._dynamo.config.suppress_errors
    # does NOT catch this (the crashing region appears to be compiled with
    # fullgraph=True, which disallows the usual graph-break fallback). This
    # script instead sets the TORCHDYNAMO_DISABLE=1 environment variable
    # before torch is imported at all, which disables torch.compile
    # everywhere and forces plain eager execution -- slower, but it loads.
    # If you still hit a hard crash during loading, restart the session
    # and try `!pip install -U einops` before re-running.

USAGE — upload your reference clip and script, then from a cell:

    !python colab_voiceover_voxcpm.py /content/reference.wav /content/script.txt \
        --out /content/drive/MyDrive/voiceover_out

    # --out on Google Drive is strongly recommended (see below).

LANGUAGE: VoxCPM2 supports 30 languages including Tagalog, auto-detected
from the text -- no language tag needed. It does NOT support Cebuano/
Bisaya; do not use this for that language (see project notes on why
mms-tts-ceb isn't a viable substitute either -- non-commercial license,
no cloning, no emotion control).

SCRIPT FILE FORMAT — two supported, chosen by file extension:

  .txt  Plain text, one VO line per line. Blank lines and lines starting
        with "#" are skipped. A line with multiple sentences is split on
        sentence-ending punctuation, so each sentence becomes its own clip.
        Every line gets the same --style descriptor (if any).
        Output files: out/<stem>/<stem>_0001.wav, _0002.wav, ...

  .csv  Columns: path,text,style,cfg_value,inference_timesteps
        - path: output file (without .wav), may include subfolders, e.g.
          "colors/Gold" -> out/<stem>/colors/Gold.wav
        - text: what gets spoken
        - style: optional free-text style/emotion descriptor for this
          line, e.g. "excited, bouncy, cheerful kid's voice" -- see
          EXPRESSIVENESS below. Overrides --style for this row. Leave
          blank to use --style (if given) or no style guidance at all.
        - cfg_value, inference_timesteps: optional per-row overrides of
          the --cfg-value / --inference-timesteps CLI defaults.

EXPRESSIVENESS / EMOTION
-----------------------------------
VoxCPM2 has no numeric emotion knob (unlike Chatterbox's exaggeration/
cfg_weight). Instead it reads a natural-language style description
written in parentheses at the start of the line, e.g.:

    (excited, bouncy, cheerful kid's voice) We did it! Great job!

This script builds that automatically from --style / the CSV "style"
column -- write the descriptor text only (no parentheses) and it gets
wrapped for you. Keep descriptors short (gender/age/tone/emotion/pace is
the documented sweet spot, e.g. "young woman, gentle and sweet voice" or
"slightly faster, cheerful tone").

Two things worth knowing:
  - Style guidance only takes effect in voice-cloning mode (i.e. when a
    reference clip is supplied). This script always supplies one, so
    style descriptors are always active.
  - --cfg-value controls how strongly the model follows the style
    description (and the reference voice) -- default 2.0; raise it if
    style descriptors seem to be getting ignored, at some risk of a
    stiffer, less natural read.
  - This has not been tuned/validated end-to-end by hand -- audition a
    few style phrases on real lines before trusting a full batch.

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

# Must be set before torch is imported anywhere (including by voxcpm) --
# a runtime torch._dynamo.config flag set after import is not enough to
# stop VoxCPM2's internal fullgraph-compiled regions from hard-crashing
# on the T4 (see KNOWN ISSUE note above). This forces eager execution
# everywhere, no torch.compile at all.
os.environ.setdefault('TORCHDYNAMO_DISABLE', '1')

import numpy as np

DEFAULT_CFG_VALUE = 2.0
DEFAULT_TIMESTEPS = 10


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

    lines = []
    for raw_line in raw.splitlines():
        line = raw_line.strip()
        if not line or line.startswith('#'):
            continue
        for sentence in re.split(r'(?<=[.!?])\s+', line):
            sentence = sentence.strip()
            if sentence:
                lines.append(sentence)

    if not lines:
        raise ValueError(
            f'No speakable lines found in script (only blanks/comments): {script_path}'
        )
    return [
        {'rel': f'{i + 1:04d}', 'text': t, 'style': None, 'cfg_value': None, 'inference_timesteps': None}
        for i, t in enumerate(lines)
    ]


def load_units_csv(script_path):
    with open(script_path, encoding='utf-8-sig', newline='') as f:
        rows = list(csv.DictReader(f))

    units = []
    for n, row in enumerate(rows, 2):  # row 1 is the header
        rel = (row.get('path') or '').strip()
        text = (row.get('text') or '').strip()
        if not rel or not text:
            print(f'  (row {n}: missing path/text, skipped)')
            continue
        style = (row.get('style') or '').strip()
        cfgv = (row.get('cfg_value') or '').strip()
        ts = (row.get('inference_timesteps') or '').strip()
        units.append({
            'rel': rel,
            'text': text,
            'style': style or None,
            'cfg_value': float(cfgv) if cfgv else None,
            'inference_timesteps': int(ts) if ts else None,
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
    """VoxCPM2 documents a numpy return; accept a torch tensor too, just in case."""
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
        description='VoxCPM2 batch voice-over generator (Colab / T4 GPU). Tagalog-capable; not Cebuano.'
    )
    ap.add_argument('ref_audio', help='Reference voice clip to clone (WAV/MP3, ~10-30s)')
    ap.add_argument('script_file', help='.txt (one line per VO line) or .csv (path,text,style,cfg_value,inference_timesteps)')
    ap.add_argument(
        '--out', default='out',
        help='Output directory root (default: ./out). Use a mounted Drive path for long batches.',
    )
    ap.add_argument('--device', default='auto', help='auto | cpu | cuda | cuda:0 | mps (default: auto)')
    ap.add_argument(
        '--style', default=None,
        help='Style/emotion descriptor applied to every line (CSV "style" column overrides per-row), '
             'e.g. "excited, bouncy, cheerful kid\'s voice". No parentheses needed -- added automatically.',
    )
    ap.add_argument('--cfg-value', type=float, default=DEFAULT_CFG_VALUE, help='Guidance scale (CSV rows can override)')
    ap.add_argument('--inference-timesteps', type=int, default=DEFAULT_TIMESTEPS, help='Diffusion steps, 4-30 (CSV rows can override)')
    ap.add_argument('--seed', type=int, default=None, help='Fix the seed for reproducible output (default: unset/random)')
    ap.add_argument('--normalize', action='store_true', help='Expand numbers and dates in the text before synthesis')
    ap.add_argument('--denoise', action='store_true', help='Denoise the reference clip before cloning (loads the denoiser submodule too)')
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

    try:
        import torch
    except ImportError as e:
        sys.exit(f'torch is not importable ({e}). Run the install cell (see the top of this file) first.')

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
    print(f'Loading VoxCPM2 (device={args.device}, first run downloads model weights)...')
    t_load_start = time.time()
    try:
        from voxcpm import VoxCPM
        model = VoxCPM.from_pretrained(
            'openbmb/VoxCPM2',
            load_denoiser=args.denoise,
            device=args.device,
        )
    except oom_error:
        sys.exit(
            'CUDA out of memory while loading the model. Free the GPU '
            '(Runtime > Restart session) and try again with --device cpu if it recurs.'
        )
    except ImportError as e:
        sys.exit(
            f'voxcpm is not importable ({e}).\n'
            'If you already ran the install cell, this is usually a dependency version '
            'conflict rather than a missing package -- run:\n'
            '  !python -c "from voxcpm import VoxCPM"\n'
            'in a Colab cell to see the full traceback, then fix/reinstall that specific '
            'package (Runtime > Restart session first if numpy/torch was involved).'
        )
    load_time = time.time() - t_load_start
    model_sr = model.tts_model.sample_rate
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
                style = unit['style'] if unit['style'] is not None else args.style
                prompt = f'({style}) {unit["text"]}' if style else unit['text']
                cfg_value = unit['cfg_value'] if unit['cfg_value'] is not None else args.cfg_value
                timesteps = unit['inference_timesteps'] if unit['inference_timesteps'] is not None else args.inference_timesteps

                gen_kwargs = dict(
                    text=prompt,
                    reference_wav_path=args.ref_audio,
                    cfg_value=cfg_value,
                    inference_timesteps=timesteps,
                    normalize=args.normalize,
                    denoise=args.denoise,
                )
                if args.seed is not None:
                    gen_kwargs['seed'] = args.seed

                wav = model.generate(**gen_kwargs)
                x = to_numpy(wav)
                if x.size == 0:
                    raise RuntimeError('model produced no audio')

                os.makedirs(os.path.dirname(path), exist_ok=True)
                sf.write(path, x, model_sr, subtype='PCM_16')

                ok_count += 1
                print(f'[{i:3d}/{len(units)}] {truncate(unit["text"]):<56} '
                      f'{time.time() - line_t0:5.2f}s  elapsed {fmt_elapsed(time.time() - t_gen_start)}')

            except oom_error as e:
                if oom_error is RuntimeError and 'out of memory' not in str(e).lower():
                    raise
                print(f'[{i:3d}/{len(units)}] {truncate(unit["text"]):<56} CUDA OUT OF MEMORY -- skipped')
                failed.append((i, unit['text'], 'CUDA out of memory'))
                if torch.cuda.is_available():
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
    full_path = build_full_take(paths, out_dir, stem, args.gap, model_sr)

    # --- Summary ------------------------------------------------------------
    total_time = time.time() - t_script_start
    print('\n' + '=' * 60)
    print('SUMMARY' + (' (interrupted)' if interrupted else ''))
    print(f'  Model load time : {fmt_elapsed(load_time)}')
    print(f'  Generation time : {fmt_elapsed(gen_time)}')
    print(f'  Total runtime   : {fmt_elapsed(total_time)}')
    print(f'  Lines OK        : {ok_count}/{len(units)}')
    if failed:
        print(f'  Lines FAILED    : {len(failed)}')
        for i, text, reason in failed:
            print(f'    [{i:3d}] {truncate(text, 45)} -- {reason}')
        print('  Re-run the same command to retry failed/missing lines (existing ones are skipped).')
    print(f'  Per-line WAVs   : {out_dir}')
    print(f'  Full take       : {full_path or "not created"}')
    print('=' * 60)

    if interrupted:
        sys.exit(130)


if __name__ == '__main__':
    main()
