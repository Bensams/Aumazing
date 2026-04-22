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
  static const invalidChildAgeMessage =
      'Aumazing currently supports children ages 2 to 6.';

  final AuthService _authService;
  final ConnectivityService _connectivityService;
  final SupabaseService _supabaseService;
  final LocalDbService _localDbService;

  Future<BootstrapResult> bootstrap() async {
    if (_connectivityService.isOnline && _authService.isLoggedIn) {
      await _authService.refreshSession();
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

    final child = children.first;
    final validation = validateBirthDate(child.birthDate);
    if (validation != ChildBirthDateValidation.valid) {
      return const BootstrapResult(
        destination: BootstrapDestination.childProfileSetup,
        errorMessage: invalidChildAgeMessage,
      );
    }

    return const BootstrapResult(destination: BootstrapDestination.home);
  }

  Future<void> _hydrateChildrenFromSupabase(String userId) async {
    final remoteChildren = await _supabaseService.getChildren(userId);

    for (final remote in remoteChildren) {
      await _localDbService.upsertChild(
        ChildProfile.fromSupabase(remote),
        ownerId: userId,
        markPending: false,
      );
    }
  }
}
