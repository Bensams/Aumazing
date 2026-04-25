import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/config/api_config.dart';
import '../model/ai_assessment_response.dart';
import '../model/gameplay_session.dart';

/// Service that calls the XGBoost AI Assessment API to predict
/// a child's developmental profile from their gameplay sessions.
///
/// Falls back gracefully if the API is unreachable (offline mode).
class AiAssessmentService {
  final String _baseUrl;
  final http.Client _client;

  AiAssessmentService({
    String? baseUrl,
    http.Client? client,
  })  : _baseUrl = baseUrl ?? ApiConfig.aiAssessmentBaseUrl,
        _client = client ?? http.Client();

  /// Predict developmental profile from gameplay sessions.
  ///
  /// Returns null if the API is unreachable or returns an error,
  /// allowing the caller to fall back to rule-based scoring.
  Future<AiAssessmentResponse?> predictFromSessions({
    required String childId,
    required List<GameplaySession> sessions,
  }) async {
    if (sessions.isEmpty) {
      debugPrint('[AiAssessment] No sessions to predict from');
      return null;
    }

    final url = Uri.parse('$_baseUrl/predict-from-sessions');
    final body = jsonEncode({
      'child_id': childId,
      'sessions': sessions
          .map((s) => {
                'game_id': s.gameId,
                'score': s.score,
                'total_items': s.totalItems,
                'error_count': s.errorCount,
                'total_response_time_ms': s.totalResponseTimeMs,
                'retry_count': s.retryCount,
                'hint_count': s.hintCount,
                'prompt_count': s.promptCount,
                'idle_time_seconds': s.idleTimeSeconds,
                'random_touch_count': s.randomTouchCount,
                'avg_response_time': s.avgResponseTime,
                'avg_valid_response_time': s.avgValidResponseTime,
                'off_task_action_count': s.offTaskActionCount,
                'improvement_score': s.improvementScore,
                'consistency_score': s.consistencyScore,
                'bg_music_enabled': s.bgMusicEnabled,
                'haptic_feedback_enabled': s.hapticFeedbackEnabled,
              })
          .toList(),
    });

    try {
      debugPrint(
          '[AiAssessment] 📤 Calling $url with ${sessions.length} sessions');
      debugPrint('[AiAssessment] 📤 Request body: $body');

      final response = await _client
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(Duration(seconds: ApiConfig.aiApiTimeoutSeconds));

      debugPrint(
          '[AiAssessment] 📥 Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        debugPrint('[AiAssessment] 📥 Response body: ${response.body}');
        final result = AiAssessmentResponse.fromJson(json);
        debugPrint('[AiAssessment] ✅ Prediction: $result');
        debugPrint('[AiAssessment] ✅ Module details: ${result.moduleDetails}');
        debugPrint('[AiAssessment] ✅ Skill areas: ${result.skillAreas}');
        return result;
      } else {
        debugPrint(
            '[AiAssessment] ❌ API returned ${response.statusCode}: ${response.body}');
        return null;
      }
    } on SocketException catch (e) {
      debugPrint('[AiAssessment] Network error (offline?): $e');
      return null;
    } on HttpException catch (e) {
      debugPrint('[AiAssessment] HTTP error: $e');
      return null;
    } catch (e) {
      debugPrint('[AiAssessment] Unexpected error: $e');
      return null;
    }
  }

  /// Check if the AI API is reachable.
  Future<bool> isAvailable() async {
    try {
      final response = await _client
          .get(Uri.parse('$_baseUrl/health'))
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  void dispose() {
    _client.close();
  }
}
