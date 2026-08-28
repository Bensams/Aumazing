import 'package:flutter_test/flutter_test.dart';

import 'package:aumazing/dev/developer_tools_config.dart';
import 'package:aumazing/services/entitlement_service.dart';

/// AUM-168 — client-side entitlement rules.
///
/// The app can never grant itself Premium; these tests pin the two
/// client behaviours that keep that true: only the backend/cache seam controls
/// the genuine value, and the developer override stays separate from it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final service = EntitlementService.instance;

  setUp(() {
    // The override is a no-op unless the developer toolbox is compiled in.
    DeveloperToolsConfig.debugAvailableOverride = true;
  });

  tearDown(() {
    service.setDeveloperPremiumOverride(false);
    service.debugSetRealPremium(false);
    DeveloperToolsConfig.debugAvailableOverride = null;
  });

  group('real entitlement', () {
    test('a backend-confirmed grant unlocks Premium', () {
      service.debugSetRealPremium(true);
      expect(service.isPremium, isTrue);
      expect(service.isRealPremium, isTrue);
    });

    test('a revoked entitlement stays Free', () {
      service.debugSetRealPremium(false);
      expect(service.isPremium, isFalse);
    });
  });

  group('developer override', () {
    test('forces Premium without touching the genuine entitlement', () {
      service.debugSetRealPremium(false);
      service.setDeveloperPremiumOverride(true);

      expect(service.isPremium, isTrue);
      expect(service.isRealPremium, isFalse,
          reason: 'the real entitlement must keep flowing underneath');
      expect(service.isDeveloperPremiumOverrideActive, isTrue);
    });

    test('turning the override off restores the real entitlement', () {
      service.debugSetRealPremium(true);
      service.setDeveloperPremiumOverride(true);
      service.setDeveloperPremiumOverride(false);

      expect(service.isPremium, isTrue);
      expect(service.isDeveloperPremiumOverrideActive, isFalse);
    });

    test('turning override off restores a revoked real entitlement', () {
      service.debugSetRealPremium(false);
      service.setDeveloperPremiumOverride(true);
      expect(service.isPremium, isTrue);

      service.setDeveloperPremiumOverride(false);
      expect(service.isPremium, isFalse);
    });
  });

  group('notifications', () {
    test('listeners are told when the entitlement changes', () {
      var notifications = 0;
      void listener() => notifications++;
      service.addListener(listener);

      service.debugSetRealPremium(true);
      service.setDeveloperPremiumOverride(true);

      service.removeListener(listener);
      expect(notifications, greaterThanOrEqualTo(2));
    });
  });
}
