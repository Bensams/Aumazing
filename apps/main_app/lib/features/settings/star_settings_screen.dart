import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_ui/shared_ui.dart';

import 'widgets/settings_scaffold.dart';

import '../../model/star_ledger_entry.dart';
import '../../providers/child_provider.dart';
import '../../providers/stars_provider.dart';
import '../stars/star_catalogue.dart';
import '../stars/widgets/character_picker.dart';

/// Parent controls for the Star Shop (STAR-A2, B3, C6, G1, G2).
///
/// The four things a parent can do here are deliberately the *only* four.
/// There is no "give my child stars" button and no way to edit the ledger:
/// stars mean something because they were earned, and a parent who can mint
/// them has turned the token board back into pocket money. The history below
/// is read-only for the same reason.
class StarSettingsScreen extends StatefulWidget {
  const StarSettingsScreen({super.key, required this.palette});

  final GamePalette palette;

  @override
  State<StarSettingsScreen> createState() => _StarSettingsScreenState();
}

class _StarSettingsScreenState extends State<StarSettingsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final childId = context.read<ChildProvider>().profile?.id;
      await context.read<StarsProvider>().bind(childId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SettingsScaffold(
      title: 'Stars & Costumes',
      icon: Icons.star_rounded,
      palette: widget.palette,
      children: [
        Consumer2<ChildProvider, StarsProvider>(
          builder: (context, childProv, stars, _) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _characterCard(context, childProv),
                const SizedBox(height: AppSpacing.md),
                _howStarsWorkCard(context, stars),
                const SizedBox(height: AppSpacing.md),
                _controlsCard(context, childProv),
                const SizedBox(height: AppSpacing.md),
                _historyCard(context, stars),
              ],
            );
          },
        ),
      ],
    );
  }

  /// STAR-A2 — change the character without losing anything.
  Widget _characterCard(BuildContext context, ChildProvider childProv) {
    return SettingsCard(
      children: [
        const _StarSectionLabel('Character'),
        const SizedBox(height: 2),
        const SettingsHintText(
          'Who keeps your child company in the games. Changing this keeps '
          'every star and costume they have earned.',
        ),
        const SizedBox(height: AppSpacing.sm),
        CharacterPicker(
          selected: childProv.profile?.character,
          onSelected: (c) => childProv.setCharacter(c),
        ),
      ],
    );
  }

  /// STAR-B3 — the earning rules, in full, generated from the same constants
  /// the award logic uses so the two cannot drift apart.
  Widget _howStarsWorkCard(BuildContext context, StarsProvider stars) {
    final theme = Theme.of(context);
    return SettingsCard(
      children: [
        const _StarSectionLabel('How stars work'),
        const SizedBox(height: 2),
        const SettingsHintText(
          'Nothing here changes. Your child earns the same amount every time, '
          'however the game goes.',
        ),
        const SizedBox(height: AppSpacing.sm),
        _rule(theme, 'Finishing any game', '$kStarsPerGame ⭐'),
        _rule(theme, 'Finishing an assessment', '$kStarsPerGame ⭐'),
        _rule(theme, 'Most in one day', '$kDailyStarCap ⭐'),
        const Divider(height: AppSpacing.lg),
        _rule(theme, 'Earned today', '${stars.earnedToday} ⭐'),
        _rule(theme, 'Stars right now', '${stars.balance} ⭐'),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Stars are never taken away and never expire. Playing badly still '
          'earns the full amount — the reward is for trying, not for scoring.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _rule(ThemeData theme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(child: Text(label, style: theme.textTheme.bodyMedium)),
          Text(
            value,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
          ),
        ],
      ),
    );
  }

  /// STAR-G2 and STAR-C6.
  Widget _controlsCard(BuildContext context, ChildProvider childProv) {
    return SettingsCard(
      children: [
        const _StarSectionLabel('Controls'),
        const SizedBox(height: AppSpacing.sm),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: childProv.shopEnabled,
          onChanged: childProv.setShopEnabled,
          title: const Text('Show the costume shop'),
          subtitle: const Text(
            'Turn this off if the shop distracts from the games. Stars keep '
            'adding up either way.',
          ),
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: childProv.requirePurchaseApproval,
          onChanged: childProv.setRequirePurchaseApproval,
          title: const Text('Ask me before buying'),
          subtitle: const Text(
            'Your child picks a costume and you confirm it.',
          ),
        ),
      ],
    );
  }

  /// STAR-G1 — read-only history.
  Widget _historyCard(BuildContext context, StarsProvider stars) {
    final theme = Theme.of(context);
    return SettingsCard(
      children: [
        const _StarSectionLabel('Star history'),
        const SizedBox(height: AppSpacing.sm),
        FutureBuilder<List<StarLedgerEntry>>(
          future: stars.history(limit: 50),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Padding(
                padding: EdgeInsets.all(AppSpacing.md),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final entries = snapshot.data!;
            if (entries.isEmpty) {
              return Text(
                'No stars yet — they appear here after the first game.',
                style: theme.textTheme.bodySmall,
              );
            }
            return Column(
              children: [
                for (final e in entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_describe(e), style: theme.textTheme.bodyMedium),
                              Text(
                                _formatDate(e.createdAt),
                                style: theme.textTheme.labelSmall,
                              ),
                            ],
                          ),
                        ),
                        Text(
                          e.delta > 0 ? '+${e.delta} ⭐' : '${e.delta} ⭐',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  String _describe(StarLedgerEntry e) => switch (e.reason) {
        StarReason.gamePlayed => 'Finished a game',
        StarReason.assessmentCompleted => 'Finished an assessment',
        StarReason.purchase =>
          'Got ${Costume.fromId(e.itemId).displayName}',
      };

  String _formatDate(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}  '
        '${two(d.hour)}:${two(d.minute)}';
  }
}

/// Local copy of the settings screens' section label, which is private there.
class _StarSectionLabel extends StatelessWidget {
  const _StarSectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppTextStyles.labelLarge.copyWith(
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
    );
  }
}
