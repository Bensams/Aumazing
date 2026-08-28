import 'dart:ui';

/// Where a sprite cell should be drawn inside a layout box so that it keeps
/// its own proportions.
///
/// Every mascot sheet shares one cell size — 406x490 as generated, and
/// `scripts/SPRITES.md` treats that uniformity as an invariant, because it is
/// what lets a character swap between `idle`, `point` and `celebrate` without
/// changing size or sliding sideways. Handing a cell straight to
/// [Canvas.drawImageRect] with the component's own rect throws that away: the
/// image is stretched to whatever shape the layout happens to be.
///
/// That failure is easy to miss in review and easy to miss on a tablet. Games
/// size their characters from the *playfield*, and a 16:9 playfield often
/// produces a box close enough to the cell's proportions that nothing looks
/// wrong. It is on a short landscape phone — where the box collapses to a wide,
/// shallow strip — that the character turns into a smear. Tulong, Kaibigan!
/// shipped exactly that: a box 2.6x too wide at 800x360 and 4.5x too wide at
/// 960x300, while looking correct at 1280x720.
///
/// [contain] returns the largest rect with the cell's aspect ratio that fits
/// inside [box], anchored to the bottom centre — characters stand on the
/// ground, so spare height belongs above their head, never under their feet.
Rect fitSpriteCell(Rect box, double cellWidth, double cellHeight) {
  if (cellWidth <= 0 || cellHeight <= 0 || box.width <= 0 || box.height <= 0) {
    return box;
  }

  final scale = _min(box.width / cellWidth, box.height / cellHeight);
  final w = cellWidth * scale;
  final h = cellHeight * scale;

  return Rect.fromLTWH(
    box.center.dx - w / 2,
    box.bottom - h,
    w,
    h,
  );
}

double _min(double a, double b) => a < b ? a : b;
