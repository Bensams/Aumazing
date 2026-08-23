import 'package:flutter_test/flutter_test.dart';
import 'package:aumazing/model/ai_assessment_response.dart';
import 'package:aumazing/services/ai_prediction_fallback_service.dart';

AiAssessmentResponse response(String profile) => AiAssessmentResponse(
  predictedProfile: profile,
  confidence: 1,
  summary: profile,
  supportLevel: 'low',
  recommendedModules: const [],
  moduleDetails: const [],
  skillAreas: const [],
  areaLevels: const {},
);

void main() {
  test('uses on-device first', () async {
    final result = await const AiPredictionFallbackService().predict(
      onDevice: () async => response('device'),
      cloud: () async => response('cloud'),
      rubric: () async => response('rubric'),
    );
    expect(result?.predictedProfile, 'device');
  });

  test('falls back to cloud after on-device failure', () async {
    final result = await const AiPredictionFallbackService().predict(
      onDevice: () async => throw StateError('missing model'),
      cloud: () async => response('cloud'),
      rubric: () async => response('rubric'),
    );
    expect(result?.predictedProfile, 'cloud');
  });

  test('falls back to rubric after both AI tiers fail', () async {
    final result = await const AiPredictionFallbackService().predict(
      onDevice: () async => null,
      cloud: () async => throw StateError('offline'),
      rubric: () async => response('rubric'),
    );
    expect(result?.predictedProfile, 'rubric');
  });
}
