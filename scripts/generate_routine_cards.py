#!/usr/bin/env python3
"""Generate the fourteen Ano'ng Susunod? routine cards, starring BPS and Reiz.

Engine: kie.ai `google/nano-banana-edit`. Each card is generated from TWO
reference images in one call:

  1. the character's chibi artwork — carries identity (face, hair, outfit)
  2. a strip of three shipped routine cards — carries the drawing style

Two references rather than one because the two things we need are pulled from
different places. Prompted from the chibi alone the model returns chibi art:
huge head, cel shading, soft outlines — a different book from the rest of the
card set. Prompted from the style strip alone it returns the generic child the
strip already shows. Naming which reference governs what is what gets BPS's
plaid shirt drawn in the card set's flat sticker style.

Casting is by routine, so a child working through one sequence sees one
familiar face:

  Morning + Mealtime -> BPS        Bedtime + Playtime -> Reiz

`brush_teeth` and `wash_hands` each belong to two routines, so they cannot
follow that rule; they are pinned to one character apiece and appear in both.

Usage:
  pip install pillow numpy scipy requests
  export KIE_API_KEY=...           # never commit this
  python scripts/generate_routine_cards.py                  # all fourteen
  python scripts/generate_routine_cards.py --only wake,bath
  python scripts/generate_routine_cards.py --post-only      # re-run the
                                                            # post-process on
                                                            # cached raw output

Output:
  packages/shared_ui/assets/routine_cards/{name}.png   512px, RGBA, palettised

Raw generations are cached in .card_cache/ (gitignored) so a re-run costs
nothing for cards that already came back, and a rejected card can be inspected
before it is regenerated.
"""

import argparse
import base64
import json
import os
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import numpy as np
import requests
from PIL import Image
from scipy import ndimage

# ── Paths ─────────────────────────────────────────────────────────────
SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parent
DEST = PROJECT_ROOT / "packages" / "shared_ui" / "assets" / "routine_cards"
CHARACTER_ART = PROJECT_ROOT / "packages" / "assets" / "images" / "Character"
CACHE = PROJECT_ROOT / ".card_cache"

JOBS_API = "https://api.kie.ai"
UPLOAD_API = "https://kieai.redpandaai.co"      # NOT api.kie.ai; the docs are wrong

# ── Output geometry ───────────────────────────────────────────────────
CARD_PX = 512         # what ships; the card renders far smaller than this
CONTENT = 0.94        # drawing width as a fraction of the square, after trim
WHITE_CUT = 232       # channel value above which a pixel reads as page
INK_SOFT = 30.0       # edge-feather ramp, in channel values
COLORS = 255          # adaptive palette; the art is flat, so this is lossless
                      # to the eye at the size a card actually draws

# ── References ────────────────────────────────────────────────────────
# `face` and `clothes` are kept apart because bedtime needs to change one
# without touching the other: Reiz out of his blazer must still be Reiz.
CHARACTERS = {
    "bps": {
        "art": CHARACTER_ART / "BPS_chibi.png",
        "face": ("a cheerful young Filipino boy with fair skin, warm brown "
                 "eyes, and messy spiky black hair"),
        # Spelled out rather than left to the reference image because
        # nano-banana reliably drops the garment it is not told about, and BPS
        # without his plaid overshirt is just a boy in a white tee.
        "clothes": ("an open pale blue and orange plaid button-up shirt over a "
                    "plain white t-shirt, light grey trousers and white "
                    "sneakers"),
    },
    "reiz": {
        "art": CHARACTER_ART / "Reiz_Chibi_nb.png",
        "face": ("a friendly young Filipino boy with fair skin, dark grey "
                 "eyes, and soft wavy black hair"),
        "clothes": ("an open black blazer over a plain white t-shirt, a thin "
                    "silver pendant necklace, black trousers and black shoes"),
    },
}

for _c in CHARACTERS.values():
    _c["look"] = f"{_c['face']}, wearing {_c['clothes']}"

# The style reference: three finished cards side by side, committed as one
# image rather than rebuilt from the asset folder each run.
#
# It was derived from the asset folder at first, and that is a trap. A run that
# regenerates a card the strip is built from leaves the NEXT run learning its
# style from that card — so when `play` came back with a panel border drawn
# around it, the following run was handed the border as the house style and
# duly drew another one. A style reference has to be a fixed thing that a bad
# take cannot get into.
#
# Deliberately three DIFFERENT subjects — a plain figure, a figure with props,
# and a figure in a scene — so the model reads a style rather than copying one
# drawing. Rebuild it with --rebuild-style-ref after a deliberate style change.
STYLE_REF = SCRIPT_DIR / "assets" / "routine_card_style.png"
STYLE_CARDS = ["brush_teeth", "eat", "wash_hands"]

STYLE = (
    "STYLE: copy the drawing style of the second reference image exactly — a "
    "flat 2D children's picture-card illustration, simple and clean, with "
    "thick even dark charcoal outlines of a single weight, soft flat pastel "
    "fill colours (mint green, sky blue, peach, butter yellow, lavender), "
    "small round rosy cheeks, simple dot eyes and a small smile. No gradients, "
    "no textures, no cel shading, no drop shadows, no outline thickness "
    "variation, no sketchy or painterly marks. "
    "IMPORTANT: this is NOT the chibi style of the first reference image — do "
    "not draw a large chibi head, do not use cel shading or soft rendering. "
    "Normal picture-book child proportions, roughly five heads tall. "
    "COMPOSITION: one single scene, centred, filling the frame with a clear "
    "even margin on all four sides. Exactly one child in the picture and no "
    "other people. "
    "BACKGROUND: plain solid pure white and completely empty. No border, no "
    "frame, no panel, no rounded card outline drawn around the scene, no "
    "floor line, no wall, no background scenery, no text, no letters, no "
    "numbers, no labels, no captions, no watermark, no logo."
)

# name -> (character, scene) or (character, scene, outfit).
#
# One line of scene each, because a card that needs a paragraph to describe is
# a card a two-year-old will not read at a glance.
#
# `outfit` overrides the character's default clothes. Bedtime needs it: pinned
# to his blazer, Reiz came back asleep in a suit jacket, which contradicts the
# pyjamas card immediately before it in the same routine. The sequence is the
# thing being taught, so it has to survive contact with the costume.
CARDS = {
    # ── Morning (umaga) — BPS ────────────────────────────────────────
    "wake": ("bps",
             "The boy has just woken up: he is sitting up in bed with the "
             "pale blue blanket across his lap, both arms stretched high "
             "above his head in a big waking stretch, eyes open, mouth open "
             "in a wide yawn, with a warm yellow sun shining beside him."),
    "brush_teeth": ("bps",
                    "The boy is brushing his teeth: he stands facing the "
                    "viewer holding a blue toothbrush to his open smiling "
                    "mouth, white teeth and a little white foam showing."),
    "breakfast": ("bps",
                  "The boy is eating breakfast: he sits behind a large mint "
                  "green bowl of steaming porridge that stands on a small "
                  "table in front of him, holding a wooden spoon up in one "
                  "hand, with three curls of steam rising from the bowl."),
    "school": ("bps",
               "The boy is going to school: he walks cheerfully to the right, "
               "wearing a small mint green backpack and waving one hand, in "
               "front of a small peach school building with a blue pitched "
               "roof, a yellow door, two square windows and a little flag on "
               "top."),
    # ── Mealtime (kainan) — sit / eat / clear are BPS ────────────────
    "sit_at_table": ("bps",
                     "The boy is sitting down at the table: he sits upright "
                     "and still on a wooden chair pulled up to a small round "
                     "wooden table, both hands resting quietly on the table "
                     "top, waiting politely. The table is EMPTY — no plate, "
                     "no bowl, no food and no cutlery anywhere in the "
                     "picture."),
    "eat": ("bps",
            "The boy is eating a meal: he sits at a table holding a fork up "
            "to his smiling mouth, taking a bite, with a full white plate of "
            "food on the table in front of him."),
    "clear_plate": ("bps",
                    "The boy is clearing his plate away: he stands and walks "
                    "to the right carrying an empty white plate in both "
                    "hands, towards a pale blue kitchen sink at the right of "
                    "the picture."),
    # ── Bedtime (gabi) — Reiz ────────────────────────────────────────
    "bath": ("reiz",
             "The boy is taking a bath: only his head, shoulders and one "
             "waving arm show above the white foam in a lavender bathtub with "
             "curved feet, with round soap bubbles in the air and a small "
             "yellow rubber duck floating beside him. He is smiling happily."),
    "pajamas": ("reiz",
                "The boy is putting on his pyjamas: he stands smiling in "
                "lavender star-patterned pyjama trousers, holding up a "
                "matching lavender star-patterned pyjama top in front of him "
                "with both hands, about to put it on.",
                "a plain white t-shirt and lavender pyjama trousers with a "
                "small yellow star pattern, holding the matching pyjama top"),
    "sleep": ("reiz",
              "The boy is asleep: he lies on his back in bed with his head on "
              "a white pillow and a mint green blanket pulled up to his chest, "
              "both eyes peacefully closed as two curved lines, a small "
              "content smile on his face.",
              "lavender pyjamas with a small yellow star pattern"),
    # ── Playtime (laro) — Reiz ───────────────────────────────────────
    # The shelf is described as attached to a wall bracket because "a shelf
    # above him" alone came back as a plank floating in white space with the
    # ball hovering off it.
    "get_toy": ("reiz",
                "The boy is getting a toy out: he stands reaching up with one "
                "hand and takes hold of a butter yellow ball that is sitting "
                "ON TOP of a low wooden shelf beside him, looking up at the "
                "ball with a happy expression. The shelf is a simple wooden "
                "box shelf standing on the floor, no higher than his "
                "shoulders, and the ball rests directly on its top surface, "
                "touching it. The boy is drawn LARGE and fills most of the "
                "picture. Do NOT draw a square, a panel, a frame or any "
                "outlined box around the scene — the drawing sits directly on "
                "empty white with nothing enclosing it."),
    # First take drew the whole scene inside a bordered white panel, which the
    # background key cannot remove — it is ink, not page. Hence the repeat.
    "play": ("reiz",
             "The boy is playing: he sits on the floor on a small round mat, "
             "smiling and building a tower out of mint green, sky blue and "
             "peach toy blocks with both hands, with a few loose blocks "
             "scattered around him. He is drawn LARGE and fills most of the "
             "picture. Do NOT draw a square, a panel, a frame or any outlined "
             "box around the scene — the drawing sits directly on empty white "
             "with nothing enclosing it."),
    "put_away": ("reiz",
                 "The boy is tidying his toys away: he kneels beside an open "
                 "peach toy box and drops a mint green ball and a toy rabbit "
                 "down into it with both hands, smiling."),
    # ── Shared step — pinned to Reiz ─────────────────────────────────
    "wash_hands": ("reiz",
                   "The boy is washing his hands: he stands on a small wooden "
                   "step stool at a white sink, rubbing both soapy hands "
                   "together under water running from a yellow tap, with "
                   "round white soap bubbles in the air and a bottle of soap "
                   "beside the sink."),
}


def key() -> str:
    k = os.environ.get("KIE_API_KEY")
    if not k:
        sys.exit("KIE_API_KEY is not set")
    return k


def headers() -> dict:
    return {"Authorization": f"Bearer {key()}", "Content-Type": "application/json"}


# ── References ────────────────────────────────────────────────────────
MAX_REF_PX = 1024     # the model renders far smaller; more is only slower upload


def character_ref(name: str) -> Path:
    """The character's artwork, flattened onto white and scaled for upload."""
    src = CHARACTERS[name]["art"]
    if not src.exists():
        sys.exit(f"{name}: character artwork not found at {src}")
    im = Image.open(src).convert("RGBA")
    flat = Image.new("RGB", im.size, (255, 255, 255))
    flat.paste(im, (0, 0), im)
    flat.thumbnail((MAX_REF_PX, MAX_REF_PX), Image.LANCZOS)
    out = CACHE / f"ref_{name}.png"
    flat.save(out)
    return out


def build_style_ref() -> Path:
    """Re-derive the committed style strip from three cards in the asset folder.

    Only run deliberately, and only from cards that have been eyeballed — see
    the note on [STYLE_REF].
    """
    cells = []
    for name in STYLE_CARDS:
        p = DEST / f"{name}.png"
        if not p.exists():
            sys.exit(f"style reference missing: {p}")
        im = Image.open(p).convert("RGBA")
        flat = Image.new("RGB", im.size, (255, 255, 255))
        flat.paste(im, (0, 0), im)
        cells.append(flat.resize((512, 512), Image.LANCZOS))

    strip = Image.new("RGB", (512 * len(cells), 512), (255, 255, 255))
    for i, c in enumerate(cells):
        strip.paste(c, (i * 512, 0))
    STYLE_REF.parent.mkdir(parents=True, exist_ok=True)
    strip.save(STYLE_REF)
    print(f"style reference rebuilt from {', '.join(STYLE_CARDS)} -> "
          f"{STYLE_REF.relative_to(PROJECT_ROOT)}")
    return STYLE_REF


def upload(path: Path) -> str:
    b64 = base64.b64encode(path.read_bytes()).decode()
    r = requests.post(f"{UPLOAD_API}/api/file-base64-upload", headers=headers(),
                      json={"base64Data": f"data:image/png;base64,{b64}",
                            "uploadPath": "images/aumazing",
                            "fileName": path.name},
                      timeout=300)
    r.raise_for_status()
    d = r.json()
    if not d.get("success"):
        sys.exit(f"upload failed: {d}")
    return d["data"]["downloadUrl"]


# ── Generation ────────────────────────────────────────────────────────
def prompt_for(name: str) -> str:
    character, scene, outfit = (CARDS[name] + (None,))[:3]
    wearing = (CHARACTERS[character]["look"] if outfit is None else
               f"{CHARACTERS[character]['face']}, wearing {outfit}")
    return (
        "Draw a single children's routine picture card.\n\n"
        "The FIRST reference image is the character. Keep him recognisably the "
        f"same boy: {wearing}. Same hair shape, same hair colour, same eye "
        "colour and same skin tone in every card. He does NOT carry a book or "
        "any other object except what the scene below describes.\n\n"
        "The SECOND reference image shows three finished cards from the same "
        "set. Match their drawing style, line weight, colour palette and "
        "framing exactly, so this card belongs beside them.\n\n"
        f"SCENE: {scene}\n\n" + STYLE
    )


def generate(name: str, char_urls: dict, style_url: str) -> Path:
    raw = CACHE / f"raw_{name}.png"
    if raw.exists():
        print(f"[{name}] cached")
        return raw

    character = CARDS[name][0]
    body = {
        "model": "google/nano-banana-edit",
        "input": {
            "prompt": prompt_for(name),
            "image_urls": [char_urls[character], style_url],
            "output_format": "png",
            "image_size": "1:1",
        },
    }
    r = requests.post(f"{JOBS_API}/api/v1/jobs/createTask",
                      headers=headers(), json=body, timeout=60)
    r.raise_for_status()
    d = r.json()
    if d.get("code") != 200:
        sys.exit(f"[{name}] createTask failed: {d}")
    task_id = d["data"]["taskId"]
    print(f"[{name}] {character} -> task {task_id}")

    data = {}
    for _ in range(90):
        time.sleep(5)
        data = (requests.get(f"{JOBS_API}/api/v1/jobs/recordInfo",
                             headers=headers(), params={"taskId": task_id},
                             timeout=60).json().get("data") or {})
        if data.get("state") == "success":
            print(f"[{name}] {data.get('costTime')}ms, "
                  f"{data.get('creditsConsumed')} credits")
            break
        if data.get("state") == "fail":
            sys.exit(f"[{name}] failed: {data.get('failMsg')}")
    else:
        sys.exit(f"[{name}] timed out")

    url = json.loads(data["resultJson"])["resultUrls"][0]
    raw.write_bytes(requests.get(url, timeout=600).content)
    return raw


# ── Post-processing ───────────────────────────────────────────────────
def cutout(a: np.ndarray) -> np.ndarray:
    """RGB -> RGBA, removing only page white that reaches the frame border.

    A plain white key would punch through white *inside* a drawing — teeth,
    bath foam, a plate, BPS's t-shirt. Those regions are enclosed by the dark
    outline so they never connect to the border, and they survive.
    """
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
    """Bounding box of the drawing, with compression specks discarded.

    JPEG-ish ringing along the page edge survives the white key as isolated
    dark pixels. A raw min/max over the alpha channel then reports the drawing
    as filling the whole page, and every card ends up trimmed to nothing.
    """
    m = rgba[..., 3] > 16
    lbl, n = ndimage.label(m)
    if n > 1:
        sizes = ndimage.sum(m, lbl, range(1, n + 1))
        keep = [i + 1 for i, s in enumerate(sizes) if s >= 0.005 * sizes.max()]
        m = np.isin(lbl, keep)
    ys, xs = np.where(m)
    return xs.min(), ys.min(), xs.max() + 1, ys.max() + 1


def postprocess(raw: Path, name: str) -> Path:
    """Key out the page, trim to the drawing, re-pad square, shrink, palettise.

    Squaring every card here is what lets the game position art with one rule
    instead of fourteen: `drawRoutineArt` draws into a square box and trusts
    the picture to already be centred in one.
    """
    src = Image.open(raw).convert("RGB")
    rgba = cutout(np.asarray(src).astype(np.int16))
    x0, y0, x1, y1 = content_box(rgba)
    drawing = Image.fromarray(rgba).crop((x0, y0, x1, y1))

    inner = round(CARD_PX * CONTENT)
    scale = inner / max(drawing.width, drawing.height)
    drawing = drawing.resize((max(1, round(drawing.width * scale)),
                              max(1, round(drawing.height * scale))),
                             Image.LANCZOS)

    card = Image.new("RGBA", (CARD_PX, CARD_PX), (0, 0, 0, 0))
    card.alpha_composite(drawing, ((CARD_PX - drawing.width) // 2,
                                   (CARD_PX - drawing.height) // 2))

    out = DEST / f"{name}.png"
    card.quantize(colors=COLORS, method=Image.FASTOCTREE).save(out, optimize=True)
    print(f"  {out.name:18} {x1-x0:4}x{y1-y0:4} -> {CARD_PX}px  "
          f"{out.stat().st_size/1e3:5.0f} KB")
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", help="comma-separated subset of card names")
    ap.add_argument("--post-only", action="store_true",
                    help="skip the API, re-run post-processing on cached raws")
    ap.add_argument("--force", action="store_true",
                    help="regenerate even if a raw is already cached")
    ap.add_argument("--jobs", type=int, default=4, help="concurrent generations")
    ap.add_argument("--rebuild-style-ref", action="store_true",
                    help=f"re-derive {STYLE_REF.name} from {', '.join(STYLE_CARDS)}")
    args = ap.parse_args()

    if args.rebuild_style_ref:
        build_style_ref()

    names = args.only.split(",") if args.only else list(CARDS)
    for n in names:
        if n not in CARDS:
            sys.exit(f"unknown card: {n}")
    CACHE.mkdir(parents=True, exist_ok=True)

    if args.force:
        for n in names:
            (CACHE / f"raw_{n}.png").unlink(missing_ok=True)

    if args.post_only:
        raws = {n: CACHE / f"raw_{n}.png" for n in names}
        missing = [n for n, p in raws.items() if not p.exists()]
        if missing:
            sys.exit(f"no cached raw for: {', '.join(missing)}")
    else:
        # Uploaded once and shared by every card: the references are what make
        # the set consistent, so they must be byte-identical across the batch.
        if not STYLE_REF.exists():
            sys.exit(f"style reference missing: {STYLE_REF}\n"
                     f"rebuild it with --rebuild-style-ref")
        style_url = upload(STYLE_REF)
        char_urls = {c: upload(character_ref(c)) for c in CHARACTERS}
        print(f"style   -> {style_url}")
        for c, u in char_urls.items():
            print(f"{c:7} -> {u}")

        with ThreadPoolExecutor(max_workers=args.jobs) as ex:
            futs = {n: ex.submit(generate, n, char_urls, style_url)
                    for n in names}
            raws = {n: f.result() for n, f in futs.items()}

    print("\npost-processing")
    for n in names:
        postprocess(raws[n], n)


if __name__ == "__main__":
    main()
