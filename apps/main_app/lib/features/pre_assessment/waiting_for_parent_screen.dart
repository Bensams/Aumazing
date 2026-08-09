import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_audio/shared_audio.dart';
import 'package:shared_ui/shared_ui.dart' hide AnimatedBuilder;

import '../../model/ai_assessment_response.dart';
import '../../model/assessment_result.dart';
import '../../model/support_profile.dart';
import '../../widgets/mascot.dart';
import 'game_summary_dialog.dart';
import 'pre_assessment_result_screen.dart';

/// Screen shown to the child after all pre-assessment games are complete.
///
/// First displays a celebration phase with a trophy and "You did it!" message
/// for ~4.5 seconds, then transitions to the parent-verification content.
class WaitingForParentScreen extends StatefulWidget {
  const WaitingForParentScreen({
    super.key,
    required this.results,
    required this.profile,
    this.aiResponse,
  });

  final List<AssessmentResult> results;
  final SupportProfile profile;

  /// AI prediction data, or null if AI was unavailable (rule-based fallback).
  final AiAssessmentResponse? aiResponse;

  @override
  State<WaitingForParentScreen> createState() => _WaitingForParentScreenState();
}

class _WaitingForParentScreenState extends State<WaitingForParentScreen>
    with TickerProviderStateMixin {
  /// Whether the celebration phase is currently showing.
  bool _showCelebration = true;

  Timer? _celebrationTimer;

  // ── Celebration animations ──────────────────────────────────────────
  late final AnimationController _trophyScaleController;
  late final Animation<double> _trophyScale;

  late final AnimationController _textFadeController;
  late final Animation<double> _textFade;

  late final AnimationController _starsController;

  @override
  void initState() {
    super.initState();
    // Still a child-facing screen — stays landscape with the activities.
    lockParentLandscape();

    // Trophy bounce-in animation
    _trophyScaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _trophyScale = CurvedAnimation(
      parent: _trophyScaleController,
      curve: Curves.elasticOut,
    );

    // Text fade-in animation (starts slightly after trophy)
    _textFadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _textFade = CurvedAnimation(
      parent: _textFadeController,
      curve: Curves.easeIn,
    );

    // Floating stars/emojis animation
    _starsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    );

    // Start the celebration sequence
    _trophyScaleController.forward();
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _textFadeController.forward();
    });
    _starsController.forward();

    // Play celebration SFX
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        final audioService = context.read<AudioService>();
        audioService.playGameCompleteSfx();
      } catch (_) {
        // AudioService may not be available; ignore gracefully.
      }
    });

    // Auto-dismiss celebration after 4.5 seconds
    _celebrationTimer = Timer(const Duration(milliseconds: 4500), () {
      if (mounted) {
        setState(() => _showCelebration = false);
      }
    });
  }

  @override
  void dispose() {
    _celebrationTimer?.cancel();
    _trophyScaleController.dispose();
    _textFadeController.dispose();
    _starsController.dispose();
    super.dispose();
  }

  // ── Parent verification flow (unchanged) ────────────────────────────

  void _showParentVerification(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const ParentVerificationDialog(),
    ).then((verified) {
      if (verified == true && context.mounted) {
        _showSummaryDialog(context);
      }
    });
  }

  void _showSummaryDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => GameSummaryDialog(
        results: widget.results,
        aiResponse: widget.aiResponse,
        onContinue: () {
          Navigator.of(dialogContext).pop();
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => PreAssessmentResultScreen(
                profile: widget.profile,
                results: widget.results,
                aiResponse: widget.aiResponse,
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Build ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 600),
        switchInCurve: Curves.easeIn,
        switchOutCurve: Curves.easeOut,
        child: _showCelebration
            ? _buildCelebration(context)
            : _buildWaitingContent(context),
      ),
    );
  }

  // ── Celebration phase ───────────────────────────────────────────────

  Widget _buildCelebration(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Container(
      key: const ValueKey('celebration'),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFFFF3E0), // warm cream/orange top
            Color(0xFFFFE0B2), // soft amber
            Color(0xFFFFF9C4), // light yellow bottom
          ],
        ),
      ),
      child: SafeArea(
        child: AnimatedBuilder(
          animation:
              Listenable.merge([_trophyScaleController, _starsController]),
          builder: (context, _) {
            return Stack(
              fit: StackFit.expand,
              children: [
                // Floating celebration emojis
                ..._buildFloatingEmojis(size),

                // Center content: trophy + text
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Trophy with scale animation
                      ScaleTransition(
                        scale: _trophyScale,
                        child: const Text(
                          '🏆',
                          style: TextStyle(fontSize: 96),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // "You did it!" text with fade animation
                      FadeTransition(
                        opacity: _textFade,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'You did it!',
                              style: AppTextStyles.headlineLarge.copyWith(
                                fontSize: 36,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFFE65100),
                                letterSpacing: 1.2,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'You finished all the games!',
                              style: AppTextStyles.titleMedium.copyWith(
                                color: const Color(0xFFBF360C),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Star sparkle below the trophy
                      FadeTransition(
                        opacity: _textFade,
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('⭐', style: TextStyle(fontSize: 28)),
                            SizedBox(width: 8),
                            Text('🌟', style: TextStyle(fontSize: 32)),
                            SizedBox(width: 8),
                            Text('⭐', style: TextStyle(fontSize: 28)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Generates floating emoji widgets that drift upward during the celebration.
  List<Widget> _buildFloatingEmojis(Size screenSize) {
    const emojis = ['⭐', '🌟', '✨', '💫', '🎉', '🎈', '🏆', '💖', '🎊'];
    final count = 18;
    final widgets = <Widget>[];

    for (var i = 0; i < count; i++) {
      final emoji = emojis[i % emojis.length];
      // Distribute across the screen width
      final xFraction = (i * 0.0618 + 0.05) % 1.0; // golden-ratio spacing
      final delay = (i * 0.05) % 0.6;
      final speed = 0.3 + (i % 5) * 0.15;
      final fontSize = 18.0 + (i % 4) * 6.0;

      final t = (_starsController.value - delay).clamp(0.0, 1.0) /
          (1.0 - delay).clamp(0.01, 1.0);
      final progress = t.clamp(0.0, 1.0);
      final y = 1.0 - progress * speed;
      final x = xFraction +
          (progress * 3.14159 * 2).clamp(0.0, 6.28) *
              0.02 *
              ((i % 2 == 0) ? 1 : -1);

      widgets.add(
        Positioned(
          left: x * screenSize.width,
          top: y * screenSize.height,
          child: Opacity(
            opacity: (1.0 - progress).clamp(0.0, 1.0) * 0.8,
            child: Text(emoji, style: TextStyle(fontSize: fontSize)),
          ),
        ),
      );
    }

    return widgets;
  }

  /// The BPS mascot: waves hello when this phase appears, then rests with a
  /// gentle breathing idle. Falls back to the celebration-emoji circle while
  /// the sprite sheets are still loading (or if they fail to load).
  Widget _buildMascot(BuildContext context) {
    return Mascot(
      height: 140,
      fallback: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          color: AppColors.lavenderLight.withAlpha(150),
          shape: BoxShape.circle,
        ),
        child: const Center(
          child: Text('🎉', style: TextStyle(fontSize: 40)),
        ),
      ),
    );
  }

  // ── Waiting-for-parent phase (original content) ─────────────────────

  Widget _buildWaitingContent(BuildContext context) {
    return Container(
      key: const ValueKey('waiting'),
      decoration:
          const BoxDecoration(gradient: AppGradients.parentLavenderMint),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildMascot(context),
                const SizedBox(height: 16),

                Text(
                  'Great Job!',
                  style: AppTextStyles.headlineLarge.copyWith(
                    color: AppColors.primaryPurple,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),

                Text(
                  'You finished all the games!',
                  style: AppTextStyles.titleMedium.copyWith(
                    color: AppColors.mutedForeground,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),

                // Waiting message for child
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 16),
                  decoration: BoxDecoration(
                    color: AppColors.white.withAlpha(200),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('⏳', style: TextStyle(fontSize: 28)),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Please give the device to your parent.',
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: AppColors.foreground,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              'They will review your results.',
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.mutedForeground,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Parent verification button
                SizedBox(
                  width: 220,
                  child: AppPrimaryButton(
                    label: 'I\'m the Parent',
                    icon: Icons.verified_user_rounded,
                    onPressed: () => _showParentVerification(context),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Parents: Tap above to view results',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.mutedForeground,
                    fontStyle: FontStyle.italic,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
