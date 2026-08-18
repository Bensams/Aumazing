import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../star_catalogue.dart';

/// One costume in the shop grid (STAR-C1, STAR-C2).
///
/// Deliberately has no "locked" visual state. Every card renders the artwork
/// in full colour whether or not the child can afford it; how far away it is
/// shows as a progress bar underneath. Greying out an unaffordable costume, or
/// stamping a padlock on it, turns "you're working towards this" into "you
/// can't have this" — and this app does not tell a child that.
class CostumeCard extends StatelessWidget {
  const CostumeCard({
    super.key,
    required this.offer,
    required this.character,
    required this.isWorn,
    required this.onTap,
  });

  final CostumeOffer offer;
  final ChildCharacter character;
  final bool isWorn;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      button: true,
      label: '${offer.costume.displayName}. ${offer.spokenProgress}',
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.largeBorder,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: AppRadius.largeBorder,
            border: Border.all(
              color: isWorn ? theme.colorScheme.primary : theme.dividerColor,
              width: isWorn ? 3 : 1.5,
            ),
          ),
          child: Column(
            children: [
              Expanded(
                child: Stack(
                  alignment: Alignment.topRight,
                  children: [
                    Positioned.fill(
                      child: Image.asset(
                        offer.costume.assetFor(character),
                        // Full colour, always. No opacity change for
                        // affordability — see the class doc.
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) =>
                            const Icon(Icons.checkroom, size: 48),
                      ),
                    ),
                    if (offer.owned)
                      Icon(
                        isWorn ? Icons.check_circle : Icons.inventory_2,
                        color: theme.colorScheme.primary,
                        size: 24,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                offer.costume.displayName,
                style: theme.textTheme.titleSmall,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: AppSpacing.xs),
              _footer(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _footer(BuildContext context) {
    final theme = Theme.of(context);

    if (isWorn) {
      return Text('Wearing', style: theme.textTheme.labelMedium);
    }
    if (offer.owned) {
      return Text('Tap to wear', style: theme.textTheme.labelMedium);
    }
    if (offer.affordable) {
      return Text(
        '${offer.costume.priceStars} ⭐  ready!',
        style: theme.textTheme.labelMedium
            ?.copyWith(fontWeight: FontWeight.w700),
      );
    }

    // The progress bar leads and the numeral follows, because many users
    // cannot read numerals — a bar three-quarters full is legible to a child
    // for whom "18" is not (STAR-C2).
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: offer.progress,
            minHeight: 8,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '${offer.balance} / ${offer.costume.priceStars} ⭐',
          style: theme.textTheme.labelSmall,
        ),
      ],
    );
  }
}
