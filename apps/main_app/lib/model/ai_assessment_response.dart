import 'module_recommendation.dart';

/// Response model from the AI Assessment API's /predict-from-sessions endpoint.
///
/// Maps to the Python PreAssessmentResponse schema in ai_assessment/app/schemas.py.
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

  const AiAssessmentResponse({
    required this.predictedProfile,
    required this.confidence,
    required this.summary,
    required this.supportLevel,
    required this.recommendedModules,
    this.featureValues,
    this.moduleDetails = const [],
    this.skillAreas = const [],
  });

  factory AiAssessmentResponse.fromJson(Map<String, dynamic> json) {
    final preResult =
        json['pre_assessment_result'] as Map<String, dynamic>? ?? {};
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
      };

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
      'skillAreas=$skillAreas)';
}
