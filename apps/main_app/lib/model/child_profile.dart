import '../core/child_profile_policy.dart';

/// Represents a child's profile including learning preferences and
/// gameplay comfort settings (music, vibration).
class ChildProfile {
  final String id;
  final String userId;
  final String displayName;
  final DateTime? birthDate;
  final int? legacyAgeYears;
  final String avatar;
  final bool musicEnabled;
  final bool vibrationEnabled;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ChildProfile({
    required this.id,
    required this.userId,
    required this.displayName,
    required this.birthDate,
    this.legacyAgeYears,
    required this.avatar,
    this.musicEnabled = true,
    this.vibrationEnabled = true,
    required this.createdAt,
    required this.updatedAt,
  });

  int ageYears({DateTime? today}) {
    final resolvedBirthDate = birthDate;
    if (resolvedBirthDate != null) {
      return calculateAgeYears(resolvedBirthDate, today: today);
    }

    final resolvedLegacyAge = legacyAgeYears;
    if (resolvedLegacyAge != null) {
      return resolvedLegacyAge;
    }

    throw StateError('Cannot calculate age for child without a birth date.');
  }

  @Deprecated('Use displayName instead.')
  String get name => displayName;

  @Deprecated('Use ageYears() instead.')
  int get age => ageYears();

  ChildProfile copyWith({
    String? displayName,
    DateTime? birthDate,
    bool clearBirthDate = false,
    String? avatar,
    bool? musicEnabled,
    bool? vibrationEnabled,
  }) {
    return ChildProfile(
      id: id,
      userId: userId,
      displayName: displayName ?? this.displayName,
      birthDate: clearBirthDate ? null : birthDate ?? this.birthDate,
      legacyAgeYears:
          clearBirthDate
              ? legacyAgeYears
              : birthDate != null
              ? null
              : legacyAgeYears,
      avatar: avatar ?? this.avatar,
      musicEnabled: musicEnabled ?? this.musicEnabled,
      vibrationEnabled: vibrationEnabled ?? this.vibrationEnabled,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'user_id': userId,
    'display_name': displayName,
    'birth_date': birthDate?.toIso8601String().split('T').first,
    'avatar': avatar,
    'music_enabled': musicEnabled ? 1 : 0,
    'vibration_enabled': vibrationEnabled ? 1 : 0,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  factory ChildProfile.fromMap(Map<String, dynamic> map) {
    final birthDateValue = map['birth_date'];
    final parsedBirthDate =
        birthDateValue == null
            ? null
            : birthDateValue is DateTime
            ? birthDateValue
            : DateTime.parse(birthDateValue as String);
    final legacyAgeValue = map['age'];
    final parsedLegacyAge =
        parsedBirthDate != null
            ? null
            : legacyAgeValue is int
            ? legacyAgeValue
            : legacyAgeValue is String
            ? int.tryParse(legacyAgeValue)
            : null;

    return ChildProfile(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      displayName: (map['display_name'] ?? map['name'] ?? 'Child') as String,
      birthDate: parsedBirthDate,
      legacyAgeYears: parsedLegacyAge,
      avatar: (map['avatar'] as String?) ?? 'avatar_1',
      musicEnabled: (map['music_enabled'] ?? 1) == 1,
      vibrationEnabled: (map['vibration_enabled'] ?? 1) == 1,
      createdAt: DateTime.parse(
        (map['created_at'] ?? map['local_created_at']) as String,
      ),
      updatedAt: DateTime.parse(
        (map['updated_at'] ?? map['created_at'] ?? map['local_created_at'])
            as String,
      ),
    );
  }

  /// Creates a ChildProfile from Supabase JSON (booleans, not ints).
  factory ChildProfile.fromSupabase(Map<String, dynamic> map) => ChildProfile(
    id: map['id'] as String,
    userId: map['parent_user_id'] as String,
    displayName: map['display_name'] as String,
    birthDate:
        map['birth_date'] != null
            ? DateTime.parse(map['birth_date'] as String)
            : null,
    legacyAgeYears: null,
    avatar: (map['avatar'] as String?) ?? 'avatar_1',
    musicEnabled: map['music_enabled'] as bool? ?? true,
    vibrationEnabled: map['vibration_enabled'] as bool? ?? true,
    createdAt: DateTime.parse(map['created_at'] as String),
    updatedAt: DateTime.parse(map['updated_at'] as String),
  );

  Map<String, dynamic> toSupabase() => {
    'id': id,
    'parent_user_id': userId,
    'display_name': displayName,
    'birth_date': birthDate?.toIso8601String().split('T').first,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };
}
