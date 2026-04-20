import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../model/child_profile.dart';
import '../services/auth_service.dart';
import '../services/local_db_service.dart';
import '../services/sync_service.dart';

/// Offline-first repository for child profile operations.
///
/// All operations write to local SQLite first, then trigger
/// background sync to Supabase when connectivity allows.
///
/// Supports guest mode - creates records with temporary owner_id
/// that gets backfilled after authentication.
class ChildRepository {
  final LocalDbService _localDb;
  final AuthService _authService;
  final SyncService _syncService;
  final Uuid _uuid = const Uuid();

  ChildRepository({
    LocalDbService? localDb,
    AuthService? authService,
    SyncService? syncService,
  })  : _localDb = localDb ?? localDbService,
        _authService = authService ?? AuthService(),
        _syncService = syncService ?? SyncService();

  /// Get the current effective user ID (authenticated or guest)
  String get _effectiveUserId {
    return _authService.currentUser?.id ??
           _authService.currentGuestId ??
           'guest';
  }

  /// Check if we're in guest mode
  bool get _isGuestMode => _authService.currentUser == null;

  // ─── CRUD Operations ──────────────────────────────────────────────────

  /// Create a new child profile (offline-first)
  ///
  /// In guest mode, the child is created with a placeholder owner_id
  /// that will be backfilled when the user authenticates.
  Future<ChildProfile> createChild({
    required String displayName,
    required DateTime birthDate,
    required String avatar,
    bool musicEnabled = true,
    bool vibrationEnabled = true,
  }) async {
    final now = DateTime.now();
    final userId = _effectiveUserId;

    final child = ChildProfile(
      id: _uuid.v4(),
      userId: userId,
      displayName: displayName,
      birthDate: birthDate,
      avatar: avatar,
      musicEnabled: musicEnabled,
      vibrationEnabled: vibrationEnabled,
      createdAt: now,
      updatedAt: now,
    );

    // Save locally first (always)
    await _localDb.upsertChild(
      child,
      ownerId: userId,
      markPending: true,
    );

    debugPrint('[ChildRepository] Child created locally: ${child.id} '
        '(guest: $_isGuestMode)');

    // Trigger background sync if online
    if (!_isGuestMode) {
      _syncService.syncNow();
    }

    return child;
  }

  /// Get a child by ID
  Future<ChildProfile?> getChild(String id) async {
    return _localDb.getChild(id);
  }

  /// Get all children for the current user
  Future<List<ChildProfile>> getChildren() async {
    final userId = _effectiveUserId;
    return _localDb.getChildren(userId: userId);
  }

  /// Update child profile
  Future<ChildProfile> updateChild(
    ChildProfile child, {
    String? displayName,
    DateTime? birthDate,
    String? avatar,
    bool? musicEnabled,
    bool? vibrationEnabled,
  }) async {
    final updated = child.copyWith(
      displayName: displayName,
      birthDate: birthDate,
      avatar: avatar,
      musicEnabled: musicEnabled,
      vibrationEnabled: vibrationEnabled,
    );

    await _localDb.upsertChild(
      updated,
      markPending: true,
    );

    debugPrint('[ChildRepository] Child updated: ${child.id}');

    if (!_isGuestMode) {
      _syncService.syncNow();
    }

    return updated;
  }

  /// Soft delete a child (propagated to Supabase on sync)
  Future<void> deleteChild(String id) async {
    await _localDb.deleteChild(id);
    debugPrint('[ChildRepository] Child soft-deleted: $id');

    if (!_isGuestMode) {
      _syncService.syncNow();
    }
  }

  // ─── Guest Mode Operations ────────────────────────────────────────────

  /// Convert guest-created children to authenticated user ownership
  ///
  /// Called automatically when user signs in.
  Future<void> backfillGuestChildren(String guestId, String authenticatedUserId) async {
    await _localDb.backfillGuestData(guestId, authenticatedUserId);
    debugPrint('[ChildRepository] Guest children backfilled to: $authenticatedUserId');
  }

  // ─── Sync Operations ──────────────────────────────────────────────────

  /// Force sync of pending child records
  Future<void> syncPending() async {
    if (_isGuestMode) {
      debugPrint('[ChildRepository] Cannot sync in guest mode');
      return;
    }
    await _syncService.syncNow();
  }

  /// Check if there are pending syncs for children
  Future<bool> hasPendingSync() async {
    final counts = await _localDb.getPendingCounts();
    return (counts['children_local'] ?? 0) > 0;
  }
}

/// Global instance for app-wide access
final childRepository = ChildRepository();
