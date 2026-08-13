import 'ai_assessment_response.dart';
import 'assessment_result.dart';
import 'support_profile.dart';

/// An immutable record of one *completed* assessment run.
///
/// A run's results, the support profile finalized with it, and the model
/// prediction made from its sessions belong together. Keeping them in one
/// frozen object is what stops a later run from rewriting an earlier one:
/// the pre-assessment summary always renders the pre snapshot, and the
/// post-assessment comparison always reads the pre snapshot as its baseline
/// and the post snapshot as the new state — never the provider's "latest"
/// prediction, which by then describes the post run.
class AssessmentRunSnapshot {
  const AssessmentRunSnapshot({
    required this.assessmentType,
    required this.childId,
    required this.completedAt,
    required this.results,
    this.assessmentRunId,
    this.profile,
    this.prediction,
  });

  /// 'pre' or 'post'.
  final String assessmentType;

  final String childId;

  /// The run these results came from, when the run id was known.
  final String? assessmentRunId;

  final DateTime completedAt;

  /// One result per game, as finalized.
  final List<AssessmentResult> results;

  /// The support profile built from this run.
  final SupportProfile? profile;

  /// The prediction made from *this* run's sessions.
  final AiAssessmentResponse? prediction;

  bool get isEmpty => results.isEmpty;

  Map<String, dynamic> toJson() => {
    'assessment_type': assessmentType,
    'child_id': childId,
    'assessment_run_id': assessmentRunId,
    'completed_at': completedAt.toIso8601String(),
    'results': results.map((r) => r.toSupabase()).toList(),
    'profile': profile?.toMap(),
    'prediction': prediction?.toJson(),
  };

  factory AssessmentRunSnapshot.fromJson(Map<String, dynamic> json) =>
      AssessmentRunSnapshot(
        assessmentType: json['assessment_type'] as String,
        childId: json['child_id'] as String,
        assessmentRunId: json['assessment_run_id'] as String?,
        completedAt: DateTime.parse(json['completed_at'] as String),
        results: [
          for (final raw in (json['results'] as List<dynamic>? ?? const []))
            AssessmentResult.fromSupabase(
              Map<String, dynamic>.from(raw as Map),
            ),
        ],
        profile:
            json['profile'] == null
                ? null
                : SupportProfile.fromMap(
                  Map<String, dynamic>.from(json['profile'] as Map),
                ),
        prediction:
            json['prediction'] == null
                ? null
                : AiAssessmentResponse.fromJson(
                  Map<String, dynamic>.from(json['prediction'] as Map),
                ),
      );
}
