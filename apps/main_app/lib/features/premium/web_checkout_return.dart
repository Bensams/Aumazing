import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/web/browser_url.dart';
import '../../services/entitlement_service.dart';
import 'premium_plan.dart';

/// The web app's side of a Premium checkout.
///
/// On Android/iOS checkout runs in an in-app WebView. In the browser the
/// parent leaves for PayMongo in the same tab (a new tab opened after a
/// network wait is blocked as a pop-up by mobile Safari), and PayMongo sends
/// them back to the app's own address with `?payment=success` or
/// `?payment=cancelled`. The app reads that once at start-up, removes it from
/// the address bar, and [WebCheckoutReturnBanner] finishes the purchase —
/// Premium, or an extra child profile (AUM-349).
class WebCheckoutReturn {
  WebCheckoutReturn._();

  static const _startedKey = 'web_checkout_started_at';
  static const _productKey = 'web_checkout_product';
  static const _slotsBeforeKey = 'web_checkout_slots_before';
  static const _untilBeforeKey = 'web_checkout_premium_until_before';

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

  /// Remembers that this browser just left for checkout, what for, and — for
  /// an extra profile — how many purchased slots the account had before, or
  /// — for a Premium renewal (AUM-169) — when the running period ended.
  static Future<void> markStarted({
    String product = 'premium',
    int slotsBefore = 0,
    DateTime? premiumUntilBefore,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_startedKey, DateTime.now().millisecondsSinceEpoch);
    await prefs.setString(_productKey, product);
    await prefs.setInt(_slotsBeforeKey, slotsBefore);
    if (premiumUntilBefore == null) {
      await prefs.remove(_untilBeforeKey);
    } else {
      await prefs.setString(
        _untilBeforeKey,
        premiumUntilBefore.toUtc().toIso8601String(),
      );
    }
  }

  /// The checkout return to report, once, or null. Only a return to a
  /// checkout this browser started counts, so an old link with
  /// `?payment=success` shows nothing.
  static Future<CheckoutReturn?> takeOutcome({DateTime? now}) async {
    final outcome = _outcome;
    _outcome = null;
    if (outcome != 'success' && outcome != 'cancelled') return null;
    final prefs = await SharedPreferences.getInstance();
    final started = prefs.getInt(_startedKey);
    final product = prefs.getString(_productKey) ?? 'premium';
    final slotsBefore = prefs.getInt(_slotsBeforeKey) ?? 0;
    final untilBefore = DateTime.tryParse(
      prefs.getString(_untilBeforeKey) ?? '',
    );
    await prefs.remove(_startedKey);
    await prefs.remove(_productKey);
    await prefs.remove(_slotsBeforeKey);
    await prefs.remove(_untilBeforeKey);
    if (started == null) return null;
    final age = (now ?? DateTime.now()).difference(
      DateTime.fromMillisecondsSinceEpoch(started),
    );
    if (age.isNegative || age > _window) return null;
    return CheckoutReturn(
      paid: outcome == 'success',
      profileSlot: product == 'profile_slot',
      slotsBefore: slotsBefore,
      premiumUntilBefore: untilBefore,
    );
  }

  @visibleForTesting
  static set debugOutcome(String? value) => _outcome = value;
}

/// How a web checkout this browser started came back.
class CheckoutReturn {
  const CheckoutReturn({
    required this.paid,
    required this.profileSlot,
    this.slotsBefore = 0,
    this.premiumUntilBefore,
  });

  /// True for `?payment=success`, false for `?payment=cancelled`.
  final bool paid;

  /// True for an extra child profile, false for Premium.
  final bool profileSlot;

  /// Purchased slots before this checkout, for an extra profile.
  final int slotsBefore;

  /// When running Premium was due to end, for a renewal; null for a first
  /// purchase.
  final DateTime? premiumUntilBefore;
}

enum _ReturnState {
  none,
  activating,
  active,
  renewed,
  pending,
  slotAdding,
  slotAdded,
  slotPending,
  cancelled,
}

/// Shows, over whatever screen the app opens on, how a web checkout ended.
/// A pass-through everywhere else.
class WebCheckoutReturnBanner extends StatefulWidget {
  const WebCheckoutReturnBanner({
    super.key,
    required this.child,
    this.waitForActivation,
    this.waitForProfileSlot,
  });

  final Widget child;

  /// Test seam; defaults to [EntitlementService.waitForActivation].
  final Future<bool> Function(DateTime? extendedPast)? waitForActivation;

  /// Test seam; defaults to [EntitlementService.waitForProfileSlot].
  final Future<bool> Function(int above)? waitForProfileSlot;

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
    final result = await WebCheckoutReturn.takeOutcome();
    if (!mounted || result == null) return;
    if (!result.paid) {
      setState(() => _state = _ReturnState.cancelled);
      _autoHide = Timer(const Duration(seconds: 8), _dismiss);
      return;
    }
    if (result.profileSlot) {
      setState(() => _state = _ReturnState.slotAdding);
      final added = await (widget.waitForProfileSlot ??
          (above) => EntitlementService.instance.waitForProfileSlot(
            above: above,
          ))(result.slotsBefore);
      if (!mounted) return;
      setState(
        () => _state = added ? _ReturnState.slotAdded : _ReturnState.slotPending,
      );
      return;
    }
    setState(() => _state = _ReturnState.activating);
    // The payment webhook usually lands before PayMongo redirects back, but
    // give it a minute before saying it is still on its way.
    final renewal = result.premiumUntilBefore;
    final active = await (widget.waitForActivation ??
        (extendedPast) => EntitlementService.instance.waitForActivation(
          extendedPast: extendedPast,
          timeout: const Duration(seconds: 60),
        ))(renewal);
    if (!mounted) return;
    setState(
      () => _state = !active
          ? _ReturnState.pending
          : renewal != null
          ? _ReturnState.renewed
          : _ReturnState.active,
    );
  }

  String _renewedBody() {
    final until = EntitlementService.instance.premiumUntil;
    return until == null
        ? '30 more days were added to your Premium.'
        : '30 more days were added. Premium now runs until '
            '${PremiumPlan.formatDate(until)}.';
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
      _ReturnState.renewed => (
        Icons.workspace_premium_rounded,
        'Premium renewed 🎉',
        _renewedBody(),
      ),
      _ReturnState.pending => (
        Icons.hourglass_top_rounded,
        'Payment received',
        'Activation is taking a moment. Premium turns on by itself once '
            'PayMongo confirms — you can keep using the app.',
      ),
      _ReturnState.slotAdding => (
        null,
        'Adding your extra profile…',
        'Confirming your payment with PayMongo.',
      ),
      _ReturnState.slotAdded => (
        Icons.person_add_alt_1_rounded,
        'Extra child profile added 🎉',
        'Open Manage Children and tap Add child to set it up.',
      ),
      _ReturnState.slotPending => (
        Icons.hourglass_top_rounded,
        'Payment received',
        'The extra profile appears by itself once PayMongo confirms — you '
            'can keep using the app.',
      ),
      _ReturnState.cancelled => (
        Icons.info_outline_rounded,
        'Payment cancelled',
        'Nothing was charged. You can try again any time.',
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
                          if (_state != _ReturnState.activating &&
                              _state != _ReturnState.slotAdding)
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
