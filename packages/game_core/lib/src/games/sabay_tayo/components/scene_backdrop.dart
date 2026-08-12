import 'dart:ui';

import 'package:flame/components.dart';

/// The ground the buddy stands on, and nothing else.
///
/// Purely decorative — it never handles a touch and is drawn behind every
/// interactive component. Its whole job is to give the buddy a floor: a
/// character with no ground under it reads as a picture pasted onto the screen,
/// and this game needs the child to treat it as *someone in the room with
/// them*, because that is the difference between following a gaze and matching
/// a symbol.
///
/// Far emptier than [StoreBackdrop], and that is the design. Every trial asks
/// the child to find the one thing being looked at, so anything else drawn on
/// the field is a competing candidate. Two bands and a soft pool of shade under
/// the buddy's feet is the whole scene.
class SceneBackdrop extends PositionComponent {
  SceneBackdrop({
    required Vector2 position,
    required Vector2 size,
    required this.groundTop,
    required this.buddyFootX,
  }) : super(position: position, size: size, priority: -10);

  /// Y (local) where the floor meets the back wall.
  final double groundTop;

  /// X (local) of the buddy's feet, for the contact shadow.
  final double buddyFootX;

  // Low-arousal palette, one step quieter than the object cards. The room
  // recedes; the objects and the buddy keep the contrast budget.
  static const _wall = Color(0xFFF3EFE7);
  static const _floor = Color(0xFFE4DCCE);
  static const _seam = Color(0xFFD5CABA);

  @override
  void render(Canvas canvas) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.x, groundTop),
      Paint()..color = _wall,
    );
    canvas.drawRect(
      Rect.fromLTWH(0, groundTop, size.x, size.y - groundTop),
      Paint()..color = _floor,
    );
    canvas.drawLine(
      Offset(0, groundTop),
      Offset(size.x, groundTop),
      Paint()
        ..color = _seam
        ..strokeWidth = 2,
    );

    // Contact shadow: a flat ellipse under the feet. Without it the buddy
    // floats, and a floating character is harder to read as a person facing a
    // direction in the same space as the objects.
    final shadowY = size.y - (size.y - groundTop) * 0.14;
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(buddyFootX, shadowY),
        width: size.x * 0.16,
        height: size.y * 0.045,
      ),
      Paint()..color = const Color(0x1A5A5A6B),
    );
  }
}
