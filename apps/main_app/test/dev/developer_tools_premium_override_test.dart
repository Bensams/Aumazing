import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aumazing/dev/developer_tools_config.dart';
import 'package:aumazing/services/entitlement_service.dart';

/// The Premium override exists so a developer can see the paid experience
/// without paying. It must never become a way for the app to grant itself
/// Premium: the genuine entitlement stays the source of truth underneath, and
/// nothing about the override is written anywhere.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final entitlement = EntitlementService.instance;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DeveloperToolsConfig.debugAvailableOverride = true;
    entitlement.setDeveloperPremiumOverride(false);
    entitlement.debugSetRealPremium(false);
  });

  tearDown(() {
    DeveloperToolsConfig.debugAvailableOverride = true;
    entitlement.setDeveloperPremiumOverride(false);
    entitlement.debugSetRealPremium(false);
    DeveloperToolsConfig.debugAvailableOverride = null;
  });

  test('the override flips effective Premium and notifies listeners', () {
    var notifications = 0;
    void listener() => notifications++;
    entitlement.addListener(listener);
    addTearDown(() => entitlement.removeListener(listener));

    expect(entitlement.isPremium, isFalse);

    entitlement.setDeveloperPremiumOverride(true);

    expect(entitlement.isPremium, isTrue,
        reason: 'every existing isPremium gate must see it');
    expect(entitlement.isDeveloperPremiumOverrideActive, isTrue);
    expect(notifications, 1,
        reason: 'ListenableBuilder gates refresh immediately');
  });

  test('turning it off restores the genuine entitlement', () {
    entitlement.setDeveloperPremiumOverride(true);
    expect(entitlement.isPremium, isTrue);

    entitlement.setDeveloperPremiumOverride(false);

    expect(entitlement.isPremium, isFalse);
    expect(entitlement.isRealPremium, isFalse);

    // …and with a genuinely subscribed account, dropping the override leaves
    // the real entitlement intact rather than clearing it.
    entitlement.debugSetRealPremium(true);
    entitlement.setDeveloperPremiumOverride(true);
    entitlement.setDeveloperPremiumOverride(false);
    expect(entitlement.isPremium, isTrue);
    expect(entitlement.isRealPremium, isTrue);
  });

  test('the override never touches the genuine cached value or storage',
      () async {
    entitlement.setDeveloperPremiumOverride(true);

    expect(entitlement.isRealPremium, isFalse,
        reason: 'the real entitlement is not overwritten');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), isEmpty,
        reason: 'nothing is cached, so it cannot survive a restart');
  });

  test('a backend refresh does not cancel an active override', () {
    entitlement.setDeveloperPremiumOverride(true);

    // What refresh() does when the backend says "not premium".
    entitlement.debugSetRealPremium(false);

    expect(entitlement.isDeveloperPremiumOverrideActive, isTrue);
    expect(entitlement.isPremium, isTrue);

    // And when the backend says "premium", the override is still what the
    // toolbox reports as its own doing.
    entitlement.debugSetRealPremium(true);
    expect(entitlement.isRealPremium, isTrue);
    expect(entitlement.isDeveloperPremiumOverrideActive, isTrue);
  });

  test('the override cannot activate when the toolbox is unavailable', () {
    DeveloperToolsConfig.debugAvailableOverride = false;
    var notifications = 0;
    void listener() => notifications++;
    entitlement.addListener(listener);
    addTearDown(() => entitlement.removeListener(listener));

    entitlement.setDeveloperPremiumOverride(true);

    expect(entitlement.isDeveloperPremiumOverrideActive, isFalse);
    expect(entitlement.isPremium, isFalse);
    expect(notifications, 0);
  });
}
