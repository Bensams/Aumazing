import 'package:aumazing/core/config/premium_access_config.dart';
import 'package:aumazing/dev/developer_tools_config.dart';
import 'package:aumazing/services/entitlement_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const expectedUnlocked = bool.fromEnvironment(
    'EXPECT_PREMIUM_UNLOCKED',
    defaultValue: false,
  );

  test('compile-time product edition controls effective Premium access', () {
    expect(PremiumAccessConfig.unlockedForEveryone, expectedUnlocked);
    expect(EntitlementService.instance.isPremium, expectedUnlocked);
    expect(EntitlementService.instance.isRealPremium, isFalse);
    expect(DeveloperToolsConfig.enabled, isFalse);
    expect(DeveloperToolsConfig.isAvailable, isFalse);
  });
}
