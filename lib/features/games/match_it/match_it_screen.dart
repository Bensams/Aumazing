import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_gradients.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/child_mode_top_bar.dart';
import '../../../core/widgets/large_game_object_card.dart';
import '../../../core/widgets/parent_verification_dialog.dart';
import '../../../core/widgets/voice_over_prompt_bubble.dart';

/// Example child game screen: "Match It"
///
/// Demonstrates the landscape-oriented, ASD-friendly layout using the
/// full design system: gradient background, large touch targets, progress
/// dots, voice-over bubble, parent lock button, and gentle animations.
class MatchItScreen extends StatefulWidget {
  const MatchItScreen({super.key});

  @override
  State<MatchItScreen> createState() => _MatchItScreenState();
}

class _MatchItScreenState extends State<MatchItScreen> {
  static const _totalSteps = 5;
  int _currentStep = 0;
  int? _selectedLeft;
  int? _selectedRight;
  bool _showPrompt = true;

  final List<_MatchPair> _pairs = const [
    _MatchPair(icon: Icons.star_rounded, color: AppColors.butterYellow, label: 'Star'),
    _MatchPair(icon: Icons.favorite_rounded, color: AppColors.peach, label: 'Heart'),
    _MatchPair(icon: Icons.circle, color: AppColors.mint, label: 'Circle'),
  ];

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  void _onLeftTap(int index) {
    setState(() {
      _selectedLeft = index;
      _showPrompt = false;
    });
    _checkMatch();
  }

  void _onRightTap(int index) {
    setState(() {
      _selectedRight = index;
      _showPrompt = false;
    });
    _checkMatch();
  }

  void _checkMatch() {
    if (_selectedLeft != null && _selectedRight != null) {
      if (_selectedLeft == _selectedRight) {
        Future.delayed(const Duration(milliseconds: 500), () {
          if (!mounted) return;
          setState(() {
            _currentStep = (_currentStep + 1).clamp(0, _totalSteps - 1);
            _selectedLeft = null;
            _selectedRight = null;
          });
        });
      } else {
        Future.delayed(const Duration(milliseconds: 600), () {
          if (!mounted) return;
          setState(() {
            _selectedLeft = null;
            _selectedRight = null;
          });
        });
      }
    }
  }

  Future<void> _handleParentTap() async {
    final verified = await ParentVerificationDialog.show(context);
    if (verified && mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppGradients.matchIt),
        child: Column(
          children: [
            ChildModeTopBar(
              totalSteps: _totalSteps,
              currentStep: _currentStep,
              onParentTap: _handleParentTap,
            ),

            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
                child: Row(
                  children: [
                    // Left column: prompt objects
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(_pairs.length, (i) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.sm,
                            ),
                            child: LargeGameObjectCard(
                              size: 128,
                              color: _pairs[i].color.withAlpha(60),
                              isHighlighted: _selectedLeft == i,
                              onTap: () => _onLeftTap(i),
                              child: Icon(
                                _pairs[i].icon,
                                size: 56,
                                color: _pairs[i].color,
                              ),
                            ),
                          );
                        }),
                      ),
                    ),

                    // Center divider / instruction
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Match!',
                            style: AppTextStyles.headlineLarge.copyWith(
                              color: AppColors.primaryPurple.withAlpha(180),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Icon(
                            Icons.swap_horiz_rounded,
                            size: 40,
                            color: AppColors.primaryPurple.withAlpha(120),
                          ),
                        ],
                      ),
                    ),

                    // Right column: answer objects (shuffled order)
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(_pairs.length, (i) {
                          final ri = (_pairs.length - 1) - i;
                          return Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.sm,
                            ),
                            child: LargeGameObjectCard(
                              size: 128,
                              color: _pairs[ri].color.withAlpha(60),
                              isHighlighted: _selectedRight == ri,
                              onTap: () => _onRightTap(ri),
                              child: Icon(
                                _pairs[ri].icon,
                                size: 56,
                                color: _pairs[ri].color,
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Voice-over prompt area
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: VoiceOverPromptBubble(
                text: 'Tap the shapes that look the same!',
                isVisible: _showPrompt,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MatchPair {
  const _MatchPair({
    required this.icon,
    required this.color,
    required this.label,
  });

  final IconData icon;
  final Color color;
  final String label;
}
