import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

/// One question answered by tapping a chip — the building block of the
/// observed-assessment screens (AUM-351).
///
/// Single choice by default ([selected]); pass [isSelected] for a
/// choose-any question. A chosen chip is filled with a check mark, and
/// [isQuiet] answers ("Prefer not to say", "None") sit back on a soft grey
/// fill so they do not read as a finding.
class ObservationChoiceRow<T> extends StatelessWidget {
  const ObservationChoiceRow({
    super.key,
    required this.keyPrefix,
    required this.question,
    required this.values,
    required this.label,
    required this.id,
    required this.onSelected,
    this.selected,
    this.isSelected,
    this.isQuiet,
    this.hint,
  });

  /// Chip keys are `<keyPrefix>.<id>`, for tests.
  final String keyPrefix;
  final String question;
  final List<T> values;
  final String Function(T) label;
  final String Function(T) id;
  final ValueChanged<T> onSelected;
  final T? selected;
  final bool Function(T)? isSelected;
  final bool Function(T)? isQuiet;

  /// A short line under the question, e.g. "Choose one".
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            question,
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (hint != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                hint!,
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final v in values)
                Builder(
                  builder: (context) {
                    final on = isSelected?.call(v) ?? v == selected;
                    final quiet = isQuiet?.call(v) ?? false;
                    return ChoiceChip(
                      key: Key('$keyPrefix.${id(v)}'),
                      label: Text(label(v)),
                      selected: on,
                      showCheckmark: true,
                      checkmarkColor: AppColors.white,
                      backgroundColor:
                          quiet ? AppColors.muted : AppColors.white,
                      selectedColor: AppColors.textPrimary,
                      side: BorderSide(
                        color:
                            on
                                ? AppColors.textPrimary
                                : quiet
                                ? AppColors.mutedForeground
                                : AppColors.textSecondary,
                      ),
                      labelStyle: AppTextStyles.bodySmall.copyWith(
                        color: on ? AppColors.white : AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                      onSelected: (_) => onSelected(v),
                    );
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}
