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
    this.tags = const [],
    this.actionLabel,
    this.onAction,
    this.dismissLabel,
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

  /// Short labels shown as chips under [body] — for a step that names a few
  /// things at once, such as the four skill areas an assessment covers.
  final List<String> tags;

  /// Turns the step into a call to action: the primary button reads this
  /// instead of Next / Done, and pressing it — or tapping the spotlighted
  /// control itself — ends the overlay and runs [onAction].
  final String? actionLabel;

  final VoidCallback? onAction;

  /// Replaces "Skip" on the secondary button, e.g. "Later" for a prompt the
  /// parent can come back to.
  final String? dismissLabel;

  bool get hasAction => actionLabel != null && onAction != null;
}

/// A coach-mark tour: dims the screen, cuts a hole around one control at a
/// time, and explains it in a sentence with **Next** / **Skip** controls.
///
/// Steps whose target is not currently on screen are skipped automatically,
/// so a single step list can serve both the landscape and the portrait
/// dashboard, and cards that only appear in some states (premium banner,
/// screen-time meter) never leave the parent staring at an empty spotlight.
///
/// A step with an action ([TourStep.actionLabel]) is a prompt rather than an
/// explanation: its ring pulses to draw the eye, and the spotlighted control
/// stays tappable through the scrim.
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

class _GuidedTourOverlayState extends State<GuidedTourOverlay>
    with SingleTickerProviderStateMixin {
  /// Index into [widget.steps]; null until the first step is measured.
  int? _index;

  /// The spotlight, in this overlay's coordinates. Null = no cutout.
  Rect? _rect;

  bool _remeasureScheduled = false;
  bool _finished = false;

  static const _padding = 8.0;
  static const _cardWidth = 380.0;

  /// Drives the pulsing ring on an action step. Only runs while one is shown.
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _goTo(0));
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
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
    if (widget.steps[i].hasAction) {
      _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
    }
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
    _pulse.stop();
    widget.onFinish();
  }

  /// Closes the overlay first, so whatever [TourStep.onAction] opens is not
  /// covered by the scrim, then runs the action.
  void _runAction(TourStep step) {
    if (_finished) return;
    _finish();
    step.onAction!();
  }

  /// A tap on the scrim advances; on an action step, a tap on the
  /// spotlighted control itself does what that control would have done.
  void _onScrimTap(Offset position) {
    final i = _index;
    if (i == null) return;
    final step = widget.steps[i];
    final hole = _rect?.inflate(_padding);
    if (step.hasAction && hole != null && hole.contains(position)) {
      _runAction(step);
      return;
    }
    _goTo(i + 1);
  }

  Rect? _rectFor(TourStep step) {
    final ctx = step.targetKey?.currentContext;
    if (ctx == null) return null;
    final target = ctx.findRenderObject();
    final self = context.findRenderObject();
    if (target is! RenderBox || self is! RenderBox) return null;
    if (!target.hasSize || !self.hasSize) return null;
    final topLeft = target.localToGlobal(Offset.zero, ancestor: self);
    // Keep the spotlight, its padding and the ring on screen: a card taller
    // than the viewport, or one scrolled hard against the bottom edge, would
    // otherwise push the ring past the edge where the parent cannot see it.
    const margin = _padding + 4;
    final visible = (Offset.zero & self.size).deflate(margin);
    final rect = (topLeft & target.size).intersect(visible);
    if (rect.width <= 0 || rect.height <= 0) return null;
    return rect;
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
                  (fresh.center - current.center).distance > 0.5 ||
                  (fresh.size.width - current.size.width).abs() > 0.5 ||
                  (fresh.size.height - current.size.height).abs() > 0.5;
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
                onTapUp:
                    i == null ? null : (d) => _onScrimTap(d.localPosition),
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
            if (hole != null && step != null && step.hasAction)
              Positioned.fromRect(
                rect: hole.inflate(10),
                child: IgnorePointer(
                  child: ListenableBuilder(
                    listenable: _pulse,
                    builder: (context, _) {
                      final t = Curves.easeInOut.transform(_pulse.value);
                      return Transform.scale(
                        scale: 0.96 + 0.06 * t,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: AppColors.white.withValues(
                                alpha: 0.9 - 0.6 * t,
                              ),
                              width: 3,
                            ),
                          ),
                        ),
                      );
                    },
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
            onNext:
                step.hasAction
                    ? () => _runAction(step)
                    : () => _goTo(index + 1),
            onBack: widget.steps.take(index).any(_isVisible) ? _goBack : null,
            onSkip: _finish,
          );

          if (hole == null) {
            return Center(child: SizedBox(width: width, child: card));
          }

          // Sit under the spotlight, or above it, or — when a tall target
          // such as a full-height side panel leaves room for neither —
          // float over it; the ring still marks what is being described.
          const estimatedHeight = 230.0;
          final spaceBelow = constraints.maxHeight - hole.bottom - 12;
          final spaceAbove = hole.top - 12;
          double? top;
          double? bottom;
          if (spaceBelow >= estimatedHeight) {
            top = (hole.bottom + 12).clamp(
              16.0,
              (constraints.maxHeight - estimatedHeight - 16).clamp(
                16.0,
                double.infinity,
              ),
            );
          } else if (spaceAbove >= estimatedHeight) {
            bottom = constraints.maxHeight - hole.top + 12;
          } else {
            // Prefer a bottom-anchored card when neither side has enough
            // measured room. Its intrinsic height is the source of truth;
            // the old estimated-height centering could place Next below a
            // short landscape viewport.
            bottom = 16.0;
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
              // A single-step prompt is not a tour; "1 of 1" would only
              // suggest there is more to come.
              if (total > 1)
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
          if (step.tags.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final tag in step.tags)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.lavenderLight,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      tag,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              TextButton(
                onPressed: onSkip,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                ),
                child: Text(step.dismissLabel ?? 'Skip'),
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
                label: step.actionLabel ?? (isLast ? 'Done' : 'Next'),
                width: step.actionLabel == null ? 120 : 150,
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
///
/// The hole is an even-odd fill of one path holding both the screen and the
/// target, not a `Path.combine` difference: the web renderer drew the
/// combined path as a solid scrim, so the "spotlit" control came out exactly
/// as dim as everything around it and only the ring marked it.
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
    final path =
        Path()
          ..fillType = PathFillType.evenOdd
          ..addRect(screen)
          ..addRRect(
            RRect.fromRectAndRadius(target, const Radius.circular(14)),
          );
    canvas.drawPath(path, scrim);
  }

  @override
  bool shouldRepaint(_SpotlightPainter oldDelegate) => oldDelegate.hole != hole;
}
