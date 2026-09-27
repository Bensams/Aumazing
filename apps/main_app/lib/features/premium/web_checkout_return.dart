import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/web/browser_url.dart';
import '../../services/entitlement_service.dart';

/// The web app's side of a Premium checkout.
///
/// On Android/iOS checkout runs in an in-app WebView. In the browser the
/// parent leaves for PayMongo in the same tab (a new tab opened after a
/// network wait is blocked as a pop-up by mobile Safari), and PayMongo sends
/// them back to the app's own address with `?payment=success` or
/// `?payment=cancelled`. The app reads that once at start-up, removes it from
/// the address bar, and [WebCheckoutReturnBanner] finishes the upgrade.
class WebCheckoutReturn {
  WebCheckoutReturn._();

  static const _startedKey = 'web_checkout_started_at';

  /// How long after leaving for checkout a return still counts as ours.
  static const _window = Duration(hours: 2);

  static String? _outcome;

  /// Where PayMongo should bring the parent back to: this app's address
  /// without any query or fragment.
  static String get returnUrl => '${Uri.base.origin}${Uri.base.path}';

  /// Reads `?payment=` from the address the app was opened at, then removes
  /// it so a reload or a bookmark does not repeat it. Call once, early.
  static void captureFromUrl() {
    if (!kIsWeb) return;
    final params = Uri.base.queryParameters;
    final outcome = params['payment'];
    if (outcome == null) return;
    _outcome = outcome;
    final rest = Map.of(params)..remove('payment');
    replaceBrowserUrl(
      Uri.base.replace(queryParameters: rest.isEmpty ? null : rest).toString(),
    );
  }

  /// Remembers that this browser just left for checkout.
  static Future<void> markStarted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_startedKey, DateTime.now().millisecondsSinceEpoch);
  }

  /// The checkout outcome to report, once: `success`, `cancelled`, or null.
  /// Only a return to a checkout this browser started counts, so an old link
  /// with `?payment=success` shows nothing.
  static Future<String?> takeOutcome({DateTime? now}) async {
    final outcome = _outcome;
    _outcome = null;
    if (outcome != 'success' && outcome != 'cancelled') return null;
    final prefs = await SharedPreferences.getInstance();
    final started = prefs.getInt(_startedKey);
    await prefs.remove(_startedKey);
    if (started == null) return null;
    final age = (now ?? DateTime.now()).difference(
      DateTime.fromMillisecondsSinceEpoch(started),
    );
    return age.isNegative || age > _window ? null : outcome;
  }

  @visibleForTesting
  static set debugOutcome(String? value) => _outcome = value;
}

enum _ReturnState { none, activating, active, pending, cancelled }

/// Shows, over whatever screen the app opens on, how a web checkout ended.
/// A pass-through everywhere else.
class WebCheckoutReturnBanner extends StatefulWidget {
  const WebCheckoutReturnBanner({
    super.key,
    required this.child,
    this.waitForActivation,
  });

  final Widget child;

  /// Test seam; defaults to [EntitlementService.waitForActivation].
  final Future<bool> Function()? waitForActivation;

  @override
  State<WebCheckoutReturnBanner> createState() =>
      _WebCheckoutReturnBannerState();
}

class _WebCheckoutReturnBannerState extends State<WebCheckoutReturnBanner> {
  var _state = _ReturnState.none;
  Timer? _autoHide;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final outcome = await WebCheckoutReturn.takeOutcome();
    if (!mounted || outcome == null) return;
    if (outcome == 'cancelled') {
      setState(() => _state = _ReturnState.cancelled);
      _autoHide = Timer(const Duration(seconds: 8), _dismiss);
      return;
    }
    setState(() => _state = _ReturnState.activating);
    // The payment webhook usually lands before PayMongo redirects back, but
    // give it a minute before saying it is still on its way.
    final active = await (widget.waitForActivation ??
        () => EntitlementService.instance.waitForActivation(
          timeout: const Duration(seconds: 60),
        ))();
    if (!mounted) return;
    setState(() => _state = active ? _ReturnState.active : _ReturnState.pending);
  }

  void _dismiss() {
    if (mounted) setState(() => _state = _ReturnState.none);
  }

  @override
  void dispose() {
    _autoHide?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_state == _ReturnState.none) return widget.child;
    final (icon, title, body) = switch (_state) {
      _ReturnState.activating => (
        null,
        'Finishing your upgrade…',
        'Confirming your payment with PayMongo.',
      ),
      _ReturnState.active => (
        Icons.workspace_premium_rounded,
        'Welcome to Premium! 🎉',
        'Advanced analytics and the interactive therapy locator are now '
            'unlocked.',
      ),
      _ReturnState.pending => (
        Icons.hourglass_top_rounded,
        'Payment received',
        'Activation is taking a moment. Premium turns on by itself once '
            'PayMongo confirms — you can keep using the app.',
      ),
      _ReturnState.cancelled => (
        Icons.info_outline_rounded,
        'Payment cancelled',
        'Nothing was charged. You can upgrade any time from Premium.',
      ),
      _ReturnState.none => (null, '', ''),
    };
    return Stack(
      children: [
        widget.child,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Material(
                    key: const Key('web-checkout-return-banner'),
                    elevation: 6,
                    borderRadius: BorderRadius.circular(18),
                    color: Colors.white,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 28,
                            height: 28,
                            child: icon == null
                                ? const Padding(
                                    padding: EdgeInsets.all(4),
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                    ),
                                  )
                                : Icon(icon, color: const Color(0xFF3AA88F)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  title,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(body),
                              ],
                            ),
                          ),
                          if (_state != _ReturnState.activating)
                            IconButton(
                              tooltip: 'Close',
                              icon: const Icon(Icons.close_rounded),
                              onPressed: _dismiss,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
