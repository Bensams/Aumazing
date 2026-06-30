import 'area_level.dart';
import 'module_recommendation.dart';

/// Response model from the AI Assessment API's /predict-from-sessions endpoint.
///
/// Maps to the Python PreAssessmentResponse schema in ai_assessment/app/schemas.py.
/// Path B (May 2026): the canonical AI output is now [areaLevels] (per-area
/// ordinal predictions). The legacy [predictedProfile] / [confidence] fields
/// are still populated by the API for backwards compatibility (dual-response).
class AiAssessmentResponse {
  final String predictedProfile;
  final double confidence;
  final String summary;
  final String supportLevel;
  final List<String> recommendedModules;
  final Map<String, double>? featureValues;

  /// Structured module recommendations with starting levels.
  final List<ModuleRecommendation> moduleDetails;

  /// Skill areas identified by the AI (e.g., 'communication', 'social').
  final List<String> skillAreas;

  /// Per-area ordinal predictions keyed by area name.
  ///
  /// Keys: 'communication', 'social', 'play', 'attention'.
  /// This is the canonical AI output under the Path B per-area design.
  /// Empty when talking to a legacy API that does not yet emit `area_levels`.
  final Map<String, AreaLevel> areaLevels;

  /// True when this prediction was produced by the on-device ONNX model
  /// (vs. the cloud API). Used to surface an "On-Device AI" indicator.
  final bool onDevice;

  const AiAssessmentResponse({
    required this.predictedProfile,
    required this.confidence,
    required this.summary,
    required this.supportLevel,
    required this.recommendedModules,
    this.featureValues,
    this.moduleDetails = const [],
    this.skillAreas = const [],
    this.areaLevels = const {},
    this.onDevice = false,
  });

  factory AiAssessmentResponse.fromJson(Map<String, dynamic> json) {
    final preResult =
        json['pre_assessment_result'] as Map<String, dynamic>? ?? {};

    final rawAreaLevels =
        json['area_levels'] as Map<String, dynamic>? ?? const {};
    final parsedAreaLevels = <String, AreaLevel>{
      for (final entry in rawAreaLevels.entries)
        entry.key: AreaLevel.fromJson(entry.value as Map<String, dynamic>),
    };

    return AiAssessmentResponse(
      predictedProfile:
          json['predicted_profile'] as String? ?? 'balanced_profile',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      summary: preResult['summary'] as String? ?? '',
      supportLevel: preResult['support_level'] as String? ?? 'moderate',
      recommendedModules: (json['recommended_modules'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      featureValues:
          (json['feature_values'] as Map<String, dynamic>?)?.map(
        (k, v) => MapEntry(k, (v as num).toDouble()),
      ),
      moduleDetails: (json['module_details'] as List<dynamic>?)
              ?.map((e) =>
                  ModuleRecommendation.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      skillAreas: (json['skill_areas'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      areaLevels: parsedAreaLevels,
      onDevice: json['on_device'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'predicted_profile': predictedProfile,
        'confidence': confidence,
        'pre_assessment_result': {
          'summary': summary,
          'support_level': supportLevel,
        },
        'recommended_modules': recommendedModules,
        if (featureValues != null) 'feature_values': featureValues,
        'module_details': moduleDetails.map((m) => m.toJson()).toList(),
        'skill_areas': skillAreas,
        'area_levels': {
          for (final entry in areaLevels.entries)
            entry.key: entry.value.toJson(),
        },
        'on_device': onDevice,
      };

  /// True when the API returned per-area predictions (Path B response).
  bool get hasAreaLevels => areaLevels.isNotEmpty;

  /// Human-readable profile name.
  String get profileDisplayName {
    switch (predictedProfile) {
      case 'communication_support':
        return 'Communication Support';
      case 'social_support':
        return 'Social Support';
      case 'play_support':
        return 'Play Support';
      case 'attention_support':
        return 'Attention Support';
      case 'balanced_profile':
        return 'Balanced Profile';
      default:
        return predictedProfile;
    }
  }

  /// Confidence as a percentage string (e.g., "82%").
  String get confidencePercent => '${(confidence * 100).round()}%';

  @override
  String toString() => 'AiAssessmentResponse('
      'profile=$predictedProfile, '
      'confidence=$confidencePercent, '
      'modules=$recommendedModules, '
      'moduleDetails=$moduleDetails, '
      'skillAreas=$skillAreas, '
      'areaLevels=$areaLevels)';
}
