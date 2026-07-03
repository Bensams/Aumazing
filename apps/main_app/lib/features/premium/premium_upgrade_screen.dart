import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:shared_ui/shared_ui.dart';

import '../../providers/child_provider.dart';
import '../../services/entitlement_service.dart';

/// Premium upgrade screen (freemium model, PayMongo sandbox).
///
/// The checkout itself is PayMongo's hosted page rendered in an in-app
/// WebView — the parent never leaves the app, and card data never touches
/// our code. Entitlement is granted server-side by the webhook.
class PremiumUpgradeScreen extends StatefulWidget {
  const PremiumUpgradeScreen({super.key});

  @override
  State<PremiumUpgradeScreen> createState() => _PremiumUpgradeScreenState();
}

class _PremiumUpgradeScreenState extends State<PremiumUpgradeScreen> {
  bool _busy = false;
  String? _error;

  static const _benefits = [
    (Icons.trending_up_rounded, 'Advanced dashboard',
        'Historical skill trends across assessment cycles'),
    (Icons.my_location_rounded, 'Interactive therapy locator',
        'GPS-ranked centers near you with directions'),
    (Icons.auto_awesome_rounded, 'Continuous AI recommendations',
        'Fresh learning paths after every assessment'),
  ];

  Future<void> _startCheckout() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final response = await Supabase.instance.client.functions
          .invoke('create-checkout');
      final data = response.data as Map<String, dynamic>?;
      final checkoutUrl = data?['checkout_url'] as String?;
      if (checkoutUrl == null) {
        throw Exception(data?['error'] ?? 'no checkout url');
      }
      if (!mounted) return;

      final paid = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => _CheckoutWebViewScreen(checkoutUrl: checkoutUrl),
        ),
      );
      if (!mounted) return;

      if (paid == true) {
        setState(() => _busy = true);
        final active = await EntitlementService.instance.waitForActivation();
        if (!mounted) return;
        if (active) {
          await showDialog<void>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Welcome to Premium! 🎉'),
              content: const Text(
                  'Advanced analytics and the interactive therapy locator '
                  'are now unlocked.'),
              actions: [
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Great!'),
                ),
              ],
            ),
          );
          if (mounted) Navigator.of(context).pop();
          return;
        }
        setState(() => _error =
            'Payment received — activation is taking a moment. '
            'Pull to refresh the dashboard shortly.');
      }
    } catch (e) {
      setState(() => _error = 'Could not start checkout. Please try again.');
      debugPrint('[Premium] checkout failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.watch<ChildProvider>().activePalette;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: palette.parentBackground),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Material(
                          color: AppColors.white.withValues(alpha: 0.85),
                          shape: const CircleBorder(),
                          child: IconButton(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: Icon(Icons.arrow_back_rounded,
                                color: palette.primary),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    const Text('⭐', style: TextStyle(fontSize: 48),
                        textAlign: TextAlign.center),
                    Text(
                      'Aumazing Premium',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.headlineLarge
                          .copyWith(color: palette.primary),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '₱149 / month',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.titleLarge
                          .copyWith(color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    for (final (icon, title, subtitle) in _benefits)
                      Padding(
                        padding:
                            const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: AppCard(
                          child: Row(
                            children: [
                              Icon(icon,
                                  color: palette.primary, size: 28),
                              const SizedBox(width: AppSpacing.md),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(title,
                                        style: AppTextStyles.titleMedium
                                            .copyWith(
                                                color:
                                                    AppColors.textPrimary)),
                                    Text(subtitle,
                                        style: AppTextStyles.bodySmall
                                            .copyWith(
                                                color: AppColors
                                                    .mutedForeground)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (_error != null) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(_error!,
                          textAlign: TextAlign.center,
                          style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.statusWarningDark)),
                    ],
                    const SizedBox(height: AppSpacing.md),
                    AppPrimaryButton(
                      label: 'Upgrade with PayMongo',
                      icon: Icons.lock_rounded,
                      isLoading: _busy,
                      onPressed: _busy ? null : _startCheckout,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Sandbox build: use PayMongo test cards — no real '
                      'charges.',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodySmall
                          .copyWith(color: AppColors.mutedForeground),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// PayMongo's hosted checkout rendered inside the app. Watches navigation
/// for the success/cancel sentinel URLs and pops with the outcome.
class _CheckoutWebViewScreen extends StatefulWidget {
  const _CheckoutWebViewScreen({required this.checkoutUrl});

  final String checkoutUrl;

  @override
  State<_CheckoutWebViewScreen> createState() =>
      _CheckoutWebViewScreenState();
}

class _CheckoutWebViewScreenState extends State<_CheckoutWebViewScreen> {
  late final WebViewController _controller;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onNavigationRequest: (request) {
            if (request.url.startsWith('https://aumazing.app/payment/success')) {
              Navigator.of(context).pop(true);
              return NavigationDecision.prevent;
            }
            if (request.url.startsWith('https://aumazing.app/payment/cancel')) {
              Navigator.of(context).pop(false);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.checkoutUrl));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Secure Checkout'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading) const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
