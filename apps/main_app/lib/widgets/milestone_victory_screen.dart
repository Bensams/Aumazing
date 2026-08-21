import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_audio/shared_audio.dart';
import 'package:shared_haptic/shared_haptic.dart';
import 'package:shared_ui/shared_ui.dart' hide AnimatedBuilder;

import '../providers/child_provider.dart';
import 'mascot.dart';
import 'milestone_victory_scene.dart';

/// How long the finished pose is held before the continue control appears, so
/// the child has a beat to take in that they have arrived and the trophy is
/// theirs.
const Duration kMilestoneHoldDuration = Duration(milliseconds: 1600);

/// A safety valve: even if the companion never reports arriving (a sheet fails
/// to load, a timer is lost), the continue control appears by now so the child
/// is never trapped on the celebration.
const Duration kMilestoneMaxHold = Duration(seconds: 8);

/// The full-screen milestone celebration for a completed learning path.
///
/// Wraps [MilestoneVictoryScene] with the one game-complete sound and haptic
/// (played once, respecting the child's own settings) and a single large,
/// icon-first continue control that returns them to their path map. The control
/// is reading-free and only appears once the celebration has been held, and a
/// max-hold fallback reveals it even if the animation stalls — the child is
/// never left with no way forward.
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
    this.maxHold = kMilestoneMaxHold,
    this.playSfx = true,
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

  /// How long after arrival the continue control appears.
  final Duration holdDuration;

  /// Absolute cap after which the control appears regardless of arrival.
  final Duration maxHold;

  /// Whether to play the game-complete cue. A test seam; production leaves it
  /// on and the [AudioService]/[HapticService] honour the child's settings.
  final bool playSfx;

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
  Timer? _maxHoldTimer;

  @override
  void initState() {
    super.initState();
    // Child-facing: stay landscape with the games and the lobby.
    lockParentLandscape();

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

    // Never trap the child: even if arrival is never reported, reveal the
    // control by the max hold.
    _maxHoldTimer = Timer(widget.maxHold, _revealContinue);
  }

  /// The companion has reached the trophy — hold the pose briefly, then let the
  /// child move on.
  void _onArrived() {
    _holdTimer?.cancel();
    _holdTimer = Timer(widget.holdDuration, _revealContinue);
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
    _maxHoldTimer?.cancel();
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
            onArrived: _onArrived,
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
