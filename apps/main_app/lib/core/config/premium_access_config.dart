/// Compile-time product edition settings for Premium feature access.
///
/// Normal builds keep Premium tied to the backend entitlement. A deliberately
/// prepared free-distribution build can pass
/// `--dart-define=UNLOCK_PREMIUM_FEATURES=true` to make every existing Premium
/// gate available without enabling the developer toolbox.
class PremiumAccessConfig {
  const PremiumAccessConfig._();

  static const bool unlockedForEveryone = bool.fromEnvironment(
    'UNLOCK_PREMIUM_FEATURES',
    defaultValue: false,
  );
}
