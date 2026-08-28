import 'package:shared_audio/shared_audio.dart';

import '../core/child_profile_policy.dart';
import '../features/stars/star_catalogue.dart';

/// Reward preference options for celebration effects.
/// Values: balloons, fireworks, bubbles, candy, random
enum RewardPreference {
  balloons('balloons'),
  fireworks('fireworks'),
  bubbles('bubbles'),
  candy('candy'),
  random('random');

  final String value;
  const RewardPreference(this.value);

  static RewardPreference fromString(String? value) {
    if (value == null) return bubbles;
    return RewardPreference.values.firstWhere(
      (e) => e.value == value,
      orElse: () => bubbles,
    );
  }

  /// Get a random reward type (excluding 'random' itself)
  static RewardPreference get randomType {
    final values = [balloons, fireworks, bubbles, candy];
    return values[DateTime.now().millisecond % values.length];
  }
}

/// Child's sex/gender selection.
/// Values: male, female, preferNotToSay
enum ChildSex {
  male('male'),
  female('female'),
  preferNotToSay('prefer_not_to_say');

  final String value;
  const ChildSex(this.value);

  static ChildSex? fromString(String? value) {
    if (value == null) return null;
    return ChildSex.values.firstWhere(
      (e) => e.value == value,
      orElse: () => ChildSex.preferNotToSay,
    );
  }
}

/// Avatar identifier to emoji mapping.
/// Maps stored avatar strings (e.g., 'avatar_1') to display emojis.
class AvatarMapper {
  static const _avatarMap = {
    'avatar_1': '🐻',
    'avatar_2': '🐼',
    'avatar_3': '🦊',
    'avatar_4': '🐨',
    'avatar_5': '🐸',
    'avatar_6': '🦄',
    'avatar_7': '🐙',
    'avatar_8': '🐰',
    '🐻': '🐻',
    '🐼': '🐼',
    '🦊': '🦊',
    '🐨': '🐨',
    '🐸': '🐸',
    '🦄': '🦄',
    '🐙': '🐙',
    '🐰': '🐰',
  };

  static String toEmoji(String? avatarId) {
    if (avatarId == null) return '🐻';
    return _avatarMap[avatarId] ?? '🐻';
  }
}

/// Represents a child's profile including learning preferences and
/// gameplay comfort settings (music, vibration).
class ChildProfile {
  final String id;
  final String userId;
  final String displayName;
  final DateTime? birthDate;
  final int? legacyAgeYears;
  final String avatar;
  final ChildSex? sex;
  final bool musicEnabled;
  final double musicVolume;

  /// Which background-music category the parent picked, as a [BgmCategory] key.
  ///
  /// One track from this category is chosen per session and loops. An unknown
  /// value (a profile written by a build that shipped a category this build
  /// does not have) falls back to the default rather than failing.
  final String musicCategory;
  final double sfxVolume;
  final bool vibrationEnabled;
  final double animationIntensity;
  final double promptSpeed;
  final bool sensoryPreferencesSet;
  final RewardPreference rewardPreference;
  final bool useRandomReward;

  /// Which character guides this child, as a [ChildCharacter.id].
  ///
  /// Chosen deliberately by the parent during setup and changeable afterwards.
  /// **Never derived from [sex]** — that field is assessment data, and inferring
  /// a companion from it is the exact bias this feature removes (STAR-A3).
  final String characterId;

  /// The costume currently worn, as a [Costume.id]. `'none'` is the
  /// character's own clothes and is always available.
  final String equippedCostume;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// The chosen character, resolved. Unknown ids fall back rather than throw:
  /// a profile written by a build that shipped a character this build does not
  /// have must still open.
  ChildCharacter get character => ChildCharacter.fromId(characterId);

  /// The costume currently worn, resolved. Same fallback reasoning.
  Costume get costume => Costume.fromId(equippedCostume);

  /// Artwork of this child's character wearing their costume.
  String get characterArtAsset => costume.assetFor(character);

  const ChildProfile({
    required this.id,
    required this.userId,
    required this.displayName,
    required this.birthDate,
    this.legacyAgeYears,
    required this.avatar,
    this.sex,
    this.musicEnabled = true,
    this.musicVolume = 0.5,
    this.musicCategory = kDefaultBgmCategory,
    this.sfxVolume = 0.7,
    this.vibrationEnabled = true,
    this.animationIntensity = 1.0,
    this.promptSpeed = 1.0,
    this.sensoryPreferencesSet = false,
    this.rewardPreference = RewardPreference.bubbles,
    this.useRandomReward = false,
    this.characterId = 'bps',
    this.equippedCostume = 'none',
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

  /// Get the avatar as an emoji for display.
  String get avatarEmoji => AvatarMapper.toEmoji(avatar);

  @Deprecated('Use ageYears() instead.')
  int get age => ageYears();

  /// Returns sensory settings as a map (used by scoring/assessment).
  Map<String, dynamic> get sensorySettingsMap => {
        'music_enabled': musicEnabled,
        'music_volume': musicVolume,
        'music_category': musicCategory,
        'sfx_volume': sfxVolume,
        'vibration_enabled': vibrationEnabled,
        'animation_intensity': animationIntensity,
        'prompt_speed': promptSpeed,
      };

  ChildProfile copyWith({
    String? displayName,
    DateTime? birthDate,
    bool clearBirthDate = false,
    String? avatar,
    ChildSex? sex,
    bool clearSex = false,
    bool? musicEnabled,
    double? musicVolume,
    String? musicCategory,
    double? sfxVolume,
    bool? vibrationEnabled,
    double? animationIntensity,
    double? promptSpeed,
    bool? sensoryPreferencesSet,
    RewardPreference? rewardPreference,
    bool? useRandomReward,
    String? characterId,
    String? equippedCostume,
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
      sex: clearSex ? null : sex ?? this.sex,
      musicEnabled: musicEnabled ?? this.musicEnabled,
      musicVolume: musicVolume ?? this.musicVolume,
      musicCategory: musicCategory ?? this.musicCategory,
      sfxVolume: sfxVolume ?? this.sfxVolume,
      vibrationEnabled: vibrationEnabled ?? this.vibrationEnabled,
      animationIntensity: animationIntensity ?? this.animationIntensity,
      promptSpeed: promptSpeed ?? this.promptSpeed,
      sensoryPreferencesSet: sensoryPreferencesSet ?? this.sensoryPreferencesSet,
      rewardPreference: rewardPreference ?? this.rewardPreference,
      useRandomReward: useRandomReward ?? this.useRandomReward,
      characterId: characterId ?? this.characterId,
      equippedCostume: equippedCostume ?? this.equippedCostume,
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
    'sex': sex?.value,
    'music_enabled': musicEnabled ? 1 : 0,
    'music_volume': musicVolume,
    'music_category': musicCategory,
    'sfx_volume': sfxVolume,
    'vibration_enabled': vibrationEnabled ? 1 : 0,
    'animation_intensity': animationIntensity,
    'prompt_speed': promptSpeed,
    'sensory_preferences_set': sensoryPreferencesSet ? 1 : 0,
    'reward_preference': rewardPreference.value,
    'use_random_reward': useRandomReward ? 1 : 0,
    'character_id': characterId,
    'equipped_costume': equippedCostume,
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
      sex: ChildSex.fromString(map['sex'] as String?),
      musicEnabled: (map['music_enabled'] ?? 1) == 1,
      musicVolume: (map['music_volume'] as num?)?.toDouble() ?? 0.5,
      musicCategory:
          (map['music_category'] as String?) ?? kDefaultBgmCategory,
      sfxVolume: (map['sfx_volume'] as num?)?.toDouble() ?? 0.7,
      vibrationEnabled: (map['vibration_enabled'] ?? 1) == 1,
      animationIntensity: (map['animation_intensity'] as num?)?.toDouble() ?? 1.0,
      promptSpeed: (map['prompt_speed'] as num?)?.toDouble() ?? 1.0,
      sensoryPreferencesSet: (map['sensory_preferences_set'] ?? 0) == 1,
      rewardPreference: RewardPreference.fromString(map['reward_preference'] as String?),
      useRandomReward: (map['use_random_reward'] ?? 0) == 1,
      characterId: (map['character_id'] as String?) ?? 'bps',
      equippedCostume: (map['equipped_costume'] as String?) ?? 'none',
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
    sex: ChildSex.fromString(map['sex'] as String?),
    musicEnabled: map['music_enabled'] as bool? ?? true,
    musicVolume: (map['music_volume'] as num?)?.toDouble() ?? 0.5,
    musicCategory: (map['music_category'] as String?) ?? kDefaultBgmCategory,
    sfxVolume: (map['sfx_volume'] as num?)?.toDouble() ?? 0.7,
    vibrationEnabled: map['vibration_enabled'] as bool? ?? true,
    animationIntensity: (map['animation_intensity'] as num?)?.toDouble() ?? 1.0,
    promptSpeed: (map['prompt_speed'] as num?)?.toDouble() ?? 1.0,
    sensoryPreferencesSet: map['sensory_preferences_set'] as bool? ?? false,
    rewardPreference: RewardPreference.fromString(map['reward_preference'] as String?),
    useRandomReward: map['use_random_reward'] as bool? ?? false,
    characterId: (map['character_id'] as String?) ?? 'bps',
    equippedCostume: (map['equipped_costume'] as String?) ?? 'none',
    createdAt: DateTime.parse(map['created_at'] as String),
    updatedAt: DateTime.parse(map['updated_at'] as String),
  );

  Map<String, dynamic> toSupabase() => {
    'id': id,
    'parent_user_id': userId,
    'display_name': displayName,
    'birth_date': birthDate?.toIso8601String().split('T').first,
    'avatar': avatar,
    'sex': sex?.value,
    'music_enabled': musicEnabled,
    'music_volume': musicVolume,
    'music_category': musicCategory,
    'sfx_volume': sfxVolume,
    'vibration_enabled': vibrationEnabled,
    'animation_intensity': animationIntensity,
    'prompt_speed': promptSpeed,
    'sensory_preferences_set': sensoryPreferencesSet,
    'reward_preference': rewardPreference.value,
    'use_random_reward': useRandomReward,
    'character_id': characterId,
    'equipped_costume': equippedCostume,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };
}
