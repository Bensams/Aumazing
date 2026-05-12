/// Per-area ordinal prediction returned by the AI Assessment API.
///
/// Path B (per-area ordinal design, May 2026) — each child receives one
/// `AreaLevel` per skill area: communication, social, play, attention.
/// Maps to the Python `AreaLevel` schema in `ai_assessment/app/schemas.py`.
class AreaLevel {
  /// Snake-case label as returned by the API:
  /// 'needs_support' | 'emerging' | 'strength'.
  final String level;

  /// Ordinal integer encoding: 0 = Needs Support, 1 = Emerging, 2 = Strength.
  final int levelInt;

  /// Title-case label suitable for UI display: 'Needs Support', 'Emerging', 'Strength'.
  final String levelName;

  /// Model confidence for this area's prediction (0.0–1.0).
  final double confidence;

  const AreaLevel({
    required this.level,
    required this.levelInt,
    required this.levelName,
    required this.confidence,
  });

  factory AreaLevel.fromJson(Map<String, dynamic> json) {
    return AreaLevel(
      level: json['level'] as String? ?? 'emerging',
      levelInt: (json['level_int'] as num?)?.toInt() ?? 1,
      levelName: json['level_name'] as String? ?? 'Emerging',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() => {
        'level': level,
        'level_int': levelInt,
        'level_name': levelName,
        'confidence': confidence,
      };

  /// Confidence as a percentage string (e.g. "84%").
  String get confidencePercent => '${(confidence * 100).round()}%';

  /// True when the child needs support in this area.
  bool get isNeedsSupport => levelInt == 0;

  /// True when the child is emerging in this area.
  bool get isEmerging => levelInt == 1;

  /// True when the child shows strength in this area.
  bool get isStrength => levelInt == 2;

  @override
  String toString() =>
      'AreaLevel(level=$level, int=$levelInt, conf=$confidencePercent)';
}
