#!/usr/bin/env python3
"""Generate the Night Sky world's spaceship sprite.

Engine: kie.ai `google/nano-banana` (text-to-image — no reference needed, since
there is no character or existing card set to sit beside). The ship is flown
across the star field during game transitions in the space world; see
`packages/shared_ui/lib/src/widgets/spaceship_transition.dart`. A missing file
degrades to a drawn rocket, so this asset is an upgrade, never a dependency.

The sprite is drawn NOSE TO THE RIGHT on pure white, then keyed to transparent
and trimmed square — the transition flies it left-to-right and rotates it, so a
right-facing, centred, transparent sprite drops straight in. The post-process is
the emotion-card cutout (flood-fill white that reaches the border), which keeps
white *inside* the drawing (a porthole glint, a hull highlight) because those
regions are enclosed by the dark outline and never touch the frame edge.

Usage:
  pip install pillow numpy scipy requests
  # KIE_API_KEY lives in tools/voice_gen/.env; nothing auto-loads it:
  set -a; . tools/voice_gen/.env; set +a
  python scripts/generate_spaceship.py
  python scripts/generate_spaceship.py --post-only   # re-key the cached raw
  python scripts/generate_spaceship.py --force       # regenerate from the API

Output:
  packages/shared_ui/assets/worlds/spaceship.png   512px, RGBA, palettised

The raw generation is cached in .card_cache/ (gitignored) so a re-run costs
nothing and a rejected take can be inspected before regenerating.
"""

import argparse
import json
import os
import sys
import time
from pathlib import Path

import numpy as np
import requests
from PIL import Image
from scipy import ndimage

# ── Paths ─────────────────────────────────────────────────────────────
SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parent
DEST = PROJECT_ROOT / "packages" / "shared_ui" / "assets" / "worlds"
CACHE = PROJECT_ROOT / ".card_cache"

JOBS_API = "https://api.kie.ai"

# ── Output geometry ───────────────────────────────────────────────────
SPRITE_PX = 512
CONTENT = 0.92        # ship width as a fraction of the square, after trim
WHITE_CUT = 232       # channel value above which a pixel reads as page
INK_SOFT = 30.0       # edge-feather ramp, in channel values
COLORS = 255

NAME = "spaceship"

# The look is written to sit inside the Night Sky world (deep indigo sky, warm
# gold trail and ring accents) and to match the app's soft, friendly cartoon
# style — thick even outlines, flat pastel fills, nothing frightening. Nose to
# the right so it agrees with the transition's left-to-right flight.
PROMPT = (
    "Draw a single cute friendly cartoon spaceship for a young children's app, "
    "flying and pointed toward the RIGHT side of the frame.\n\n"
    "SHAPE: a rounded, chunky little rocket with a smooth capsule body, a gently "
    "pointed nose cone on the right, two small swept fins at the back-left, and "
    "one round porthole window near the front. A small warm flame and a few soft "
    "puffs of exhaust trail from the engine at the back-left. The ship looks "
    "happy and safe, like a toy — not military, not sharp, not scary.\n\n"
    "COLOURS: a soft off-white and pale lavender hull, a warm golden-yellow nose "
    "cone and fins, a sky-blue glass porthole with a small white glint, and a "
    "warm orange-and-yellow flame. These sit against the deep indigo night-sky "
    "world of the app, so the ship is bright and reads clearly on a dark sky.\n\n"
    "STYLE: a flat 2D children's picture-book illustration — thick even dark "
    "outlines of a single weight, soft flat pastel fills, small simple shapes, "
    "gently rounded, cheerful. No gradients, no textures, no cel shading, no "
    "drop shadows, no realistic rendering, no photographic look.\n\n"
    "COMPOSITION: one single spaceship, centred, filling most of the frame with "
    "an even margin on all sides, seen from the side. No pilot, no face on the "
    "ship, no planets, no stars, no other objects.\n\n"
    "BACKGROUND: plain solid pure white and completely empty. No border, no "
    "frame, no panel, no ground line, no scenery, no text, no letters, no "
    "numbers, no labels, no watermark, no logo."
)


def key() -> str:
    k = os.environ.get("KIE_API_KEY")
    if not k:
        sys.exit("KIE_API_KEY is not set (source tools/voice_gen/.env)")
    return k


def headers() -> dict:
    return {"Authorization": f"Bearer {key()}", "Content-Type": "application/json"}


# ── Generation ────────────────────────────────────────────────────────
def generate() -> Path:
    raw = CACHE / f"raw_{NAME}.png"
    if raw.exists():
        print(f"[{NAME}] cached")
        return raw

    body = {
        "model": "google/nano-banana",
        "input": {
            "prompt": PROMPT,
            "output_format": "png",
            "image_size": "1:1",
        },
    }
    r = requests.post(f"{JOBS_API}/api/v1/jobs/createTask",
                      headers=headers(), json=body, timeout=60)
    r.raise_for_status()
    d = r.json()
    if d.get("code") != 200:
        sys.exit(f"[{NAME}] createTask failed: {d}")
    task_id = d["data"]["taskId"]
    print(f"[{NAME}] -> task {task_id}")

    data = {}
    for _ in range(90):
        time.sleep(5)
        data = (requests.get(f"{JOBS_API}/api/v1/jobs/recordInfo",
                             headers=headers(), params={"taskId": task_id},
                             timeout=60).json().get("data") or {})
        if data.get("state") == "success":
            print(f"[{NAME}] {data.get('costTime')}ms, "
                  f"{data.get('creditsConsumed')} credits")
            break
        if data.get("state") == "fail":
            sys.exit(f"[{NAME}] failed: {data.get('failMsg')}")
    else:
        sys.exit(f"[{NAME}] timed out")

    url = json.loads(data["resultJson"])["resultUrls"][0]
    raw.write_bytes(requests.get(url, timeout=600).content)
    return raw


# ── Post-processing ───────────────────────────────────────────────────
def cutout(a: np.ndarray) -> np.ndarray:
    """RGB -> RGBA, removing only page white that reaches the frame border."""
    near_white = a.min(axis=2) > WHITE_CUT
    lbl, _ = ndimage.label(near_white)
    border = set(lbl[0, :]) | set(lbl[-1, :]) | set(lbl[:, 0]) | set(lbl[:, -1])
    border.discard(0)
    bg = np.isin(lbl, list(border))

    alpha = np.where(bg, 0.0, 1.0)
    ring = ndimage.binary_dilation(bg, iterations=2) & ~bg
    ink = np.clip((255 - a.min(axis=2)) / INK_SOFT, 0, 1)
    alpha = np.where(ring, np.minimum(alpha, ink), alpha)

    out = np.zeros((*a.shape[:2], 4), np.uint8)
    out[..., :3] = a.astype(np.uint8)
    out[..., 3] = (alpha * 255).astype(np.uint8)
    return out


def content_box(rgba: np.ndarray) -> tuple:
    """Bounding box of the drawing, with compression specks discarded."""
    m = rgba[..., 3] > 16
    lbl, n = ndimage.label(m)
    if n > 1:
        sizes = ndimage.sum(m, lbl, range(1, n + 1))
        keep = [i + 1 for i, s in enumerate(sizes) if s >= 0.005 * sizes.max()]
        m = np.isin(lbl, keep)
    ys, xs = np.where(m)
    return xs.min(), ys.min(), xs.max() + 1, ys.max() + 1


def postprocess(raw: Path) -> Path:
    """Key out the page, trim to the ship, re-pad square, shrink, palettise."""
    src = Image.open(raw).convert("RGB")
    rgba = cutout(np.asarray(src).astype(np.int16))
    x0, y0, x1, y1 = content_box(rgba)
    drawing = Image.fromarray(rgba).crop((x0, y0, x1, y1))

    inner = round(SPRITE_PX * CONTENT)
    scale = inner / max(drawing.width, drawing.height)
    drawing = drawing.resize((max(1, round(drawing.width * scale)),
                              max(1, round(drawing.height * scale))),
                             Image.LANCZOS)

    card = Image.new("RGBA", (SPRITE_PX, SPRITE_PX), (0, 0, 0, 0))
    card.alpha_composite(drawing, ((SPRITE_PX - drawing.width) // 2,
                                   (SPRITE_PX - drawing.height) // 2))

    DEST.mkdir(parents=True, exist_ok=True)
    out = DEST / f"{NAME}.png"
    card.quantize(colors=COLORS, method=Image.FASTOCTREE).save(out, optimize=True)
    print(f"  {out.name:16} {x1-x0:4}x{y1-y0:4} -> {SPRITE_PX}px  "
          f"{out.stat().st_size/1e3:5.0f} KB")
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--post-only", action="store_true",
                    help="skip the API, re-run post-processing on the cached raw")
    ap.add_argument("--force", action="store_true",
                    help="regenerate even if a raw is already cached")
    args = ap.parse_args()

    CACHE.mkdir(parents=True, exist_ok=True)
    raw = CACHE / f"raw_{NAME}.png"
    if args.force:
        raw.unlink(missing_ok=True)

    if args.post_only:
        if not raw.exists():
            sys.exit(f"no cached raw at {raw}")
    else:
        raw = generate()

    print("\npost-processing")
    postprocess(raw)


if __name__ == "__main__":
    main()
