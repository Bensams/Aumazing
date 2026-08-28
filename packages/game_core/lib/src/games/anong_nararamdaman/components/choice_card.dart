import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:shared_ui/shared_ui.dart' show GameLanguage;

import '../../../config/game_motion.dart';
// Shared rather than copied: the printed name has to look the same everywhere
// in the app, and a second layout cache would drift from this one the first
// time either was tuned.
import '../../anong_susunod/components/step_label.dart';
import '../emotion_art_cache.dart';
import '../emotions.dart';

/// One large tappable answer card — a face, or a caring response.
///
/// Two things about it matter more than its looks:
///
/// * **The hit box is 20% larger than the drawing** (see [containsLocal]),
///   exactly as `sari_sari_sort` inflates its bins. A child aiming at a face
///   card with an imprecise reach lands just outside it more often than they
///   land on the wrong one, and a near-miss scored as a wrong answer is a
///   recognition error the child did not make. The visual bounds stay honest;
///   only the touch bounds grow.
/// * **A wrong tap dims and settles back.** It does not shake, flash red, or
///   disappear. The card is not wrong — the child looked at the wrong picture,
///   and the difference matters in a game about feelings, where "no, that is
///   not sad" is one short step from "no, that is not how you feel".
abstract class ChoiceCard extends PositionComponent {
  ChoiceCard({
    required this.language,
    required Vector2 position,
    required Vector2 size,
  }) : super(position: position, size: size, anchor: Anchor.center);

  /// The language the printed label is drawn in — the child's, not the
  /// device's.
  final GameLanguage language;

  final StepLabel _label = StepLabel();

  /// Under the child's finger right now.
  bool pressed = false;

  /// Dimmed and settling back after a wrong tap, or faded out by the
  /// narrow-the-field prompt. Both look the same on purpose: the card recedes,
  /// it is never marked.
  bool dimmed = false;

  /// The correct card, pulsing as the third rung of the prompt hierarchy.
  bool pulsing = false;

  /// Locked in as the answer — held bright while the trial resolves.
  bool chosen = false;

  double _t = 0;

  static const Color _surface = Color(0xFFFFFDF8);
  static const Color _outline = Color(0x333F3B4A);
  static const Color _primary = Color(0xFF9B82C4);
  static const Color _butter = Color(0xFFFFF4C4);

  /// What the card's picture is; drawn into a square box by the subclass.
  void paintArt(Canvas canvas, Offset origin, double size);

  /// The word printed under the picture.
  String get labelText;

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
  }

  /// Hit test with the bounds inflated by [_touchSlack] on every side.
  ///
  /// Cards are laid out with a gap wider than twice the slack, so two inflated
  /// boxes never overlap and the generosity can never turn a tap meant for one
  /// card into a hit on its neighbour.
  bool containsLocal(Vector2 point) {
    final half = size / 2;
    return (point.x - position.x).abs() <= half.x * _touchSlack &&
        (point.y - position.y).abs() <= half.y * _touchSlack;
  }

  /// 1.2 — a fifth wider than the card looks.
  static const double _touchSlack = 1.2;

  @override
  void render(Canvas canvas) {
    final rect = Rect.fromLTWH(0, 0, size.x, size.y);
    final radius = size.x * 0.14;

    // Dimmed cards recede rather than vanish, so the field the child is
    // choosing from still looks like the field they were given.
    final opacity = dimmed ? 0.32 : 1.0;

    // A slow, shallow pulse on the hinted card. Under reduced motion the warm
    // ring alone carries it — the state is never conveyed by movement only.
    var scale = 1.0;
    if (pulsing && !GameMotion.reduced) {
      scale = 1.0 + 0.045 * (0.5 + 0.5 * _wave(_t * 1.4));
    } else if (pressed) {
      scale = 0.97;
    }

    canvas.save();
    if (scale != 1.0) {
      canvas.translate(size.x / 2, size.y / 2);
      canvas.scale(scale);
      canvas.translate(-size.x / 2, -size.y / 2);
    }

    final rr = RRect.fromRectXY(rect, radius, radius);

    canvas.drawRRect(
      RRect.fromRectXY(rect.translate(0, chosen ? 5 : 3), radius, radius),
      Paint()..color = Color.fromRGBO(63, 59, 74, 0.10 * opacity),
    );

    canvas.drawRRect(rr, Paint()..color = _surface.withValues(alpha: opacity));

    if (pulsing || chosen) {
      canvas.drawRRect(
        RRect.fromRectXY(rect.inflate(5), radius + 4, radius + 4),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..color = _butter.withValues(alpha: opacity),
      );
    }

    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = pulsing || chosen ? 4 : 2.5
        ..color = (pulsing || chosen ? _primary : _outline)
            .withValues(alpha: opacity),
    );

    // The picture keeps the bulk of the card; the name takes a strip along the
    // bottom, sized so a two-line label still clears the rounded corner.
    final labelBand = size.y * 0.24;
    final pictureHeight = size.y - labelBand;
    final art = math.min(size.x * 0.8, pictureHeight * 0.92);

    canvas.saveLayer(
        rect.inflate(8), Paint()..color = Color.fromRGBO(255, 255, 255, opacity));
    paintArt(
      canvas,
      Offset((size.x - art) / 2, (pictureHeight - art) / 2),
      art,
    );
    canvas.restore();

    _label.paint(
      canvas,
      labelText,
      origin: Offset(size.x * 0.06, pictureHeight),
      width: size.x * 0.88,
      height: labelBand,
      fontSize: math.max(9.0, size.x * 0.125),
    );

    canvas.restore();
  }

  static double _wave(double t) {
    // Cheap triangle wave — no trig needed for a slow breathe.
    final f = t % 1.0;
    return f < 0.5 ? f * 2 : 2 - f * 2;
  }
}

/// A face card: one of the five emotions, drawn at full expression.
class EmotionCard extends ChoiceCard {
  EmotionCard({
    required this.emotion,
    required super.language,
    required super.position,
    required super.size,
  });

  final Emotion emotion;

  @override
  void paintArt(Canvas canvas, Offset origin, double size) =>
      drawFace(canvas, emotion, origin, size);

  @override
  String get labelText => emotion.label(language);
}

/// A "what would you do?" card — tier 3's second question.
class ResponseCard extends ChoiceCard {
  ResponseCard({
    required this.response,
    required super.language,
    required super.position,
    required super.size,
  });

  final CaringResponse response;

  @override
  void paintArt(Canvas canvas, Offset origin, double size) =>
      drawResponse(canvas, response.art, origin, size);

  @override
  String get labelText => response.label(language);
}
