import 'package:flame/components.dart';
import 'package:flutter/painting.dart' show PaintingBinding;

/// Rebuilds a component's [TextPaint]s whenever the engine finishes loading a
/// font, so text drawn before the font arrived is drawn again with it.
///
/// On the web the engine ships no emoji font. The first time a game draws an
/// emoji it gets a crossed-out placeholder box while Noto Color Emoji
/// downloads (or, offline, loads from the service worker's cache). Flutter
/// widgets re-lay out when that font lands, but a [TextPaint] keeps the first
/// layout of every string it renders for as long as it lives — so a basket
/// drawn on a game's first frame kept its placeholder box for the whole round.
/// Building fresh [TextPaint]s drops those stale layouts.
///
/// Mix into a component and move its [TextPaint] construction into
/// [buildTextPaints]:
///
/// ```dart
/// late TextPaint _emojiPaint;
///
/// @override
/// void buildTextPaints() {
///   _emojiPaint = TextPaint(style: TextStyle(fontSize: size.y * 0.5));
/// }
/// ```
///
/// The paints are built when the component mounts, before its first render,
/// and again on every font change while it stays mounted.
mixin FontAwareText on Component {
  /// Creates (or recreates) every [TextPaint] this component renders with.
  void buildTextPaints();

  @override
  void onMount() {
    super.onMount();
    buildTextPaints();
    PaintingBinding.instance.systemFonts.addListener(buildTextPaints);
  }

  @override
  void onRemove() {
    PaintingBinding.instance.systemFonts.removeListener(buildTextPaints);
    super.onRemove();
  }
}
