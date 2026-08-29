import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_audio/shared_audio.dart';
import 'package:shared_haptic/shared_haptic.dart';
import 'package:shared_ui/shared_ui.dart' hide AnimatedBuilder;

import '../providers/child_provider.dart';
import 'mascot.dart';
import 'milestone_victory_scene.dart';

/// Builds the narrator the milestone scene speaks through. Injectable so a
/// widget test can observe the cue without a platform audio player.
typedef MilestoneVoiceOverFactory = VoiceOverService Function(
    BuildContext context);

/// How long the celebration is held before the continue control appears.
///
/// The scene is a playable stage — a trophy and stars the child pops — not a
/// flourish to be snatched away after a beat, so it is held long enough to
/// actually be played with. Matched to the assessment hand-off's own hold
/// (`kHandoffCelebrationDuration`) so a milestone feels the same length
/// wherever the child meets it. Timed from when the screen appears, not from
/// the companion's arrival: a slow climb must not push the whole hold later.
///
/// A child who clears every reward before this is up moves on early — see
/// [kMilestoneMinHold].
const Duration kMilestoneHoldDuration = Duration(seconds: 12);

/// The floor under the early exit. Even a child who pops the trophy and every
/// star in one fast drag stays long enough for the spoken milestone line —
/// dispatched 650 ms in — to be heard rather than cut off.
const Duration kMilestoneMinHold = Duration(seconds: 3);

/// The beat left after the last reward is popped, so its burst finishes on the
/// stage rather than being cut mid-sparkle by the control fading in.
const Duration kMilestoneAllPoppedSettle = Duration(milliseconds: 900);

/// A safety valve: even if a timer is lost, the continue control appears by now
/// so the child is never trapped on the celebration.
const Duration kMilestoneMaxHold = Duration(seconds: 15);

/// The full-screen milestone celebration for a completed learning path.
///
/// Wraps [MilestoneVictoryScene] with the one game-complete sound and haptic
/// (played once, respecting the child's own settings) and a single large,
/// icon-first continue control that returns them to their path map. The control
/// is reading-free and only appears once the celebration has been held — twelve
/// seconds, or sooner for a child who has already popped the trophy and every
/// star and so has nothing left to play with. A max-hold fallback reveals it
/// even if a timer is lost, so the child is never left with no way forward.
///
/// The pre- and post-assessment milestones do *not* use this screen: they embed
/// the same [MilestoneVictoryScene] inside the assessment hand-off, which owns
/// their timing, narration and verification gate.
class MilestoneVictoryScreen extends StatefulWidget {
  const MilestoneVictoryScreen({
    super.key,
    required this.kind,
    required this.onContinue,
    this.character,
    this.costumeId,
    this.reducedMotion,
    this.climbDuration = kMilestoneClimbDuration,
    this.holdDuration = kMilestoneHoldDuration,
    this.minHold = kMilestoneMinHold,
    this.allPoppedSettle = kMilestoneAllPoppedSettle,
    this.maxHold = kMilestoneMaxHold,
    this.playSfx = true,
    this.voiceOverFactory,
    this.continueSemanticLabel = 'Continue',
  });

  /// Which milestone this is — supplies the title/subtitle copy.
  final MilestoneKind kind;

  /// Runs once when the child continues (tap or auto). Guaranteed to fire at
  /// most once no matter how many times the control is tapped.
  final VoidCallback onContinue;

  final MascotCharacter? character;
  final String? costumeId;
  final bool? reducedMotion;
  final Duration climbDuration;

  /// How long after the celebration appears the continue control does.
  final Duration holdDuration;

  /// The earliest the control may appear, even with every reward popped.
  final Duration minHold;

  /// How long the cleared stage is held after the final pop.
  final Duration allPoppedSettle;

  /// Absolute cap after which the control appears no matter what.
  final Duration maxHold;

  /// Whether to play the game-complete cue. A test seam; production leaves it
  /// on and the [AudioService]/[HapticService] honour the child's settings.
  final bool playSfx;

  /// Overrides how the milestone narrator is built. Tests inject a recording
  /// double; production builds one from the child's own voice settings.
  final MilestoneVoiceOverFactory? voiceOverFactory;

  final String continueSemanticLabel;

  /// Pushes the milestone celebration and completes when the child continues.
  ///
  /// The caller performs the actual navigation afterwards (e.g. popping back to
  /// the lobby), so this screen never has to know where "next" is.
  static Future<void> show(
    BuildContext context, {
    required MilestoneKind kind,
    MascotCharacter? character,
    String? costumeId,
    Duration climbDuration = kMilestoneClimbDuration,
    Duration holdDuration = kMilestoneHoldDuration,
    Duration minHold = kMilestoneMinHold,
  }) {
    final completer = Completer<void>();
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 350),
        pageBuilder: (_, __, ___) => MilestoneVictoryScreen(
          kind: kind,
          character: character,
          costumeId: costumeId,
          climbDuration: climbDuration,
          holdDuration: holdDuration,
          minHold: minHold,
          onContinue: () {
            if (!completer.isCompleted) completer.complete();
          },
        ),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
    return completer.future;
  }

  @override
  State<MilestoneVictoryScreen> createState() => _MilestoneVictoryScreenState();
}

class _MilestoneVictoryScreenState extends State<MilestoneVictoryScreen> {
  bool _showContinue = false;
  bool _continued = false;
  Timer? _holdTimer;
  Timer? _minHoldTimer;
  Timer? _allPoppedTimer;
  Timer? _maxHoldTimer;
  Timer? _voiceTimer;
  bool _spokeMilestone = false;

  /// Whether the child has cleared every reward, and whether the minimum hold
  /// has passed. The early exit needs both: the first says the child is
  /// finished playing, the second protects the spoken milestone line.
  bool _allRewardsPopped = false;
  bool _minHoldElapsed = false;

  /// Narrator for the milestone line, built from the child's own voice pack.
  late final VoiceOverService _voiceOver;

  @override
  void initState() {
    super.initState();
    // Child-facing: stay landscape with the games and the lobby.
    lockParentLandscape();

    _voiceOver = (widget.voiceOverFactory ?? _defaultVoiceOver)(context);

    // The one celebration cue, played once, honouring the child's settings.
    if (widget.playSfx) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        try {
          context.read<AudioService>().playGameCompleteSfx();
        } catch (_) {
          // AudioService may be unavailable — the scene stands on its own.
        }
        try {
          if (context.read<ChildProvider>().vibrationEnabled) {
            context.read<HapticService>().gameCompleteFeedback();
          }
        } catch (_) {
          // HapticService/ChildProvider may be unavailable; ignore.
        }
      });
    }

    // Speak the milestone once, a beat after the completion chime so the
    // narration lands clear of it rather than under it. The written headline is
    // not drawn on the scene, so this line is what tells a pre-reader what they
    // just achieved.
    _voiceTimer = Timer(const Duration(milliseconds: 650), () {
      if (!mounted || _spokeMilestone) return;
      _spokeMilestone = true;
      _voiceOver.play(widget.kind.voiceCue);
    });

    // The full hold. Timed from here rather than from the companion's arrival
    // so the stage stays playable for a predictable length whatever the climb
    // does.
    _holdTimer = Timer(widget.holdDuration, _revealContinue);

    // The early exit only opens after the minimum hold.
    _minHoldTimer = Timer(widget.minHold, () {
      if (!mounted) return;
      _minHoldElapsed = true;
      _maybeRevealAfterAllPopped();
    });

    // Never trap the child: even if a timer is lost, reveal the control by the
    // max hold.
    _maxHoldTimer = Timer(widget.maxHold, _revealContinue);
  }

  /// Builds the narrator from the child's own language, pack and prompt speed.
  static VoiceOverService _defaultVoiceOver(BuildContext context) {
    final childProvider = context.read<ChildProvider>();
    return VoiceOverService(
      languageCode: childProvider.voiceAssetFolder,
      speed: childProvider.voicePlaybackRate,
    );
  }

  /// The child popped the last reward — the trophy and every star are gone, so
  /// there is nothing left on the stage to play with. Let them move on rather
  /// than making them wait out the full hold.
  void _onAllRewardsPopped() {
    if (_allRewardsPopped) return;
    _allRewardsPopped = true;
    _maybeRevealAfterAllPopped();
  }

  /// Reveals the control once both the stage is empty and the minimum hold has
  /// passed. Idempotent: a second call never schedules a second reveal.
  void _maybeRevealAfterAllPopped() {
    if (!_allRewardsPopped || !_minHoldElapsed) return;
    if (_allPoppedTimer != null || _showContinue) return;
    _allPoppedTimer = Timer(widget.allPoppedSettle, _revealContinue);
  }

  void _revealContinue() {
    if (!mounted || _showContinue) return;
    setState(() => _showContinue = true);
  }

  void _continue() {
    // A double tap, or the auto-transition racing a tap, must not run the
    // continuation twice or open two screens.
    if (_continued) return;
    _continued = true;
    _holdTimer?.cancel();
    _minHoldTimer?.cancel();
    _allPoppedTimer?.cancel();
    _maxHoldTimer?.cancel();
    // Always pushed in production (via [show]); the guard keeps it safe if it
    // is ever the only route on screen.
    final navigator = Navigator.of(context);
    if (navigator.canPop()) navigator.pop();
    widget.onContinue();
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _minHoldTimer?.cancel();
    _allPoppedTimer?.cancel();
    _maxHoldTimer?.cancel();
    _voiceTimer?.cancel();
    _voiceOver.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          MilestoneVictoryScene(
            title: widget.kind.title,
            subtitle: widget.kind.subtitle,
            character: widget.character,
            costumeId: widget.costumeId,
            reducedMotion: widget.reducedMotion,
            climbDuration: widget.climbDuration,
            onAllRewardsPopped: _onAllRewardsPopped,
          ),
          // Large, icon-first continue control — appears only once the child
          // can see they have arrived. Reading-free: a big forward arrow.
          Positioned(
            right: 28,
            bottom: 28,
            child: AnimatedOpacity(
              opacity: _showContinue ? 1 : 0,
              duration: const Duration(milliseconds: 400),
              child: IgnorePointer(
                ignoring: !_showContinue,
                child: Semantics(
                  button: true,
                  label: widget.continueSemanticLabel,
                  child: Material(
                    color: const Color(0xFFE65100),
                    shape: const CircleBorder(),
                    elevation: 6,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _continue,
                      child: const SizedBox(
                        width: 84,
                        height: 84,
                        child: Icon(
                          Icons.arrow_forward_rounded,
                          size: 44,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
