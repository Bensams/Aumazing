import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../sync/sync_status.dart';

/// Service for all Supabase cloud operations.
///
/// Handles upserts, batch operations, and conflict resolution.
/// All methods use upsert to avoid duplicate records when syncing.
///
/// Usage:
/// ```dart
/// final supabase = SupabaseService();
/// await supabase.upsertChild(child.toSupabase(), child.id);
/// ```
class SupabaseService {
  final SupabaseClient _client = Supabase.instance.client;

  // ─── Children ─────────────────────────────────────────────────────────

  /// Upsert a child record to Supabase
  Future<void> upsertChild(Map<String, dynamic> data, String id) async {
    try {
      await _client
          .from(RemoteTables.children)
          .upsert(
            data,
            onConflict: 'id',
          );
      debugPrint('[SupabaseService] Child upserted: $id');
    } catch (e) {
      debugPrint('[SupabaseService] upsertChild error: $e');
      rethrow;
    }
  }

  /// Get children for current user
  Future<List<Map<String, dynamic>>> getChildren(String userId) async {
    try {
      final response = await _client
          .from(RemoteTables.children)
          .select()
          .eq('user_id', userId);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('[SupabaseService] getChildren error: $e');
      return [];
    }
  }

  // ─── Assessment Runs ──────────────────────────────────────────────────

  Future<void> upsertAssessmentRun(Map<String, dynamic> data, String id) async {
    try {
      await _client
          .from(RemoteTables.assessmentRuns)
          .upsert(data, onConflict: 'id');
    } catch (e) {
      debugPrint('[SupabaseService] upsertAssessmentRun error: $e');
      rethrow;
    }
  }

  // ─── Game Sessions ────────────────────────────────────────────────────

  Future<void> upsertGameSession(Map<String, dynamic> data, String id) async {
    try {
      await _client
          .from(RemoteTables.gameSessions)
          .upsert(data, onConflict: 'id');
    } catch (e) {
      debugPrint('[SupabaseService] upsertGameSession error: $e');
      rethrow;
    }
  }

  /// Batch upsert multiple game sessions
  Future<void> upsertGameSessionsBatch(
    List<Map<String, dynamic>> records,
  ) async {
    if (records.isEmpty) return;
    try {
      await _client
          .from(RemoteTables.gameSessions)
          .upsert(records, onConflict: 'id');
      debugPrint('[SupabaseService] ${records.length} game sessions upserted');
    } catch (e) {
      debugPrint('[SupabaseService] upsertGameSessionsBatch error: $e');
      rethrow;
    }
  }

  // ─── Game Rounds ───────────────────────────────────────────────────────

  Future<void> upsertGameRound(Map<String, dynamic> data, String id) async {
    try {
      await _client
          .from(RemoteTables.gameRounds)
          .upsert(data, onConflict: 'id');
    } catch (e) {
      debugPrint('[SupabaseService] upsertGameRound error: $e');
      rethrow;
    }
  }

  Future<void> upsertGameRoundsBatch(
    List<Map<String, dynamic>> records,
  ) async {
    if (records.isEmpty) return;
    try {
      await _client
          .from(RemoteTables.gameRounds)
          .upsert(records, onConflict: 'id');
    } catch (e) {
      debugPrint('[SupabaseService] upsertGameRoundsBatch error: $e');
      rethrow;
    }
  }

  // ─── Session Events ─────────────────────────────────────────────────────

  Future<void> upsertSessionEvent(Map<String, dynamic> data, String id) async {
    try {
      await _client
          .from(RemoteTables.sessionEvents)
          .upsert(data, onConflict: 'id');
    } catch (e) {
      debugPrint('[SupabaseService] upsertSessionEvent error: $e');
      rethrow;
    }
  }

  // ─── Caregiver Questionnaires ─────────────────────────────────────────

  Future<void> upsertCaregiverQuestionnaire(
    Map<String, dynamic> data,
    String id,
  ) async {
    try {
      await _client
          .from(RemoteTables.caregiverQuestionnaires)
          .upsert(data, onConflict: 'id');
    } catch (e) {
      debugPrint('[SupabaseService] upsertCaregiverQuestionnaire error: $e');
      rethrow;
    }
  }

  // ─── Assessment Results ────────────────────────────────────────────────

  Future<void> upsertAssessmentResult(
    Map<String, dynamic> data,
    String id,
  ) async {
    try {
      await _client
          .from(RemoteTables.assessmentResults)
          .upsert(data, onConflict: 'id');
    } catch (e) {
      debugPrint('[SupabaseService] upsertAssessmentResult error: $e');
      rethrow;
    }
  }

  Future<void> upsertAssessmentResultsBatch(
    List<Map<String, dynamic>> records,
  ) async {
    if (records.isEmpty) return;
    try {
      await _client
          .from(RemoteTables.assessmentResults)
          .upsert(records, onConflict: 'id');
    } catch (e) {
      debugPrint('[SupabaseService] upsertAssessmentResultsBatch error: $e');
      rethrow;
    }
  }

  // ─── Module Recommendations ─────────────────────────────────────────────

  Future<void> upsertModuleRecommendation(
    Map<String, dynamic> data,
    String id,
  ) async {
    try {
      await _client
          .from(RemoteTables.moduleRecommendations)
          .upsert(data, onConflict: 'id');
    } catch (e) {
      debugPrint('[SupabaseService] upsertModuleRecommendation error: $e');
      rethrow;
    }
  }

  // ─── Assessment Comparisons ────────────────────────────────────────────

  Future<void> upsertAssessmentComparison(
    Map<String, dynamic> data,
    String id,
  ) async {
    try {
      await _client
          .from(RemoteTables.assessmentComparisons)
          .upsert(data, onConflict: 'id');
    } catch (e) {
      debugPrint('[SupabaseService] upsertAssessmentComparison error: $e');
      rethrow;
    }
  }

  // ─── Reference Data (Cached Tables) ───────────────────────────────────

  /// Fetch all learning modules for caching
  Future<List<Map<String, dynamic>>> fetchLearningModules() async {
    try {
      final response = await _client
          .from(RemoteTables.learningModules)
          .select();
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('[SupabaseService] fetchLearningModules error: $e');
      return [];
    }
  }

  /// Fetch all module paths for caching
  Future<List<Map<String, dynamic>>> fetchModulePaths() async {
    try {
      final response = await _client
          .from(RemoteTables.modulePaths)
          .select();
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('[SupabaseService] fetchModulePaths error: $e');
      return [];
    }
  }

  /// Fetch all module path items for caching
  Future<List<Map<String, dynamic>>> fetchModulePathItems() async {
    try {
      final response = await _client
          .from(RemoteTables.modulePathItems)
          .select();
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('[SupabaseService] fetchModulePathItems error: $e');
      return [];
    }
  }

  // ─── Conflict Resolution Helpers ───────────────────────────────────────

  /// Get remote record timestamp for conflict resolution
  Future<DateTime?> getRemoteUpdatedAt(
    String table,
    String id,
  ) async {
    try {
      final response = await _client
          .from(table)
          .select('updated_at')
          .eq('id', id)
          .maybeSingle();
      if (response == null) return null;
      return DateTime.parse(response['updated_at'] as String);
    } catch (e) {
      debugPrint('[SupabaseService] getRemoteUpdatedAt error: $e');
      return null;
    }
  }

  // ─── Soft Delete Propagation ───────────────────────────────────────────

  /// Mark a record as deleted in Supabase (soft delete)
  Future<void> softDeleteRemote(String table, String id) async {
    try {
      await _client
          .from(table)
          .update({
            'deleted_at': DateTime.now().toIso8601String(),
          })
          .eq('id', id);
      debugPrint('[SupabaseService] Soft deleted $table:$id');
    } catch (e) {
      debugPrint('[SupabaseService] softDeleteRemote error: $e');
      rethrow;
    }
  }

  // ─── Auth Helpers ───────────────────────────────────────────────────────

  /// Get current user ID
  String? get currentUserId => _client.auth.currentUser?.id;

  /// Check if user is authenticated
  bool get isAuthenticated => _client.auth.currentUser != null;
}

/// Global instance for app-wide access
final supabaseService = SupabaseService();
