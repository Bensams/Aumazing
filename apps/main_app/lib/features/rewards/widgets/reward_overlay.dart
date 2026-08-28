import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_haptic/shared_haptic.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../model/child_profile.dart';
import '../../../providers/child_provider.dart';
import '../reward_type.dart';

/// Full-screen reward overlay that displays the celebration effect
/// and waits for user interaction before completing
class RewardOverlay extends StatefulWidget {
  final RewardType rewardType;
  final VoidCallback onComplete;
  final VoidCallback? onAllItemsInteracted;
  final Duration minDisplayDuration;
  final bool showContinueButton;
  final String? continueButtonText;

  const RewardOverlay({
    super.key,
    required this.rewardType,
    required this.onComplete,
    this.onAllItemsInteracted,
    this.minDisplayDuration = const Duration(seconds: 10),
    this.showContinueButton = true,
    this.continueButtonText,
  });

  /// Create overlay from child's reward preference
  factory RewardOverlay.forChild({
    required ChildProfile profile,
    required VoidCallback onComplete,
    VoidCallback? onAllItemsInteracted,
    Duration minDisplayDuration = const Duration(seconds: 10),
    bool showContinueButton = true,
    String? continueButtonText,
  }) {
    final rewardType = RewardSelector.getRewardForChild(profile);
    return RewardOverlay(
      rewardType: rewardType,
      onComplete: onComplete,
      onAllItemsInteracted: onAllItemsInteracted,
      minDisplayDuration: minDisplayDuration,
      showContinueButton: showContinueButton,
      continueButtonText: continueButtonText,
    );
  }

  @override
  State<RewardOverlay> createState() => _RewardOverlayState();
}

class _RewardOverlayState extends State<RewardOverlay>
    with TickerProviderStateMixin {
  bool _canContinue = false;
  // Dialogue ("Great Job! You completed the game") is skipped — go straight to
  // the reward so non-reading children just pop it.
  final bool _showDialogue = false;
  final bool _showReward = true;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  late AnimationController _dialogueFadeController;
  late Animation<double> _dialogueFadeAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    ));

    _dialogueFadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200), // Faster fade out
    );
    _dialogueFadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _dialogueFadeController,
      curve: Curves.easeOut,
    ));
    _dialogueFadeController.forward();

    // Start the flow: dialogue (2s) → reward (6s) → auto proceed
    _startRewardFlow();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _dialogueFadeController.dispose();
    super.dispose();
  }

  void _startRewardFlow() {
    // Trigger celebration haptic feedback when reward flow starts
    if (context.read<ChildProvider>().vibrationEnabled) {
      context.read<HapticService>().celebrationFeedback();
    }

    // No text card — fade the reward in immediately so children just pop it.
    _fadeController.forward();

    // Floor before it can auto-complete, so quick popping still gets a moment.
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _canContinue = true);
    });

    // Auto-proceed once the reward has been shown for minDisplayDuration.
    Future.delayed(widget.minDisplayDuration, () {
      if (mounted && _canContinue) _onContinue();
    });
  }

  void _onContinue() {
    if (!_canContinue) return;

    // Fade out animation
    _fadeController.reverse().then((_) {
      if (mounted) {
        widget.onComplete();
      }
    });
  }

  void _onAllItemsInteracted() {
    if (widget.onAllItemsInteracted != null) {
      widget.onAllItemsInteracted!();
    }
    // Auto-complete after all items are interacted with
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted && _canContinue) {
        _onContinue();
      }
    });
  }

  Widget _buildRewardEffect() {
    // Scale particle counts to the graphics quality (fewer on lower tiers →
    // less GPU work / heat), keeping at least a few so the effect still reads.
    final scale = context.read<ChildProvider>().graphicsQuality.effectScale;
    int n(int base) => (base * scale).round().clamp(3, base);
    switch (widget.rewardType) {
      case RewardType.balloons:
        return BalloonsReward(
          onComplete: () {},
          onAllPopped: _onAllItemsInteracted,
          balloonCount: n(24),
          duration: const Duration(seconds: 12),
        );
      case RewardType.fireworks:
        return FireworksReward(
          onComplete: () {},
          onAllExploded: _onAllItemsInteracted,
          rocketCount: n(16),
          duration: const Duration(seconds: 12),
        );
      case RewardType.bubbles:
        return BubblesReward(
          onComplete: () {},
          onAllPopped: _onAllItemsInteracted,
          bubbleCount: n(30),
          duration: const Duration(seconds: 12),
        );
      case RewardType.candy:
        return CandyReward(
          onComplete: () {},
          onAllCollected: _onAllItemsInteracted,
          candyCount: n(28),
          duration: const Duration(seconds: 12),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isSmallScreen = size.width < 360 || size.height < 600;

    // Shown via showDialog with no Material ancestor, so Text inherits the
    // fallback DefaultTextStyle — which carries a yellow underline. Neutralize
    // the inherited decoration here so the hints and dialogue text are never
    // underlined, whatever way this overlay happens to be mounted.
    return DefaultTextStyle.merge(
      style: const TextStyle(
        decoration: TextDecoration.none,
        decorationColor: Colors.transparent,
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {},
        child: Container(
          color: Colors.transparent,
          child: SafeArea(
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Dialogue card (shown first for 2 seconds)
                if (_showDialogue)
                  FadeTransition(
                    opacity: _dialogueFadeAnimation,
                    child: _buildDialogueCard(),
                  ),

                // Reward effect layer (shown after dialogue fades)
                if (_showReward)
                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: SizedBox.expand(child: _buildRewardEffect()),
                  ),

                // Continue button overlay
                if (_showReward && widget.showContinueButton)
                  Positioned(
                    bottom: 40,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: AnimatedOpacity(
                        opacity: _canContinue ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 300),
                        child: ElevatedButton.icon(
                          onPressed: _canContinue ? _onContinue : null,
                          icon: const Icon(Icons.arrow_forward, size: 20),
                          label: Text(
                            widget.continueButtonText ?? 'Continue',
                            style: TextStyle(
                              fontSize: isSmallScreen ? 14 : 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white.withAlpha(230),
                            foregroundColor: const Color(0xFF9B82C4),
                            padding: EdgeInsets.symmetric(
                              horizontal: isSmallScreen ? 20 : 28,
                              vertical: isSmallScreen ? 10 : 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                            elevation: 4,
                            shadowColor: Colors.black.withAlpha(50),
                          ),
                        ),
                      ),
                    ),
                  ),

                // Hint text
                if (_showReward)
                  Positioned(
                    top: 60,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: isSmallScreen ? 12 : 16,
                          vertical: isSmallScreen ? 6 : 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(200),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          _getHintText(),
                          style: TextStyle(
                            fontSize: isSmallScreen ? 14 : 16,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF9B82C4),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDialogueCard() {
    final size = MediaQuery.of(context).size;
    final isSmallScreen = size.width < 360 || size.height < 600;

    return Center(
      child: Container(
        margin: EdgeInsets.symmetric(horizontal: isSmallScreen ? 20 : 40),
        padding: EdgeInsets.symmetric(
          horizontal: isSmallScreen ? 24 : 40,
          vertical: isSmallScreen ? 30 : 48,
        ),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFE8DEFA), Color(0xFFD4F4E8)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(20),
              blurRadius: 20,
              spreadRadius: 4,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '🎉 Great Job!',
              style: TextStyle(
                fontSize: isSmallScreen ? 28 : 36,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF9B82C4),
              ),
            ),
            SizedBox(height: isSmallScreen ? 12 : 16),
            Text(
              'You completed the game!',
              style: TextStyle(
                fontSize: isSmallScreen ? 16 : 20,
                color: const Color(0xFF666666),
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: isSmallScreen ? 20 : 28),
            const CircularProgressIndicator(
              color: Color(0xFF9B82C4),
              strokeWidth: 3,
            ),
          ],
        ),
      ),
    );
  }

  String _getHintText() {
    switch (widget.rewardType) {
      case RewardType.balloons:
        return '🎈 Pop the balloons!';
      case RewardType.fireworks:
        return '🎆 Tap the rockets!';
      case RewardType.bubbles:
        return '🫧 Pop the bubbles!';
      case RewardType.candy:
        return '🍬 Collect the candy!';
    }
  }
}

/// Extension to show reward overlay as a dialog
extension RewardOverlayExtension on BuildContext {
  /// Shows a reward overlay as a full-screen dialog
  Future<void> showRewardOverlay({
    required RewardType rewardType,
    Duration minDisplayDuration = const Duration(seconds: 10),
    bool barrierDismissible = false,
  }) {
    return showDialog(
      context: this,
      barrierDismissible: barrierDismissible,
      barrierColor: Colors.transparent,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: RewardOverlay(
          rewardType: rewardType,
          onComplete: () => Navigator.of(dialogContext).pop(),
          minDisplayDuration: minDisplayDuration,
        ),
      ),
    );
  }

  /// Shows reward overlay based on child's preference
  Future<void> showRewardForChild({
    required ChildProfile profile,
    Duration minDisplayDuration = const Duration(seconds: 10),
    bool barrierDismissible = false,
  }) {
    final rewardType = RewardSelector.getRewardForChild(profile);
    return showRewardOverlay(
      rewardType: rewardType,
      minDisplayDuration: minDisplayDuration,
      barrierDismissible: barrierDismissible,
    );
  }
}
