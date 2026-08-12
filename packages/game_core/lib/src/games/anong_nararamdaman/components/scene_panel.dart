import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:shared_ui/shared_ui.dart' show GameLanguage;

import '../../anong_susunod/components/step_label.dart';
import '../emotion_art_cache.dart';
import '../emotions.dart';

/// The situation card: what happened, as a picture with a short caption.
///
/// It is not tappable. The child's answer is a face, and a scene that responded
/// to touch would invite tapping the thing they are being asked to look at.
///
/// On tier 3 the panel is **hidden for the response step** ([visible] goes
/// false). That is the whole reason the second question is worth asking: with
/// the picture still up, "what would you do?" can be answered off the scene
/// without ever consulting the feeling. Hidden, the only thing left on screen to
/// reason from is the buddy's face — so the child has to carry the emotion
/// forward, which is the skill being probed.
class ScenePanel extends PositionComponent {
  ScenePanel({
    required this.language,
    required Vector2 position,
    required Vector2 size,
  }) : super(position: position, size: size, anchor: Anchor.center);

  final GameLanguage language;

  final StepLabel _caption = StepLabel();

  EmotionScene? scene;

  /// Hidden during tier 3's response step — see the class doc.
  bool visible = true;

  static const Color _surface = Color(0xFFFFFDF8);
  static const Color _outline = Color(0x333F3B4A);

  @override
  void render(Canvas canvas) {
    final current = scene;
    if (!visible || current == null) return;

    final rect = Rect.fromLTWH(0, 0, size.x, size.y);
    final radius = size.x * 0.09;
    final rr = RRect.fromRectXY(rect, radius, radius);

    canvas.drawRRect(
      RRect.fromRectXY(rect.translate(0, 3), radius, radius),
      Paint()..color = const Color(0x1A3F3B4A),
    );
    canvas.drawRRect(rr, Paint()..color = _surface);
    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = _outline,
    );

    final captionBand = size.y * 0.22;
    final pictureHeight = size.y - captionBand;
    final art = math.min(size.x * 0.86, pictureHeight * 0.94);
    drawScene(
      canvas,
      current.art,
      Offset((size.x - art) / 2, (pictureHeight - art) / 2),
      art,
    );

    _caption.paint(
      canvas,
      current.caption(language),
      origin: Offset(size.x * 0.06, pictureHeight),
      width: size.x * 0.88,
      height: captionBand,
      fontSize: math.max(9.0, size.x * 0.075),
    );
  }
}
