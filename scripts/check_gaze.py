#!/usr/bin/env python3
"""Verify a character's gaze poses actually look the way their names claim.

`look_left` / `look_right` are generated as two independent clips, and the
model does NOT reliably honour the direction it was asked for: BPS came back
with both poses inverted, Reiz with one correct and one looking the wrong way.
Nothing else in the pipeline notices — a wrong-way pose is perfectly scaled,
perfectly centred and passes every geometry check — so it has to be measured.

    python scripts/check_gaze.py bps reiz

Exits non-zero unless every opposing pair of poses points opposite ways.
"""

import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

MIN_TRAVEL = 2.5   # % of eye size; below this it cannot be seen on screen

DEST = Path(__file__).resolve().parent.parent / "packages" / "shared_ui" \
    / "assets" / "characters"


def cell(name: str, action: str) -> np.ndarray:
    """RGBA of one pose. `idle` yields cell 0 of its 3x2 sheet."""
    im = Image.open(DEST / f"{name}_{action}.png").convert("RGBA")
    if action == "idle":
        im = im.crop((0, 0, im.width // 3, im.height // 2))
    return np.asarray(im).astype(float)


def gaze(pose: np.ndarray) -> tuple[float, float]:
    """How far the irises sit from the centre of the eye openings, as (x, y).

    Negative is left/up, positive is right/down, scaled by the size of the eye
    so the two characters are comparable. Everything is measured WITHIN one
    pose — no cross-pose alignment — because the poses come from separate
    clips whose hair and outlines differ slightly everywhere, which defeats
    any attempt to find the eyes by diffing two poses against each other.

    The eyes are found by their whites: a big, bright, unsaturated region is
    not something else on these characters, and unlike a hard-coded band it
    does not care that the two mascots wear their eyes at different heights.
    """
    rgb, alpha = pose[..., :3], pose[..., 3] > 16
    mx, mn = rgb.max(axis=2), rgb.min(axis=2)
    sclera = alpha & (mx > 185) & ((mx - mn) < 28)
    iris = alpha & (mn < 150) & (mx < 190)

    # Two largest whites in the top 60% of the cell: the two eyes.
    upper = np.zeros_like(sclera)
    upper[:int(pose.shape[0] * 0.6)] = True
    lbl, n = ndimage.label(sclera & upper)
    if n < 2:
        raise SystemExit("could not find two eye whites")
    sizes = ndimage.sum(sclera & upper, lbl, range(1, n + 1))
    eyes = [int(i) + 1 for i in np.argsort(sizes)[-2:]]

    offsets = []
    for label in eyes:
        ys, xs = np.where(lbl == label)
        # Widen past the white to take in the whole eye opening — the white is
        # itself pushed to one side by the iris, so it is not a stable centre.
        padx = int((xs.max() - xs.min()) * 0.7)
        pady = int((ys.max() - ys.min()) * 0.7)
        box = (slice(max(ys.min() - pady, 0), ys.max() + pady + 1),
               slice(max(xs.min() - padx, 0), xs.max() + padx + 1))
        white, dark = sclera[box], iris[box]
        if white.sum() < 20 or dark.sum() < 20:
            continue
        # Reference is the BOUNDING BOX of the eye opening, which the eyelids
        # define and the eyeball cannot move. A centroid of the opening is not
        # usable: it shifts with the iris it is meant to be measuring.
        oy, ox = np.where(white | dark)
        bx = (ox.min() + ox.max()) / 2
        by = (oy.min() + oy.max()) / 2
        w = ox.max() - ox.min() + 1
        h = oy.max() - oy.min() + 1
        iy, ix = np.where(dark)
        sy, sx = np.where(white)
        # Two independent readings, averaged. The iris is the direct signal but
        # the upper lid CLIPS it on any upward glance, which skews its centroid
        # — that alone reported BPS's top corners as pointing the wrong way
        # round when they plainly do not. The white is never clipped and simply
        # piles up on the side the eye is looking away from, so it stays honest
        # exactly where the iris stops being so.
        offsets.append((
            ((ix.mean() - bx) - (sx.mean() - bx)) / 2 / w,
            ((iy.mean() - by) - (sy.mean() - by)) / 2 / h,
        ))
    if not offsets:
        raise SystemExit("found eye whites but no irises")
    return (float(np.mean([o[0] for o in offsets])) * 100,
            float(np.mean([o[1] for o in offsets])) * 100)


# Each pose is checked against its OPPOSITE, on the axis they disagree about.
#
# Deliberately not checked against the rest frame. The neutral pose is not a
# reliable zero — BPS's idle measures well left of its own `look_left`, which
# marked four perfectly good poses as failures — whereas two poses that are
# supposed to point opposite ways can always be asked which one is further
# over, and that is the property that actually matters.
OPPOSING = [
    ("look_left", "look_right", 0),
    ("look_up_left", "look_up_right", 0),
    ("look_down_left", "look_down_right", 0),
    ("look_up", "look_down", 1),
    ("look_up_left", "look_down_left", 1),
    ("look_up_right", "look_down_right", 1),
]

AXIS = ("x", "y")


def check(name: str) -> bool:
    measured = {}
    for pose in set(p for pair in OPPOSING for p in pair[:2]):
        try:
            measured[pose] = gaze(cell(name, pose))
        except FileNotFoundError:
            pass

    missing = sorted(set(p for pair in OPPOSING for p in pair[:2])
                     - measured.keys())
    if missing:
        print(f"{name}: not generated - {', '.join(missing)}")
    if not measured:
        return True

    ok = True
    print(f"{name}:")
    for low, high, axis in OPPOSING:
        if low not in measured or high not in measured:
            continue
        gap = measured[high][axis] - measured[low][axis]
        # DIRECTION is asserted; magnitude is only advised. Every real defect
        # this tool has caught was a sign error — an inverted pair, a pose that
        # looked the wrong way, a malformed frame with no iris at all — and the
        # sign is robust. The magnitude is not: an upward glance is clipped by
        # the eyelid, so a corner pose that is unmistakable to the eye can
        # still measure small. Failing on size would reject good art, which is
        # worse than the weak pose it would be protecting against.
        if gap <= 0:
            note = "FAIL - points the wrong way"
        elif gap < MIN_TRAVEL:
            note = "ok (weak - eyeball it before shipping)"
        else:
            note = "ok"
        print(f"  {low:16} < {high:16} on {AXIS[axis]}   gap {gap:+6.1f}   "
              f"{note}")
        ok &= gap > 0
    return ok


if __name__ == "__main__":
    names = sys.argv[1:] or ["bps", "reiz"]
    sys.exit(0 if all([check(n) for n in names]) else 1)
