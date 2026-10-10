import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

/// One question answered by tapping a chip — the building block of the
/// observed-assessment screens (AUM-351).
///
/// Single choice by default ([selected]); pass [isSelected] for a
/// choose-any question.
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
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final v in values)
                Builder(
                  builder: (context) {
                    final on = isSelected?.call(v) ?? v == selected;
                    return ChoiceChip(
                      key: Key('$keyPrefix.${id(v)}'),
                      label: Text(label(v)),
                      selected: on,
                      selectedColor: AppColors.textPrimary,
                      side: const BorderSide(color: AppColors.textSecondary),
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
