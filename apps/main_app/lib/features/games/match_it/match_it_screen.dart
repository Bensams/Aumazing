import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:game_core/game_core.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../providers/assessment_provider.dart';
import '../../../providers/child_provider.dart';

/// Child game screen: "Match It"
///
/// Uses a hybrid Flutter + Flame architecture:
/// - Flutter: ChildModeTopBar (progress dots + parent lock) and VoiceOverPromptBubble
/// - Flame: GameWidget hosting MatchItGame for the interactive game area
class MatchItScreen extends StatefulWidget {
  const MatchItScreen({
    super.key,
    this.assessmentContext = 'practice',
  });

  /// 'pre_assessment', 'post_assessment', or 'practice'
  final String assessmentContext;

  @override
  State<MatchItScreen> createState() => _MatchItScreenState();
}

class _MatchItScreenState extends State<MatchItScreen> {
  static const _totalRounds = 5;
  int _currentStep = 0;
  bool _showPrompt = true;
  bool _gameComplete = false;
  late final MatchItGame _game;
  late final DateTime _sessionStartTime;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    _sessionStartTime = DateTime.now();

    _game = MatchItGame(
      totalRounds: _totalRounds,
      onStepChanged: _onStepChanged,
      onGameComplete: _onGameComplete,
    );
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  void _onStepChanged(int step) {
    setState(() {
      _currentStep = step;
      _showPrompt = false;
    });
  }

  void _onGameComplete({
    required int score,
    required int totalItems,
    required int errorCount,
    required int totalResponseTimeMs,
  }) {
    setState(() => _gameComplete = true);

    // Record the session in the assessment provider
    final childProvider = context.read<ChildProvider>();
    final assessmentProvider = context.read<AssessmentProvider>();
    final childId = childProvider.profile?.id ?? 'unknown';

    assessmentProvider.recordGameSession(
      childId: childId,
      gameId: 'match_it',
      context: widget.assessmentContext,
      score: score,
      totalItems: totalItems,
      errorCount: errorCount,
      totalResponseTimeMs: totalResponseTimeMs,
      startedAt: _sessionStartTime,
    );

    // Show completion feedback
    if (mounted) {
      _showCompletionDialog(score, totalItems, errorCount);
    }
  }

  void _showCompletionDialog(int score, int totalItems, int errorCount) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🎉', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            Text(
              'Great Job!',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: const Color(0xFF9B82C4),
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'You matched $score out of $totalItems shapes!',
              textAlign: TextAlign.center,
            ),
            if (errorCount == 0)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('Perfect — no mistakes! ⭐',
                    style: TextStyle(color: Color(0xFFB8E8D4))),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(); // Close dialog
              Navigator.of(context).pop(); // Return to previous screen
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );
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
            // Flutter: Top bar with progress + parent lock
            ChildModeTopBar(
              totalSteps: _totalRounds,
              currentStep: _currentStep,
              onParentTap: _handleParentTap,
            ),

            // Flame: Game area
            Expanded(
              child: GameWidget(
                game: _game,
                backgroundBuilder: (_) => const SizedBox.shrink(),
              ),
            ),

            // Flutter: Voice-over prompt
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: VoiceOverPromptBubble(
                text: _gameComplete
                    ? 'Well done! You finished the game!'
                    : 'Tap the shapes that look the same!',
                isVisible: _showPrompt || _gameComplete,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
