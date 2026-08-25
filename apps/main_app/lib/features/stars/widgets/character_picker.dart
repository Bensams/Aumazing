import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../star_catalogue.dart';

/// Lets a parent choose which character will keep their child company
/// (STAR-A1, STAR-A2).
///
/// The design rules here are acceptance criteria, not styling preferences, so
/// they are worth stating before anyone "tidies" them:
///
///  * **All three cards are identical apart from the character.** Same size,
///    same border, same background colour. The palette is the real gender-bias
///    vector — a pink card and a blue card would reintroduce exactly the bias
///    this screen exists to remove, no matter which characters sit on them.
///  * **Nothing is preselected** and nothing is labelled "recommended". A
///    highlighted default is a recommendation whether or not it is called one.
///  * **Selection is never inferred from the child's recorded sex.** This
///    widget is not given the child's sex at all, which is the cheapest way to
///    guarantee it cannot use it.
///
/// Skipping is handled by the caller: it assigns a character at random rather
/// than falling back to a fixed one, so a skipped step does not quietly become
/// "the boy by default".
class CharacterPicker extends StatelessWidget {
  const CharacterPicker({
    super.key,
    required this.selected,
    required this.onSelected,
    this.onSpeak,
  });

  /// The current choice, or null when the parent has not chosen yet — which is
  /// the correct initial state, and why this is nullable.
  final ChildCharacter? selected;

  final ValueChanged<ChildCharacter> onSelected;

  /// Speaks the character's name. Wired to the voice-over pipeline by the
  /// caller so a non-reading parent or child can hear the options (STAR-A4);
  /// absent, the picker is still fully usable.
  final void Function(ChildCharacter)? onSpeak;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Three across whenever they fit at a comfortable tap size, stacking
        // only when they genuinely cannot. Keeping them on one row matters:
        // a wrapped third card reads as an afterthought rather than an equal.
        final threeAcross = constraints.maxWidth >= 360;
        final cardWidth = threeAcross
            ? (constraints.maxWidth - AppSpacing.md * 2) / 3
            : constraints.maxWidth;

        return Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          alignment: WrapAlignment.center,
          children: [
            for (final character in ChildCharacter.values)
              SizedBox(
                width: cardWidth,
                child: _CharacterCard(
                  character: character,
                  isSelected: selected == character,
                  onTap: () {
                    onSelected(character);
                    onSpeak?.call(character);
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}

class _CharacterCard extends StatelessWidget {
  const _CharacterCard({
    required this.character,
    required this.isSelected,
    required this.onTap,
  });

  final ChildCharacter character;
  final bool isSelected;
  final VoidCallback onTap;
  static const double _borderWidth = 1.5;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      button: true,
      selected: isSelected,
      label: character.displayName,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.largeBorder,
        child: AnimatedContainer(
          duration: AppAnimations.tapFeedback,
          // `AppTouchTargets.small` is 128 — these are child-sized targets
          // already, so one is the right card height, not a multiple.
          constraints: const BoxConstraints(
            minHeight: AppTouchTargets.small,
          ),
          padding: const EdgeInsets.symmetric(
            vertical: AppSpacing.md,
            horizontal: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            // Identical for all three. Selection is shown by the border and
            // the check, never by a per-character colour.
            color: theme.colorScheme.surface,
            borderRadius: AppRadius.largeBorder,
            border: Border.all(
              color: isSelected
                  ? theme.colorScheme.primary
                  : theme.dividerColor,
              width: _borderWidth,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // A FIXED height, not Expanded. The picker sits inside the
              // setup screen's scroll view, where height is unbounded, and a
              // flex child there is a layout assertion rather than a big
              // portrait. All three are the same height regardless, which is
              // what the "identical apart from the character" rule needs.
              SizedBox(
                height: 116,
                child: Image.asset(
                  character.baseArtAsset,
                  fit: BoxFit.contain,
                  // A missing portrait must not take the whole step down —
                  // the parent can still read the name and choose.
                  errorBuilder: (_, __, ___) => Icon(
                    Icons.person_outline,
                    size: 48,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                character.displayName,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              // Reserved whether or not it is selected, so choosing does not
              // reflow the row and shift the other two cards under the
              // parent's finger.
              SizedBox(
                height: 24,
                child: isSelected
                    ? Icon(
                        Icons.check_circle,
                        size: 24,
                        color: theme.colorScheme.primary,
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
