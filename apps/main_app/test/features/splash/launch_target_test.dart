import 'package:aumazing/core/services/child_bootstrap_service.dart';
import 'package:aumazing/features/splash/loading_screen.dart';
import 'package:flutter_test/flutter_test.dart';

/// Launch routing (AUM-306): a returning authenticated user opens in child
/// mode, while onboarding, first login, and the protected parent base are
/// preserved. [resolveLaunchTarget] is the single decision point, so these
/// cases stand in for the session and account edges the card calls out.
void main() {
  AppLaunchTarget resolve({
    required BootstrapDestination destination,
    bool sessionExpired = false,
    bool hasConsent = true,
    bool hasSeenParentTour = true,
  }) => resolveLaunchTarget(
    destination: destination,
    sessionExpired: sessionExpired,
    hasConsent: hasConsent,
    hasSeenParentTour: hasSeenParentTour,
  );

  group('returning authenticated users', () {
    test('a restored session with a usable child opens in child mode', () {
      expect(
        resolve(destination: BootstrapDestination.home),
        AppLaunchTarget.childMode,
      );
    });

    test('an app restart lands the returning parent in child mode', () {
      // Identical inputs to a cold restore: the decision is stateless, so a
      // restart cannot accidentally reopen the parent dashboard.
      expect(
        resolve(destination: BootstrapDestination.home),
        AppLaunchTarget.childMode,
      );
    });

    test(
      'a logout/login of an already-onboarded account opens in child mode',
      () {
        // Re-login also resolves to home (a usable child exists) and the tour
        // has been seen, so the returning user still skips the dashboard.
        expect(
          resolve(destination: BootstrapDestination.home),
          AppLaunchTarget.childMode,
        );
      },
    );
  });

  group('onboarding and first login are preserved', () {
    test('a brand-new account with no usable child goes to child setup', () {
      expect(
        resolve(destination: BootstrapDestination.childProfileSetup),
        AppLaunchTarget.childProfileSetup,
      );
    });

    test('the first parent visit (tour unseen) opens the parent dashboard', () {
      // First login before the guided tour has run: the parent must land on
      // the dashboard so onboarding completes, never straight into child mode.
      expect(
        resolve(
          destination: BootstrapDestination.home,
          hasSeenParentTour: false,
        ),
        AppLaunchTarget.parentHome,
      );
    });
  });

  group('sessions fail closed to authentication', () {
    test('an expired session routes to login even when set up', () {
      expect(
        resolve(destination: BootstrapDestination.home, sessionExpired: true),
        AppLaunchTarget.login,
      );
    });

    test('a fresh install without privacy consent routes to login', () {
      expect(
        resolve(
          destination: BootstrapDestination.home,
          hasConsent: false,
          hasSeenParentTour: false,
        ),
        AppLaunchTarget.login,
      );
    });

    test('consent gate wins even for a returning, tour-seen user', () {
      expect(
        resolve(destination: BootstrapDestination.home, hasConsent: false),
        AppLaunchTarget.login,
      );
    });

    test('an unauthenticated bootstrap routes to login', () {
      expect(
        resolve(destination: BootstrapDestination.login),
        AppLaunchTarget.login,
      );
    });
  });
}
