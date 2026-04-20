import '../core/child_profile_policy.dart';

/// Represents a child's profile including learning preferences and
/// gameplay comfort settings (music, vibration).
class ChildProfile {
  final String id;
  final String userId;
  final String displayName;
  final DateTime birthDate;
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
    required this.avatar,
    this.musicEnabled = true,
    this.vibrationEnabled = true,
    required this.createdAt,
    required this.updatedAt,
  });

  int ageYears({DateTime? today}) => calculateAgeYears(birthDate, today: today);

  @Deprecated('Use displayName instead.')
  String get name => displayName;

  @Deprecated('Use ageYears() instead.')
  int get age => ageYears();

  ChildProfile copyWith({
    String? displayName,
    DateTime? birthDate,
    String? avatar,
    bool? musicEnabled,
    bool? vibrationEnabled,
  }) {
    return ChildProfile(
      id: id,
      userId: userId,
      displayName: displayName ?? this.displayName,
      birthDate: birthDate ?? this.birthDate,
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
        'birth_date': birthDate.toIso8601String().split('T').first,
        'avatar': avatar,
        'music_enabled': musicEnabled ? 1 : 0,
        'vibration_enabled': vibrationEnabled ? 1 : 0,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory ChildProfile.fromMap(Map<String, dynamic> map) => ChildProfile(
        id: map['id'] as String,
        userId: map['user_id'] as String,
        displayName: map['display_name'] as String,
        birthDate: DateTime.parse(map['birth_date'] as String),
        avatar: map['avatar'] as String,
        musicEnabled: (map['music_enabled'] ?? 1) == 1,
        vibrationEnabled: (map['vibration_enabled'] ?? 1) == 1,
        createdAt: DateTime.parse(map['created_at'] as String),
        updatedAt: DateTime.parse(map['updated_at'] as String),
      );

  /// Creates a ChildProfile from Supabase JSON (booleans, not ints).
  factory ChildProfile.fromSupabase(Map<String, dynamic> map) => ChildProfile(
        id: map['id'] as String,
        userId: map['parent_user_id'] as String,
        displayName: map['display_name'] as String,
        birthDate: DateTime.parse(map['birth_date'] as String),
        avatar: map['avatar'] as String,
        musicEnabled: map['music_enabled'] as bool? ?? true,
        vibrationEnabled: map['vibration_enabled'] as bool? ?? true,
        createdAt: DateTime.parse(map['created_at'] as String),
        updatedAt: DateTime.parse(map['updated_at'] as String),
      );

  Map<String, dynamic> toSupabase() => {
        'id': id,
        'parent_user_id': userId,
        'display_name': displayName,
        'birth_date': birthDate.toIso8601String().split('T').first,
        'avatar': avatar,
        'music_enabled': musicEnabled,
        'vibration_enabled': vibrationEnabled,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };
}
