/// Sync status values for offline-first data synchronization.
///
/// Records flow through these states:
/// - [pending]: Local-only record, needs to be synced to cloud
/// - [syncing]: Currently being uploaded to Supabase
/// - [synced]: Successfully synced to cloud and matches remote state
/// - [failed]: Sync attempt failed, will be retried
enum SyncStatus {
  pending,
  syncing,
  synced,
  failed,
}

/// Extension methods for SyncStatus enum
extension SyncStatusX on SyncStatus {
  /// Convert to string for database storage
  String get value => name;

  /// Check if record needs to be synced
  bool get needsSync => this == SyncStatus.pending || this == SyncStatus.failed;

  /// Check if record is in terminal state (synced or failed)
  bool get isTerminal => this == SyncStatus.synced || this == SyncStatus.failed;
}

/// Helper to parse sync status from string
SyncStatus syncStatusFromString(String? value) {
  switch (value) {
    case 'syncing':
      return SyncStatus.syncing;
    case 'synced':
      return SyncStatus.synced;
    case 'failed':
      return SyncStatus.failed;
    case 'pending':
    default:
      return SyncStatus.pending;
  }
}

/// Mixin for sync metadata fields required on all local entities.
///
/// All local tables should include these fields for proper sync tracking:
/// - sync_status: Current sync state
/// - last_synced_at: When last successfully synced (null if never)
/// - deleted_at: Soft delete timestamp (null if not deleted)
/// - updated_at: Local modification timestamp for conflict resolution
/// - local_created_at: When record was created locally
/// - owner_id: User ID who owns this record (for guest mode backfill)
mixin SyncMetadata {
  SyncStatus get syncStatus;
  DateTime? get lastSyncedAt;
  DateTime? get deletedAt;
  DateTime get updatedAt;
  DateTime get localCreatedAt;
  String? get ownerId;

  /// Check if record is soft-deleted
  bool get isDeleted => deletedAt != null;

  /// Check if record needs to be synced to cloud
  bool get needsSync => syncStatus.needsSync;

  /// Convert sync metadata to map for database storage
  Map<String, dynamic> syncMetadataToMap() => {
        'sync_status': syncStatus.value,
        'last_synced_at': lastSyncedAt?.toIso8601String(),
        'deleted_at': deletedAt?.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'local_created_at': localCreatedAt.toIso8601String(),
        'owner_id': ownerId,
      };

  /// Parse sync metadata from database map
  static SyncMetadataFields fromMap(Map<String, dynamic> map) {
    return SyncMetadataFields(
      syncStatus: syncStatusFromString(map['sync_status'] as String?),
      lastSyncedAt: map['last_synced_at'] != null
          ? DateTime.parse(map['last_synced_at'] as String)
          : null,
      deletedAt: map['deleted_at'] != null
          ? DateTime.parse(map['deleted_at'] as String)
          : null,
      updatedAt: DateTime.parse(map['updated_at'] as String),
      localCreatedAt: DateTime.parse(
        (map['local_created_at'] as String?) ??
            (map['created_at'] as String?) ??
            DateTime.now().toIso8601String(),
      ),
      ownerId: map['owner_id'] as String?,
    );
  }
}

/// Data class holding sync metadata fields
class SyncMetadataFields {
  final SyncStatus syncStatus;
  final DateTime? lastSyncedAt;
  final DateTime? deletedAt;
  final DateTime updatedAt;
  final DateTime localCreatedAt;
  final String? ownerId;

  const SyncMetadataFields({
    required this.syncStatus,
    this.lastSyncedAt,
    this.deletedAt,
    required this.updatedAt,
    required this.localCreatedAt,
    this.ownerId,
  });

  SyncMetadataFields copyWith({
    SyncStatus? syncStatus,
    DateTime? lastSyncedAt,
    DateTime? deletedAt,
    DateTime? updatedAt,
    DateTime? localCreatedAt,
    String? ownerId,
  }) {
    return SyncMetadataFields(
      syncStatus: syncStatus ?? this.syncStatus,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      localCreatedAt: localCreatedAt ?? this.localCreatedAt,
      ownerId: ownerId ?? this.ownerId,
    );
  }

  Map<String, dynamic> toMap() => {
        'sync_status': syncStatus.value,
        'last_synced_at': lastSyncedAt?.toIso8601String(),
        'deleted_at': deletedAt?.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'local_created_at': localCreatedAt.toIso8601String(),
        'owner_id': ownerId,
      };
}

/// Constants for table names to ensure consistency
class LocalTables {
  static const String children = 'children_local';
  static const String assessmentRuns = 'assessment_runs_local';
  static const String gameSessions = 'game_sessions_local';
  static const String gameRounds = 'game_rounds_local';
  static const String sessionEvents = 'session_events_local';
  static const String caregiverQuestionnaires = 'caregiver_questionnaires_local';
  static const String assessmentResults = 'assessment_results_local';
  static const String moduleRecommendations = 'module_recommendations_local';
  static const String assessmentComparisons = 'assessment_comparisons_local';
  static const String learningModulesCache = 'learning_modules_cache';
  static const String modulePathsCache = 'module_paths_cache';
  static const String modulePathItemsCache = 'module_path_items_cache';
  static const String syncQueue = 'sync_queue';
}

/// Constants for Supabase remote table names
class RemoteTables {
  static const String children = 'children';
  static const String assessmentRuns = 'assessment_runs';
  static const String gameSessions = 'game_sessions';
  static const String gameRounds = 'game_rounds';
  static const String sessionEvents = 'session_events';
  static const String caregiverQuestionnaires = 'caregiver_questionnaires';
  static const String assessmentResults = 'assessment_results';
  static const String moduleRecommendations = 'module_recommendations';
  static const String assessmentComparisons = 'assessment_comparisons';
  static const String learningModules = 'learning_modules';
  static const String modulePaths = 'module_paths';
  static const String modulePathItems = 'module_path_items';
}

/// Sync dependency order - ensures parent records sync before children
/// This prevents foreign key violations in Supabase
class SyncOrder {
  /// Ordered list of table names for sync operations
  static const List<String> dependencyOrder = [
    LocalTables.children,
    LocalTables.assessmentRuns,
    LocalTables.gameSessions,
    LocalTables.gameRounds,
    LocalTables.sessionEvents,
    LocalTables.caregiverQuestionnaires,
    LocalTables.assessmentResults,
    LocalTables.moduleRecommendations,
    LocalTables.assessmentComparisons,
  ];

  /// Get the remote table name for a local table
  static String? getRemoteTable(String localTable) {
    final mapping = {
      LocalTables.children: RemoteTables.children,
      LocalTables.assessmentRuns: RemoteTables.assessmentRuns,
      LocalTables.gameSessions: RemoteTables.gameSessions,
      LocalTables.gameRounds: RemoteTables.gameRounds,
      LocalTables.sessionEvents: RemoteTables.sessionEvents,
      LocalTables.caregiverQuestionnaires: RemoteTables.caregiverQuestionnaires,
      LocalTables.assessmentResults: RemoteTables.assessmentResults,
      LocalTables.moduleRecommendations: RemoteTables.moduleRecommendations,
      LocalTables.assessmentComparisons: RemoteTables.assessmentComparisons,
    };
    return mapping[localTable];
  }
}
