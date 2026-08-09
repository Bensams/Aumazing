import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:shared_ui/shared_ui.dart';

/// Shared utility for rendering 3D-looking shapes with gradients,
/// drop shadows, and specular highlights.
///
/// All draw methods take a [Canvas], center position ([cx], [cy]),
/// radius [r], and the base [color]. They render:
/// 1. A soft drop shadow beneath the shape
/// 2. A radial gradient fill (light top-left → dark bottom-right)
/// 3. A specular highlight (small bright spot at top-left)
class ShapePainter3D {
  const ShapePainter3D._();

  // ── Public API ──────────────────────────────────────────────────────

  static void drawCircle(ui.Canvas canvas, double cx, double cy, double r,
      ui.Color color) {
    _drawShadow(canvas, cx, cy, r, color);
    final gradient = _radialGradient(cx, cy, r, color);
    canvas.drawCircle(ui.Offset(cx, cy), r, ui.Paint()..shader = gradient);
    _drawHighlight(canvas, cx, cy, r);
  }

  static void drawStar(ui.Canvas canvas, double cx, double cy, double r,
      ui.Color color) {
    final path = _starPath(cx, cy, r);
    _drawPathShadow(canvas, path, cx, cy, r, color);
    canvas.drawPath(path, ui.Paint()..shader = _radialGradient(cx, cy, r, color));
    _drawHighlight(canvas, cx, cy, r * 0.55);
  }

  static void drawHeart(ui.Canvas canvas, double cx, double cy, double r,
      ui.Color color) {
    final path = _heartPath(cx, cy, r);
    _drawPathShadow(canvas, path, cx, cy, r, color);
    canvas.drawPath(path, ui.Paint()..shader = _radialGradient(cx, cy, r, color));
    _drawHighlight(canvas, cx - r * 0.22, cy - r * 0.25, r * 0.35);
  }

  static void drawTriangle(ui.Canvas canvas, double cx, double cy, double r,
      ui.Color color) {
    final path = _trianglePath(cx, cy, r);
    _drawPathShadow(canvas, path, cx, cy, r, color);
    canvas.drawPath(path, ui.Paint()..shader = _radialGradient(cx, cy, r, color));
    _drawHighlight(canvas, cx - r * 0.15, cy - r * 0.2, r * 0.35);
  }

  static void drawDiamond(ui.Canvas canvas, double cx, double cy, double r,
      ui.Color color) {
    final path = _diamondPath(cx, cy, r);
    _drawPathShadow(canvas, path, cx, cy, r, color);
    canvas.drawPath(path, ui.Paint()..shader = _radialGradient(cx, cy, r, color));
    _drawHighlight(canvas, cx - r * 0.12, cy - r * 0.25, r * 0.32);
  }

  /// Dispatches by shape-type string (used by Do What I Say / Copy Me).
  static void drawByName(ui.Canvas canvas, String shapeType, double cx, double cy,
      double r, ui.Color color) {
    switch (shapeType) {
      case 'circle':
        drawCircle(canvas, cx, cy, r, color);
      case 'star':
        drawStar(canvas, cx, cy, r, color);
      case 'triangle':
        drawTriangle(canvas, cx, cy, r, color);
      case 'diamond':
        drawDiamond(canvas, cx, cy, r, color);
      case 'heart':
        drawHeart(canvas, cx, cy, r, color);
    }
  }

  // ── Card background with 3D effect ─────────────────────────────────

  /// Draws a rounded-rect card with gradient fill, shadow, and rim light.
  static void drawCard3D(
    ui.Canvas canvas,
    ui.Rect rect, {
    required ui.Color color,
    double cornerRadius = 20.0,
    int alpha = 40,
    bool showBorder = false,
    ui.Color? borderColor,
    double borderWidth = 3.0,
  }) {
    final rrect =
        ui.RRect.fromRectAndRadius(rect, ui.Radius.circular(cornerRadius));

    // Drop shadow
    final shadowRect = rect.translate(2, 3);
    final shadowRRect =
        ui.RRect.fromRectAndRadius(shadowRect, ui.Radius.circular(cornerRadius));
    canvas.drawRRect(
      shadowRRect,
      ui.Paint()
        ..color = const ui.Color(0xFF000000).withAlpha(22)
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 6),
    );

    // Gradient card fill.
    //
    // A parent-set card colour replaces the object's own tint entirely. The
    // original `color.withAlpha(alpha)` made the card a 16% wash of the very
    // shape drawn on top of it, which is why a gold star could measure
    // 1.00:1 against its own card. A fixed colour has no such relationship
    // to the object, so the object stays visible whatever colour it is.
    //
    // The alpha is still honoured as a *state* signal rather than a tint: a
    // matched card (alpha below the resting 40) fades back, everything else
    // paints solid.
    final style = GameObjectStyle.current;
    final override = style.cardColour;
    final baseColor = override != null
        ? override.withValues(alpha: alpha < 40 ? 0.45 : 1.0)
        : color.withAlpha(alpha);
    final lighter = _lighten(baseColor, 0.25);
    final darker = _darken(baseColor, 0.15);
    final gradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [lighter, baseColor, darker],
      stops: const [0.0, 0.5, 1.0],
    );
    canvas.drawRRect(
      rrect,
      ui.Paint()..shader = gradient.createShader(rect),
    );

    // Rim highlight (top edge)
    final rimRect = ui.Rect.fromLTWH(
      rect.left + cornerRadius,
      rect.top + 1,
      rect.width - cornerRadius * 2,
      2,
    );
    canvas.drawRect(
      rimRect,
      ui.Paint()..color = const ui.Color(0xFFFFFFFF).withAlpha(35),
    );

    // Outline.
    //
    // Two things want to draw here and they are not the same thing:
    //
    //  * a *state* border — selected, wrong answer, hint — which the caller
    //    asks for and whose colour carries meaning, and
    //  * the *standing* outline, which exists so the card is separable from
    //    whatever is behind it and is drawn on every card, always.
    //
    // The state border wins when present. Otherwise the standing outline is
    // drawn in a colour derived from the card itself, so it is guaranteed to
    // clear 3:1 without anyone choosing it.
    if (showBorder) {
      canvas.drawRRect(
        rrect,
        ui.Paint()
          ..color = borderColor ?? color
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = borderWidth,
      );
    } else if (style.hasOutline) {
      final paint = ui.Paint()
        ..color = GameObjectStyle.outlineColourFor(baseColor)
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = style.effectiveWidth;
      if (style.outline == ObjectOutline.dashed) {
        _strokeDashed(canvas, ui.Path()..addRRect(rrect), paint);
      } else {
        canvas.drawRRect(rrect, paint);
      }
    }
  }

  /// Strokes [path] as a dashed line.
  ///
  /// Flutter has no dashed stroke, so the path is walked with [ui.PathMetric]
  /// and drawn in segments. Dash and gap scale with the stroke width, so a
  /// thick outline does not turn into a row of dots.
  static void _strokeDashed(ui.Canvas canvas, ui.Path path, ui.Paint paint) {
    final dash = math.max(6.0, paint.strokeWidth * 2.5);
    final gap = math.max(4.0, paint.strokeWidth * 1.5);
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = math.min(distance + dash, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + gap;
      }
    }
  }

  // ── Private helpers ─────────────────────────────────────────────────

  static ui.Shader _radialGradient(
      double cx, double cy, double r, ui.Color color) {
    final lighter = _lighten(color, 0.35);
    final darker = _darken(color, 0.25);
    return ui.Gradient.radial(
      ui.Offset(cx - r * 0.3, cy - r * 0.3), // light source top-left
      r * 1.6,
      [lighter, color, darker],
      [0.0, 0.55, 1.0],
    );
  }

  static void _drawShadow(
      ui.Canvas canvas, double cx, double cy, double r, ui.Color color) {
    canvas.drawCircle(
      ui.Offset(cx + 2, cy + 3),
      r + 1,
      ui.Paint()
        ..color = _darken(color, 0.4).withAlpha(50)
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 5),
    );
  }

  static void _drawPathShadow(
      ui.Canvas canvas, ui.Path path, double cx, double cy, double r, ui.Color color) {
    canvas.save();
    canvas.translate(2, 3);
    canvas.drawPath(
      path,
      ui.Paint()
        ..color = _darken(color, 0.4).withAlpha(50)
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 5),
    );
    canvas.restore();
  }

  static void _drawHighlight(
      ui.Canvas canvas, double cx, double cy, double r) {
    final highlightR = r * 0.38;
    final hx = cx - r * 0.28;
    final hy = cy - r * 0.28;
    canvas.drawOval(
      ui.Rect.fromCenter(
          center: ui.Offset(hx, hy), width: highlightR * 1.4, height: highlightR),
      ui.Paint()
        ..shader = ui.Gradient.radial(
          ui.Offset(hx, hy),
          highlightR,
          [
            const ui.Color(0xFFFFFFFF).withAlpha(90),
            const ui.Color(0xFFFFFFFF).withAlpha(0),
          ],
        ),
    );
  }

  // ── Shape paths ─────────────────────────────────────────────────────

  static ui.Path _starPath(double cx, double cy, double r) {
    final path = ui.Path();
    final inner = r * 0.45;
    for (var i = 0; i < 10; i++) {
      final angle = (i * math.pi / 5) - math.pi / 2;
      final radius = i.isEven ? r : inner;
      final x = cx + radius * math.cos(angle);
      final y = cy + radius * math.sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    return path;
  }

  static ui.Path _heartPath(double cx, double cy, double r) {
    final w = r * 1.1, h = r * 1.1;
    return ui.Path()
      ..moveTo(cx, cy + h * 0.6)
      ..cubicTo(
          cx - w * 1.2, cy - h * 0.2, cx - w * 0.4, cy - h * 0.9, cx, cy - h * 0.3)
      ..cubicTo(
          cx + w * 0.4, cy - h * 0.9, cx + w * 1.2, cy - h * 0.2, cx, cy + h * 0.6)
      ..close();
  }

  static ui.Path _trianglePath(double cx, double cy, double r) {
    return ui.Path()
      ..moveTo(cx, cy - r)
      ..lineTo(cx + r * 0.87, cy + r * 0.5)
      ..lineTo(cx - r * 0.87, cy + r * 0.5)
      ..close();
  }

  static ui.Path _diamondPath(double cx, double cy, double r) {
    return ui.Path()
      ..moveTo(cx, cy - r)
      ..lineTo(cx + r * 0.7, cy)
      ..lineTo(cx, cy + r)
      ..lineTo(cx - r * 0.7, cy)
      ..close();
  }

  // ── Color utilities ─────────────────────────────────────────────────

  static ui.Color _lighten(ui.Color c, double amount) {
    final r = (c.red + (255 - c.red) * amount).round().clamp(0, 255);
    final g = (c.green + (255 - c.green) * amount).round().clamp(0, 255);
    final b = (c.blue + (255 - c.blue) * amount).round().clamp(0, 255);
    return ui.Color.fromARGB(c.alpha, r, g, b);
  }

  static ui.Color _darken(ui.Color c, double amount) {
    final r = (c.red * (1 - amount)).round().clamp(0, 255);
    final g = (c.green * (1 - amount)).round().clamp(0, 255);
    final b = (c.blue * (1 - amount)).round().clamp(0, 255);
    return ui.Color.fromARGB(c.alpha, r, g, b);
  }
}
