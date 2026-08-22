import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_audio/shared_audio.dart';
// shared_ui exports its own AnimatedBuilder, which would shadow Flutter's.
import 'package:shared_ui/shared_ui.dart' hide AnimatedBuilder;

import '../providers/child_provider.dart';
import 'mascot.dart';

/// Which milestone the victory scene is celebrating. Carries only the copy —
/// the visuals are identical, because to the child the achievement is the same
/// shape every time: "you finished the whole thing".
enum MilestoneKind {
  preAssessment,
  learningPath,
  postAssessment;

  /// Big line, read aloud in spirit by the celebration itself.
  String get title => switch (this) {
        MilestoneKind.preAssessment => 'Pre-Assessment Complete!',
        MilestoneKind.learningPath => 'You Completed Your Learning Path!',
        MilestoneKind.postAssessment => 'Post-Assessment Complete!',
      };

  /// Smaller line under the title. Short, positive, understandable to a
  /// pre-reader hearing it described.
  String get subtitle => switch (this) {
        MilestoneKind.preAssessment => 'You finished all the activities!',
        MilestoneKind.learningPath => 'You finished every activity on your path!',
        MilestoneKind.postAssessment => 'You finished all the activities!',
      };

  /// The voice-over line that *speaks* the milestone. The written [title] is
  /// not drawn on the scene — it overflows and a pre-reader cannot use it — so
  /// this narrated line carries the headline instead. Falls back to
  /// "You finished it!" in any pack that lacks its own recording.
  VoiceOverCue get voiceCue => switch (this) {
        MilestoneKind.preAssessment =>
          VoiceOverCue.milestonePreAssessmentComplete,
        MilestoneKind.learningPath =>
          VoiceOverCue.milestoneLearningPathComplete,
        MilestoneKind.postAssessment =>
          VoiceOverCue.milestonePostAssessmentComplete,
      };
}

/// Identifies the drawn trophy in the scene, so a test can prove it is a real
/// composed trophy rather than a bare emoji.
const Key kMilestoneTrophyKey = Key('milestone_trophy');

/// How long the companion takes to climb the podium toward the trophy.
///
/// Matched to [Mascot]'s own entrance travel so the legs (walk frames, driven
/// by the entrance) and the body (this outer climb) finish together. Kept slow
/// enough for a child who processes visual change slowly to follow the whole
/// ascent.
const Duration kMilestoneClimbDuration = Duration(milliseconds: 1600);

/// A warm, magical golden stage: a short podium rises toward a glowing trophy,
/// the child's chosen companion climbs it and celebrates beside the cup, and a
/// restrained scatter of sparkles frames the finished pose.
///
/// Purely visual and self-contained. It plays no sound and speaks no line —
/// the container above it (the assessment hand-off, or [MilestoneVictoryScreen])
/// owns the one game-complete cue and the later narration, so nothing here can
/// stack a second celebration or talk over the "give the device to your parent"
/// prompt.
///
/// The companion is *always* the profile's own [ChildProfile.characterId]
/// wearing [ChildProfile.equippedCostume] — never inferred from the child's sex,
/// never a hard-coded mascot. Character space is reserved while the sheets
/// decode (see [Mascot.fallback]) so the layout never jumps, and the existing
/// safe costume fallback stands in when a costume has no sheets yet.
///
/// Reduced motion is honoured two ways — the child's own setting *and*
/// Flutter's platform "disable animations" signal: the companion is simply
/// already at the top beside the trophy, nothing travels or bounces, no
/// particles drift, and only gentle opacity fades remain. The milestone message
/// and the [onArrived] outcome are identical either way.
class MilestoneVictoryScene extends StatefulWidget {
  const MilestoneVictoryScene({
    super.key,
    required this.title,
    required this.subtitle,
    this.character,
    this.costumeId,
    this.reducedMotion,
    this.climbDuration = kMilestoneClimbDuration,
    this.onArrived,
    this.mascotHeight = 128,
  });

  /// The big milestone line.
  final String title;

  /// The smaller supporting line.
  final String subtitle;

  /// The companion to show. Null — the usual case — resolves the child's own
  /// choice from [ChildProvider]. An explicit value is a test seam.
  final MascotCharacter? character;

  /// The equipped costume, as a [Costume.id]. Null resolves from the profile.
  final String? costumeId;

  /// Forces reduced motion regardless of provider/platform. A test seam; in
  /// production it is left null and resolved live.
  final bool? reducedMotion;

  /// How long the climb takes. Injectable so a widget test can drive the whole
  /// sequence on the test clock without waiting on wall-time.
  final Duration climbDuration;

  /// Fired once, the moment the companion reaches the top and the celebration
  /// begins (immediately under reduced motion). Lets a container reveal a
  /// continue control only after the child can see they have arrived.
  final VoidCallback? onArrived;

  /// Display height of the companion. Kept modest so the trophy stays a
  /// co-focal point rather than being dwarfed.
  final double mascotHeight;

  @override
  State<MilestoneVictoryScene> createState() => _MilestoneVictorySceneState();
}

class _MilestoneVictorySceneState extends State<MilestoneVictoryScene>
    with TickerProviderStateMixin {
  /// Fades the golden stage and the trophy's glow in first.
  late final AnimationController _stage;

  /// The trophy's gentle bounce/settle as it is revealed.
  late final AnimationController _trophy;

  /// The companion's ascent up the podium (outer vertical travel; the walk
  /// frames themselves come from the [Mascot] entrance).
  late final AnimationController _climb;

  /// The slow drift/twinkle of the surrounding sparkles.
  late final AnimationController _sparkle;

  /// Fades the milestone message in once the companion is on its way up.
  late final AnimationController _message;

  /// The staged delays that kick off the trophy and the climb. Held so dispose
  /// can cancel them rather than leaving pending callbacks against dead tickers.
  Timer? _trophyTimer;
  Timer? _climbTimer;

  bool _firedArrived = false;

  bool _resolveReducedMotion() {
    if (widget.reducedMotion != null) return widget.reducedMotion!;
    var reduced = false;
    try {
      reduced = context.read<ChildProvider>().reducedMotion;
    } catch (_) {
      // ChildProvider may be absent in isolated previews/tests.
    }
    // Flutter's platform "disable animations" accessibility signal counts too.
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) reduced = true;
    return reduced;
  }

  @override
  void initState() {
    super.initState();
    _stage = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _trophy = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _climb = AnimationController(vsync: this, duration: widget.climbDuration);
    _sparkle = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    );
    _message = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    // Sequencing runs after the first frame so the reduced-motion resolution
    // can read MediaQuery/ChildProvider from a mounted context.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _start(_resolveReducedMotion());
    });
  }

  void _start(bool reduced) {
    if (reduced) {
      // Everything already at rest, at the top: no travel, no bounce, no
      // drifting particles — just the finished, held composition fading in.
      _stage.value = 1;
      _trophy.value = 1;
      _climb.value = 1;
      _message.value = 1;
      _fireArrived();
      return;
    }

    _stage.forward();
    // Trophy settles in just behind the stage.
    _trophyTimer = Timer(const Duration(milliseconds: 250), () {
      if (mounted) _trophy.forward();
    });
    _sparkle.repeat();
    // Companion sets off up the podium once the stage has appeared, and the
    // message fades in as it climbs so the two land together.
    _climbTimer = Timer(const Duration(milliseconds: 550), () {
      if (!mounted) return;
      _message.forward();
      _climb.forward().whenComplete(_fireArrived);
    });
  }

  void _fireArrived() {
    if (_firedArrived) return;
    _firedArrived = true;
    widget.onArrived?.call();
  }

  @override
  void dispose() {
    _trophyTimer?.cancel();
    _climbTimer?.cancel();
    _stage.dispose();
    _trophy.dispose();
    _climb.dispose();
    _sparkle.dispose();
    _message.dispose();
    super.dispose();
  }

  // ── Companion resolution ────────────────────────────────────────────

  MascotCharacter get _character {
    if (widget.character != null) return widget.character!;
    try {
      final profile = context.read<ChildProvider>().profile;
      return MascotCharacter.fromId(profile?.characterId);
    } catch (_) {
      return MascotCharacter.bps;
    }
  }

  String? get _costumeId {
    if (widget.costumeId != null) return widget.costumeId;
    try {
      return context.read<ChildProvider>().profile?.equippedCostume;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduced = _resolveReducedMotion();

    return Semantics(
      container: true,
      // Keep the trophy, companion and message as their own nodes rather than
      // folding them into one label, so a screen reader can reach each.
      explicitChildNodes: true,
      label: '${widget.title} ${widget.subtitle}',
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFFFF3E0), // warm cream top
              Color(0xFFFFE0B2), // soft amber
              Color(0xFFFFF9C4), // light yellow bottom
            ],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => _buildStage(
              constraints.biggest,
              reduced,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStage(Size size, bool reduced) {
    final w = size.width;
    final h = size.height;

    // The trophy sits high and centred; the podium rises to meet it, and the
    // companion comes to rest on the top step just beside the cup.
    final trophyCenter = Offset(w * 0.5, h * 0.30);
    final podiumTop = h * 0.44;
    final podiumWidth = math.min(w * 0.62, 460.0);
    const trophySize = 132.0;

    return AnimatedBuilder(
      animation: Listenable.merge(
          [_stage, _trophy, _climb, _sparkle, _message]),
      builder: (context, _) {
        final stage = Curves.easeOut.transform(_stage.value);
        return Stack(
          fit: StackFit.expand,
          children: [
            // Column of light behind the trophy — the "illuminated staircase"
            // beam from the reference, fading in with the stage.
            Positioned(
              left: trophyCenter.dx - podiumWidth * 0.42,
              top: 0,
              width: podiumWidth * 0.84,
              height: podiumTop + 40,
              child: Opacity(
                opacity: stage * 0.9,
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0x00FFF8E1),
                        Color(0x66FFF3C4),
                        Color(0x00FFF3C4),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Restrained sparkles/stars around the finished pose. Skipped
            // whole under reduced motion.
            if (!reduced)
              ..._buildSparkles(size, trophyCenter, podiumWidth),

            // The podium/staircase.
            Positioned(
              left: trophyCenter.dx - podiumWidth / 2,
              top: podiumTop,
              width: podiumWidth,
              height: h - podiumTop,
              child: Opacity(
                opacity: stage,
                child: CustomPaint(painter: _PodiumPainter()),
              ),
            ),

            // The trophy, with its glow — a gentle bounce as it appears.
            Positioned(
              left: trophyCenter.dx - trophySize / 2,
              top: trophyCenter.dy - trophySize / 2,
              width: trophySize,
              height: trophySize,
              child: _buildTrophy(reduced, trophySize),
            ),

            // The companion, climbing to rest on the top step beside the cup.
            _buildCompanion(size, trophyCenter, podiumTop, reduced),

            // The milestone message.
            Positioned(
              left: 24,
              right: 24,
              bottom: h * 0.06,
              child: Opacity(
                opacity: Curves.easeIn.transform(_message.value),
                child: _buildMessage(),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTrophy(bool reduced, double size) {
    // Bounce in (elastic) normally; a plain settle under reduced motion.
    final curve = reduced ? Curves.easeOut : Curves.elasticOut;
    final scale = 0.4 + curve.transform(_trophy.value).clamp(0.0, 1.4) * 0.6;
    // A soft, steady breathing glow so the cup stays the eye's anchor.
    final glow = reduced
        ? 0.55
        : 0.45 + 0.2 * (0.5 + 0.5 * math.sin(_sparkle.value * math.pi * 2));

    return Semantics(
      key: kMilestoneTrophyKey,
      label: 'Golden trophy',
      image: true,
      child: Transform.scale(
        scale: scale.clamp(0.0, 1.0),
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFFD54F).withValues(alpha: glow),
                blurRadius: 44,
                spreadRadius: 6,
              ),
            ],
          ),
          child: CustomPaint(
            size: Size(size, size),
            painter: _TrophyPainter(),
          ),
        ),
      ),
    );
  }

  Widget _buildCompanion(
    Size size,
    Offset trophyCenter,
    double podiumTop,
    bool reduced,
  ) {
    // Resting position: standing on the top step, just to the left of the cup.
    final restLeft = trophyCenter.dx - widget.mascotHeight * 0.95;
    final restTop = podiumTop - widget.mascotHeight * 0.72;

    // Outer vertical travel: starts a good way down the podium and rises to
    // rest. The horizontal walk-in is the Mascot entrance's own job, so the
    // net path reads as climbing up-and-in from the lower left.
    final climb = Curves.easeInOut.transform(_climb.value);
    final dy = reduced ? 0.0 : (1 - climb) * size.height * 0.34;

    return Positioned(
      left: restLeft,
      top: restTop,
      child: Transform.translate(
        offset: Offset(0, dy),
        child: Mascot(
          character: _character,
          costumeId: _costumeId,
          height: widget.mascotHeight,
          // Walk in (walk frames) when motion is allowed; already-there under
          // reduced motion. Either way it greets with a celebration on arrival.
          entrance:
              reduced ? MascotEntrance.none : MascotEntrance.fromLeft,
          gesture: MascotGesture.celebrate,
          greetOnAppear: true,
          greetDelay: reduced
              ? const Duration(milliseconds: 200)
              : const Duration(milliseconds: 250),
          semanticLabel: 'Your companion celebrating',
          // Reserve the character's box while the sheets decode so nothing on
          // the podium jumps when it appears.
          fallback: SizedBox(
            height: widget.mascotHeight,
            width: widget.mascotHeight,
          ),
        ),
      ),
    );
  }

  /// The visible message is deliberately the subtitle *only*. The headline
  /// [MilestoneVictoryScene.title] is spoken (see [MilestoneKind.voiceCue]),
  /// not drawn: at a child-legible size it overflows the landscape stage and,
  /// being text, is no use to a pre-reader anyway. It is still exposed to
  /// screen readers through the scene's container [Semantics] label.
  Widget _buildMessage() {
    return Text(
      widget.subtitle,
      textAlign: TextAlign.center,
      style: AppTextStyles.headlineSmall.copyWith(
        fontSize: 26,
        color: const Color(0xFFE65100),
        fontWeight: FontWeight.w700,
      ),
    );
  }

  /// A modest scatter of stars/sparkles around the trophy and podium. Held to a
  /// small count and a slow twinkle — restrained, never a strobing burst.
  List<Widget> _buildSparkles(
    Size size,
    Offset trophyCenter,
    double podiumWidth,
  ) {
    const glyphs = ['⭐', '🌟', '✨', '💫'];
    const count = 10;
    final widgets = <Widget>[];
    final rng = math.Random(7); // fixed seed → stable, deterministic layout

    for (var i = 0; i < count; i++) {
      final angle = (i / count) * math.pi * 2;
      final radius = podiumWidth * (0.44 + rng.nextDouble() * 0.28);
      final base = Offset(
        trophyCenter.dx + math.cos(angle) * radius,
        trophyCenter.dy + math.sin(angle) * radius * 0.7,
      );
      // Slow, out-of-phase twinkle — a gentle rise and fade, never a flash.
      final phase = (_sparkle.value + i / count) % 1.0;
      final twinkle = 0.35 + 0.45 * math.sin(phase * math.pi);
      final drift = math.sin(phase * math.pi * 2) * 6;
      final fontSize = 16.0 + (i % 3) * 6.0;

      widgets.add(Positioned(
        left: base.dx - fontSize / 2,
        top: base.dy - fontSize / 2 + drift,
        child: Opacity(
          opacity: twinkle.clamp(0.0, 1.0) * 0.85,
          child: Text(
            glyphs[i % glyphs.length],
            style: TextStyle(fontSize: fontSize),
          ),
        ),
      ));
    }
    return widgets;
  }
}

/// A short, warm-golden staircase/podium: a stack of centred steps narrowing
/// as they rise, drawn from shapes so it needs no bundled art.
class _PodiumPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const steps = 4;
    final w = size.width;
    final h = size.height;
    // The top step is the plinth the companion and trophy stand on.
    final stepHeight = (h * 0.9) / (steps + 1.2);

    // Warm golds, lighter at the lit top, deeper toward the base.
    const top = Color(0xFFFFCC66);
    const bottom = Color(0xFFE8A63C);

    for (var i = 0; i < steps; i++) {
      final t = steps == 1 ? 0.0 : i / (steps - 1);
      // Narrowest at the top (i = 0), widening downward.
      final stepWidth = w * (0.42 + 0.58 * t);
      final left = (w - stepWidth) / 2;
      final top0 = i * stepHeight;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, top0, stepWidth, stepHeight * 1.05),
        const Radius.circular(8),
      );
      final color = Color.lerp(top, bottom, t)!;
      canvas.drawRRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              color,
              Color.lerp(color, Colors.black, 0.12)!,
            ],
          ).createShader(rect.outerRect),
      );
      // A soft highlight lip along the front edge of each tread.
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, top0, stepWidth, stepHeight * 0.18),
          const Radius.circular(8),
        ),
        Paint()..color = Colors.white.withValues(alpha: 0.18),
      );
    }
  }

  @override
  bool shouldRepaint(_PodiumPainter oldDelegate) => false;
}

/// A drawn golden cup: bowl with two curved handles, a stem, and a base. Warm
/// and friendly, matching Aumazing's soft visual language — never a flat emoji.
class _TrophyPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;

    final gold = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFFFE082), Color(0xFFF9A825)],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    final deepGold = Paint()..color = const Color(0xFFEF9A00);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.02
      ..color = const Color(0x33B26A00);

    // Handles (drawn first so the bowl sits over their roots).
    final handleStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.055
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFF9A825);
    for (final sign in [-1.0, 1.0]) {
      final path = Path()
        ..moveTo(cx + sign * w * 0.20, h * 0.20)
        ..cubicTo(
          cx + sign * w * 0.42, h * 0.18,
          cx + sign * w * 0.42, h * 0.42,
          cx + sign * w * 0.22, h * 0.42,
        );
      canvas.drawPath(path, handleStroke);
    }

    // Bowl of the cup — a rounded goblet tapering to the stem.
    final bowl = Path()
      ..moveTo(cx - w * 0.24, h * 0.16)
      ..lineTo(cx + w * 0.24, h * 0.16)
      ..cubicTo(
        cx + w * 0.24, h * 0.44,
        cx + w * 0.14, h * 0.54,
        cx, h * 0.54,
      )
      ..cubicTo(
        cx - w * 0.14, h * 0.54,
        cx - w * 0.24, h * 0.44,
        cx - w * 0.24, h * 0.16,
      )
      ..close();
    canvas.drawPath(bowl, gold);
    canvas.drawPath(bowl, stroke);

    // A soft sheen on the bowl.
    canvas.drawOval(
      Rect.fromLTWH(cx - w * 0.14, h * 0.20, w * 0.14, h * 0.16),
      Paint()..color = Colors.white.withValues(alpha: 0.28),
    );

    // Stem.
    canvas.drawRect(
      Rect.fromLTWH(cx - w * 0.04, h * 0.54, w * 0.08, h * 0.14),
      deepGold,
    );

    // Base: a small plinth under the stem.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - w * 0.10, h * 0.66, w * 0.20, h * 0.06),
        const Radius.circular(3),
      ),
      gold,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - w * 0.18, h * 0.72, w * 0.36, h * 0.08),
        const Radius.circular(4),
      ),
      deepGold,
    );
  }

  @override
  bool shouldRepaint(_TrophyPainter oldDelegate) => false;
}
