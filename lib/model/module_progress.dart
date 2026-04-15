/// Tracks a child's progress through a specific learning module.
class ModuleProgress {
  final String id;
  final String childId;
  final String moduleId;
  final String moduleName;
  final int currentLevel;
  final int maxLevel;

  /// One of: 'not_started', 'in_progress', 'completed'
  final String status;

  final DateTime? startedAt;
  final DateTime? completedAt;
  final DateTime updatedAt;

  const ModuleProgress({
    required this.id,
    required this.childId,
    required this.moduleId,
    required this.moduleName,
    this.currentLevel = 1,
    this.maxLevel = 5,
    this.status = 'not_started',
    this.startedAt,
    this.completedAt,
    required this.updatedAt,
  });

  bool get isCompleted => status == 'completed';
  bool get isInProgress => status == 'in_progress';
  double get progressPercent =>
      maxLevel > 0 ? (currentLevel / maxLevel).clamp(0.0, 1.0) : 0.0;

  ModuleProgress copyWith({
    int? currentLevel,
    String? status,
    DateTime? startedAt,
    DateTime? completedAt,
  }) {
    return ModuleProgress(
      id: id,
      childId: childId,
      moduleId: moduleId,
      moduleName: moduleName,
      currentLevel: currentLevel ?? this.currentLevel,
      maxLevel: maxLevel,
      status: status ?? this.status,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      updatedAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'child_id': childId,
        'module_id': moduleId,
        'module_name': moduleName,
        'current_level': currentLevel,
        'max_level': maxLevel,
        'status': status,
        'started_at': startedAt?.toIso8601String(),
        'completed_at': completedAt?.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory ModuleProgress.fromMap(Map<String, dynamic> map) => ModuleProgress(
        id: map['id'] as String,
        childId: map['child_id'] as String,
        moduleId: map['module_id'] as String,
        moduleName: map['module_name'] as String,
        currentLevel: map['current_level'] as int? ?? 1,
        maxLevel: map['max_level'] as int? ?? 5,
        status: map['status'] as String? ?? 'not_started',
        startedAt: map['started_at'] != null
            ? DateTime.parse(map['started_at'] as String)
            : null,
        completedAt: map['completed_at'] != null
            ? DateTime.parse(map['completed_at'] as String)
            : null,
        updatedAt: DateTime.parse(map['updated_at'] as String),
      );
}
