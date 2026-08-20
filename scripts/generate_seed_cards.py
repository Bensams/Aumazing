#!/usr/bin/env python3
"""Generate "seed" object picture cards — a reusable content bank for the games.

A *seed* is a single everyday object (an animal, a fruit, a toy …) drawn as one
clean picture card. Games that today show objects as emoji (Sari-Sari Sort) or
vector glyphs (Trace It) can instead pull real drawn art from this bank; each
seed also has naming voice-over lines (see `generate_seed_lines.py`) and both
are indexed by `packages/shared_ui/assets/seed_cards/seeds.json`.

Engine: kie.ai `google/nano-banana-edit`. This is the object-card half of
`generate_emotion_cards.py` with the character dropped — read that file's header
first; every hard-won rule there (the white-to-border cutout, the anti-panel
clause, squaring every card) applies here unchanged. The two differences:

  1. ONE reference image, not two. These cards have no character in them, so the
     only thing a reference has to carry is the drawing STYLE — supplied by the
     same `routine_card_style.png` strip the routine and emotion cards use, so a
     seed card sits beside them drawn by the same hand. There is deliberately no
     identity reference: a seed is a generic object, not a specific one.
  2. The subject is DESCRIBED AS GEOMETRY, exactly like the emotion faces. Ask
     for "a dog" and the model returns its average dog, which drifts breed and
     pose between cards; ask for "a sitting puppy seen from the front, facing the
     viewer, upright ears, round head" and the set stays consistent enough that a
     child reads them as one family of pictures.

Everything is deliberately gentle and cute — friendly cartoon animals, no teeth,
no fear, no predator/prey pairing. This bank is for autistic children and the
same "eyeball every card" rule from SPRITES.md holds: the measurement here is a
human looking at the picture and asking "is this obviously a <thing>, and is it
friendly?"

Usage:
  pip install pillow numpy scipy requests
  export KIE_API_KEY=...           # never commit this
  python scripts/generate_seed_cards.py                    # every seed
  python scripts/generate_seed_cards.py --category animals  # one category
  python scripts/generate_seed_cards.py --only dog,cat
  python scripts/generate_seed_cards.py --post-only         # re-run post-process
                                                            # on cached raws

Output:
  packages/shared_ui/assets/seed_cards/{category}/{slug}.png  512px RGBA palettised

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
DEST = PROJECT_ROOT / "packages" / "shared_ui" / "assets" / "seed_cards"
CACHE = PROJECT_ROOT / ".card_cache"
STYLE_REF = SCRIPT_DIR / "assets" / "routine_card_style.png"

JOBS_API = "https://api.kie.ai"
UPLOAD_API = "https://kieai.redpandaai.co"      # NOT api.kie.ai; the docs are wrong

# ── Output geometry (identical to the other card sets) ────────────────
CARD_PX = 512
CONTENT = 0.90        # a little more breathing room than the faces' 0.94
WHITE_CUT = 232       # channel value above which a pixel reads as page
INK_SOFT = 30.0       # edge-feather ramp, in channel values
COLORS = 255
MAX_REF_PX = 1024

# ── Shared style block ────────────────────────────────────────────────
# Copied verbatim from generate_emotion_cards.py so seed cards are drawn in the
# exact same hand as the routine and emotion sets. If that block is ever
# retuned, retune it here too — the two must not drift apart.
STYLE = (
    "STYLE: copy the drawing style of the reference image exactly — a flat 2D "
    "children's picture-card illustration, simple and clean, with thick even "
    "dark charcoal outlines of a single weight, soft flat pastel fill colours "
    "(mint green, sky blue, peach, butter yellow, lavender, rose pink), small "
    "round rosy cheeks and simple dot eyes. No gradients, no textures, no cel "
    "shading, no drop shadows, no outline thickness variation, no sketchy or "
    "painterly marks. "
    "COMPOSITION: one single object, centred, filling the frame with a clear "
    "even margin on all four sides. Nothing else in the picture at all. "
    "BACKGROUND: plain solid pure white and completely empty. No border, no "
    "frame, no panel, no rounded card outline drawn around the object, no floor "
    "line, no shadow, no wall, no background scenery, no text, no letters, no "
    "numbers, no labels, no captions, no watermark, no logo."
)

# A panel drawn around the object is INK, not page, so the white key in `cutout`
# cannot remove it — it survives as a box the card is trapped inside. Reused
# from the emotion cards, where get_toy/play came back framed.
NOPANEL = (
    " Do NOT draw a square, a panel, a frame or any outlined box around the "
    "object — the drawing sits directly on empty white with nothing enclosing "
    "it.")

# ── The seeds ─────────────────────────────────────────────────────────
# Each entry: slug -> {category, en, tl, ceb, subject}
#
# `subject` is the object described as GEOMETRY and pose, not just named — see
# the header. Kept friendly and cute throughout: rounded shapes, front-facing,
# a small smile, no teeth, no menace. The tl/ceb names feed the voice lines and
# the manifest; keep them in sync with generate_seed_lines.py.
SEEDS = {
    # ── Animals (pilot) ──────────────────────────────────────────────
    "dog": {
        "category": "animals", "en": "Dog", "tl": "Aso", "ceb": "Iro",
        "subject": (
            "a cute cartoon puppy sitting and facing the viewer: a round head "
            "with two floppy ears, big friendly round eyes, a small oval black "
            "nose and a gentle closed smile, light tan fur, sitting upright on "
            "its haunches with front paws together. Cute and friendly, mouth "
            "closed, no teeth." + NOPANEL),
    },
    "cat": {
        "category": "animals", "en": "Cat", "tl": "Pusa", "ceb": "Iring",
        "subject": (
            "a cute cartoon kitten sitting and facing the viewer: a round head "
            "with two upright pointed triangular ears, big friendly round eyes, "
            "a tiny pink triangular nose, small whiskers and a gentle closed "
            "smile, soft grey fur, tail curled neatly around its front paws. "
            "Cute and friendly, mouth closed." + NOPANEL),
    },
    "bird": {
        "category": "animals", "en": "Bird", "tl": "Ibon", "ceb": "Langgam",
        "subject": (
            "a cute round little cartoon bird facing the viewer: a plump oval "
            "body, a small head, big friendly round eyes, a small orange "
            "triangular beak, two little folded wings and two thin orange feet. "
            "Sky blue feathers with a paler tummy. Cute and cheerful, perched "
            "upright." + NOPANEL),
    },
    "fish": {
        "category": "animals", "en": "Fish", "tl": "Isda", "ceb": "Isda",
        "subject": (
            "a cute cartoon fish seen from the side: a rounded teardrop body, "
            "one big friendly round eye, a small smiling mouth, a curved tail "
            "fin and two small side fins. Bright orange with a paler belly and "
            "simple curved scale lines. Cute and friendly." + NOPANEL),
    },
    "rabbit": {
        "category": "animals", "en": "Rabbit", "tl": "Kuneho", "ceb": "Koneho",
        "subject": (
            "a cute cartoon bunny sitting and facing the viewer: a round head "
            "with two tall upright ears, big friendly round eyes, a tiny pink "
            "nose, a small closed smile and a round fluffy body, soft white "
            "fur with a pale pink inner ear. Sitting upright with small front "
            "paws together. Cute and gentle." + NOPANEL),
    },
    "duck": {
        "category": "animals", "en": "Duck", "tl": "Pato", "ceb": "Itik",
        "subject": (
            "a cute cartoon duckling standing and facing the viewer: a round "
            "body and round head, big friendly round eyes, a flat rounded "
            "orange beak with a gentle smile, two little wings and two webbed "
            "orange feet. Soft butter-yellow feathers. Cute and cheerful, "
            "standing upright." + NOPANEL),
    },
    "cow": {
        "category": "animals", "en": "Cow", "tl": "Baka", "ceb": "Baka",
        "subject": (
            "a cute cartoon cow standing and facing the viewer: a round body, "
            "a big friendly head with two little rounded horns and floppy ears, "
            "big round eyes, a soft pink muzzle with a gentle smile, white hide "
            "with a few soft grey patches, and four short legs. Cute and "
            "friendly, mouth closed." + NOPANEL),
    },
    "pig": {
        "category": "animals", "en": "Pig", "tl": "Baboy", "ceb": "Baboy",
        "subject": (
            "a cute cartoon piglet standing and facing the viewer: a round "
            "body, a round head with two small floppy ears, big friendly round "
            "eyes, a round pink snout with two little nostrils and a gentle "
            "smile, soft rose-pink skin, four short legs and a little curly "
            "tail. Cute and friendly." + NOPANEL),
    },
    "elephant": {
        "category": "animals", "en": "Elephant", "tl": "Elepante",
        "ceb": "Elepante",
        "subject": (
            "a cute cartoon baby elephant standing and facing the viewer: a "
            "round body, a big head with two large round ears, big friendly "
            "round eyes, a short curled-up trunk and a gentle smile, soft "
            "grey-blue skin and four sturdy round legs. Cute and gentle, no "
            "tusks." + NOPANEL),
    },
    "frog": {
        "category": "animals", "en": "Frog", "tl": "Palaka", "ceb": "Baki",
        "subject": (
            "a cute cartoon frog sitting and facing the viewer: a round green "
            "body, a wide gentle closed smile, two big round eyes on top of "
            "its head, a paler green tummy and four little legs with rounded "
            "toes. Cute and friendly, mouth closed, no tongue." + NOPANEL),
    },

    # ── Fruits ───────────────────────────────────────────────────────
    # Drawn as plain, appetising objects with NO face — a face would read as a
    # character rather than the fruit the child is meant to name.
    "apple": {
        "category": "fruits", "en": "Apple", "tl": "Mansanas",
        "ceb": "Mansanas",
        "subject": (
            "a single bright red apple, a rounded heart-like silhouette with a "
            "small dip at the top, one short brown stem and one small green "
            "leaf. A soft pale highlight on one side. No face." + NOPANEL),
    },
    "banana": {
        "category": "fruits", "en": "Banana", "tl": "Saging", "ceb": "Saging",
        "subject": (
            "a single ripe yellow banana, a smooth curved crescent shape with "
            "a small brown tip at each end. No face." + NOPANEL),
    },
    "orange": {
        "category": "fruits", "en": "Orange", "tl": "Kahel", "ceb": "Kahel",
        "subject": (
            "a single round orange fruit, bright orange, with a small round "
            "dimple at the top and one small green leaf. A soft pale highlight "
            "on one side. No face." + NOPANEL),
    },
    "grapes": {
        "category": "fruits", "en": "Grapes", "tl": "Ubas", "ceb": "Ubas",
        "subject": (
            "a single bunch of purple grapes, a neat triangular cluster of "
            "about eight round berries, with one short brown stem and one "
            "small green leaf at the top. No face." + NOPANEL),
    },
    "watermelon": {
        "category": "fruits", "en": "Watermelon", "tl": "Pakwan",
        "ceb": "Pakwan",
        "subject": (
            "a single triangular slice of watermelon: bright pink-red flesh "
            "with a few small black seeds, a thin white layer, and a rounded "
            "green rind along the curved edge. No face." + NOPANEL),
    },
    "strawberry": {
        "category": "fruits", "en": "Strawberry", "tl": "Strawberry",
        "ceb": "Strawberry",
        "subject": (
            "a single red strawberry, a rounded heart-shaped berry pointing "
            "down, dotted with tiny seeds, topped with a small green leafy "
            "crown. No face." + NOPANEL),
    },
    "mango": {
        "category": "fruits", "en": "Mango", "tl": "Mangga", "ceb": "Mangga",
        "subject": (
            "a single ripe mango, a smooth rounded oval that curves gently to "
            "one side, warm golden-yellow with a soft blush, one short stem "
            "and one small green leaf at the top. No face." + NOPANEL),
    },
    "pineapple": {
        "category": "fruits", "en": "Pineapple", "tl": "Pinya", "ceb": "Pinya",
        "subject": (
            "a single pineapple standing upright: a golden-yellow oval body "
            "with a simple criss-cross diamond pattern, topped with a crown of "
            "pointed green leaves. No face." + NOPANEL),
    },

    # ── Toys ─────────────────────────────────────────────────────────
    # Plain objects, except the doll and teddy which naturally have a face.
    # These mirror Sari-Sari Sort's toy category (bola, manika, kotse, teddy).
    "ball": {
        "category": "toys", "en": "Ball", "tl": "Bola", "ceb": "Bola",
        "subject": (
            "a single classic ball, a round sphere divided into simple curved "
            "panels in sky blue and white, with a soft pale highlight on one "
            "side. No face." + NOPANEL),
    },
    "doll": {
        "category": "toys", "en": "Doll", "tl": "Manika", "ceb": "Munyeka",
        "subject": (
            "a single cute rag doll standing and facing the viewer: a round "
            "head with simple dot eyes, rosy cheeks and a small smile, short "
            "brown yarn hair, a simple mint-green dress, and little arms and "
            "legs. Friendly and sweet." + NOPANEL),
    },
    "car": {
        "category": "toys", "en": "Car", "tl": "Kotse", "ceb": "Awto",
        "subject": (
            "a single cute toy car seen from the side: a rounded chunky red "
            "body with one window, two black round wheels and a small yellow "
            "headlight. Simple and toy-like. No face." + NOPANEL),
    },
    "teddy": {
        "category": "toys", "en": "Teddy bear", "tl": "Teddy", "ceb": "Teddy",
        "subject": (
            "a single cute teddy bear sitting and facing the viewer: a round "
            "head with two round ears, small dot eyes, a little oval muzzle "
            "with a stitched nose and gentle smile, a round tan body and short "
            "rounded arms and legs. Soft and cuddly." + NOPANEL),
    },
    "blocks": {
        "category": "toys", "en": "Blocks", "tl": "Bloke", "ceb": "Bloke",
        "subject": (
            "a small stack of toy building blocks: three cube blocks, one sky "
            "blue, one butter yellow and one rose pink, stacked and slightly "
            "offset, each with a soft highlight. No letters, no numbers, no "
            "face." + NOPANEL),
    },
    "kite": {
        "category": "toys", "en": "Kite", "tl": "Saranggola", "ceb": "Tabanog",
        "subject": (
            "a single diamond-shaped kite, divided into four coloured panels "
            "(mint green, sky blue, butter yellow, rose pink), with a simple "
            "cross frame and a wavy tail with two small bows hanging from the "
            "bottom point. No face." + NOPANEL),
    },
}


def seeds_in(category: str | None, only: list[str] | None) -> list[str]:
    names = list(SEEDS)
    if category:
        names = [n for n in names if SEEDS[n]["category"] == category]
    if only:
        for n in only:
            if n not in SEEDS:
                sys.exit(f"unknown seed: {n}")
        names = only
    return names


# ── kie.ai plumbing (same as the other card scripts) ──────────────────
def key() -> str:
    k = os.environ.get("KIE_API_KEY")
    if not k:
        sys.exit("KIE_API_KEY is not set")
    return k


def headers() -> dict:
    return {"Authorization": f"Bearer {key()}", "Content-Type": "application/json"}


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


def style_ref() -> Path:
    """The shared style strip, flattened onto white and scaled for upload."""
    if not STYLE_REF.exists():
        sys.exit(f"style reference missing: {STYLE_REF}\n"
                 f"rebuild it with generate_routine_cards.py --rebuild-style-ref")
    im = Image.open(STYLE_REF).convert("RGBA")
    flat = Image.new("RGB", im.size, (255, 255, 255))
    flat.paste(im, (0, 0), im)
    flat.thumbnail((MAX_REF_PX, MAX_REF_PX), Image.LANCZOS)
    out = CACHE / "ref_seed_style.png"
    flat.save(out)
    return out


def prompt_for(slug: str) -> str:
    body = SEEDS[slug]["subject"]
    return (
        "Draw a single children's picture card showing one everyday object.\n\n"
        "The reference image shows finished cards from the same set. Match their "
        "drawing style, line weight, colour palette and framing exactly, so this "
        "card belongs beside them. Do NOT copy the objects or people in the "
        "reference — draw only the object described below.\n\n"
        f"OBJECT: {body}\n\n" + STYLE
    )


# ── Generation ────────────────────────────────────────────────────────
def generate(slug: str, style_url: str) -> Path:
    raw = CACHE / f"raw_seed_{slug}.png"
    if raw.exists():
        print(f"[{slug}] cached")
        return raw

    body = {
        "model": "google/nano-banana-edit",
        "input": {
            "prompt": prompt_for(slug),
            "image_urls": [style_url],
            "output_format": "png",
            "image_size": "1:1",
        },
    }
    r = requests.post(f"{JOBS_API}/api/v1/jobs/createTask",
                      headers=headers(), json=body, timeout=60)
    r.raise_for_status()
    d = r.json()
    if d.get("code") != 200:
        sys.exit(f"[{slug}] createTask failed: {d}")
    task_id = d["data"]["taskId"]
    print(f"[{slug}] -> task {task_id}")

    data = {}
    for _ in range(90):
        time.sleep(5)
        data = (requests.get(f"{JOBS_API}/api/v1/jobs/recordInfo",
                             headers=headers(), params={"taskId": task_id},
                             timeout=60).json().get("data") or {})
        if data.get("state") == "success":
            print(f"[{slug}] {data.get('costTime')}ms, "
                  f"{data.get('creditsConsumed')} credits")
            break
        if data.get("state") == "fail":
            sys.exit(f"[{slug}] failed: {data.get('failMsg')}")
    else:
        sys.exit(f"[{slug}] timed out")

    url = json.loads(data["resultJson"])["resultUrls"][0]
    raw.write_bytes(requests.get(url, timeout=600).content)
    return raw


# ── Post-processing (identical to the emotion/routine cards) ──────────
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


def postprocess(raw: Path, slug: str) -> Path:
    """Key out the page, trim to the object, re-pad square, shrink, palettise."""
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

    out_dir = DEST / SEEDS[slug]["category"]
    out_dir.mkdir(parents=True, exist_ok=True)
    out = out_dir / f"{slug}.png"
    card.quantize(colors=COLORS, method=Image.FASTOCTREE).save(out, optimize=True)
    print(f"  {SEEDS[slug]['category']}/{out.name:16} {x1-x0:4}x{y1-y0:4} "
          f"-> {CARD_PX}px  {out.stat().st_size/1e3:5.0f} KB")
    return out


def write_manifest():
    """Index every seed whose card exists on disk into seeds.json.

    The manifest is the app-facing contract: it names each seed's card and its
    per-language voice line, so a game can load the bank without knowing how it
    was generated. Every path is relative to this file's own directory (the
    `seed_cards/` bank root), so a consumer resolves them against one base.
    Lines are referenced by the path generate_seed_lines.py writes; a missing
    line file is left as null rather than invented.
    """
    entries = []
    for slug, s in SEEDS.items():
        card = DEST / s["category"] / f"{slug}.png"
        if not card.exists():
            continue
        lines = {}
        for lang in ("en", "tl", "ceb"):
            wav = DEST / "audio" / lang / f"{slug.capitalize()}.wav"
            rel = str(wav.relative_to(DEST)).replace("\\", "/")
            lines[lang] = rel if wav.exists() else None
        entries.append({
            "slug": slug,
            "category": s["category"],
            "names": {"en": s["en"], "tl": s["tl"], "ceb": s["ceb"]},
            "card": str(card.relative_to(DEST)).replace("\\", "/"),
            "lines": lines,
        })

    DEST.mkdir(parents=True, exist_ok=True)
    out = DEST / "seeds.json"
    out.write_text(json.dumps({"seeds": entries}, indent=2, ensure_ascii=False),
                   encoding="utf-8")
    print(f"\nmanifest: {len(entries)} seed(s) -> {out}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--category", help="only seeds in this category (e.g. animals)")
    ap.add_argument("--only", help="comma-separated subset of seed slugs")
    ap.add_argument("--post-only", action="store_true",
                    help="skip the API, re-run post-processing on cached raws")
    ap.add_argument("--manifest-only", action="store_true",
                    help="just (re)write seeds.json from whatever is on disk")
    ap.add_argument("--force", action="store_true",
                    help="regenerate even if a raw is already cached")
    ap.add_argument("--jobs", type=int, default=4, help="concurrent generations")
    args = ap.parse_args()

    if args.manifest_only:
        write_manifest()
        return

    only = args.only.split(",") if args.only else None
    names = seeds_in(args.category, only)
    CACHE.mkdir(parents=True, exist_ok=True)

    if args.force:
        for n in names:
            (CACHE / f"raw_seed_{n}.png").unlink(missing_ok=True)

    if args.post_only:
        raws = {n: CACHE / f"raw_seed_{n}.png" for n in names}
        missing = [n for n, p in raws.items() if not p.exists()]
        if missing:
            sys.exit(f"no cached raw for: {', '.join(missing)}")
    else:
        style_url = upload(style_ref())
        print(f"style -> {style_url}")
        with ThreadPoolExecutor(max_workers=args.jobs) as ex:
            futs = {n: ex.submit(generate, n, style_url) for n in names}
            raws = {n: f.result() for n, f in futs.items()}

    print("\npost-processing")
    for n in names:
        postprocess(raws[n], n)

    write_manifest()


if __name__ == "__main__":
    main()
