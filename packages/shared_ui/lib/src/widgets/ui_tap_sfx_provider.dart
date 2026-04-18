import 'package:flutter/widgets.dart';

/// Callback type for playing a UI tap sound effect.
typedef UiTapSfxCallback = Future<void> Function();

/// An [InheritedWidget] that provides a tap-SFX callback to descendant
/// widgets (buttons, cards, etc.) without coupling shared_ui to shared_audio.
///
/// Wrap your [MaterialApp] (or a subtree) with this provider and supply
/// the [AudioService.playButtonTap] method as the [onTap] callback.
///
/// Example (in main_app):
/// ```dart
/// UiTapSfxProvider(
///   onTap: audioService.playButtonTap,
///   child: MaterialApp(...),
/// )
/// ```
class UiTapSfxProvider extends InheritedWidget {
  const UiTapSfxProvider({
    super.key,
    required this.onTap,
    required super.child,
  });

  /// The callback to invoke when a UI button is tapped.
  final UiTapSfxCallback onTap;

  /// Play the tap sound if a [UiTapSfxProvider] exists above [context].
  ///
  /// Silently does nothing when no provider is found (e.g. inside a Flame
  /// game screen that intentionally omits it).
  static void play(BuildContext context) {
    final provider =
        context.dependOnInheritedWidgetOfExactType<UiTapSfxProvider>();
    provider?.onTap();
  }

  /// Returns the provider if one exists above [context], or null.
  static UiTapSfxProvider? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<UiTapSfxProvider>();
  }

  @override
  bool updateShouldNotify(UiTapSfxProvider oldWidget) =>
      onTap != oldWidget.onTap;
}
