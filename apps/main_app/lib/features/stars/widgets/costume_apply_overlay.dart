import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../providers/child_provider.dart';
import '../star_catalogue.dart';

/// The short "putting the costume on" moment shown right after a child equips
/// one in the shop (STAR-D1).
///
/// It exists for a specific glitch. A costume's animated sprite sheets — 21 of
/// them — are decoded and sliced the first time the mascot actually shows them.
/// Before this, that happened lazily back in the lobby, so a child who equipped
/// a costume watched their character stand in its old outfit for a beat and
/// then pop into the new one. This overlay holds a calm screen while
/// [CharacterSprites.precacheCostumed] warms those sheets, so by the time the
/// child is back in the lobby the change is already on the character.
///
/// Deliberately calm and brief, in the same register as [StarEarnedOverlay]:
///
///  * a single gentle fade — nothing flashes, strobes or zooms;
///  * scaled by the child's `animationIntensity`, and effectively still at 0;
///  * a short minimum hold so an already-warmed outfit does not flicker the
///    screen open and shut, and no dead-end if warming is slow — it always
///    leaves on its own.
class CostumeApplyOverlay extends StatefulWidget {
  const CostumeApplyOverlay({
    super.key,
    required this.character,
    required this.costume,
  });

  final ChildCharacter character;
  final Costume costume;

  /// Equips nothing itself — the caller has already recorded the choice. Shows
  /// the moment, warms the sheets, and completes once it has gone, so the shop
  /// flow can await it and know the costume is ready before moving on.
  static Future<void> show(
    BuildContext context, {
    required ChildCharacter character,
    required Costume costume,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black26,
      builder: (_) => CostumeApplyOverlay(
        character: character,
        costume: costume,
      ),
    );
  }

  @override
  State<CostumeApplyOverlay> createState() => _CostumeApplyOverlayState();
}

class _CostumeApplyOverlayState extends State<CostumeApplyOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  /// Floor on how long the moment stays up. Warming is often faster than this
  /// (an outfit already seen is cached), and a dialog that opens and closes in
  /// a single frame reads as a flicker — the opposite of the calm hand-off this
  /// is for. Short enough that a child never waits *on* it.
  static const Duration _minHold = Duration(milliseconds: 700);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppAnimations.entrance,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      final profile = context.read<ChildProvider>().profile;
      final intensity = profile?.animationIntensity ?? 1.0;

      // Reduced motion is honoured by skipping the fade, not by speeding it up:
      // a faster movement is worse for a child sensitive to it, not better. At
      // zero the card simply appears.
      if (intensity <= 0 ||
          MediaQuery.maybeOf(context)?.disableAnimations == true) {
        _controller.value = 1;
      } else {
        _controller.animateTo(1, curve: AppAnimations.gentleCurve);
      }

      // Warm the equipped outfit's sheets and hold the floor at the same time;
      // the moment lasts however long the slower of the two takes. Warming is
      // best-effort inside precacheCostumed, so this await never throws and the
      // overlay always reaches its pop.
      await Future.wait<void>([
        CharacterSprites.precacheCostumed(
          widget.character.id,
          widget.costume.id,
        ),
        Future<void>.delayed(_minHold),
      ]);
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// What is being put on. `none` is a change *out* of a costume, so it is
  /// phrased as tidying up rather than dressing up.
  String get _message => widget.costume == Costume.none
      ? 'Getting ready…'
      : 'Putting on the ${widget.costume.displayName}…';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Shown via showDialog with no Material ancestor, so Text inherits the
    // fallback DefaultTextStyle — which carries a yellow underline. Neutralize
    // the inherited decoration here so the costume message is never underlined,
    // whatever way this overlay happens to be mounted.
    return DefaultTextStyle.merge(
      style: const TextStyle(
        decoration: TextDecoration.none,
        decorationColor: Colors.transparent,
      ),
      child: Center(
        child: FadeTransition(
          opacity: _controller,
          child: ScaleTransition(
            // A small settle from 96% — not a pop from zero. The difference is
            // the difference between "noticed" and "startled".
            scale: Tween<double>(begin: 0.96, end: 1).animate(_controller),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xl,
                vertical: AppSpacing.lg,
              ),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: AppRadius.extraLargeBorder,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // The outfit being applied, so the wait is about something the
                  // child can see. This still art is already cached from the shop
                  // grid, so it shows at once while the animated sheets warm
                  // behind it.
                  SizedBox(
                    height: 120,
                    child: Image.asset(
                      widget.costume.assetFor(widget.character),
                      fit: BoxFit.contain,
                      errorBuilder:
                          (_, __, ___) =>
                              const Icon(Icons.checkroom_rounded, size: 64),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    _message,
                    style: theme.textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
