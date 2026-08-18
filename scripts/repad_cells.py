"""Re-pad a character's sprite sheets to a wider cell, without regenerating.

Lexianne's base cell moved 430 -> 500 so her `point` reach would not be
clipped (see CHARACTERS in generate_sprites.py). Her costume sheets had
already been cut at 430, which left her base and her costumes on different
cells — and `CalmMascot` renders with `BoxFit.contain`, so a costume with a
different cell aspect makes the mascot change size the instant a child equips
it. That is the one thing a costume swap must never do.

The whole difference is transparent margin, so this is an image operation
rather than a regeneration: split each sheet back into its cells, centre each
cell in a wider transparent one, and reassemble. No pixel of artwork moves
relative to its own cell, the row heights are untouched, and it costs nothing.

Idempotent: a sheet already at the target cell is skipped.

    python scripts/repad_cells.py --character lexianne --from 430 --to 500
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from PIL import Image

PROJECT_ROOT = Path(__file__).resolve().parent.parent
SHEETS = PROJECT_ROOT / "packages" / "shared_ui" / "assets" / "characters"


def repad(path: Path, cell_from: int, cell_to: int, dry_run: bool) -> str:
    img = Image.open(path).convert("RGBA")
    width, height = img.size

    if width % cell_to == 0 and width % cell_from != 0:
        return "already at target"
    if width % cell_from != 0:
        # Refuse rather than guess: a sheet whose width is not a whole number
        # of source cells is not the grid this script was pointed at, and
        # slicing it anyway would shred the artwork.
        return f"SKIP: {width}px is not a multiple of {cell_from}"

    cols = width // cell_from
    if cols == 0:
        return f"SKIP: no cells at {cell_from}px"

    out = Image.new("RGBA", (cols * cell_to, height), (0, 0, 0, 0))
    # Split the difference so the character keeps its position relative to the
    # centre of its own cell. An off-centre pad would slide the mascot
    # sideways the moment a costume went on.
    offset = (cell_to - cell_from) // 2
    for col in range(cols):
        cell = img.crop((col * cell_from, 0, (col + 1) * cell_from, height))
        out.paste(cell, (col * cell_to + offset, 0))

    if dry_run:
        return f"would repad {cols} cells -> {out.size[0]}x{height}"
    out.save(path)
    return f"repadded {cols} cells -> {out.size[0]}x{height}"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--character", required=True)
    ap.add_argument("--from", dest="cell_from", type=int, required=True)
    ap.add_argument("--to", dest="cell_to", type=int, required=True)
    ap.add_argument(
        "--costumes-only",
        action="store_true",
        help="only {character}_{costume}_* sheets, leaving the base set alone",
    )
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    if args.cell_to <= args.cell_from:
        print("--to must be wider than --from; this script only pads")
        return 2

    paths = sorted(SHEETS.glob(f"{args.character}_*.png"))
    if args.costumes_only:
        # A base sheet is `{character}_{action}.png`; a costume sheet has the
        # costume in between, so it always has one more underscore-separated
        # part than the longest base action name. Matching on the known
        # costume names is simpler and cannot misfire on `look_up_left`.
        costumes = ("teddy", "panda", "pig")
        paths = [
            p for p in paths
            if p.stem.split("_")[1] in costumes
        ]

    if not paths:
        print("no sheets matched")
        return 1

    for path in paths:
        print(f"{path.name:34} {repad(path, args.cell_from, args.cell_to, args.dry_run)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
