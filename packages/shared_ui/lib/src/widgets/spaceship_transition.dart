import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/world_theme.dart';
import 'world_backdrop.dart';

/// A page transition for the Night Sky ("space") world: a little spaceship
/// flies across the star field towards the next game, and the destination
/// screen fades in behind it as it arrives.
///
/// Why a bespoke route rather than the default push: on the space world the
/// child's whole progression is framed as a journey — the path map is a trail
/// between platforms floating over planets. Moving from one game to the next
/// with a plain screen swap breaks that frame; a ship that visibly *travels*
/// to the next round keeps "you are going somewhere" legible without a word of
/// text, which is the whole point for a pre-reading ASD child.
///
/// Every choice about how it moves follows the same rules the lobby's "door"
/// transition already committed to (see `child_mode_lobby_screen.dart`):
///
/// * **Slow enough to follow.** [_duration] is well past a typical UI
///   flourish, so a child who processes visual change slowly can track the
///   ship from one side to the other instead of it being over before they
///   found it.
/// * **No sudden onset.** The ship eases in from rest and the cover fades in;
///   nothing snaps onto the screen on the first frame.
/// * **Nothing overshoots, spins or flashes.** The ship travels once, left to
///   right, along a single gentle arc, at a steady pace.
/// * **Opt-out honoured.** With [reducedMotion] on, the same change is a plain
///   cross-fade over the same duration — nothing travels across the screen.
///
/// Falls back to a drawn rocket when [spaceshipAsset] is missing or unreadable,
/// so a half-finished art drop can never take the transition off screen.
class SpaceshipTransitionRoute<T> extends PageRouteBuilder<T> {
  SpaceshipTransitionRoute({
    required WidgetBuilder builder,
    required this.style,
    this.reducedMotion = false,
    this.spaceshipAsset = _defaultAsset,
    super.settings,
  }) : super(
          pageBuilder: (context, _, __) => builder(context),
          transitionDuration: reducedMotion ? _reducedDuration : _duration,
          reverseTransitionDuration:
              reducedMotion ? _reducedDuration : _reverseDuration,
          opaque: true,
          transitionsBuilder: (context, animation, _, child) {
            if (reducedMotion) {
              return FadeTransition(opacity: animation, child: child);
            }
            return _SpaceshipTransition(
              animation: animation,
              style: style,
              spaceshipAsset: spaceshipAsset,
              child: child,
            );
          },
        );

  /// The space world whose star field the ship crosses.
  final WorldStyle style;

  /// Reduced-motion opt-out: a plain cross-fade instead of the flight.
  final bool reducedMotion;

  /// Illustrated ship, resolved against the shared_ui package. A missing file
  /// degrades to the drawn rocket rather than an error box.
  final String spaceshipAsset;

  static const _defaultAsset = 'assets/worlds/spaceship.png';

  static const _duration = Duration(milliseconds: 1400);
  static const _reverseDuration = Duration(milliseconds: 450);
  static const _reducedDuration = Duration(milliseconds: 400);
}

class _SpaceshipTransition extends StatelessWidget {
  const _SpaceshipTransition({
    required this.animation,
    required this.style,
    required this.spaceshipAsset,
    required this.child,
  });

  final Animation<double> animation;
  final WorldStyle style;
  final String spaceshipAsset;
  final Widget child;

  /// The destination screen is held back until the ship is well on its way,
  /// then fades in over the tail of the flight — so the child sees the ship
  /// *arrive at* the next round rather than the round appearing under it.
  static const _revealStart = 0.62;

  /// The star-field cover lingers until the destination is fully in, then
  /// lifts. Kept opaque for most of the flight so the previous screen does not
  /// bleed through behind the ship.
  static const _coverFadeOutStart = 0.82;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = animation.value;

        // Destination reveal: 0 until the ship is on its way, then eased in.
        final revealRaw =
            ((t - _revealStart) / (1 - _revealStart)).clamp(0.0, 1.0);
        final reveal = Curves.easeIn.transform(revealRaw);

        // Cover opacity: solid through the crossing, easing out at the end so
        // the star field dissolves off the finished screen.
        final coverFade = t <= _coverFadeOutStart
            ? 1.0
            : 1 - ((t - _coverFadeOutStart) / (1 - _coverFadeOutStart));
        final cover = Curves.easeOut.transform(coverFade.clamp(0.0, 1.0));

        return Stack(
          fit: StackFit.expand,
          children: [
            Opacity(opacity: reveal, child: child),
            if (cover > 0)
              Opacity(
                opacity: cover,
                child: _SpaceScene(
                  progress: t,
                  style: style,
                  spaceshipAsset: spaceshipAsset,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// The star field with the ship flying across it, at a given [progress].
class _SpaceScene extends StatelessWidget {
  const _SpaceScene({
    required this.progress,
    required this.style,
    required this.spaceshipAsset,
  });

  final double progress;
  final WorldStyle style;
  final String spaceshipAsset;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;

        // The ship flies from off the left edge to off the right edge, so it
        // enters and leaves cleanly and never just parks in the middle.
        final flight = Curves.easeInOut.transform(progress);
        final x = -0.18 * w + flight * (w + 0.36 * w);

        // A shallow arc: it dips toward the middle of the sky and lifts again,
        // reading as travel rather than a flat slide. A single sine hump keeps
        // it smooth with no doubling back.
        final arc = math.sin(flight * math.pi);
        final y = h * 0.42 - arc * h * 0.10;

        // Grows a touch as it passes the centre, then settles — a gentle sense
        // of coming closer without any startling zoom.
        final scale = 0.82 + arc * 0.24;

        // Banks slightly into the arc, nose-up on the way in, level at the top.
        final tilt = (1 - arc) * 0.18 * (flight < 0.5 ? 1 : -1);

        const shipSize = 132.0;

        return Stack(
          fit: StackFit.expand,
          children: [
            WorldBackdrop(style: style),
            Positioned(
              left: x - shipSize / 2,
              top: y - shipSize / 2,
              child: Transform.rotate(
                angle: tilt,
                child: Transform.scale(
                  scale: scale,
                  child: _Spaceship(
                    size: shipSize,
                    asset: spaceshipAsset,
                    accent: style.currentRing,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The ship itself: the illustrated sprite when present, a drawn rocket when
/// not. The drawn form points to the right (its travel direction) so the two
/// read the same way round.
class _Spaceship extends StatelessWidget {
  const _Spaceship({
    required this.size,
    required this.asset,
    required this.accent,
  });

  final double size;
  final String asset;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Image.asset(
        asset,
        package: 'shared_ui',
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) => CustomPaint(
          painter: _RocketPainter(accent: accent),
        ),
      ),
    );
  }
}

/// A simple drawn rocket used until the illustrated ship is generated. Nose to
/// the right, a warm flame trailing left, so it matches the flight direction.
class _RocketPainter extends CustomPainter {
  const _RocketPainter({required this.accent});

  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cy = h / 2;

    // Flame first, so the body sits over its root.
    final flame = Path()
      ..moveTo(w * 0.30, cy - h * 0.09)
      ..quadraticBezierTo(w * 0.02, cy, w * 0.30, cy + h * 0.09)
      ..close();
    canvas.drawPath(
      flame,
      Paint()..color = const Color(0xFFFFB24D),
    );
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.30, cy - h * 0.05)
        ..quadraticBezierTo(w * 0.14, cy, w * 0.30, cy + h * 0.05)
        ..close(),
      Paint()..color = const Color(0xFFFFE08A),
    );

    // Body: a rounded capsule tapering to a nose on the right.
    final body = Path()
      ..moveTo(w * 0.30, cy - h * 0.16)
      ..lineTo(w * 0.66, cy - h * 0.16)
      ..quadraticBezierTo(w * 0.92, cy - h * 0.13, w * 0.94, cy)
      ..quadraticBezierTo(w * 0.92, cy + h * 0.13, w * 0.66, cy + h * 0.16)
      ..lineTo(w * 0.30, cy + h * 0.16)
      ..quadraticBezierTo(w * 0.24, cy, w * 0.30, cy - h * 0.16)
      ..close();
    canvas.drawPath(body, Paint()..color = const Color(0xFFECEAF6));

    // Fins.
    final finPaint = Paint()..color = accent;
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.36, cy - h * 0.15)
        ..lineTo(w * 0.30, cy - h * 0.30)
        ..lineTo(w * 0.46, cy - h * 0.15)
        ..close(),
      finPaint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.36, cy + h * 0.15)
        ..lineTo(w * 0.30, cy + h * 0.30)
        ..lineTo(w * 0.46, cy + h * 0.15)
        ..close(),
      finPaint,
    );

    // Porthole.
    canvas.drawCircle(
      Offset(w * 0.62, cy),
      h * 0.09,
      Paint()..color = const Color(0xFF6FC4E8),
    );
    canvas.drawCircle(
      Offset(w * 0.62, cy),
      h * 0.09,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = h * 0.02
        ..color = const Color(0xFFECEAF6),
    );
  }

  @override
  bool shouldRepaint(_RocketPainter oldDelegate) => oldDelegate.accent != accent;
}
