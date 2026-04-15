/// Represents a child's profile including learning preferences and
/// gameplay comfort settings (music, vibration).
class ChildProfile {
  final String id;
  final String userId;
  final String name;
  final int age;
  final String avatar;
  final bool musicEnabled;
  final bool vibrationEnabled;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ChildProfile({
    required this.id,
    required this.userId,
    required this.name,
    required this.age,
    required this.avatar,
    this.musicEnabled = true,
    this.vibrationEnabled = true,
    required this.createdAt,
    required this.updatedAt,
  });

  ChildProfile copyWith({
    String? name,
    int? age,
    String? avatar,
    bool? musicEnabled,
    bool? vibrationEnabled,
  }) {
    return ChildProfile(
      id: id,
      userId: userId,
      name: name ?? this.name,
      age: age ?? this.age,
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
        'name': name,
        'age': age,
        'avatar': avatar,
        'music_enabled': musicEnabled ? 1 : 0,
        'vibration_enabled': vibrationEnabled ? 1 : 0,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory ChildProfile.fromMap(Map<String, dynamic> map) => ChildProfile(
        id: map['id'] as String,
        userId: map['user_id'] as String,
        name: map['name'] as String,
        age: map['age'] as int,
        avatar: map['avatar'] as String,
        musicEnabled: (map['music_enabled'] ?? 1) == 1,
        vibrationEnabled: (map['vibration_enabled'] ?? 1) == 1,
        createdAt: DateTime.parse(map['created_at'] as String),
        updatedAt: DateTime.parse(map['updated_at'] as String),
      );

  /// Creates a ChildProfile from Supabase JSON (booleans, not ints).
  factory ChildProfile.fromSupabase(Map<String, dynamic> map) => ChildProfile(
        id: map['id'] as String,
        userId: map['user_id'] as String,
        name: map['name'] as String,
        age: map['age'] as int,
        avatar: map['avatar'] as String,
        musicEnabled: map['music_enabled'] as bool? ?? true,
        vibrationEnabled: map['vibration_enabled'] as bool? ?? true,
        createdAt: DateTime.parse(map['created_at'] as String),
        updatedAt: DateTime.parse(map['updated_at'] as String),
      );

  Map<String, dynamic> toSupabase() => {
        'id': id,
        'user_id': userId,
        'name': name,
        'age': age,
        'avatar': avatar,
        'music_enabled': musicEnabled,
        'vibration_enabled': vibrationEnabled,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };
}
