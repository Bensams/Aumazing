import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../../../config/game_motion.dart';
import '../buddy_art_cache.dart';
import '../greetings.dart';

/// What the buddy is doing right now.
enum BuddyState {
  /// Walking in from the side at the start of a round. Skipped entirely under
  /// [GameMotion.reduced] — a character sliding across the screen is exactly
  /// the kind of large motion that setting exists to remove.
  arriving,

  /// Standing, breathing, waiting. The neutral pose between greetings.
  resting,

  /// Holding a greeting out to the child. The bid is live.
  offering,

  /// Completing the greeting the child just returned — the palm meets, the
  /// wave is waved back. This is the reinforcement; there is no score to show.
  connecting,
}

/// The character the child greets.
///
/// Draws a sprite sheet when one decoded and a painted stand-in when it did
/// not, so a missing PNG costs the child a nice-looking buddy and nothing else.
///
/// Two therapeutic decisions live in this component:
///
/// * **The buddy never gives up.** [BuddyState.offering] holds indefinitely.
///   The skill is responding to a social bid, and a bid that expires teaches
///   that hesitating makes people leave.
/// * **There is no unhappy pose.** A wrong tap moves the buddy back to
///   [BuddyState.offering] — it re-offers the same greeting — rather than
///   showing disappointment. Reading an adult's disappointment is a harder
///   task than the one being taught.
class Buddy extends PositionComponent {
  Buddy({
    required this.art,
    required Vector2 position,
    required Vector2 size,
  }) : super(position: position, size: size, anchor: Anchor.bottomCenter) {
    _restPosition = position.clone();
  }

  /// Decoded sheets, or null when none loaded at all.
  final BuddyArtCache? art;

  late Vector2 _restPosition;

  BuddyState _state = BuddyState.resting;
  BuddyState get state => _state;

  /// The greeting currently being offered or completed, if any.
  Greeting? _greeting;
  Greeting? get greeting => _greeting;

  /// Seconds in the current state; drives frame selection and the walk-in.
  double _elapsed = 0;

  /// Extra scale applied while a gesture is being repeated as a prompt —
  /// rung 1 of the hierarchy is "bigger and slower", so amplitude is a
  /// property of the pose rather than a separate animation.
  double _emphasis = 1.0;

  /// Frames per second for gesture playback. Deliberately slow: 8 fps is the
  /// ceiling `CalmMascot` uses, and a greeting the child must *read* wants to
  /// be nearer the floor.
  static const double _fps = 6;

  /// How long the walk-in takes. Slow enough to be watched, short enough that
  /// it never becomes the thing the child is waiting for.
  static const double _arriveSeconds = 1.4;

  void setResting() {
    _state = BuddyState.resting;
    _greeting = null;
    _emphasis = 1.0;
    _elapsed = 0;
  }

  /// Offer [greeting]. [emphasis] > 1 plays it larger and slower, which is the
  /// first prompt rung.
  void offer(Greeting greeting, {double emphasis = 1.0}) {
    _state = BuddyState.offering;
    _greeting = greeting;
    // Reduced motion keeps the gesture but not the exaggeration: the prompt
    // still happens, it just doesn't grow.
    _emphasis = GameMotion.reduced ? 1.0 : emphasis;
    _elapsed = 0;
  }

  /// The greeting was returned — complete it.
  void connect() {
    if (_greeting == null) return;
    _state = BuddyState.connecting;
    _elapsed = 0;
  }

  /// Walk in from off-screen. Under reduced motion the buddy is simply already
  /// standing where it belongs.
  void arrive() {
    if (GameMotion.reduced) {
      setResting();
      return;
    }
    _state = BuddyState.arriving;
    _elapsed = 0;
    position = Vector2(-size.x, _restPosition.y);
  }

  /// Re-anchor after a resize; the game owns the layout arithmetic.
  void moveRestTo(Vector2 target) {
    _restPosition = target.clone();
    if (_state != BuddyState.arriving) position = target.clone();
  }

  /// The point on the buddy a returned greeting visually connects with — the
  /// raised hand, roughly. The ghost hand and the connect flash aim here.
  Vector2 get handPosition =>
      Vector2(position.x + size.x * 0.22, position.y - size.y * 0.62);

  @override
  void update(double dt) {
    super.update(dt);
    _elapsed += dt;

    if (_state == BuddyState.arriving) {
      final t = math.min(_elapsed / _arriveSeconds, 1.0);
      position = Vector2(
        _lerp(-size.x, _restPosition.x, _easeOut(t)),
        _restPosition.y,
      );
      if (t >= 1) setResting();
    }
  }

  // ── Rendering ────────────────────────────────────────────────────────

  String get _action {
    switch (_state) {
      case BuddyState.arriving:
        return 'walk';
      case BuddyState.resting:
        return 'idle';
      case BuddyState.offering:
      case BuddyState.connecting:
        return _greeting?.spriteAction ?? 'idle';
    }
  }

  int get _frame {
    final count = art?.frameCount(_action) ?? 0;
    if (count == 0) return 0;

    switch (_state) {
      case BuddyState.arriving:
        return (_elapsed * _fps * 1.6).floor() % count;
      case BuddyState.resting:
        // Idle breathes; it does not loop a gesture.
        return GameMotion.reduced ? 0 : (_elapsed * 2).floor() % count;
      case BuddyState.offering:
        // Play the gesture out, then HOLD the last frame — the offer stays on
        // the table. Slower when emphasised.
        return math.min((_elapsed * (_fps / _emphasis)).floor(), count - 1);
      case BuddyState.connecting:
        return math.min((_elapsed * _fps * 1.3).floor(), count - 1);
    }
  }

  @override
  void render(Canvas canvas) {
    final scale = _state == BuddyState.offering ? _emphasis : 1.0;
    final w = size.x * scale;
    final h = size.y * scale;
    // Grows from the feet, so an emphasised gesture never lifts the character
    // off the ground it was standing on.
    final dest = Rect.fromLTWH((size.x - w) / 2, size.y - h, w, h);

    if (art?.drawFrame(canvas, _action, _frame, dest) ?? false) return;
    _paintFallback(canvas, dest);
  }

  /// A plain, friendly stand-in used when no sheet decoded.
  ///
  /// It has to carry the *greeting*, not just the character: the child cannot
  /// answer a bid they cannot see. So the body is minimal and the offered hand
  /// is the same glyph the icon row uses, which guarantees the two match.
  void _paintFallback(Canvas canvas, Rect dest) {
    const skin = Color(0xFFF2DFC0);
    const ink = Color(0xFF5A5A6B);
    const body = Color(0xFF8FC4E6);

    final headR = dest.width * 0.24;
    final headC = Offset(dest.center.dx, dest.top + headR * 1.1);

    final torsoTop = headC.dy + headR * 0.95;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(dest.center.dx - dest.width * 0.22, torsoTop,
            dest.width * 0.44, math.max(dest.bottom - torsoTop, 1)),
        Radius.circular(dest.width * 0.14),
      ),
      Paint()..color = body,
    );

    canvas.drawCircle(headC, headR, Paint()..color = skin);
    canvas.drawCircle(
      headC,
      headR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = dest.width * 0.02
        ..color = ink,
    );
    for (final dx in [-headR * 0.35, headR * 0.35]) {
      canvas.drawCircle(headC.translate(dx, -headR * 0.05), headR * 0.11,
          Paint()..color = ink);
    }

    final greeting = _greeting;
    if (greeting != null && _state != BuddyState.resting) {
      final handSize = dest.width * 0.46;
      paintGreetingGlyph(
        canvas,
        greeting,
        Rect.fromCenter(
          center:
              Offset(dest.center.dx + dest.width * 0.30, headC.dy + headR * 0.2),
          width: handSize,
          height: handSize,
        ),
        skin: skin,
        ink: ink,
      );
    }
  }
}

double _lerp(double a, double b, double t) => a + (b - a) * t;

double _easeOut(double t) {
  final inv = 1 - t;
  return 1 - inv * inv * inv;
}
