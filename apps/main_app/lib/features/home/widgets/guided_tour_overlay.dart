import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

/// One stop on a guided tour: a spotlight on a widget plus one short
/// sentence saying what it does.
class TourStep {
  const TourStep({
    required this.title,
    required this.body,
    this.targetKey,
    this.icon,
  });

  /// Two or three words naming the control.
  final String title;

  /// One short sentence. Parents read this while holding a child.
  final String body;

  /// The widget to spotlight. Null (or a key that isn't on screen right
  /// now) shows the card centred with no cutout — used for the welcome
  /// and for explaining flows that happen on another screen.
  final GlobalKey? targetKey;

  final IconData? icon;
}

/// A coach-mark tour: dims the screen, cuts a hole around one control at a
/// time, and explains it in a sentence with **Next** / **Skip** controls.
///
/// Steps whose target is not currently on screen are skipped automatically,
/// so a single step list can serve both the landscape and the portrait
/// dashboard, and cards that only appear in some states (premium banner,
/// screen-time meter) never leave the parent staring at an empty spotlight.
class GuidedTourOverlay extends StatefulWidget {
  const GuidedTourOverlay({
    super.key,
    required this.steps,
    required this.onFinish,
  });

  final List<TourStep> steps;

  /// Called once, when the parent reaches the end or taps Skip.
  final VoidCallback onFinish;

  @override
  State<GuidedTourOverlay> createState() => _GuidedTourOverlayState();
}

class _GuidedTourOverlayState extends State<GuidedTourOverlay> {
  /// Index into [widget.steps]; null until the first step is measured.
  int? _index;

  /// The spotlight, in this overlay's coordinates. Null = no cutout.
  Rect? _rect;

  bool _remeasureScheduled = false;
  bool _finished = false;

  static const _padding = 8.0;
  static const _cardWidth = 380.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _goTo(0));
  }

  /// Whether [step] can be shown right now — a step with a target that is
  /// not mounted (wrong layout, card hidden) has nothing to point at.
  bool _isVisible(TourStep step) {
    final key = step.targetKey;
    if (key == null) return true;
    final ctx = key.currentContext;
    if (ctx == null) return false;
    final box = ctx.findRenderObject();
    // A collapsed section still has an element, so require real size — an
    // empty spotlight would be worse than skipping the step.
    return box is RenderBox && box.hasSize && box.size.shortestSide > 4;
  }

  /// Moves to the first showable step at or after [from], scrolling it into
  /// view first. Runs off the end of the list → the tour is over.
  Future<void> _goTo(int from) async {
    var i = from;
    while (i < widget.steps.length && !_isVisible(widget.steps[i])) {
      i++;
    }
    if (i >= widget.steps.length) {
      _finish();
      return;
    }

    final ctx = widget.steps[i].targetKey?.currentContext;
    if (ctx != null) {
      // Cards further down the dashboard have to come into view before
      // there is anything to spotlight.
      await Scrollable.ensureVisible(
        ctx,
        alignment: 0.5,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );
    }
    if (!mounted) return;
    setState(() {
      _index = i;
      _rect = _rectFor(widget.steps[i]);
    });
  }

  /// Walks backwards to the previous showable step.
  void _goBack() {
    final current = _index;
    if (current == null) return;
    var i = current - 1;
    while (i >= 0 && !_isVisible(widget.steps[i])) {
      i--;
    }
    if (i < 0) return;
    _goTo(i);
  }

  void _finish() {
    if (_finished) return;
    _finished = true;
    widget.onFinish();
  }

  Rect? _rectFor(TourStep step) {
    final ctx = step.targetKey?.currentContext;
    if (ctx == null) return null;
    final target = ctx.findRenderObject();
    final self = context.findRenderObject();
    if (target is! RenderBox || self is! RenderBox) return null;
    if (!target.hasSize || !self.hasSize) return null;
    final topLeft = target.localToGlobal(Offset.zero, ancestor: self);
    return topLeft & target.size;
  }

  /// Layout shifts under the overlay — an orientation change, a card that
  /// finished loading, the scroll settling — move the target. Re-measure
  /// after the frame, but only set state when it actually moved, so this
  /// cannot spin.
  void _scheduleRemeasure() {
    if (_remeasureScheduled) return;
    _remeasureScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _remeasureScheduled = false;
      if (!mounted) return;
      final i = _index;
      if (i == null) return;
      final fresh = _rectFor(widget.steps[i]);
      final current = _rect;
      final moved =
          fresh == null
              ? current != null
              : current == null ||
                  (fresh.center - current.center).distance > 0.5;
      if (moved) setState(() => _rect = fresh);
    });
  }

  @override
  Widget build(BuildContext context) {
    _scheduleRemeasure();

    final i = _index;
    final step = i == null ? null : widget.steps[i];
    final hole = _rect?.inflate(_padding);

    return Positioned.fill(
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            // The scrim also swallows taps, so the parent cannot fire a
            // dashboard button through the tour by accident.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: i == null ? null : () => _goTo(i + 1),
                child: CustomPaint(
                  painter: _SpotlightPainter(hole),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
            if (hole != null)
              Positioned.fromRect(
                rect: hole,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.white, width: 2),
                    ),
                  ),
                ),
              ),
            if (step != null) _buildCard(step, i!, hole),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(TourStep step, int index, Rect? hole) {
    // Filled so the card is placed against the whole overlay rather than
    // shrink-wrapping in a corner of the stack.
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = _cardWidth.clamp(0.0, constraints.maxWidth - 32);
          final card = _TourCard(
            step: step,
            // Counted over the steps this parent will actually see.
            position: widget.steps.take(index + 1).where(_isVisible).length,
            total: widget.steps.where(_isVisible).length,
            isLast: !widget.steps.skip(index + 1).any(_isVisible),
            onNext: () => _goTo(index + 1),
            onBack: widget.steps.take(index).any(_isVisible) ? _goBack : null,
            onSkip: _finish,
          );

          if (hole == null) {
            return Center(child: SizedBox(width: width, child: card));
          }

          // Sit under the spotlight, or above it, or — when a tall target
          // such as a full-height side panel leaves room for neither —
          // float over it; the ring still marks what is being described.
          const estimatedHeight = 190.0;
          final spaceBelow = constraints.maxHeight - hole.bottom - 12;
          final spaceAbove = hole.top - 12;
          double? top;
          double? bottom;
          if (spaceBelow >= estimatedHeight) {
            top = hole.bottom + 12;
          } else if (spaceAbove >= estimatedHeight) {
            bottom = constraints.maxHeight - hole.top + 12;
          } else {
            top = ((constraints.maxHeight - estimatedHeight) / 2).clamp(
              16.0,
              (constraints.maxHeight - 16).clamp(16.0, double.infinity),
            );
          }
          final left = (hole.center.dx - width / 2).clamp(
            16.0,
            (constraints.maxWidth - width - 16).clamp(16.0, double.infinity),
          );

          return Stack(
            children: [
              Positioned(
                left: left,
                top: top,
                bottom: bottom,
                width: width,
                child: card,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TourCard extends StatelessWidget {
  const _TourCard({
    required this.step,
    required this.position,
    required this.total,
    required this.isLast,
    required this.onNext,
    required this.onBack,
    required this.onSkip,
  });

  final TourStep step;
  final int position;
  final int total;
  final bool isLast;
  final VoidCallback onNext;
  final VoidCallback? onBack;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: AppRadius.card,
        boxShadow: AppShadows.card,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (step.icon != null) ...[
                Icon(step.icon, size: 20, color: AppColors.primaryPurple),
                const SizedBox(width: AppSpacing.xs),
              ],
              Expanded(
                child: Text(
                  step.title,
                  style: AppTextStyles.titleMedium.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              Text(
                '$position of $total',
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.mutedForeground,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            step.body,
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              TextButton(
                onPressed: onSkip,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                ),
                child: const Text('Skip'),
              ),
              const Spacer(),
              if (onBack != null)
                TextButton(
                  onPressed: onBack,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                  ),
                  child: const Text('Back'),
                ),
              const SizedBox(width: AppSpacing.xs),
              AppPrimaryButton(
                label: isLast ? 'Done' : 'Next',
                width: 120,
                onPressed: onNext,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Paints the dimming scrim with a rounded hole punched out of it.
class _SpotlightPainter extends CustomPainter {
  const _SpotlightPainter(this.hole);

  final Rect? hole;

  @override
  void paint(Canvas canvas, Size size) {
    final scrim = Paint()..color = const Color(0xB3000000);
    final screen = Offset.zero & size;
    final target = hole;
    if (target == null) {
      canvas.drawRect(screen, scrim);
      return;
    }
    final path = Path.combine(
      PathOperation.difference,
      Path()..addRect(screen),
      Path()
        ..addRRect(RRect.fromRectAndRadius(target, const Radius.circular(14))),
    );
    canvas.drawPath(path, scrim);
  }

  @override
  bool shouldRepaint(_SpotlightPainter oldDelegate) => oldDelegate.hole != hole;
}
