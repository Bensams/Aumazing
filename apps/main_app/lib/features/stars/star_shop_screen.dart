import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../providers/child_provider.dart';
import '../../providers/stars_provider.dart';
import 'star_catalogue.dart';
import 'widgets/costume_apply_overlay.dart';
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
    // The shop is a child-facing screen and says so, rather than inheriting
    // whatever the previous route happened to leave set. Reached only from
    // the child lobby today, so in practice it was already landscape — but
    // "in practice" is how a screen ends up rotating differently depending on
    // where the child came from. The twelve game screens declare the same
    // thing in the same place.
    //
    // Nothing here touches the parent policy: parent-facing screens call
    // `lockParentAdaptive()` in their own `initState`, which keeps a phone in
    // portrait. See `parent_screen_orientation.dart`.
    lockParentLandscape();

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
              _ShopHeader(
                onBack: () => Navigator.of(context).maybePop(),
                balance: stars.balance,
              ),
              if (stars.atDailyCap) const _DailyCapNote(),
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
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CostumeSheet(offer: offer, character: character),
    );
    if (!mounted || result == null) return;

    switch (result) {
      case _CostumeAction.wear:
        await _equip(offer.costume, character);
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
          await _equip(offer.costume, character);
        }
    }
  }

  /// Records the choice, then holds a brief "putting it on" moment while the
  /// costume's animated sheets warm, so the child returns to the lobby with the
  /// change already on their character rather than watching it pop in a beat
  /// later. The overlay awaits the same decode the provider already kicked off
  /// in [ChildProvider.setEquippedCostume], so there is no duplicate work — it
  /// just gives that warm-up a calm face and keeps the shop from closing ahead
  /// of it.
  Future<void> _equip(Costume costume, ChildCharacter character) async {
    await context.read<ChildProvider>().setEquippedCostume(costume);
    if (!mounted) return;
    await CostumeApplyOverlay.show(
      context,
      character: character,
      costume: costume,
    );
  }
}

enum _CostumeAction { wear, buy }

/// Back arrow, title, and the child's star balance in the top-right corner.
///
/// Deliberately not `ChildModeTopBar`, which is the in-game step-progress bar
/// — the shop is not a game and has no steps.
///
/// The balance sits in the corner rather than in a centred band of its own:
/// on a phone the vertical space it used to take is a whole row of costumes,
/// and the number is a persistent status readout, which is where a child (and
/// an adult reading over their shoulder) already looks for one.
class _ShopHeader extends StatelessWidget {
  const _ShopHeader({required this.onBack, required this.balance});

  final VoidCallback onBack;
  final int balance;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
          Expanded(
            child: Text(
              'My Costumes',
              style: theme.textTheme.headlineSmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          _StarBalance(balance: balance),
        ],
      ),
    );
  }
}

/// The star count, as a pill in the header's trailing corner.
class _StarBalance extends StatelessWidget {
  const _StarBalance({required this.balance});

  final int balance;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      liveRegion: true,
      label: '$balance stars',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(AppRadius.large),
          border: Border.all(color: theme.dividerColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('⭐', style: TextStyle(fontSize: 24)),
            const SizedBox(width: AppSpacing.xs),
            Text(
              '$balance',
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown only once the day's stars are all earned.
///
/// A finished state, never a lockout: the child has *got* everything today
/// offers rather than being cut off. It gets its own line instead of riding
/// alongside the balance, so a long sentence can never squeeze the number.
class _DailyCapNote extends StatelessWidget {
  const _DailyCapNote();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.xs,
      ),
      child: Text(
        "You've got all of today's stars!",
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium,
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

  /// The card shape we want when there is room: taller than wide, so the
  /// character's full body reads at a glance.
  static const double _preferredAspect = 0.72;

  @override
  Widget build(BuildContext context) {
    // Sized against the real viewport rather than a fixed extent. A phone in
    // landscape is the case that breaks a width-only rule: three columns fit
    // across happily, but a card 0.72 as wide as it is tall is then taller
    // than the screen, so the first row alone fills the view and the grid
    // reads as one enormous costume. Capping the height to what is actually
    // visible keeps a whole row on screen in every orientation.
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = AppSpacing.md;
        const pad = AppSpacing.lg;
        final width = constraints.maxWidth;
        final columns = width >= 900
            ? 4
            : width >= 600
                ? 3
                : 2;
        final cardWidth = (width - pad * 2 - gap * (columns - 1)) / columns;
        final visibleHeight = constraints.maxHeight - pad * 2;
        final cardHeight = visibleHeight.isFinite && visibleHeight > 0
            ? math.min(cardWidth / _preferredAspect, visibleHeight)
            : cardWidth / _preferredAspect;

        return GridView.builder(
          padding: const EdgeInsets.all(pad),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            childAspectRatio: cardWidth / cardHeight,
            crossAxisSpacing: gap,
            mainAxisSpacing: gap,
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

  /// Roughly what the title, the progress line, both buttons and the padding
  /// between them occupy when they are stacked. The artwork gets the rest.
  static const double _stackedChromeHeight = 300;

  /// Below this the stacked layout cannot show the artwork *and* keep both
  /// buttons on screen, so the sheet turns side-by-side instead. A phone in
  /// landscape is about 390 tall, which is what puts it under this line.
  static const double _sideBySideBelow = 520;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);

    // Everything here is measured from the viewport rather than fixed. The
    // previous version reserved 320 logical pixels for the artwork whatever
    // the screen was, which overflowed a phone by ~197px and left a tablet
    // with a postage stamp. `viewPadding` rather than `padding`, because a
    // bottom sheet consumes the inset itself.
    final available =
        media.size.height - media.viewPadding.top - media.viewPadding.bottom;
    final maxSheetHeight = available * 0.9;
    final sideBySide = maxSheetHeight < _sideBySideBelow &&
        media.size.width > media.size.height;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxSheetHeight),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppRadius.extraLarge),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: sideBySide
                ? _sideBySideBody(context, maxSheetHeight)
                : _stackedBody(context, maxSheetHeight),
          ),
        ),
      ),
    );
  }

  /// Portrait phones and tablets: title, costume, progress, actions, stacked.
  Widget _stackedBody(BuildContext context, double maxSheetHeight) {
    // Clamped at both ends: never so small the costume is unreadable, never
    // so tall it crowds the buttons out.
    final artHeight = (maxSheetHeight - _stackedChromeHeight)
        .clamp(140.0, 420.0)
        .toDouble();

    // The scroll view is a backstop, not the layout: at the sizes we ship the
    // content fits and nothing scrolls. It is here so a very large system
    // font scrolls instead of clipping the buttons a child needs to press.
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _title(context),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: artHeight,
            width: double.infinity,
            child: _art(),
          ),
          const SizedBox(height: AppSpacing.md),
          _progress(context),
          const SizedBox(height: AppSpacing.lg),
          _sheetAction(context),
          const SizedBox(height: AppSpacing.sm),
          _notYet(context),
        ],
      ),
    );
  }

  /// Landscape phones: the costume beside its actions rather than above them.
  ///
  /// Stacking here is what produced the reported overflow — a phone on its
  /// side has roughly 350 usable pixels of height, and the title, artwork,
  /// progress line and two buttons cannot all live in that column. Turning
  /// the sheet sideways uses the axis that actually has room, and keeps
  /// "Not yet" on screen without scrolling.
  Widget _sideBySideBody(BuildContext context, double maxSheetHeight) {
    // The artwork needs an explicit height even here. `Image` inside an
    // `Expanded` is only width-constrained, so it takes the height its aspect
    // ratio asks for — 900/657 of a third of a landscape phone is taller than
    // the phone — and pushes the whole row past the sheet.
    final artHeight = (maxSheetHeight - AppSpacing.lg * 2)
        .clamp(120.0, 360.0)
        .toDouble();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(flex: 4, child: SizedBox(height: artHeight, child: _art())),
        const SizedBox(width: AppSpacing.lg),
        Expanded(
          flex: 5,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _title(context),
                const SizedBox(height: AppSpacing.sm),
                _progress(context),
                const SizedBox(height: AppSpacing.md),
                _sheetAction(context),
                const SizedBox(height: AppSpacing.sm),
                _notYet(context),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _title(BuildContext context) => Text(
        offer.costume.displayName,
        style: Theme.of(context).textTheme.headlineSmall,
        textAlign: TextAlign.center,
      );

  Widget _art() => Image.asset(
        offer.costume.assetFor(character),
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const Icon(Icons.checkroom, size: 96),
      );

  Widget _progress(BuildContext context) => Text(
        offer.spokenProgress,
        style: Theme.of(context).textTheme.bodyLarge,
        textAlign: TextAlign.center,
      );

  Widget _notYet(BuildContext context) => AppSecondaryButton(
        label: 'Not yet',
        onPressed: () => Navigator.of(context).pop(),
      );

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
