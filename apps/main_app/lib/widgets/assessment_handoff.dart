import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_audio/shared_audio.dart';
import 'package:shared_ui/shared_ui.dart' hide AnimatedBuilder;

import '../providers/child_provider.dart';
import 'mascot.dart';
import 'milestone_victory_scene.dart';

/// Builds the narrator the hand-off screen speaks through.
///
/// Injectable so a widget test can observe the cue without a platform audio
/// player; production always gets the real service built from the child's own
/// voice settings.
typedef HandoffVoiceOverFactory = VoiceOverService Function(
    BuildContext context);

/// How long the trophy celebration holds before the hand-off panel replaces it.
const Duration kHandoffCelebrationDuration = Duration(milliseconds: 4500);

/// How long after the hand-off panel appears the narrator speaks.
///
/// The cross-fade is 600 ms, so this lets the panel settle and the voice
/// arrive with the instruction it is describing rather than over the
/// celebration it is replacing.
const Duration kHandoffVoiceDelay = Duration(milliseconds: 700);

/// The child-facing end of an assessment: celebrate, then ask the child to
/// hand the device over, and gate the parent-facing results behind
/// [ParentVerificationDialog].
///
/// Shared by the pre- and post-assessment flows, which differ only in what
/// happens *after* the parent verifies — that is [onParentVerified]. Both
/// halves of the screen are child-facing, so it stays landscape throughout;
/// the result screens restore the parent orientation themselves on entry.
class AssessmentHandoffScreen extends StatefulWidget {
  const AssessmentHandoffScreen({
    super.key,
    required this.onParentVerified,
    this.title = 'You did it!',
    this.subtitle = 'You finished all the activities!',
    this.celebrationDuration = kHandoffCelebrationDuration,
    this.voiceDelay = kHandoffVoiceDelay,
    this.voiceOverFactory,
  });

  /// Runs once the parent has passed verification. Receives this screen's
  /// context so the caller can navigate from it.
  final void Function(BuildContext context) onParentVerified;

  /// The milestone headline shown on the victory scene. Pre- and
  /// post-assessment pass their own copy; the default is a neutral celebration.
  final String title;

  /// The supporting line under [title].
  final String subtitle;

  /// How long the celebration phase holds.
  final Duration celebrationDuration;

  /// Delay between the hand-off panel appearing and the narrator speaking.
  final Duration voiceDelay;

  /// Overrides how the narrator is built. Tests inject a recording double.
  final HandoffVoiceOverFactory? voiceOverFactory;

  @override
  State<AssessmentHandoffScreen> createState() =>
      _AssessmentHandoffScreenState();
}

class _AssessmentHandoffScreenState extends State<AssessmentHandoffScreen> {
  /// Whether the celebration phase is currently showing.
  bool _showCelebration = true;

  /// Set the moment the hand-off cue is dispatched, so a rebuild — an
  /// animation tick, a dialog opening and closing — never speaks it twice.
  /// The child is being asked to do one thing, once.
  bool _spokeHandOff = false;

  Timer? _celebrationTimer;
  Timer? _voiceTimer;

  /// Narrator for the hand-off prompt. Built here rather than shared, matching
  /// every other child-facing screen: each owns its own player pool and the
  /// service arbitrates the floor between them.
  late final VoiceOverService _voiceOver;

  @override
  void initState() {
    super.initState();
    // Still a child-facing screen — stays landscape with the activities.
    lockParentLandscape();

    _voiceOver = (widget.voiceOverFactory ?? _defaultVoiceOver)(context);

    // Play celebration SFX
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        context.read<AudioService>().playGameCompleteSfx();
      } catch (_) {
        // AudioService may not be available; ignore gracefully.
      }
    });

    // Hand over once the celebration has had its moment.
    _celebrationTimer = Timer(widget.celebrationDuration, () {
      if (!mounted) return;
      setState(() => _showCelebration = false);
      _speakHandOffPrompt();
    });
  }

  /// Builds the narrator from the child's own language, pack and prompt speed.
  static VoiceOverService _defaultVoiceOver(BuildContext context) {
    final childProvider = context.read<ChildProvider>();
    return VoiceOverService(
      languageCode: childProvider.voiceAssetFolder,
      speed: childProvider.voicePlaybackRate,
    );
  }

  /// Speaks the hand-off instruction as the waiting panel appears.
  ///
  /// The written line is the only thing telling the child what to do next, and
  /// a pre-reader cannot use it. It deliberately does not play during the
  /// celebration, which is a different message and has its own SFX.
  void _speakHandOffPrompt() {
    if (_spokeHandOff) return;
    _spokeHandOff = true;
    _voiceTimer = Timer(widget.voiceDelay, () {
      // Disposed while the delay was pending: the pool is gone and there is
      // nobody left to hear it.
      if (!mounted) return;
      _voiceOver.play(VoiceOverCue.giveTheDeviceToYourParent);
    });
  }

  @override
  void dispose() {
    _celebrationTimer?.cancel();
    _voiceTimer?.cancel();
    _voiceOver.dispose();
    super.dispose();
  }

  // ── Parent verification flow ────────────────────────────────────────

  void _showParentVerification(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const ParentVerificationDialog(),
    ).then((verified) {
      if (verified == true && context.mounted) {
        widget.onParentVerified(context);
      }
    });
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
    // The upgraded milestone scene *replaces* the old emoji-trophy phase — the
    // child's own companion climbs a golden podium to the trophy and celebrates
    // beside it. It plays no sound or narration itself: this screen owns the one
    // game-complete cue (above) and the later hand-off line, so the two never
    // stack or overlap.
    return KeyedSubtree(
      key: const ValueKey('celebration'),
      child: MilestoneVictoryScene(
        title: widget.title,
        subtitle: widget.subtitle,
      ),
    );
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

  // ── Waiting-for-parent phase ────────────────────────────────────────

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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
                              kHandoffInstructionText,
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

/// The on-screen line the narrator speaks. Kept as a constant so a test can
/// assert the visible instruction and the spoken cue appear together.
const String kHandoffInstructionText =
    'Please give the device to your parent.';
