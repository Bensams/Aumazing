import 'dart:math';

import '../../model/child_profile.dart';

/// Reward type options for celebration effects.
/// Excludes 'random' from the actual effect types.
enum RewardType {
  balloons,
  fireworks,
  bubbles,
  candy;

  /// Get display name for the reward type
  String get displayName {
    switch (this) {
      case RewardType.balloons:
        return 'Balloons';
      case RewardType.fireworks:
        return 'Fireworks';
      case RewardType.bubbles:
        return 'Bubbles';
      case RewardType.candy:
        return 'Candy';
    }
  }

  /// Get icon/emoji for the reward type
  String get emoji {
    switch (this) {
      case RewardType.balloons:
        return '🎈';
      case RewardType.fireworks:
        return '🎆';
      case RewardType.bubbles:
        return '🫧';
      case RewardType.candy:
        return '🍬';
    }
  }
}

/// Helper class to select the appropriate reward type for a child
class RewardSelector {
  static final _random = Random();

  /// Get the reward type to display for a child
  ///
  /// If useRandomReward is true, returns a random RewardType
  /// Otherwise, returns the child's preferred reward preference
  /// (converting 'random' preference to an actual random type)
  static RewardType getRewardForChild(ChildProfile profile) {
    if (profile.useRandomReward || profile.rewardPreference == RewardPreference.random) {
      return RewardType.values[_random.nextInt(RewardType.values.length)];
    }
    return _preferenceToType(profile.rewardPreference);
  }

  /// Convert RewardPreference to RewardType
  /// Returns bubbles as safe default
  static RewardType _preferenceToType(RewardPreference preference) {
    switch (preference) {
      case RewardPreference.balloons:
        return RewardType.balloons;
      case RewardPreference.fireworks:
        return RewardType.fireworks;
      case RewardPreference.bubbles:
        return RewardType.bubbles;
      case RewardPreference.candy:
        return RewardType.candy;
      case RewardPreference.random:
        return RewardType.values[_random.nextInt(RewardType.values.length)];
    }
  }

  /// Get all available reward types (excluding random concept)
  static List<RewardType> get allTypes => RewardType.values;
}
