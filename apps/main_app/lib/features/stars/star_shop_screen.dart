import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../providers/child_provider.dart';
import '../../providers/stars_provider.dart';
import 'star_catalogue.dart';
import 'widgets/costume_card.dart';

/// The Star Shop: browse costumes, try one on, buy it, wear it (STAR-C1…C4,
/// STAR-D1, STAR-D2).
///
/// The rules that shape this screen are acceptance criteria, not decoration:
///
///  * **Everything is always visible and always in full colour.** No padlocks,
///    no greyed-out cards, no "locked" language. A costume a child cannot
///    afford yet shows a progress ring — the same idea as `MascotGesture.oops`,
///    which exists so the app never models distress at a child. "Not yet" is a
///    progress bar; it is not a refusal.
///  * **Preview is free and works for everything**, including costumes the
///    child cannot afford. Seeing what you are working towards is the whole
///    motivational mechanism.
///  * **Prices never move.** They come from the `const` catalogue.
class StarShopScreen extends StatefulWidget {
  const StarShopScreen({super.key});

  @override
  State<StarShopScreen> createState() => _StarShopScreenState();
}

class _StarShopScreenState extends State<StarShopScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<StarsProvider>().refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final stars = context.watch<StarsProvider>();
    final childProvider = context.watch<ChildProvider>();
    final profile = childProvider.profile;
    final character = profile?.character ?? ChildCharacter.bps;
    final worn = profile?.costume ?? Costume.none;

    return Scaffold(
      body: AppGradientBackground(
        gradient: childProvider.activePalette.gameBackground,
        child: SafeArea(
          child: Column(
            children: [
              _ShopHeader(onBack: () => Navigator.of(context).maybePop()),
              _StarBalance(balance: stars.balance, atCap: stars.atDailyCap),
              Expanded(
                child: stars.isLoading && stars.offers.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : _CostumeGrid(
                        character: character,
                        worn: worn,
                        // "No costume" leads the grid and is always owned, so
                        // taking one off is exactly as easy as putting one on
                        // (STAR-D1). A child who changes their mind must never
                        // have to hunt for the way back.
                        offers: [
                          CostumeOffer(
                            costume: Costume.none,
                            owned: true,
                            balance: stars.balance,
                          ),
                          ...stars.offers,
                        ],
                        onTap: (offer) => _openCostume(offer, character),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Full-size preview with the one action that makes sense for this costume:
  /// wear it, get it, or keep going.
  Future<void> _openCostume(CostumeOffer offer, ChildCharacter character) async {
    final result = await showModalBottomSheet<_CostumeAction>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CostumeSheet(offer: offer, character: character),
    );
    if (!mounted || result == null) return;

    switch (result) {
      case _CostumeAction.wear:
        await context.read<ChildProvider>().setEquippedCostume(offer.costume);
      case _CostumeAction.buy:
        // STAR-C6. While the parent is being asked the item reads as "asked",
        // not "denied" — a child who requested a costume has done nothing
        // wrong, and a refusal-shaped screen would teach otherwise.
        if (context.read<ChildProvider>().requirePurchaseApproval) {
          final approved = await ParentVerificationDialog.show(context);
          if (!mounted || !approved) return;
        }
        final bought =
            await context.read<StarsProvider>().purchase(offer.costume);
        if (!mounted) return;
        if (bought) {
          // Equipping immediately is the point of buying — a child who spends
          // their stars should see the result on their character at once.
          await context.read<ChildProvider>().setEquippedCostume(offer.costume);
        }
    }
  }
}

enum _CostumeAction { wear, buy }

/// Back arrow plus title. Deliberately not `ChildModeTopBar`, which is the
/// in-game step-progress bar — the shop is not a game and has no steps.
class _ShopHeader extends StatelessWidget {
  const _ShopHeader({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            iconSize: 32,
            icon: const Icon(Icons.arrow_back_rounded),
            tooltip: 'Back',
          ),
          const SizedBox(width: AppSpacing.sm),
          Text('My Costumes', style: Theme.of(context).textTheme.headlineSmall),
        ],
      ),
    );
  }
}

class _StarBalance extends StatelessWidget {
  const _StarBalance({required this.balance, required this.atCap});

  final int balance;
  final bool atCap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('⭐', style: TextStyle(fontSize: 32)),
          const SizedBox(width: AppSpacing.sm),
          Text('$balance', style: theme.textTheme.displaySmall),
          if (atCap) ...[
            const SizedBox(width: AppSpacing.md),
            Flexible(
              child: Text(
                // A finished state, never a lockout: the child has *got*
                // everything today offers rather than being cut off.
                "You've got all of today's stars!",
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CostumeGrid extends StatelessWidget {
  const _CostumeGrid({
    required this.character,
    required this.worn,
    required this.offers,
    required this.onTap,
  });

  final ChildCharacter character;
  final Costume worn;
  final List<CostumeOffer> offers;
  final ValueChanged<CostumeOffer> onTap;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(AppSpacing.lg),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 260,
        childAspectRatio: 0.72,
        crossAxisSpacing: AppSpacing.md,
        mainAxisSpacing: AppSpacing.md,
      ),
      itemCount: offers.length,
      itemBuilder: (context, i) {
        final offer = offers[i];
        return CostumeCard(
          offer: offer,
          character: character,
          isWorn: worn == offer.costume,
          onTap: () => onTap(offer),
        );
      },
    );
  }
}

/// The preview sheet. Shows the child's *own* character wearing the costume,
/// full size, whether or not they can afford it.
class _CostumeSheet extends StatelessWidget {
  const _CostumeSheet({required this.offer, required this.character});

  final CostumeOffer offer;
  final ChildCharacter character;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppRadius.extraLarge),
        ),
      ),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(offer.costume.displayName, style: theme.textTheme.headlineSmall),
            const SizedBox(height: AppSpacing.md),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: Image.asset(
                offer.costume.assetFor(character),
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) =>
                    const Icon(Icons.checkroom, size: 96),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(offer.spokenProgress, style: theme.textTheme.bodyLarge),
            const SizedBox(height: AppSpacing.lg),
            _sheetAction(context),
            const SizedBox(height: AppSpacing.sm),
            AppSecondaryButton(
              label: 'Not yet',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sheetAction(BuildContext context) {
    if (offer.owned) {
      return AppPrimaryButton(
        label: 'Wear ${offer.costume.displayName}',
        onPressed: () => Navigator.of(context).pop(_CostumeAction.wear),
      );
    }
    if (offer.affordable) {
      // Phrased as a choice, not a warning. The pair of buttons is
      // "Get Panda" / "Not yet" — there is no cancel-shaped scare step.
      return AppPrimaryButton(
        label: 'Get ${offer.costume.displayName} '
            '(${offer.costume.priceStars} ⭐)',
        onPressed: () => Navigator.of(context).pop(_CostumeAction.buy),
      );
    }
    // Not affordable: no button at all rather than a disabled one. A dead
    // control a child can press and have ignored teaches that pressing does
    // nothing; the progress line above already says what to do — play more.
    return Text(
      'Keep playing to get ${offer.costume.displayName}!',
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.titleMedium,
    );
  }
}
