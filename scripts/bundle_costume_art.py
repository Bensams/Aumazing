#!/usr/bin/env python3
"""Copy costume artwork into the app bundle at display size.

`packages/assets/` is NOT a Dart package — it has no pubspec and nothing in it
is bundled. It holds full-resolution SOURCE art for the generators. Anything
the app renders at runtime has to live under a real package's declared assets,
which for shared art means `packages/shared_ui/assets/`.

Copying the sources across verbatim would add ~33 MB to the app: 30 PNGs at
roughly 1.1 MB each, every one of them a 864x1184 image that the shop draws
into a card a couple of hundred pixels wide. So they are resized to
[TARGET_H] and palettised on the way in, which is the same treatment
`quantize_sprites.py` gives the sprite sheets and lands the whole set around
3-4 MB.

The source art is left untouched — `generate_sprites.py` still cuts sheets from
the full-resolution originals, and re-running this is always safe.

Usage:
  python scripts/bundle_costume_art.py          # write them
  python scripts/bundle_costume_art.py --check  # report only, change nothing
"""

import argparse
import sys
from pathlib import Path

from PIL import Image

SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parent
SRC_COSTUMES = (PROJECT_ROOT / "packages" / "assets" / "images" / "Character"
                / "Character_Costume")
SRC_CHARACTERS = PROJECT_ROOT / "packages" / "assets" / "images" / "Character"
DEST = PROJECT_ROOT / "packages" / "shared_ui" / "assets" / "costumes"

# Tall enough for the preview sheet, which is the largest place a costume is
# drawn (~320 logical px, so ~960 physical on a 3x screen).
TARGET_H = 900
COLORS = 255

CHARACTERS = {"bps": "BPs", "lexianne": "Lexianne", "reiz": "Reiz"}
BASE_ART = {
    "bps": "BPS_chibi.png",
    "lexianne": "Lexianne_chibi.png",
    "reiz": "Reiz_Chibi_nb.png",
}
COSTUMES = ["Teddy", "Panda", "Fox", "Koala", "Frog",
            "Unicorn", "Octopus", "Rabbit", "Pig"]


def convert(src: Path, dest: Path, check: bool) -> tuple[int, int]:
    """Returns (source bytes, written bytes)."""
    if not src.exists():
        print(f"  MISSING {src.relative_to(PROJECT_ROOT)}")
        return (0, 0)
    im = Image.open(src).convert("RGB")
    if im.height > TARGET_H:
        im = im.resize(
            (round(im.width * TARGET_H / im.height), TARGET_H), Image.LANCZOS)
    src_size = src.stat().st_size
    if check:
        return (src_size, 0)
    dest.parent.mkdir(parents=True, exist_ok=True)
    im.quantize(colors=COLORS, method=Image.FASTOCTREE).save(
        dest, optimize=True)
    return (src_size, dest.stat().st_size)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true",
                    help="report what would happen; write nothing")
    args = ap.parse_args()

    if not SRC_COSTUMES.exists():
        sys.exit(f"costume art not found at {SRC_COSTUMES}")

    total_src = total_out = 0
    for key, stem in CHARACTERS.items():
        # `none` is the character's own clothes — bundled under the same naming
        # so the app resolves every costume, including "no costume", with one
        # rule instead of a special case.
        s, o = convert(SRC_CHARACTERS / BASE_ART[key],
                       DEST / f"{key}_none.png", args.check)
        total_src += s
        total_out += o

        for costume in COSTUMES:
            src = SRC_COSTUMES / costume / f"{stem}_chibi_{costume}.png"
            dest = DEST / f"{key}_{costume.lower()}.png"
            s, o = convert(src, dest, args.check)
            total_src += s
            total_out += o

    verb = "would bundle" if args.check else "bundled"
    print(f"\n{verb} {len(CHARACTERS) * (len(COSTUMES) + 1)} images")
    print(f"  source: {total_src / 1e6:.1f} MB")
    if not args.check:
        print(f"  bundle: {total_out / 1e6:.1f} MB")


if __name__ == "__main__":
    main()
