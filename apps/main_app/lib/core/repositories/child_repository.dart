import 'package:flutter/foundation.dart';
import 'package:shared_audio/shared_audio.dart';
import 'package:uuid/uuid.dart';

import '../../model/child_profile.dart';
export '../../model/child_profile.dart' show ChildSex, RewardPreference;
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
    SyncService? overrideSyncService,
  })  : _localDb = localDb ?? localDbService,
        _authService = authService ?? AuthService(),
        _syncService = overrideSyncService ?? syncService;

  /// Get the current effective user ID (authenticated or guest)
  String get _effectiveUserId {
    return _authService.currentUser?.id ??
           _authService.currentGuestId ??
           'guest';
  }

  // ─── CRUD Operations ──────────────────────────────────────────────────

  /// Create a new child profile (offline-first)
  ///
  /// In guest mode, the child is created with a placeholder owner_id
  /// that will be backfilled when the user authenticates.
  Future<ChildProfile> createChild({
    required String displayName,
    required DateTime birthDate,
    required String avatar,
    ChildSex? sex,
    bool musicEnabled = true,
    double musicVolume = 0.5,
    String musicCategory = kDefaultBgmCategory,
    double sfxVolume = 0.7,
    bool vibrationEnabled = true,
    double promptSpeed = 1.0,
    bool sensoryPreferencesSet = false,
    RewardPreference rewardPreference = RewardPreference.bubbles,
    bool useRandomReward = false,
    String characterId = 'bps',
  }) async {
    final now = DateTime.now();
    final userId = _effectiveUserId;

    final child = ChildProfile(
      id: _uuid.v4(),
      userId: userId,
      displayName: displayName,
      birthDate: birthDate,
      avatar: avatar,
      sex: sex,
      musicEnabled: musicEnabled,
      musicVolume: musicVolume,
      musicCategory: musicCategory,
      sfxVolume: sfxVolume,
      vibrationEnabled: vibrationEnabled,
      promptSpeed: promptSpeed,
      sensoryPreferencesSet: sensoryPreferencesSet,
      rewardPreference: rewardPreference,
      useRandomReward: useRandomReward,
      characterId: characterId,
      createdAt: now,
      updatedAt: now,
    );

    // Save locally first (always)
    await _localDb.upsertChild(
      child,
      ownerId: userId,
      markPending: true,
    );

    debugPrint('[ChildRepository] Child created locally: ${child.id}');

    // Trigger background sync (anonymous users are authenticated in Supabase)
    _syncService.syncNow();

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
    ChildSex? sex,
    bool? musicEnabled,
    bool? vibrationEnabled,
    RewardPreference? rewardPreference,
    bool? useRandomReward,
  }) async {
    final updated = child.copyWith(
      displayName: displayName,
      birthDate: birthDate,
      avatar: avatar,
      sex: sex,
      musicEnabled: musicEnabled,
      vibrationEnabled: vibrationEnabled,
      rewardPreference: rewardPreference,
      useRandomReward: useRandomReward,
    );

    await _localDb.upsertChild(
      updated,
      markPending: true,
    );

    debugPrint('[ChildRepository] Child updated: ${child.id}');

    // Trigger background sync (anonymous users are authenticated in Supabase)
    _syncService.syncNow();

    return updated;
  }

  /// Update reward preference for a child
  Future<ChildProfile> updateRewardPreference(
    ChildProfile child, {
    required RewardPreference rewardPreference,
    required bool useRandomReward,
  }) async {
    final updated = child.copyWith(
      rewardPreference: rewardPreference,
      useRandomReward: useRandomReward,
    );

    await _localDb.upsertChild(
      updated,
      markPending: true,
    );

    debugPrint('[ChildRepository] Reward preference updated for child: ${child.id} '
        '(preference: ${rewardPreference.value}, random: $useRandomReward)');

    // Trigger background sync (anonymous users are authenticated in Supabase)
    _syncService.syncNow();

    return updated;
  }

  /// Soft delete a child (propagated to Supabase on sync)
  ///
  /// The child row stays behind as a tombstone until the deletion reaches
  /// Supabase; the child's local progress rows are removed straight away.
  /// Offline this simply queues — the tombstone also stops cloud hydration
  /// from bringing the profile back before the deletion is propagated.
  Future<void> deleteChild(String id) async {
    await _localDb.deleteChild(id);
    await _localDb.purgeChildScopedData(id);
    debugPrint('[ChildRepository] Child soft-deleted: $id');

    // Trigger background sync (anonymous users are authenticated in Supabase)
    _syncService.syncNow();
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
