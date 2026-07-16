import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A parent's research-participation decision for one child.
class ResearchConsentStatus {
  const ResearchConsentStatus({
    required this.answered,
    required this.participate,
    required this.aiTraining,
  });

  /// Whether the parent has been asked and made a choice.
  final bool answered;

  /// Consent to research review (results visible to the research team and
  /// the SPED validator in the admin portal).
  final bool participate;

  /// Separate opt-in: gameplay telemetry may be used to improve/train the
  /// AI model.
  final bool aiTraining;

  static const unanswered = ResearchConsentStatus(
      answered: false, participate: false, aiTraining: false);
}

/// Records and serves parental research consent (RA 10173-aligned).
///
/// - Consent is per child, versioned, and explicit — nothing defaults to
///   "yes", and declining never blocks the app.
/// - Offline-first: the choice is cached locally and pushed to the
///   `research_consents` table; failed pushes are retried on next load.
/// - Deny-by-default: any query for an unknown child answers "no consent",
///   so the AI-training gate can never leak data on a cache miss.
class ResearchConsentService {
  ResearchConsentService._();

  static final ResearchConsentService instance = ResearchConsentService._();

  /// Bump when the consent wording changes — parents are re-asked.
  static const consentVersion = 'beta-1.0';

  final Map<String, ResearchConsentStatus> _memory = {};

  static String _cacheKey(String childId) => 'research_consent_$childId';

  /// The stored decision for [childId] (cache-first; deny by default).
  Future<ResearchConsentStatus> statusFor(String childId) async {
    final cached = _memory[childId];
    if (cached != null) return cached;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey(childId));
      if (raw != null) {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        // A version bump invalidates the old answer → parent is re-asked.
        if (map['version'] == consentVersion) {
          final status = ResearchConsentStatus(
            answered: true,
            participate: map['participate'] == true,
            aiTraining: map['ai_training'] == true,
          );
          _memory[childId] = status;
          if (map['pending_sync'] == true) _pushToBackend(childId, status);
          return status;
        }
      }
    } catch (e) {
      debugPrint('[ResearchConsent] cache read failed: $e');
    }
    return ResearchConsentStatus.unanswered;
  }

  /// Synchronous gate for the AI-training export. Unknown child → false.
  bool aiTrainingOptInSync(String childId) =>
      _memory[childId]?.aiTraining ?? false;

  /// Records the parent's decision: caches locally, then pushes to the
  /// backend (marked pending and retried later when offline).
  Future<void> record({
    required String childId,
    required bool participate,
    required bool aiTraining,
  }) async {
    final status = ResearchConsentStatus(
      answered: true,
      participate: participate,
      aiTraining: aiTraining,
    );
    _memory[childId] = status;

    final pushed = await _pushToBackend(childId, status);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _cacheKey(childId),
        jsonEncode({
          'version': consentVersion,
          'participate': participate,
          'ai_training': aiTraining,
          'pending_sync': !pushed,
        }),
      );
    } catch (e) {
      debugPrint('[ResearchConsent] cache write failed: $e');
    }
  }

  /// Re-push any decisions that failed to reach the backend (offline at the
  /// time). Called when connectivity is restored so consents don't sit
  /// unpushed until the next [statusFor] read.
  Future<void> retryPendingPushes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in prefs.getKeys()) {
        if (!key.startsWith('research_consent_')) continue;
        final raw = prefs.getString(key);
        if (raw == null) continue;
        final map = jsonDecode(raw) as Map<String, dynamic>;
        if (map['version'] != consentVersion) continue;
        if (map['pending_sync'] != true) continue;

        final childId = key.substring('research_consent_'.length);
        final status = ResearchConsentStatus(
          answered: true,
          participate: map['participate'] == true,
          aiTraining: map['ai_training'] == true,
        );
        if (await _pushToBackend(childId, status)) {
          map['pending_sync'] = false;
          await prefs.setString(key, jsonEncode(map));
          debugPrint('[ResearchConsent] pending push flushed for $childId');
        }
      }
    } catch (e) {
      debugPrint('[ResearchConsent] retryPendingPushes failed: $e');
    }
  }

  Future<bool> _pushToBackend(
      String childId, ResearchConsentStatus status) async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return false;
      await Supabase.instance.client.from('research_consents').upsert({
        'user_id': user.id,
        'child_id': childId,
        'consent_version': consentVersion,
        'research_participation': status.participate,
        'ai_training_opt_in': status.aiTraining,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'child_id');
      return true;
    } catch (e) {
      debugPrint('[ResearchConsent] backend push failed (queued): $e');
      return false;
    }
  }
}
