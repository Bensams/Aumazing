import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_ui/shared_ui.dart';

import '../providers/child_provider.dart';

/// BPS the mascot, ready to drop into any screen.
///
/// Wraps [CalmMascot] with the app-side plumbing every appearance needs:
/// loads the BPS sprite sheets (cached process-wide after the first load),
/// reads the child's reduced-motion setting from [ChildProvider], and waves
/// hello shortly after appearing. While the sheets are still decoding it
/// shows [fallback] (or reserves the space) so layout never jumps.
///
/// For extra waves after the greeting (e.g. each time a voice-over cue
/// plays), bump [waveTrigger].
class BpsMascot extends StatefulWidget {
  const BpsMascot({
    super.key,
    this.height = 140,
    this.waveOnAppear = true,
    this.waveDelay = const Duration(milliseconds: 500),
    this.waveTrigger,
    this.fallback,
    this.semanticLabel = 'BPS the mascot waves hello',
  });

  /// Display height in logical pixels.
  final double height;

  /// Whether BPS greets with a wave shortly after the sprites are ready.
  final bool waveOnAppear;

  /// How long after appearing (and after sprites load) the greeting plays —
  /// lets an entrance transition settle first.
  final Duration waveDelay;

  /// Change this value to play an extra wave on demand.
  final Object? waveTrigger;

  /// Shown while sprite sheets are loading (or if they fail). Defaults to
  /// an empty box of the same height so layout stays stable.
  final Widget? fallback;

  final String? semanticLabel;

  @override
  State<BpsMascot> createState() => _BpsMascotState();
}

class _BpsMascotState extends State<BpsMascot> {
  CharacterSprites? _sprites;

  /// Internal appear-wave counter, combined with [BpsMascot.waveTrigger].
  int _appearTick = 0;

  @override
  void initState() {
    super.initState();
    CharacterSprites.bps().then((s) {
      if (!mounted) return;
      setState(() => _sprites = s);
      if (widget.waveOnAppear) {
        // Bump the trigger on a later frame than the mascot's first build
        // with sprites, so CalmMascot sees a trigger *change* and waves.
        Future.delayed(widget.waveDelay, () {
          if (mounted) setState(() => _appearTick++);
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final sprites = _sprites;
    if (sprites == null) {
      return widget.fallback ?? SizedBox(height: widget.height);
    }

    var reduced = false;
    try {
      reduced = context.read<ChildProvider>().reducedMotion;
    } catch (_) {
      // ChildProvider may not be available (e.g. in isolated tests).
    }

    return CalmMascot(
      image: sprites.rest,
      height: widget.height,
      reducedMotion: reduced,
      gestureFrames: sprites.waveFrames,
      gestureTrigger: '${widget.waveTrigger}-$_appearTick',
      semanticLabel: widget.semanticLabel,
    );
  }
}
