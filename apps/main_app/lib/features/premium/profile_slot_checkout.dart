import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/entitlement_service.dart';
import 'checkout_webview_screen.dart';
import 'web_checkout_return.dart';

/// How buying one extra child profile ended (AUM-349).
enum ProfileSlotPurchase {
  /// Paid, and the backend has added the slot: the child can be added now.
  added,

  /// Paid, but the slot has not reached the backend yet.
  pending,

  /// The parent closed or cancelled the checkout; nothing was charged.
  cancelled,

  /// Web: the browser has left for PayMongo in this tab. The app reloads on
  /// return and [WebCheckoutReturnBanner] reports the result.
  redirected,

  /// The backend refused: extra profiles need active Premium.
  premiumRequired,

  /// The checkout could not be started.
  failed,
}

/// Buys one extra child profile through PayMongo, given how many purchased
/// slots the account has now. Injectable so screens can be tested without a
/// backend.
typedef ProfileSlotCheckout =
    Future<ProfileSlotPurchase> Function(
      BuildContext context, {
      required int slotsBefore,
    });

/// The real purchase: `create-checkout` with `product: profile_slot`, then
/// PayMongo's page — in the in-app WebView on Android/iOS, or in this browser
/// tab on the web — and, on a device, waiting for the signed webhook to add
/// the slot. The success redirect alone never adds anything.
Future<ProfileSlotPurchase> buyProfileSlotWithPaymongo(
  BuildContext context, {
  required int slotsBefore,
}) async {
  final String checkoutUrl;
  try {
    final response = await Supabase.instance.client.functions.invoke(
      'create-checkout',
      body: {
        'product': 'profile_slot',
        if (kIsWeb) 'return_url': WebCheckoutReturn.returnUrl,
      },
    );
    final url = (response.data as Map<String, dynamic>?)?['checkout_url'];
    if (url is! String) return ProfileSlotPurchase.failed;
    checkoutUrl = url;
  } on FunctionException catch (e) {
    debugPrint('[ProfileSlot] checkout failed: $e');
    return e.status == 403
        ? ProfileSlotPurchase.premiumRequired
        : ProfileSlotPurchase.failed;
  } catch (e) {
    debugPrint('[ProfileSlot] checkout failed: $e');
    return ProfileSlotPurchase.failed;
  }

  if (kIsWeb) {
    await WebCheckoutReturn.markStarted(
      product: 'profile_slot',
      slotsBefore: slotsBefore,
    );
    await launchUrl(Uri.parse(checkoutUrl), webOnlyWindowName: '_self');
    return ProfileSlotPurchase.redirected;
  }

  if (!context.mounted) return ProfileSlotPurchase.cancelled;
  final paid =
      await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => CheckoutWebViewScreen(checkoutUrl: checkoutUrl),
        ),
      ) ??
      false;
  if (!paid) return ProfileSlotPurchase.cancelled;
  if (!context.mounted) return ProfileSlotPurchase.pending;

  // Keep the parent informed while the webhook lands.
  final navigator = Navigator.of(context);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder:
        (_) => const AlertDialog(
          key: Key('adding-profile-slot'),
          content: Row(
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              SizedBox(width: 16),
              Expanded(child: Text('Adding your extra profile…')),
            ],
          ),
        ),
  );
  final added = await EntitlementService.instance.waitForProfileSlot(
    above: slotsBefore,
  );
  navigator.pop();
  return added ? ProfileSlotPurchase.added : ProfileSlotPurchase.pending;
}
