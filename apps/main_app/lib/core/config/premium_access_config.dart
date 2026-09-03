import 'package:flutter/foundation.dart' show kIsWeb;

/// Compile-time product edition settings for Premium feature access.
///
/// Normal (mobile) builds keep Premium tied to the backend entitlement. A
/// deliberately prepared free-distribution build can pass
/// `--dart-define=UNLOCK_PREMIUM_FEATURES=true` to make every existing Premium
/// gate available without enabling the developer toolbox.
///
/// The **web build is the public demo**, so Premium is unlocked for everyone
/// there ([kIsWeb]) — visitors can try the Premium-gated features without a
/// purchase. This does not affect the Android/iOS builds, which stay gated.
class PremiumAccessConfig {
  const PremiumAccessConfig._();

  static const bool unlockedForEveryone = kIsWeb ||
      bool.fromEnvironment(
        'UNLOCK_PREMIUM_FEATURES',
        defaultValue: false,
      );
}
