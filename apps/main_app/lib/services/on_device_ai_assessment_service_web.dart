import '../model/ai_assessment_response.dart';
import '../model/gameplay_session.dart';
import 'on_device_feature_aggregator.dart';

/// Web build of the on-device AI service.
///
/// ONNX Runtime uses `dart:ffi` and has no web implementation, so on-device
/// inference is unavailable in the browser. This stub mirrors the public API
/// of the native service but reports itself as unavailable: [predictFromSessions]
/// returns null, which makes [AiPredictionFallbackService] fall through to the
/// cloud API / rubric scoring path exactly as it does on a device without the
/// model bundled. Selected via the conditional export in
/// `on_device_ai_assessment_service.dart`.
class OnDeviceAiAssessmentService {
  OnDeviceAiAssessmentService({
    this.aggregator = const OnDeviceFeatureAggregator(),
  });

  final OnDeviceFeatureAggregator aggregator;

  /// Always false on web — the ONNX sessions can never load here.
  bool get isReady => false;

  /// No on-device model in the browser; return null so callers fall back.
  Future<AiAssessmentResponse?> predictFromSessions({
    required String childId,
    required List<GameplaySession> sessions,
  }) async {
    return null;
  }

  void dispose() {}
}
