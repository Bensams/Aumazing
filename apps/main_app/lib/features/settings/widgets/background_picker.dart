import 'package:flutter/material.dart';

import 'package:shared_ui/shared_ui.dart';

import '../../../providers/child_provider.dart';

/// Parent-facing editor for the child's game-screen background.
///
/// Three ways in, from easiest to most controlled: tap a ready-made circle,
/// pick freely on the wheel, or blend two colours as a gradient. The preset
/// themes above this section stay available — this only takes over when the
/// parent applies something.
///
/// The preview is the important part. It draws the real Match It shape
/// colours on the chosen background, because "seven of ten shapes are clearly
/// visible" means much less to a parent than seeing the gold star vanish.
class BackgroundPicker extends StatefulWidget {
  const BackgroundPicker({super.key, required this.childProv});

  final ChildProvider childProv;

  @override
  State<BackgroundPicker> createState() => _BackgroundPickerState();
}

class _BackgroundPickerState extends State<BackgroundPicker> {
  late ChildBackground _draft = widget.childProv.customBackground ??
      const ChildBackground.solid(Color(0xFFFAF9F6));

  /// Which gradient stop the wheel is editing (0 = start, 1 = end). Ignored
  /// for a solid background.
  int _stop = 0;

  bool get _isGradient => _draft.kind == ChildBackgroundKind.gradient;

  Color get _editing => _stop == 0 ? _draft.start : _draft.end;

  void _setEditing(Color c) => setState(() {
        _draft = _stop == 0
            ? _draft.copyWith(start: c, end: _isGradient ? _draft.end : c)
            : _draft.copyWith(end: c);
      });

  void _setKind(ChildBackgroundKind kind) => setState(() {
        _stop = 0;
        _draft = kind == ChildBackgroundKind.solid
            ? ChildBackground.solid(_draft.start)
            // Seed the second stop from the first so switching to gradient
            // does not jump to an unrelated colour.
            : ChildBackground.gradient(_draft.start, _draft.end);
      });

  @override
  Widget build(BuildContext context) {
    final applied = widget.childProv.customBackground;
    final unchanged = applied == _draft;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentedButton<ChildBackgroundKind>(
          segments: const [
            ButtonSegment(
              value: ChildBackgroundKind.solid,
              label: Text('One colour'),
              icon: Icon(Icons.circle, size: 16),
            ),
            ButtonSegment(
              value: ChildBackgroundKind.gradient,
              label: Text('Blend two'),
              icon: Icon(Icons.gradient_rounded, size: 16),
            ),
          ],
          selected: {_draft.kind},
          onSelectionChanged: (s) => _setKind(s.first),
        ),
        const SizedBox(height: AppSpacing.md),

        Text('Ready-made', style: AppTextStyles.labelLarge),
        const SizedBox(height: AppSpacing.xs),
        _SwatchRow(
          selected: _editing,
          onPick: _setEditing,
        ),
        const SizedBox(height: AppSpacing.md),

        // Which stop the wheel edits. Only meaningful for a blend.
        if (_isGradient) ...[
          Row(
            children: [
              Expanded(
                child: _StopChip(
                  label: 'From',
                  colour: _draft.start,
                  selected: _stop == 0,
                  onTap: () => setState(() => _stop = 0),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _StopChip(
                  label: 'To',
                  colour: _draft.end,
                  selected: _stop == 1,
                  onTap: () => setState(() => _stop = 1),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
        ],

        Center(
          child: ColorWheelPicker(
            colour: _editing,
            diameter: 190,
            label: _isGradient
                ? (_stop == 0 ? 'From colour' : 'To colour')
                : 'Background colour',
            onChanged: _setEditing,
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        _BackgroundPreview(background: _draft),
        const SizedBox(height: AppSpacing.sm),
        _ContrastNote(background: _draft),
        const SizedBox(height: AppSpacing.md),

        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: unchanged
                    ? null
                    : () => widget.childProv.setCustomBackground(_draft),
                icon: const Icon(Icons.check_rounded, size: 18),
                label: Text(unchanged ? 'Applied' : 'Use this background'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(kMinInteractiveDimension),
                ),
              ),
            ),
            if (applied != null) ...[
              const SizedBox(width: AppSpacing.sm),
              TextButton(
                onPressed: () => widget.childProv.clearCustomBackground(),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  minimumSize: const Size(
                    kMinInteractiveDimension,
                    kMinInteractiveDimension,
                  ),
                ),
                child: const Text('Remove'),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// The ready-made circles. Sized to the 48dp minimum and individually named,
/// so this row — not the wheel — is the accessible path to a colour.
class _SwatchRow extends StatelessWidget {
  const _SwatchRow({required this.selected, required this.onPick});

  final Color selected;
  final ValueChanged<Color> onPick;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final swatch in ChildBackgroundSwatches.ready)
          Builder(builder: (context) {
            final isSelected = swatch.colour == selected;
            final clears =
                ChildBackground.solid(swatch.colour).shapesClearingMinimum;
            return Semantics(
              button: true,
              selected: isSelected,
              label: '${swatch.name}, $clears of '
                  '${ChildBackground.totalShapes} game shapes clearly visible',
              excludeSemantics: true,
              child: InkResponse(
                onTap: () => onPick(swatch.colour),
                radius: kMinInteractiveDimension / 2,
                child: SizedBox(
                  width: kMinInteractiveDimension,
                  height: kMinInteractiveDimension,
                  child: Center(
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: swatch.colour,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected
                              ? AppColors.primaryPurple
                              : AppColors.border,
                          width: isSelected ? 3 : 1,
                        ),
                      ),
                      child: isSelected
                          ? Icon(
                              Icons.check_rounded,
                              size: 18,
                              // Tick has to survive on both the light and the
                              // dark swatches.
                              color: Contrast.relativeLuminance(
                                          swatch.colour) >
                                      0.4
                                  ? AppColors.foreground
                                  : AppColors.white,
                            )
                          : null,
                    ),
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }
}

/// "From" / "To" selector for a blended background.
class _StopChip extends StatelessWidget {
  const _StopChip({
    required this.label,
    required this.colour,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Color colour;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '$label colour',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: kMinInteractiveDimension,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppColors.primaryPurple : AppColors.border,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: colour,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.border),
                ),
              ),
              const SizedBox(width: 8),
              Text(label, style: AppTextStyles.labelLarge),
            ],
          ),
        ),
      ),
    );
  }
}

/// The chosen background with the real Match It shape colours sitting on it.
class _BackgroundPreview extends StatelessWidget {
  const _BackgroundPreview({required this.background});

  final ChildBackground background;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Preview of the game background with sample game shapes',
      image: true,
      excludeSemantics: true,
      child: Container(
        height: 88,
        decoration: BoxDecoration(
          gradient: background.toGradient(),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        alignment: Alignment.center,
        child: Wrap(
          spacing: 10,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            for (final c in GameArtColors.matchItShapes)
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(color: c, shape: BoxShape.circle),
              ),
          ],
        ),
      ),
    );
  }
}

/// Plain-language contrast readout under the preview.
class _ContrastNote extends StatelessWidget {
  const _ContrastNote({required this.background});

  final ChildBackground background;

  @override
  Widget build(BuildContext context) {
    final clears = background.shapesClearingMinimum;
    final total = ChildBackground.totalShapes;
    // Six of ten is what the best light colour manages; nine is the ceiling
    // any colour reaches. Below six is a real step down, so that is where
    // the caution starts.
    final poor = clears < 6;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: poor ? AppColors.statusWarningBg : AppColors.muted,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            poor ? Icons.warning_amber_rounded : Icons.info_outline_rounded,
            size: 18,
            color: poor
                ? AppColors.statusWarningDark
                : AppColors.mutedForeground,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$clears of $total game shapes are clearly visible on this '
              'background'
              '${poor ? ' — some will be hard for your child to tell apart.' : '.'}'
              '\nNo colour reaches all $total: the yellow shapes need a dark '
              'background and the purple one needs a light background, so a '
              'background alone cannot fix every shape.',
              style: AppTextStyles.bodySmall.copyWith(
                color: poor
                    ? AppColors.statusWarningDark
                    : AppColors.mutedForeground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
