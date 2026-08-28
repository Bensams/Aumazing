import 'package:flutter/widgets.dart';

/// Provides reward-specific SFX callbacks to reward widgets
/// without coupling shared_ui to shared_audio.
///
/// Usage (in main_app):
/// ```dart
/// RewardSfxProvider(
///   onBalloonPop: audioService.playBalloonPopSfx,
///   onBubblePop: audioService.playBubblePopSfx,
///   onFireworkPop: audioService.playFireworkPopSfx,
///   onCandyPop: audioService.playCandyPopSfx,
///   child: MaterialApp(...),
/// )
/// ```
class RewardSfxProvider extends InheritedWidget {
  final VoidCallback? onBalloonPop;
  final VoidCallback? onBubblePop;
  final VoidCallback? onFireworkPop;
  final VoidCallback? onCandyPop;

  const RewardSfxProvider({
    super.key,
    this.onBalloonPop,
    this.onBubblePop,
    this.onFireworkPop,
    this.onCandyPop,
    required super.child,
  });

  static RewardSfxProvider? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<RewardSfxProvider>();
  }

  /// Play balloon pop SFX if provider exists in tree.
  static void playBalloonPop(BuildContext context) {
    maybeOf(context)?.onBalloonPop?.call();
  }

  /// Play bubble pop SFX if provider exists in tree.
  static void playBubblePop(BuildContext context) {
    maybeOf(context)?.onBubblePop?.call();
  }

  /// Play firework pop SFX if provider exists in tree.
  static void playFireworkPop(BuildContext context) {
    maybeOf(context)?.onFireworkPop?.call();
  }

  /// Play candy pop SFX if provider exists in tree.
  static void playCandyPop(BuildContext context) {
    maybeOf(context)?.onCandyPop?.call();
  }

  @override
  bool updateShouldNotify(RewardSfxProvider oldWidget) {
    return onBalloonPop != oldWidget.onBalloonPop ||
        onBubblePop != oldWidget.onBubblePop ||
        onFireworkPop != oldWidget.onFireworkPop ||
        onCandyPop != oldWidget.onCandyPop;
  }
}
