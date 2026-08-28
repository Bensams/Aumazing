import 'dart:math' as math;
import 'dart:ui';

/// A traceable glyph (pre-writing stroke, letter, or number).
///
/// Strokes are polylines in a normalized 0..1 box (x right, y down), in the
/// order a child should trace them. Curves are pre-sampled into short
/// segments so distance checks stay simple.
class TraceGlyph {
  const TraceGlyph({
    required this.label,
    required this.strokes,
  });

  /// Display / analytics label (e.g. 'A', '3', 'circle').
  final String label;

  /// Ordered strokes; each stroke is an ordered polyline of normalized points.
  final List<List<Offset>> strokes;
}

/// Samples a circular arc into a polyline.
///
/// Angles are in degrees on a y-down canvas: 0° = right, 90° = bottom,
/// -90°/270° = top. Sweeps from [fromDeg] to [toDeg] in either direction.
List<Offset> _arc(
  double cx,
  double cy,
  double r,
  double fromDeg,
  double toDeg, {
  int steps = 24,
}) {
  final points = <Offset>[];
  for (var i = 0; i <= steps; i++) {
    final t = fromDeg + (toDeg - fromDeg) * (i / steps);
    final rad = t * math.pi / 180.0;
    points.add(Offset(cx + r * math.cos(rad), cy + r * math.sin(rad)));
  }
  return points;
}

/// Joins consecutive polyline segments into one continuous stroke.
List<Offset> _join(List<List<Offset>> parts) {
  final points = <Offset>[];
  for (final part in parts) {
    for (final p in part) {
      if (points.isEmpty || (points.last - p).distance > 0.001) {
        points.add(p);
      }
    }
  }
  return points;
}

/// Glyph pools per difficulty tier.
///
/// - Level 1 (Easy): pre-writing strokes — lines, circle, square, simple forms.
///   These come before letterforms developmentally, so children who are
///   not yet ready for letters still succeed.
/// - Level 2 (Medium): angular shapes, single-stroke letters and numbers.
/// - Level 3 (Hard): complex shapes, multi-stroke letters and numbers.
class TraceGlyphs {
  TraceGlyphs._();

  static final List<TraceGlyph> level1 = [
    const TraceGlyph(label: 'line across', strokes: [
      [Offset(0.10, 0.50), Offset(0.90, 0.50)],
    ]),
    const TraceGlyph(label: 'line down', strokes: [
      [Offset(0.50, 0.10), Offset(0.50, 0.90)],
    ]),
    const TraceGlyph(label: 'slide', strokes: [
      [Offset(0.15, 0.85), Offset(0.85, 0.15)],
    ]),
    TraceGlyph(label: 'circle', strokes: [
      _arc(0.5, 0.5, 0.40, -90, 270, steps: 36),
    ]),
    const TraceGlyph(label: 'square', strokes: [
      [
        Offset(0.15, 0.15),
        Offset(0.85, 0.15),
        Offset(0.85, 0.85),
        Offset(0.15, 0.85),
        Offset(0.15, 0.15),
      ],
    ]),
    const TraceGlyph(label: 'V', strokes: [
      [Offset(0.20, 0.15), Offset(0.50, 0.85), Offset(0.80, 0.15)],
    ]),
    const TraceGlyph(label: '1', strokes: [
      [Offset(0.35, 0.30), Offset(0.50, 0.15), Offset(0.50, 0.85)],
    ]),
  ];

  static final List<TraceGlyph> level2 = [
    const TraceGlyph(label: 'L', strokes: [
      [Offset(0.35, 0.15), Offset(0.35, 0.85), Offset(0.75, 0.85)],
    ]),
    TraceGlyph(label: 'C', strokes: [
      _arc(0.5, 0.5, 0.35, -50, -310, steps: 30),
    ]),
    TraceGlyph(label: 'U', strokes: [
      _join([
        [const Offset(0.25, 0.15), const Offset(0.25, 0.55)],
        _arc(0.5, 0.55, 0.25, 180, 0),
        [const Offset(0.75, 0.55), const Offset(0.75, 0.15)],
      ]),
    ]),
    const TraceGlyph(label: '7', strokes: [
      [Offset(0.25, 0.20), Offset(0.75, 0.20), Offset(0.40, 0.85)],
    ]),
    TraceGlyph(label: '2', strokes: [
      _join([
        _arc(0.5, 0.33, 0.18, -160, 40),
        [const Offset(0.30, 0.82), const Offset(0.75, 0.82)],
      ]),
    ]),
    TraceGlyph(label: '3', strokes: [
      _join([
        _arc(0.48, 0.33, 0.17, -140, 90),
        _arc(0.48, 0.67, 0.17, -90, 140),
      ]),
    ]),
    const TraceGlyph(label: 'triangle', strokes: [
      [
        Offset(0.50, 0.10),
        Offset(0.90, 0.85),
        Offset(0.10, 0.85),
        Offset(0.50, 0.10),
      ],
    ]),
    const TraceGlyph(label: 'diamond', strokes: [
      [
        Offset(0.50, 0.10),
        Offset(0.90, 0.50),
        Offset(0.50, 0.90),
        Offset(0.10, 0.50),
        Offset(0.50, 0.10),
      ],
    ]),
  ];

  static final List<TraceGlyph> level3 = [
    const TraceGlyph(label: 'A', strokes: [
      [Offset(0.50, 0.15), Offset(0.20, 0.85)],
      [Offset(0.50, 0.15), Offset(0.80, 0.85)],
      [Offset(0.32, 0.60), Offset(0.68, 0.60)],
    ]),
    const TraceGlyph(label: 'T', strokes: [
      [Offset(0.20, 0.18), Offset(0.80, 0.18)],
      [Offset(0.50, 0.18), Offset(0.50, 0.85)],
    ]),
    const TraceGlyph(label: 'H', strokes: [
      [Offset(0.30, 0.15), Offset(0.30, 0.85)],
      [Offset(0.70, 0.15), Offset(0.70, 0.85)],
      [Offset(0.30, 0.50), Offset(0.70, 0.50)],
    ]),
    const TraceGlyph(label: 'E', strokes: [
      [Offset(0.68, 0.15), Offset(0.35, 0.15), Offset(0.35, 0.85), Offset(0.68, 0.85)],
      [Offset(0.35, 0.50), Offset(0.62, 0.50)],
    ]),
    // The stem runs from the apex, not from mid-air: starting it at y=0.30
    // left a visible gap above it, so the guide read as a disconnected tick
    // beside the diagonal rather than the spine of a 4.
    const TraceGlyph(label: '4', strokes: [
      [Offset(0.60, 0.15), Offset(0.28, 0.60), Offset(0.78, 0.60)],
      [Offset(0.62, 0.15), Offset(0.62, 0.85)],
    ]),
    TraceGlyph(label: '5', strokes: [
      _join([
        [const Offset(0.35, 0.15), const Offset(0.35, 0.45)],
        _arc(0.48, 0.63, 0.20, -135, 120),
      ]),
      const [Offset(0.35, 0.15), Offset(0.70, 0.15)],
    ]),
    const TraceGlyph(label: 'star', strokes: [
      [
        Offset(0.50, 0.08),
        Offset(0.88, 0.82),
        Offset(0.08, 0.33),
        Offset(0.92, 0.33),
        Offset(0.12, 0.82),
        Offset(0.50, 0.08),
      ],
    ]),
    TraceGlyph(label: 'heart', strokes: [
      _join([
        [const Offset(0.50, 0.90)],
        _arc(0.30, 0.32, 0.20, 140, 360, steps: 22),
        _arc(0.70, 0.32, 0.20, 180, 400, steps: 22),
        [const Offset(0.50, 0.90)],
      ]),
    ]),
  ];

  /// The glyph pool for a 1–3 difficulty level (clamped).
  static List<TraceGlyph> forLevel(int level) {
    switch (level.clamp(1, 3)) {
      case 1:
        return level1;
      case 3:
        return level3;
      default:
        return level2;
    }
  }
}
