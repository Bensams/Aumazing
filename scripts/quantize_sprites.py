#!/usr/bin/env python3
"""Shrink the mascot sprite sheets by palettising them.

The sheets are flat cel art, so a 255-colour adaptive palette is visually
indistinguishable at the size they actually render (a 490px cell drawn ~140
logical px tall is already a 3.5x downscale, which averages out the banding)
while cutting roughly 85% of the bytes.

FASTOCTREE is used because it is the only PIL quantiser that carries the alpha
channel through; the sheets rely on transparency, and a palette without it
would key the characters onto black.

Idempotent: sheets already in palette mode are skipped, so re-running never
compounds the loss.

Usage:
  python scripts/quantize_sprites.py            # report only
  python scripts/quantize_sprites.py --apply
"""
import sys
from pathlib import Path

from PIL import Image

DEST = (Path(__file__).resolve().parent.parent
        / "packages" / "shared_ui" / "assets" / "characters")
COLORS = 255
APPLY = "--apply" in sys.argv


def main():
    sheets = sorted(DEST.glob("*.png"))
    if not sheets:
        sys.exit(f"no sheets found in {DEST}")

    before = after = 0
    skipped = []
    for p in sheets:
        size = p.stat().st_size
        before += size
        im = Image.open(p)
        if im.mode == "P":
            skipped.append(p.name)
            after += size
            continue
        q = im.convert("RGBA").quantize(colors=COLORS, method=Image.FASTOCTREE)
        if APPLY:
            q.save(p, optimize=True)
            new = p.stat().st_size
        else:
            import io
            b = io.BytesIO()
            q.save(b, format="PNG", optimize=True)
            new = b.tell()
        after += new
        print(f"  {p.name:26} {size/1e3:7.0f} KB -> {new/1e3:6.0f} KB "
              f"({100*new/size:4.1f}%)")

    if skipped:
        print(f"\nalready palettised, skipped: {', '.join(skipped)}")
    print(f"\ntotal {before/1e6:.2f} MB -> {after/1e6:.2f} MB "
          f"({100*after/before:.1f}%, saved {(before-after)/1e6:.2f} MB)")
    if not APPLY:
        print("\ndry run; pass --apply to write")


if __name__ == "__main__":
    main()
