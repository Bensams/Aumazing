/// Offline-First Integration for Aumazing
///
/// This file demonstrates how to integrate the offline-first system into the app.
/// Copy this pattern into your main.dart and use throughout the app.
///
/// ## Quick Start
///
/// ```dart
/// // In main.dart, initialize services:
/// await OfflineFirstIntegration.initialize();
///
/// // Use repositories for all data operations:
/// final child = await childRepository.createChild(...);
/// final session = await assessmentRepository.recordGameSession(...);
/// ```
///
/// ## Key Principles
///
/// 1. **Always write local first** - Repositories automatically save to SQLite
/// 2. **Sync happens automatically** - When online, data syncs to Supabase
/// 3. **Guest mode works seamlessly** - Create data before login, backfills later
/// 4. **Same IDs everywhere** - UUIDs are generated locally, used in both local and cloud
///
library;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/research_consent_service.dart';
import 'repositories/child_repository.dart';
import 'repositories/assessment_repository.dart';
import 'services/auth_service.dart';
import 'services/connectivity_service.dart';
import 'services/sync_service.dart';

export 'repositories/child_repository.dart';
export 'repositories/assessment_repository.dart';
export 'services/auth_service.dart';
export 'services/connectivity_service.dart';
export 'services/local_db_service.dart';
export 'services/sync_service.dart';
export 'sync/sync_status.dart';

/// Central integration class for offline-first initialization
class OfflineFirstIntegration {
  static bool _initialized = false;

  /// Initialize all offline-first services
  ///
  /// Call this after Supabase.initialize() in main.dart
  static Future<void> initialize() async {
    if (_initialized) return;

    debugPrint('[OfflineFirst] Initializing offline-first services...');

    // 1. Restore (or create) a persistent local guest id so offline guest
    //    usage survives restarts without any network call.
    final auth = AuthService();
    await auth.restoreOrCreateGuest();

    // 2. Initialize connectivity monitoring
    await connectivityService.initialize();

    // 2b. Pause Supabase's token auto-refresh while offline. Without this it
    //     retries every few seconds against an unreachable host, throwing an
    //     unhandled AuthRetryableFetchException each time (log spam + battery).
    _applyAutoRefreshPolicy(connectivityService.isOnline);
    connectivityService.onConnectivityChanged.listen(_applyAutoRefreshPolicy);

    // 3. Initialize sync service (listens for connectivity changes)
    await syncService.initialize();

    // 3b. Research consent bypasses the sync engine (SharedPreferences +
    //     direct upsert), so flush its pending pushes on reconnect too.
    connectivityService.onConnectivityChanged.listen((online) {
      if (online) ResearchConsentService.instance.retryPendingPushes();
    });

    // 4. Listen for auth changes to trigger backfill and sync
    Supabase.instance.client.auth.onAuthStateChange.listen((state) {
      _onAuthStateChanged(state, auth);
    });

    _initialized = true;
    debugPrint('[OfflineFirst] Initialization complete');
  }

  /// Start/stop Supabase's session auto-refresh to match connectivity.
  static void _applyAutoRefreshPolicy(bool online) {
    final client = Supabase.instance.client;
    if (online) {
      client.auth.startAutoRefresh();
      debugPrint('[OfflineFirst] Online — auth auto-refresh resumed');
    } else {
      client.auth.stopAutoRefresh();
      debugPrint('[OfflineFirst] Offline — auth auto-refresh paused');
    }
  }

  /// Handle authentication state changes
  static void _onAuthStateChanged(AuthState state, AuthService auth) {
    switch (state.event) {
      case AuthChangeEvent.signedIn:
        final userId = state.session?.user.id;
        if (userId != null) {
          debugPrint('[OfflineFirst] User signed in: $userId');

          // 1. Backfill guest data if needed
          if (auth.isGuestMode) {
            final guestId = auth.currentGuestId;
            if (guestId != null) {
              syncService.onUserAuthenticated(userId);
            }
          }

          // 2. Clear guest mode
          auth.clearGuestMode();

          // 3. Hydrate from the cloud first (reinstall / second device —
          //    no-op after the first run per user), then push pending data
          syncService
              .hydrateFromCloud()
              .whenComplete(() => syncService.syncNow());

          // 4. Refresh reference cache
          syncService.refreshReferenceCache();
        }
        break;

      case AuthChangeEvent.signedOut:
        debugPrint('[OfflineFirst] User signed out');
        // Re-initialize guest mode for continued offline usage
        auth.initializeGuestMode();
        break;

      case AuthChangeEvent.userUpdated:
        // User metadata updated, may need to sync
        syncService.syncNow();
        break;

      default:
        break;
    }
  }

  /// Get sync status for UI display
  static Stream<SyncState> get syncStateStream => syncService.onSyncStateChanged;

  /// Check if currently online
  static bool get isOnline => connectivityService.isOnline;

  /// Check if currently in guest mode
  static bool get isGuestMode {
    final auth = AuthService();
    return auth.isGuestMode;
  }

  /// Get current user ID (authenticated or guest)
  static String? get currentUserId {
    final auth = AuthService();
    return auth.effectiveUserId;
  }

  /// Force a sync operation (for manual refresh button)
  static Future<void> syncNow() => syncService.syncNow();

  /// Re-pull the signed-in user's data from the cloud (e.g. a manual
  /// "restore my data" action). Never overwrites local records.
  static Future<int> hydrateFromCloud({bool force = false}) =>
      syncService.hydrateFromCloud(force: force);

  /// Get count of pending records
  static Future<Map<String, int>> getPendingCounts() => syncService.getPendingCounts();
}

// ═══════════════════════════════════════════════════════════════════════════
// EXAMPLE USAGE SCENARIOS
// ═══════════════════════════════════════════════════════════════════════════

/// Example: Creating a child profile (works offline or online)
///
/// ```dart
/// class ChildCreationScreen extends StatelessWidget {
///   Future<void> _createChild(
///     String displayName,
///     DateTime birthDate,
///     String avatar,
///   ) async {
///     // This works whether online or offline!
///     final child = await childRepository.createChild(
///       displayName: displayName,
///       birthDate: birthDate,
///       avatar: avatar,
///     );
///
///     // If online, sync happens automatically in background
///     // If offline, data is queued and will sync when connectivity returns
///
///     ScaffoldMessenger.of(context).showSnackBar(
///       SnackBar(content: Text('Created ${child.displayName}')),
///     );
///   }
/// }
/// ```
class ExampleChildCreation {
  Future<void> createChildExample() async {
    // Works completely offline - child is saved locally
    final child = await childRepository.createChild(
      displayName: 'Alex',
      birthDate: DateTime(2021, 4, 20),
      avatar: 'avatar_1',
      musicEnabled: true,
      vibrationEnabled: false,
    );

    debugPrint('Created child: ${child.id}');
    debugPrint('Owner ID: ${child.userId}'); // Will be guest ID if not authenticated

    // Data will automatically sync when:
    // 1. User authenticates (backfills guest data)
    // 2. Connectivity returns (if already authenticated)
  }
}

/// Example: Recording gameplay (offline-first assessment)
///
/// ```dart
/// class GameScreen extends StatelessWidget {
///   Future<void> _onGameComplete(GameResult result) async {
///     // Always saves locally first
///     final session = await assessmentRepository.recordGameSession(
///       childId: result.childId,
///       gameId: 'match_it',
///       context: 'pre_assessment',
///       score: result.score,
///       totalItems: result.totalItems,
///       errorCount: result.errors,
///       totalResponseTimeMs: result.totalTimeMs,
///       startedAt: result.startTime,
///     );
///
///     // UI continues without blocking - sync is background
///   }
/// }
/// ```
class ExampleGameRecording {
  Future<void> recordGameSessionExample(String childId) async {
    // This works during pre-assessment, post-assessment, or practice
    final session = await assessmentRepository.recordGameSession(
      childId: childId,
      gameId: 'match_it',
      context: 'pre_assessment', // or 'post_assessment', 'practice'
      score: 8,
      totalItems: 10,
      errorCount: 2,
      totalResponseTimeMs: 15000,
      startedAt: DateTime.now().subtract(const Duration(minutes: 2)),
    );

    debugPrint('Recorded session: ${session.id}');
    debugPrint('Accuracy: ${session.score}/${session.totalItems}');

    // The session is immediately available locally
    // Sync to cloud happens in background when possible
  }
}

/// Example: Guest mode flow
///
/// ```dart
/// // 1. App starts - user hasn't logged in yet
/// //    (guest mode is auto-initialized)
///
/// // 2. Parent creates child profile offline
/// final child = await childRepository.createChild(...);
/// //    child.userId = "guest_abc123" (temporary)
///
/// // 3. Child plays games, assessments run - all offline
/// final session = await assessmentRepository.recordGameSession(...);
///
/// // 4. Later, parent decides to sign up
/// final auth = AuthService();
/// final response = await auth.signUpWithEmail(
///   email: 'parent@example.com',
///   password: 'secure123',
/// );
///
/// // 5. All guest data is automatically:
/// //    - Backfilled with new user ID
/// //    - Queued for sync to cloud
/// //    - Available immediately (no re-creation needed)
/// ```
class ExampleGuestMode {
  Future<void> demonstrateGuestFlow() async {
    final auth = AuthService();

    // Step 1: App starts, auto-initializes guest mode
    final guestId = auth.initializeGuestMode();
    debugPrint('Guest mode: $guestId');

    // Step 2: Create child while in guest mode
    final child = await childRepository.createChild(
      displayName: 'Sam',
      birthDate: DateTime(2020, 4, 20),
      avatar: 'avatar_2',
    );
    debugPrint('Guest-created child: ${child.userId}'); // guest_xxx

    // Step 3: Play games, record sessions - all works offline
    await assessmentRepository.recordGameSession(
      childId: child.id,
      gameId: 'copy_me',
      context: 'practice',
      score: 5,
      totalItems: 5,
      errorCount: 0,
      totalResponseTimeMs: 8000,
      startedAt: DateTime.now().subtract(const Duration(minutes: 1)),
    );

    // Step 4: User decides to authenticate
    // (in real app, this happens via sign-up screen)
    // After sign-in, data automatically backfills and syncs
  }
}

/// Example: Manual sync trigger with UI feedback
///
/// ```dart
/// class SyncButton extends StatelessWidget {
///   @override
///   Widget build(BuildContext context) {
///     return StreamBuilder<SyncState>(
///       stream: OfflineFirstIntegration.syncStateStream,
///       builder: (context, snapshot) {
///         final state = snapshot.data;
///         final isSyncing = state?.isSyncing ?? false;
///
///         return ElevatedButton.icon(
///           onPressed: isSyncing ? null : () => OfflineFirstIntegration.syncNow(),
///           icon: isSyncing
///             ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
///             : const Icon(Icons.sync),
///           label: Text(isSyncing ? 'Syncing...' : 'Sync Now'),
///         );
///       },
///     );
///   }
/// }
/// ```
class ExampleSyncUI {
  Widget buildSyncButton() {
    return StreamBuilder<SyncState>(
      stream: OfflineFirstIntegration.syncStateStream,
      builder: (context, snapshot) {
        final state = snapshot.data;
        final isSyncing = state?.isSyncing ?? false;
        final hasError = state?.hasError ?? false;

        return Column(
          children: [
            ElevatedButton.icon(
              onPressed: isSyncing ? null : () => OfflineFirstIntegration.syncNow(),
              icon: isSyncing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync),
              label: Text(isSyncing ? 'Syncing...' : 'Sync Now'),
            ),
            if (hasError)
              Text(
                'Sync failed: ${state?.error}',
                style: const TextStyle(color: Colors.red),
              ),
          ],
        );
      },
    );
  }

  Widget buildOfflineIndicator() {
    return StreamBuilder<SyncState>(
      stream: OfflineFirstIntegration.syncStateStream,
      builder: (context, snapshot) {
        final isOffline = snapshot.data?.isOffline ?? false;

        if (!isOffline) return const SizedBox.shrink();

        return Container(
          padding: const EdgeInsets.all(8),
          color: Colors.orange,
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.offline_bolt, color: Colors.white),
              SizedBox(width: 8),
              Text(
                'Offline Mode - Data saved locally',
                style: TextStyle(color: Colors.white),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Example: Checking pending sync status
///
/// Useful for showing "unsynced changes" indicator
class ExamplePendingSyncCheck {
  Future<void> checkPending() async {
    final counts = await OfflineFirstIntegration.getPendingCounts();

    int total = 0;
    counts.forEach((table, count) {
      total += count;
      if (count > 0) {
        debugPrint('Pending in $table: $count');
      }
    });

    debugPrint('Total pending records: $total');
  }
}
