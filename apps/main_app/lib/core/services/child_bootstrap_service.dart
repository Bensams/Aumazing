import '../child_profile_policy.dart';
import '../../model/child_profile.dart';
import 'auth_service.dart';
import 'connectivity_service.dart';
import 'local_db_service.dart';
import 'supabase_service.dart';

enum BootstrapDestination { login, childProfileSetup, home }

class BootstrapResult {
  const BootstrapResult({
    required this.destination,
    this.errorMessage,
  });

  final BootstrapDestination destination;
  final String? errorMessage;
}

class ChildBootstrapService {
  ChildBootstrapService({
    required AuthService authService,
    required ConnectivityService connectivityService,
    required SupabaseService supabaseService,
    required LocalDbService localDbService,
  }) : _authService = authService,
       _connectivityService = connectivityService,
       _supabaseService = supabaseService,
       _localDbService = localDbService;

  static const missingChildProfileMessage =
      'Please complete Initial Child Info.';

  final AuthService _authService;
  final ConnectivityService _connectivityService;
  final SupabaseService _supabaseService;
  final LocalDbService _localDbService;

  Future<BootstrapResult> bootstrap() async {
    if (_connectivityService.isOnline && _authService.isLoggedIn) {
      await _authService.refreshSession();
    }

    // Require either a real authenticated session (email/social/anonymous), or
    // an established offline guest — one the user explicitly chose via
    // "Continue as Guest", persisted across restarts. The startup auto-guest
    // (a local id minted for offline storage, before any choice was made) is
    // NOT a valid session: those users go to login on every fresh open / new
    // install, instead of being dropped into child setup.
    final isEstablishedGuest = await _authService.isGuestEstablished();
    if (!_authService.isLoggedIn && !isEstablishedGuest) {
      return const BootstrapResult(destination: BootstrapDestination.login);
    }

    final userId = _authService.effectiveUserId;
    if (userId == null) {
      return const BootstrapResult(destination: BootstrapDestination.login);
    }

    if (_connectivityService.isOnline && _authService.isLoggedIn) {
      await _hydrateChildrenFromSupabase(userId);
    }

    final children = await _localDbService.getChildren(userId: userId);
    if (children.isEmpty) {
      return const BootstrapResult(
        destination: BootstrapDestination.childProfileSetup,
        errorMessage: missingChildProfileMessage,
      );
    }

    // Only an actually-unusable birth date (missing or in the future) sends the
    // parent back to setup. Ages outside 2–6 are accepted here to stay
    // consistent with the child-setup screen, which no longer enforces a range.
    //
    // With several children, one usable profile is enough to reach the
    // dashboard — ChildProvider picks the active child, and a legacy record
    // among newer ones must not block the whole account.
    final hasUsableChild = children.any((child) {
      final validation = validateBirthDate(child.birthDate);
      return validation != ChildBirthDateValidation.missing &&
          validation != ChildBirthDateValidation.futureDate;
    });
    if (!hasUsableChild) {
      return const BootstrapResult(
        destination: BootstrapDestination.childProfileSetup,
        errorMessage: missingChildProfileMessage,
      );
    }

    return const BootstrapResult(destination: BootstrapDestination.home);
  }

  Future<void> _hydrateChildrenFromSupabase(String userId) async {
    final remoteChildren = await _supabaseService.getChildren(userId);
    // A child the parent deleted locally is still present in the cloud until
    // the deletion syncs. Neither those rows nor already-deleted remote rows
    // may be written back, or hydration would undo the deletion.
    final locallyDeleted = await _localDbService.getLocallyDeletedChildIds();

    for (final remote in remoteChildren) {
      if (remote['deleted_at'] != null) continue;
      if (locallyDeleted.contains(remote['id'])) continue;
      // Newer-wins, not blind replace: this runs on every online launch, so
      // writing the cloud copy over the local one unconditionally destroyed
      // any change made since the last successful push (AUM-328).
      await _localDbService.hydrateChild(
        ChildProfile.fromSupabase(remote),
        ownerId: userId,
      );
    }
  }
}
