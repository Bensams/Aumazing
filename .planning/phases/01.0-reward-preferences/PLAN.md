# Phase 01.0: Reward Preferences System

## Objective
Add a comprehensive reward preferences system that allows parents to customize celebration effects for their child, with per-child profile storage and automatic reward display after game completion.

## Requirements

### Core Functionality
1. **Reward Options**: Balloons, Fireworks, Bubbles, Candy, Random
2. **Random Mode**: App picks random reward type each time child completes a game
3. **Interactive Rewards**: Children can tap/pop the reward effects
4. **Default**: If skipped during setup, use "Bubbles" as safe default
5. **Storage**: Per-child profile with offline-first pattern (SQLite → Supabase)

### Additional Game Improvements
1. **Match It**: Convert to drag-and-drop interaction
2. **My Turn Your Turn (Buddy)**: 
   - Add voice over prompts
   - Detect and penalize when child presses during buddy's turn

### UI Locations
1. **Child Profile Setup**: Add reward preference selection step
2. **Parent Settings (SettingsModal)**: Allow changing reward preference
3. **Game Completion Flow**: Show reward animation first, then completion dialog

### Database Schema Changes
- SQLite: Add `reward_preference` (TEXT) and `use_random_reward` (INTEGER) to children table
- Supabase: Add `reward_preference` (TEXT) and `use_random_reward` (BOOLEAN) to children table

## Implementation Plan

### 1. Data Layer

#### 1.1 Update ChildProfile Model
**File**: `lib/model/child_profile.dart`
**Changes**:
- Add `RewardPreference` enum with values: balloons, fireworks, bubbles, candy, random
- Add `rewardPreference` field (default: bubbles)
- Add `useRandomReward` field (default: false)
- Update `copyWith()`, `toMap()`, `fromMap()` methods
- Update constructor with new fields

#### 1.2 Update Local Database
**File**: `lib/core/services/local_db_service.dart`
**Changes**:
- Increment `_dbVersion` to 5
- Add migration function `migrateChildrenTableToRewardPreferenceSchema()`
- Add columns: `reward_preference TEXT DEFAULT 'bubbles'`, `use_random_reward INTEGER DEFAULT 0`
- Update `upsertChild()` to include new fields
- Update `getChildren()` to parse new fields

#### 1.3 Update ChildRepository
**File**: `lib/core/repositories/child_repository.dart`
**Changes**:
- Add `rewardPreference` and `useRandomReward` parameters to `createChild()`
- Add `updateRewardPreference()` method
- Update `updateChild()` to include new fields

#### 1.4 Update ChildProvider
**File**: `lib/providers/child_provider.dart`
**Changes**:
- Add `rewardPreference` getter
- Add `useRandomReward` getter
- Add `updateRewardPreference()` method
- Add `updateUseRandomReward()` method

### 2. Supabase Migration

#### 2.1 Create Migration
**File**: Create SQL migration for Supabase
```sql
ALTER TABLE children 
ADD COLUMN IF NOT EXISTS reward_preference TEXT DEFAULT 'bubbles',
ADD COLUMN IF NOT EXISTS use_random_reward BOOLEAN DEFAULT FALSE;
```

### 3. Reward Effect Widgets

#### 3.1 Create Reward Type Enum
**File**: `lib/features/rewards/reward_type.dart`
```dart
enum RewardType {
  balloons,
  fireworks,
  bubbles,
  candy,
}
```

#### 3.2 Create Base Reward Effect Widget
**File**: `lib/features/rewards/widgets/base_reward_effect.dart`
- Abstract base class for all reward effects
- Common properties: onComplete, onItemPopped, duration
- Common methods: start(), stop(), dispose()

#### 3.3 Create Balloons Reward Widget
**File**: `lib/features/rewards/widgets/balloons_reward.dart`
- Animated floating balloons in various colors (red, blue, yellow, green, pink, orange)
- Different sizes and patterns (stars, polka dots, checkered, stripes)
- Balloons float up from bottom with slight horizontal drift
- Tap to pop with particle burst effect
- Reference: Balloons should be colorful with patterns like user reference image

#### 3.4 Create Fireworks Reward Widget
**File**: `lib/features/rewards/widgets/fireworks_reward.dart`
- Rockets at bottom that launch and explode into stars
- Various colors: pink, blue, green, yellow, purple
- Different rocket patterns (stripes, polka dots)
- Tap rockets to trigger early explosion
- Stars burst and fade out
- Reference: Colorful rockets with stars like user reference image

#### 3.5 Create Bubbles Reward Widget
**File**: `lib/features/rewards/widgets/bubbles_reward.dart`
- Transparent bubbles floating up from bottom
- Various sizes and iridescent colors
- Subtle wobble animation
- Tap to pop with splash effect
- Gentle and calming (safe default for sensory-sensitive children)

#### 3.6 Create Candy Reward Widget
**File**: `lib/features/rewards/widgets/candy_reward.dart`
- Colorful candies (lollipops, jelly beans, wrapped candy) falling from top
- Various candy types: swirl lollipops, gummy bears, candy canes
- Rotate and drift while falling
- Tap to collect/eat with sparkle effect
- Reference: Colorful candies like user reference image

#### 3.7 Create Reward Selection Helper
**File**: `lib/features/rewards/reward_selector.dart`
```dart
class RewardSelector {
  static RewardType getRewardForChild(ChildProfile profile) {
    if (profile.useRandomReward) {
      return RewardType.values[Random().nextInt(RewardType.values.length)];
    }
    return profile.rewardPreference;
  }
}
```

### 4. Reward Overlay

#### 4.1 Create Reward Overlay Widget
**File**: `lib/features/rewards/widgets/reward_overlay.dart`
```dart
class RewardOverlay extends StatefulWidget {
  final RewardType rewardType;
  final VoidCallback onComplete;
  final VoidCallback? onAllPopped;
  final int minDisplayDurationMs;
}
```
- Shows full-screen reward effect
- Auto-dismisses after minDisplayDuration OR when all items are popped (if onAllPopped provided)
- Semi-transparent background
- "Continue" button appears after min duration

### 5. UI Integration

#### 5.1 Update ChildProfileSetupScreen
**File**: `lib/features/splash/auth/child_profile_setup_screen.dart`
**Changes**:
- Add new step/page for reward preference selection
- Show visual preview of each reward type
- Option to skip (defaults to bubbles)
- Include "Random" toggle

#### 5.2 Update SettingsModal
**File**: `lib/features/home/home_screen.dart` (SettingsModal class)
**Changes**:
- Add "Reward Settings" section in modal
- Dropdown/selector for reward preference
- Toggle for "Use Random Reward"
- Visual preview of selected reward

#### 5.3 Create Reward Preference Selector Widget
**File**: `lib/features/rewards/widgets/reward_preference_selector.dart`
- Grid of reward type options with icons/previews
- Each option shows mini animation or icon
- "Random" option with shuffle icon
- Selection highlight

### 6. Game Integration

#### 6.1 Update MatchItScreen
**File**: `lib/features/games/match_it/match_it_screen.dart`
**Changes**:
- Show RewardOverlay before completion dialog
- Get child's reward preference from ChildProvider
- Convert to drag-and-drop interaction
- Update completion flow

#### 6.2 Update CopyMeScreen
**File**: `lib/features/games/copy_me/copy_me_screen.dart`
**Changes**:
- Show RewardOverlay before completion dialog
- Use child's reward preference

#### 6.3 Update DoWhatISayScreen
**File**: `lib/features/games/do_what_i_say/do_what_i_say_screen.dart`
**Changes**:
- Show RewardOverlay before completion dialog
- Use child's reward preference

#### 6.4 Update MyTurnYourTurnScreen
**File**: `lib/features/games/my_turn_your_turn/my_turn_your_turn_screen.dart`
**Changes**:
- Show RewardOverlay before completion dialog
- Add voice over prompts for turn instructions
- Add logic to detect child pressing during buddy's turn
- Increment error count when child presses out of turn
- Use child's reward preference

#### 6.5 Update PreAssessmentResultScreen
**File**: `lib/features/pre_assessment/pre_assessment_result_screen.dart`
**Changes**:
- Replace existing GameCelebrationOverlay with new RewardOverlay
- Use child's reward preference

### 7. Match It Drag-and-Drop Improvements

#### 7.1 Update MatchItGame
**File**: `packages/game_core/lib/src/games/match_it/` or relevant location
**Changes**:
- Convert tap-to-match to drag-and-drop
- Add visual feedback during drag (scale up, shadow)
- Add snap-to-target when close
- Add bounce-back animation when dropped in wrong place
- Success: item snaps into place with satisfying animation

### 8. Testing & Verification

#### 8.1 Unit Tests
- RewardSelector logic
- RewardType parsing
- ChildProfile serialization with new fields

#### 8.2 Integration Tests
- Complete reward flow from game completion to dialog
- Reward preference persistence
- Random reward selection

#### 8.3 Manual Testing Checklist
- [ ] All 4 reward types display correctly
- [ ] Rewards are interactive (poppable)
- [ ] Random mode selects different rewards each time
- [ ] Settings persist after app restart
- [ ] Default is bubbles when skipped
- [ ] Match It drag-and-drop works smoothly
- [ ] Buddy turn error detection works
- [ ] Voice over plays in Buddy game

## Dependencies

### Flutter Packages
- `flutter`: Framework
- `provider`: State management
- `sqflite`: Local database
- `supabase_flutter`: Cloud sync

### No New Packages Required
All reward effects will use Flutter's built-in animation system (AnimatedBuilder, Tween, AnimationController) and CustomPainter where needed.

## Files to Modify

### Core/Data Layer (7 files)
1. `lib/model/child_profile.dart`
2. `lib/core/services/local_db_service.dart`
3. `lib/core/repositories/child_repository.dart`
4. `lib/providers/child_provider.dart`

### New Reward System (7 files)
5. `lib/features/rewards/reward_type.dart` (NEW)
6. `lib/features/rewards/reward_selector.dart` (NEW)
7. `lib/features/rewards/widgets/base_reward_effect.dart` (NEW)
8. `lib/features/rewards/widgets/balloons_reward.dart` (NEW)
9. `lib/features/rewards/widgets/fireworks_reward.dart` (NEW)
10. `lib/features/rewards/widgets/bubbles_reward.dart` (NEW)
11. `lib/features/rewards/widgets/candy_reward.dart` (NEW)
12. `lib/features/rewards/widgets/reward_overlay.dart` (NEW)
13. `lib/features/rewards/widgets/reward_preference_selector.dart` (NEW)

### UI Integration (5 files)
14. `lib/features/splash/auth/child_profile_setup_screen.dart`
15. `lib/features/home/home_screen.dart` (SettingsModal)
16. `lib/features/games/match_it/match_it_screen.dart`
17. `lib/features/games/copy_me/copy_me_screen.dart`
18. `lib/features/games/do_what_i_say/do_what_i_say_screen.dart`
19. `lib/features/games/my_turn_your_turn/my_turn_your_turn_screen.dart`
20. `lib/features/pre_assessment/pre_assessment_result_screen.dart`

### Supabase
21. New migration file for children table

## Total: ~21 files

## Acceptance Criteria

1. **Reward Preferences Setup**: Parent can select reward preference during child profile creation
2. **Reward Settings**: Parent can change reward preference in Settings modal
3. **Random Mode**: When enabled, a different reward type shows each time
4. **Interactive Rewards**: Children can tap/pop all reward items
5. **Default Behavior**: Skipping setup defaults to bubbles
6. **Game Integration**: All 4 games show reward before completion dialog
7. **Data Persistence**: Preferences persist across app restarts and sync to cloud
8. **Offline First**: Works without internet, syncs when connected
9. **Match It**: Successfully converted to drag-and-drop
10. **Buddy Game**: Voice over plays, errors detected for out-of-turn presses

## Notes

- Reward animations should be calming for sensory-sensitive children
- Bubbles (the default) is specifically chosen as a gentle option
- Animations should respect the child's `animationIntensity` setting
- Keep reward duration reasonable (3-5 seconds) to maintain engagement
- Ensure reward overlay doesn't block navigation indefinitely
