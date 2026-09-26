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
      rubric: () async => response('rubric'),
    );
    expect(result?.predictedProfile, 'device');
  });

  test('falls back to rubric after on-device failure', () async {
    final result = await const AiPredictionFallbackService().predict(
      onDevice: () async => throw StateError('missing model'),
      rubric: () async => response('rubric'),
    );
    expect(result?.predictedProfile, 'rubric');
  });

  test('falls back to rubric when on-device returns nothing', () async {
    final result = await const AiPredictionFallbackService().predict(
      onDevice: () async => null,
      rubric: () async => response('rubric'),
    );
    expect(result?.predictedProfile, 'rubric');
  });
}
