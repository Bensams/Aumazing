import 'dart:ui';

import 'package:flame/components.dart';

import '../../../config/game_motion.dart';

/// The zone behind one player's side tray, used for the practice-mode turn
/// cues.
///
/// - [active]: it is this side's turn. The tray gets a soft fill and a solid
///   border in the side's colour, so "whose turn" reads without words.
/// - [progress]: the child's tray during the buddy's wait. A border in the
///   child's colour fills clockwise from the top as the wait runs down, and
///   closes the loop when it is the child's turn — a visual timer with no
///   numbers for children who cannot read them yet. `null` hides it.
///
/// Drawn behind the pieces. The game only creates trays outside assessment,
/// so assessment play looks exactly as it always has.
class TurnTray extends PositionComponent {
  TurnTray({
    required this.color,
    required Vector2 position,
    required Vector2 size,
  }) : super(position: position, size: size, priority: -1);

  final Color color;

  bool active = false;

  /// 0.0 (wait just started) … 1.0 (wait over); `null` = no timer.
  double? progress;

  /// 0 → 1 fade of the active highlight, so a turn change eases in rather
  /// than flashing. Snaps when reduced motion is on.
  double _activeAmount = 0;

  static const double _fadeSeconds = 0.25;
  static const double _borderWidth = 3;
  static const double _timerWidth = 5;

  @override
  void update(double dt) {
    super.update(dt);
    final target = active ? 1.0 : 0.0;
    if (GameMotion.reduced) {
      _activeAmount = target;
      return;
    }
    final step = dt / _fadeSeconds;
    if (_activeAmount < target) {
      _activeAmount = (_activeAmount + step).clamp(0.0, target);
    } else if (_activeAmount > target) {
      _activeAmount = (_activeAmount - step).clamp(target, 1.0);
    }
  }

  @override
  void render(Canvas canvas) {
    final rect = Rect.fromLTWH(0, 0, size.x, size.y);
    final radius = size.x / 2;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));

    if (_activeAmount > 0) {
      canvas.drawRRect(
        rrect,
        Paint()..color = color.withAlpha((40 * _activeAmount).round()),
      );
      canvas.drawRRect(
        rrect.inflate(3),
        Paint()
          ..color = color.withAlpha((90 * _activeAmount).round())
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = color.withAlpha((230 * _activeAmount).round())
          ..style = PaintingStyle.stroke
          ..strokeWidth = _borderWidth,
      );
    }

    final p = progress;
    if (p != null && !active) {
      final track = _clockwiseFromTop(rect, radius);
      canvas.drawPath(
        track,
        Paint()
          ..color = color.withAlpha(55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = _timerWidth,
      );
      final fraction = p.clamp(0.0, 1.0);
      if (fraction > 0) {
        final filled = Path();
        for (final metric in track.computeMetrics()) {
          filled.addPath(
            metric.extractPath(0, metric.length * fraction),
            Offset.zero,
          );
        }
        canvas.drawPath(
          filled,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = _timerWidth
            ..strokeCap = StrokeCap.round,
        );
      }
    }
  }

  /// The tray outline as one path that starts at the top centre and runs
  /// clockwise, so the timer fills from the top like a clock.
  static Path _clockwiseFromTop(Rect r, double radius) {
    final rad = Radius.circular(radius);
    return Path()
      ..moveTo(r.center.dx, r.top)
      ..lineTo(r.right - radius, r.top)
      ..arcToPoint(Offset(r.right, r.top + radius), radius: rad)
      ..lineTo(r.right, r.bottom - radius)
      ..arcToPoint(Offset(r.right - radius, r.bottom), radius: rad)
      ..lineTo(r.left + radius, r.bottom)
      ..arcToPoint(Offset(r.left, r.bottom - radius), radius: rad)
      ..lineTo(r.left, r.top + radius)
      ..arcToPoint(Offset(r.left + radius, r.top), radius: rad)
      ..lineTo(r.center.dx, r.top);
  }
}
