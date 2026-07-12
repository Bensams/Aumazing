import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Result of an assessment-summary request: either an AI-written narrative
/// or the built-in rubric summary used as a fallback.
class AssessmentSummary {
  const AssessmentSummary({required this.text, required this.isAi});

  final String text;

  /// True when Gemini produced [text]; false when it's the local fallback.
  final bool isAi;
}

/// Produces a warm, plain-language summary of an assessment result.
///
/// Calls the `summarize-assessment` Edge Function (Gemini, key held in
/// Vault). Best-effort by design: on NO internet, timeout, a missing key,
/// quota, or any error, it returns the provided local [fallback] instead —
/// the parent always sees a summary. Successful AI summaries are cached
/// per result so repeat views (and offline re-opens) are instant and free.
class AssessmentSummaryService {
  AssessmentSummaryService._();

  static final AssessmentSummaryService instance =
      AssessmentSummaryService._();

  static const _timeout = Duration(seconds: 12);

  /// Builds a summary for one assessment.
  ///
  /// [areas] — [{'name': 'Communication', 'level': 'Emerging'}, ...]
  /// [fallback] — the local rubric summary shown when AI is unavailable.
  Future<AssessmentSummary> summarize({
    required List<Map<String, String>> areas,
    required int overallPct,
    required String supportLevel,
    required List<String> recommendations,
    required String fallback,
  }) async {
    final cacheKey = _cacheKey(areas, overallPct, supportLevel);

    // 1) Cached AI summary → instant, works offline.
    final cached = await _readCache(cacheKey);
    if (cached != null) {
      return AssessmentSummary(text: cached, isAi: true);
    }

    // 2) Try the Edge Function, but never let it break the screen.
    try {
      final response = await Supabase.instance.client.functions
          .invoke('summarize-assessment', body: {
            'areas': areas,
            'overall_pct': overallPct,
            'support_level': supportLevel,
            'recommendations': recommendations,
          })
          .timeout(_timeout);

      final data = response.data;
      final summary = data is Map ? data['summary'] as String? : null;
      if (summary != null && summary.trim().isNotEmpty) {
        await _writeCache(cacheKey, summary.trim());
        return AssessmentSummary(text: summary.trim(), isAi: true);
      }
    } catch (e) {
      // Offline, timeout, 5xx, no key configured — all handled the same:
      // fall back to the local summary. Logged, never surfaced.
      debugPrint('[AssessmentSummary] AI unavailable, using fallback: $e');
    }

    return AssessmentSummary(text: fallback, isAi: false);
  }

  // ── Cache (keyed by the summary inputs, so a new result re-summarizes) ──

  static String _cacheKey(
    List<Map<String, String>> areas,
    int overallPct,
    String supportLevel,
  ) {
    final areaPart =
        areas.map((a) => '${a['name']}:${a['level']}').join('|');
    return 'ai_summary_${areaPart}_${overallPct}_$supportLevel'.hashCode
        .toString();
  }

  Future<String?> _readCache(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('ai_summary_$key');
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCache(String key, String value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('ai_summary_$key', value);
    } catch (e) {
      debugPrint('[AssessmentSummary] cache write failed: $e');
    }
  }

  /// Exposed for tests.
  @visibleForTesting
  static String debugCacheKey(
    List<Map<String, String>> areas,
    int overallPct,
    String supportLevel,
  ) =>
      _cacheKey(areas, overallPct, supportLevel);
}
