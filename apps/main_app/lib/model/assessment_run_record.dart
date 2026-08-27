/// A single assessment run for a child — one pre- or post-assessment.
///
/// Stored in `assessment_runs_local`. A run groups a set of gameplay
/// sessions and results into one assessment sitting.
class AssessmentRunRecord {
  final String id;
  final String childId;

  /// 'pre' or 'post'.
  final String type;

  /// 'in_progress', 'completed', or 'incomplete'.
  final String status;

  final DateTime startedAt;
  final DateTime? completedAt;

  const AssessmentRunRecord({
    required this.id,
    required this.childId,
    required this.type,
    required this.status,
    required this.startedAt,
    this.completedAt,
  });

  bool get isCompleted => status == 'completed';

  factory AssessmentRunRecord.fromMap(Map<String, dynamic> map) =>
      AssessmentRunRecord(
        id: map['id'] as String,
        childId: map['child_id'] as String,
        type: map['type'] as String,
        status: map['status'] as String,
        startedAt: DateTime.parse(map['started_at'] as String),
        completedAt:
            map['completed_at'] != null
                ? DateTime.parse(map['completed_at'] as String)
                : null,
      );

  Map<String, dynamic> toMap() => {
    'id': id,
    'child_id': childId,
    'type': type,
    'status': status,
    'started_at': startedAt.toIso8601String(),
    'completed_at': completedAt?.toIso8601String(),
  };
}
