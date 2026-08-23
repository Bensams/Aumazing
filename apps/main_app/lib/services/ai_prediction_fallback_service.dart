import '../model/ai_assessment_response.dart';

typedef PredictionAttempt = Future<AiAssessmentResponse?> Function();

/// Runs prediction tiers in order while isolating failures in each tier.
class AiPredictionFallbackService {
  const AiPredictionFallbackService();

  Future<AiAssessmentResponse?> predict({
    required PredictionAttempt onDevice,
    required PredictionAttempt cloud,
    required PredictionAttempt rubric,
  }) async {
    try {
      final result = await onDevice();
      if (result != null) return result;
    } catch (_) {}
    try {
      final result = await cloud();
      if (result != null) return result;
    } catch (_) {}
    try {
      return await rubric();
    } catch (_) {
      return null;
    }
  }
}
