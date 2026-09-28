import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../core/services/auth_service.dart';
import '../../services/entitlement_service.dart';
import '../premium/premium_plan.dart';
import '../premium/premium_upgrade_screen.dart';
import 'widgets/settings_scaffold.dart';

/// Settings › Your Plan (AUM-169): which plan the account is on, when paid
/// Premium ends or ended, the extra child profiles bought, and a way to renew.
///
/// Premium is a one-time payment for 30 days that never renews by itself, so
/// the page says plainly that there is nothing to cancel.
class YourPlanScreen extends StatefulWidget {
  const YourPlanScreen({
    super.key,
    required this.palette,
    required this.authService,
    this.refresh,
  });

  final GamePalette palette;
  final AuthService authService;

  /// Re-reads the entitlement when the page opens. Defaults to
  /// [EntitlementService.refresh]; injectable for tests.
  final Future<void> Function()? refresh;

  @override
  State<YourPlanScreen> createState() => _YourPlanScreenState();
}

class _YourPlanScreenState extends State<YourPlanScreen> {
  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      await (widget.refresh ?? EntitlementService.instance.refresh)();
    } catch (e) {
      // Offline or signed out: the cached plan below is still correct.
      debugPrint('[YourPlan] refresh failed: $e');
    }
  }

  void _openUpgrade() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PremiumUpgradeScreen(authService: widget.authService),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: EntitlementService.instance,
      builder: (context, _) {
        final plan = PremiumPlan.of(EntitlementService.instance);
        final action = switch (plan.kind) {
          PremiumPlanKind.free => 'Get Premium',
          PremiumPlanKind.ended => 'Renew Premium',
          PremiumPlanKind.active ||
          PremiumPlanKind.endingSoon => 'Renew now (+30 days)',
          _ => null,
        };
        return SettingsScaffold(
          title: 'Your Plan',
          icon: Icons.workspace_premium_rounded,
          palette: widget.palette,
          children: [
            _StatusCard(plan: plan),
            const SizedBox(height: AppSpacing.md),
            _InfoCard(
              icon: Icons.info_outline_rounded,
              title: 'How Premium works',
              body:
                  '₱149 for 30 days, paid once through PayMongo. It never '
                  'renews by itself and no payment details are kept, so '
                  'there is no subscription to cancel: Premium simply ends '
                  'on its end date unless you pay again. Paying before it '
                  'ends adds 30 days on top of the days you have left.',
            ),
            const SizedBox(height: AppSpacing.md),
            _InfoCard(
              key: const Key('plan-profiles-card'),
              icon: Icons.family_restroom_rounded,
              title: 'Child profiles',
              body:
                  plan.unlimitedProfiles
                      ? 'No profile limit in this edition.'
                      : plan.extraProfiles == 0
                      ? '1 free profile. Extra profiles are ₱30 each with '
                          'Premium — add one from Manage Children.'
                      : '1 free profile + ${plan.extraProfiles} extra '
                          '${plan.extraProfiles == 1 ? 'profile' : 'profiles'}'
                          ' bought.',
            ),
            if (action != null) ...[
              const SizedBox(height: AppSpacing.lg),
              AppPrimaryButton(
                key: const Key('plan-renew-button'),
                label: action,
                icon: Icons.star_rounded,
                onPressed: _openUpgrade,
              ),
            ],
          ],
        );
      },
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.plan});

  final PremiumPlan plan;

  @override
  Widget build(BuildContext context) {
    final until = plan.until;
    final (String title, String body, Color color) = switch (plan.kind) {
      PremiumPlanKind.active => (
        'Premium',
        until == null
            ? 'Active.'
            : 'Active until ${PremiumPlan.formatDate(until)} · '
                '${plan.timeLeft}.',
        AppColors.statusSuccessDark,
      ),
      PremiumPlanKind.endingSoon => (
        'Premium · ending soon',
        'Ends ${PremiumPlan.formatDate(until!)} · ${plan.timeLeft}. Renew '
            'now to keep Premium without a gap.',
        AppColors.statusWarningDark,
      ),
      PremiumPlanKind.ended => (
        'Free plan',
        'Premium ended on ${PremiumPlan.formatDate(until!)}. Every child '
            'profile and all progress are kept; Premium features are locked '
            'until you renew.',
        AppColors.statusWarningDark,
      ),
      PremiumPlanKind.free => (
        'Free plan',
        'Premium adds the advanced dashboard, the interactive therapy '
            'locator and fresh AI recommendations.',
        AppColors.textSecondary,
      ),
      PremiumPlanKind.unlocked => (
        'Everything unlocked',
        'This edition includes every Premium feature. Nothing to pay.',
        AppColors.statusSuccessDark,
      ),
      PremiumPlanKind.simulated => (
        'Premium (simulated)',
        'Unlocked by a simulated payment. It ends when the app closes and '
            'nothing was charged.',
        AppColors.statusWarningDark,
      ),
      PremiumPlanKind.developer => (
        'Premium (developer override)',
        'Forced on from the developer tools. Your real plan is unchanged.',
        AppColors.statusWarningDark,
      ),
    };
    return AppCard(
      key: const Key('plan-status-card'),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.workspace_premium_rounded, color: color, size: 36),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.titleLarge.copyWith(
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.textSecondary, size: 26),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.titleMedium.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
