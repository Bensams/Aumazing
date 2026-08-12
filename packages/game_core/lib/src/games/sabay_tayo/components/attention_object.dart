import 'dart:math' as math;
import 'dart:ui' hide TextStyle, FontWeight;

import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flutter/animation.dart';
import 'package:flutter/painting.dart' show TextStyle, FontWeight;
import 'package:shared_ui/shared_ui.dart' show GameLanguage;

import '../../../config/game_motion.dart';
import '../../shared/shape_painter_3d.dart';

/// One of the things the buddy can look at.
///
/// The names are drawn from the sari-sari store set on purpose: those eighteen
/// words already have voice recordings in all three languages
/// (`voice_over/items/…`), so naming the object back to the child on a correct
/// answer costs nothing and turns each success into another paired exposure to
/// the word. Adding a novel object here without a recording would silently make
/// this game the only one that succeeds without saying what was found.
class AttentionObjectData {
  const AttentionObjectData({
    required this.name,
    required this.en,
    required this.emoji,
    required this.color,
  });

  /// Filipino name, e.g. 'Bola'. Also the stable identifier: the analytics slug
  /// and the key the audio layer maps to a recording.
  final String name;

  /// English display label, shown when the session language is English.
  final String en;

  /// Emoji glyph used as the object's visual.
  final String emoji;

  /// The object's own natural colour, used to tint its card.
  final Color color;

  /// The printed label for [language]. Tagalog and Cebuano share [name] —
  /// these are everyday household words and they agree in both.
  String label(GameLanguage language) {
    switch (language) {
      case GameLanguage.english:
        return en;
      case GameLanguage.tagalog:
      case GameLanguage.cebuano:
        return name;
    }
  }
}

/// A tappable object card in "Sabay Tayo!".
///
/// Deliberately plain. The one thing that must distinguish the target from the
/// distractors is *where the buddy is looking*, so nothing about a card's own
/// appearance may hint at it — same size, same treatment, and (on tier 2+) the
/// distractors are the ones given idle motion, not the target. A child who taps
/// the liveliest thing on screen is not sharing attention, and the game has to
/// be able to tell the difference.
class AttentionObject extends PositionComponent {
  AttentionObject({
    required this.data,
    required this.language,
    required this.slot,
    required Vector2 position,
    required Vector2 size,
    this.idles = false,
  }) : super(position: position, size: size, anchor: Anchor.center);

  final AttentionObjectData data;
  final GameLanguage language;

  /// Name of the gaze cell this card stands in (`'upLeft'`, `'up'`, …).
  /// Carried for analytics, so a confusion between two positions can be read
  /// back later without reconstructing the layout from pixels.
  final String slot;

  /// Whether this card carries its own small idle motion. Set on distractors
  /// only — see the class comment.
  final bool idles;

  /// True once this object has been correctly identified this trial.
  bool isResolved = false;

  bool _hinting = false;
  bool _dimmed = false;

  /// Drives the idle bob and the hint pulse. Offset per card so a row of
  /// distractors does not breathe in unison, which reads as one animation
  /// rather than several objects.
  double _time = 0;
  late final double _phase = math.Random().nextDouble() * math.pi * 2;

  late TextPaint _emojiPaint;
  late TextPaint _labelPaint;

  static const double _cornerRadius = 22.0;

  /// How far outside its visual bounds a tap still counts, as a fraction of
  /// the card's size.
  ///
  /// Matches the drop tolerance in `sari_sari_sort`. An imprecise tap is a
  /// motor miss, not a social-cognition miss; scoring it as the latter would
  /// make this game measure the wrong thing entirely.
  static const double tapTolerance = 0.20;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    _emojiPaint = TextPaint(style: TextStyle(fontSize: size.y * 0.42));
    _labelPaint = TextPaint(
      style: TextStyle(
        fontSize: size.y * 0.16,
        fontWeight: FontWeight.w700,
        color: const Color(0xFF4A4458),
      ),
    );
  }

  /// Whether [point] (in the parent's coordinate space) hits this card, with
  /// [tapTolerance] of slack on every side.
  bool containsGenerously(Vector2 point) {
    final half = size / 2 * (1 + tapTolerance);
    return (point.x - position.x).abs() <= half.x &&
        (point.y - position.y).abs() <= half.y;
  }

  /// The card's centre as fractions of a [playfield] of the given size —
  /// what the buddy's gaze is aimed with.
  Vector2 fractionOf(Vector2 playfieldSize, {double playfieldTop = 0}) {
    final usableHeight = playfieldSize.y - playfieldTop;
    return Vector2(
      (position.x / playfieldSize.x).clamp(0.0, 1.0),
      usableHeight <= 0
          ? 0.5
          : ((position.y - playfieldTop) / usableHeight).clamp(0.0, 1.0),
    );
  }

  /// Draw attention to this card — the third rung of the prompt hierarchy.
  void showHint() => _hinting = true;

  void hideHint() => _hinting = false;

  /// The response to being tapped by mistake: dim, settle, and stay put. No
  /// shake and no removal — the card was a reasonable guess and the child will
  /// need it on screen for the retry.
  void showWrong() {
    if (_dimmed) return;
    _dimmed = true;
    add(SequenceEffect(
      [
        ScaleEffect.to(
          Vector2.all(0.92),
          EffectController(duration: 0.18, curve: Curves.easeOut),
        ),
        ScaleEffect.to(
          Vector2.all(1.0),
          EffectController(duration: 0.24, curve: Curves.easeIn),
        ),
      ],
      onComplete: () => _dimmed = false,
    ));
  }

  /// The response to being found: lift and brighten, then hold. The lift is
  /// the reinforcement, so it is the one animation that plays even under
  /// reduced motion — muted, but present.
  void showFound() {
    isResolved = true;
    _hinting = false;
    final rise = GameMotion.reduced ? size.y * 0.04 : size.y * 0.12;
    add(MoveEffect.by(
      Vector2(0, -rise),
      EffectController(duration: 0.28, curve: Curves.easeOut),
    ));
    add(ScaleEffect.to(
      Vector2.all(GameMotion.reduced ? 1.04 : 1.12),
      EffectController(duration: 0.28, curve: Curves.easeOut),
    ));
  }

  @override
  void update(double dt) {
    super.update(dt);
    _time += dt;
  }

  /// Vertical offset for the idle bob. Slow (~0.2 Hz) and shallow — this is
  /// competition for the child's attention by design, but it must never become
  /// the loudest thing on the screen.
  double get _bob {
    if (!idles || isResolved || GameMotion.reduced) return 0;
    return math.sin(_time * 1.3 + _phase) * size.y * 0.025;
  }

  /// Scale for the hint pulse. Static under reduced motion: the highlight is
  /// still there, it simply does not move.
  double get _hintScale {
    if (!_hinting) return 1.0;
    if (GameMotion.reduced) return 1.06;
    return 1.0 + 0.06 * (0.5 + 0.5 * math.sin(_time * 5.0));
  }

  @override
  void render(Canvas canvas) {
    final rect = Rect.fromLTWH(0, 0, size.x, size.y);

    canvas.save();
    canvas.translate(0, _bob);
    if (_hinting) {
      final s = _hintScale;
      canvas.translate(size.x / 2, size.y / 2);
      canvas.scale(s, s);
      canvas.translate(-size.x / 2, -size.y / 2);

      // A soft wash behind the card rather than a ring: "lit up", not
      // "targeted". Same reasoning as the Hintay! star's halo.
      canvas.drawCircle(
        Offset(size.x / 2, size.y / 2),
        size.x * 0.78,
        Paint()
          ..shader = Gradient.radial(
            Offset(size.x / 2, size.y / 2),
            size.x * 0.78,
            const [Color(0x99FFF4C4), Color(0x00FFF4C4)],
            const [0.5, 1.0],
          ),
      );
    }

    ShapePainter3D.drawCard3D(
      canvas,
      rect,
      color: data.color,
      cornerRadius: _cornerRadius,
      alpha: _dimmed ? 150 : 255,
      showBorder: true,
      borderColor: const Color(0xFFFFFFFF).withAlpha(180),
      borderWidth: 3.0,
    );

    _emojiPaint.render(
      canvas,
      data.emoji,
      Vector2(size.x / 2, size.y * 0.40),
      anchor: Anchor.center,
    );

    // White backing pill so the label stays legible on any card colour.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.x * 0.08, size.y * 0.68, size.x * 0.84, size.y * 0.24),
        Radius.circular(size.y * 0.12),
      ),
      Paint()..color = const Color(0xFFFFFFFF).withAlpha(220),
    );
    _labelPaint.render(
      canvas,
      data.label(language),
      Vector2(size.x / 2, size.y * 0.80),
      anchor: Anchor.center,
    );

    canvas.restore();
  }
}
