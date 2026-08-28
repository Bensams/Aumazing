#!/usr/bin/env python3
"""Drive a character's mouth from an audio track, using the `talk` sprite sheet.

Amplitude-driven, not phoneme-driven. The `talk` sheet holds six mouth
openings; this measures the narration's loudness per video frame and picks the
matching opening. That is the same technique hand-drawn animation has always
used for dialogue, and at the size a mascot appears on screen it is
indistinguishable from true visemes — mouth *shape* per phoneme is only
legible on a face filling the frame.

Why not the AI lip-sync models on kie.ai (InfiniteTalk, OmniHuman): both are
built for photorealistic human faces. A chibi face — enormous eyes, a mouth a
few dozen pixels wide, flat cel shading — is exactly the input that makes them
either redraw the face realistically or fail to locate a mouth at all. This
approach cannot break the art style, because it only ever shows cells that
were already drawn.

It also works with ANY audio, so when the scratch narration is replaced with
a real recording, re-running this re-syncs to the new voice for free.

Used by `scripts/build_avp.py`; also runnable directly to eyeball one block:
  python scripts/lipsync.py bps avp_out/voice/s4_ai.wav --out /tmp/t.mov
"""

import argparse
import subprocess
import tempfile
import wave
from pathlib import Path

import imageio_ffmpeg
import numpy as np
from PIL import Image
from scipy import ndimage

PROJECT_ROOT = Path(__file__).resolve().parent.parent
SHEETS = PROJECT_ROOT / "packages" / "shared_ui" / "assets" / "characters"

GRID = (3, 2)
SILENCE = 0.08      # below this fraction of the loud reference, mouth is shut
LOUD_PCT = 92       # percentile treated as "fully open" — peaks are outliers
HOLD = 2            # min frames to keep an opening; 1 strobes, 4+ reads slack

_cache: dict[str, tuple] = {}


def ffmpeg() -> str:
    return imageio_ffmpeg.get_ffmpeg_exe()


def mouth_cells(name: str):
    """The talk sheet's cells, ordered closed -> wide open.

    The mouth is found by TEMPORAL VARIANCE across the six cells, the same
    trick the idle sheet uses to find the eyes: the talk prompt moves nothing
    else, so whatever changes is the mouth. Two refinements matter — restrict
    to the head, because slight body drift between cells otherwise dominates,
    and take the largest connected blob, because the thin outlines everywhere
    else jitter by a pixel and would otherwise win on raw threshold count.
    """
    if name in _cache:
        return _cache[name]
    sheet = Image.open(SHEETS / f"{name}_talk.png").convert("RGBA")
    cols, rows = GRID
    w, h = sheet.width // cols, sheet.height // rows
    cells = [sheet.crop(((i % cols) * w, (i // cols) * h,
                         (i % cols) * w + w, (i // cols) * h + h))
             for i in range(cols * rows)]

    arr = [np.asarray(c) for c in cells]
    lum = np.stack([a[..., :3].mean(2) * (a[..., 3] > 16) for a in arr])
    var = lum.var(0)
    head = np.zeros_like(var)
    head[:int(h * 0.55)] = var[:int(h * 0.55)]
    lbl, n = ndimage.label(head > head.max() * 0.35)
    if not n:
        raise RuntimeError(f"{name}: could not locate a mouth in {name}_talk.png")
    sums = ndimage.sum(head, lbl, range(1, n + 1))
    ys, xs = np.where(lbl == int(np.argmax(sums)) + 1)
    y0, y1, x0, x1 = ys.min(), ys.max(), xs.min(), xs.max()

    # An open mouth is a large dark shape; a closed one is a thin line.
    ink = [(255 - lum[i, y0:y1 + 1, x0:x1 + 1]).sum() for i in range(len(cells))]
    order = [int(i) for i in np.argsort(ink)]
    _cache[name] = ([cells[i] for i in order], (w, h))
    return _cache[name]


def envelope(wav: Path, fps: int, frames: int, lead: float) -> np.ndarray:
    """Per-video-frame mouth opening (0..1), with `lead` seconds of silence first."""
    with wave.open(str(wav), "rb") as w:
        sr, n = w.getframerate(), w.getnframes()
        x = np.frombuffer(w.readframes(n), dtype="<i2").astype(np.float32) / 32768.0
        if w.getnchannels() == 2:
            x = x.reshape(-1, 2).mean(1)

    step = sr / fps
    out = np.zeros(frames, np.float32)
    start = int(round(lead * fps))
    for i in range(frames):
        j = i - start
        if j < 0:
            continue
        a, b = int(j * step), int((j + 1) * step)
        if a >= len(x):
            break
        seg = x[a:b]
        out[i] = float(np.sqrt(np.mean(seg * seg))) if len(seg) else 0.0

    voiced = out[out > 0]
    if voiced.size:
        ref = np.percentile(voiced, LOUD_PCT)
        out = np.clip(out / ref, 0, 1) if ref > 0 else out
    # Median filter first: single loud frames inside a word are consonant
    # bursts, not a wider mouth, and following them literally reads as a twitch.
    out = ndimage.median_filter(out, size=3)
    out[out < SILENCE] = 0.0
    return out


def track(name: str, wav: Path, dur: float, lead: float, dest: Path,
          fps: int = 30) -> Path:
    """Write an alpha .mov of `name` talking in sync with `wav`, `dur` long."""
    cells, _ = mouth_cells(name)
    frames = int(round(dur * fps))
    level = envelope(wav, fps, frames, lead)

    idx = np.rint(level * (len(cells) - 1)).astype(int)
    # Minimum hold. Without it the index can change every frame on a fast
    # syllable, which at 30fps flickers rather than reads as speech.
    held, last, run = [], idx[0], 0
    for v in idx:
        if v != last and run < HOLD:
            v = last
        run = run + 1 if v == last else 0
        held.append(v)
        last = v

    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        # Only six distinct images exist, so write them once and hard-link the
        # sequence at them rather than re-encoding one PNG per frame.
        for i, cell in enumerate(cells):
            cell.save(tmp / f"c{i}.png")
        for f, v in enumerate(held):
            (tmp / f"f{f:05d}.png").write_bytes((tmp / f"c{v}.png").read_bytes())
        dest.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run([ffmpeg(), "-v", "error", "-y", "-framerate", str(fps),
                        "-i", str(tmp / "f%05d.png"), "-c:v", "prores_ks",
                        "-profile:v", "4444", "-pix_fmt", "yuva444p10le",
                        str(dest)], check=True)
    return dest


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("character")
    ap.add_argument("wav", type=Path)
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--lead", type=float, default=0.0)
    ap.add_argument("--fps", type=int, default=30)
    args = ap.parse_args()

    with wave.open(str(args.wav), "rb") as w:
        dur = w.getnframes() / w.getframerate()
    track(args.character, args.wav, dur + args.lead, args.lead, args.out, args.fps)
    print(f"{args.out}  {dur + args.lead:.2f}s")


if __name__ == "__main__":
    main()
