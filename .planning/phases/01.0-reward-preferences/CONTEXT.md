# Phase 01.0: Technical Context

## Existing Code Patterns

### Offline-First Data Pattern
```dart
// Local SQLite (always) → Sync to Supabase (when online + authenticated)
await _localDb.upsertEntity(entity, ownerId: userId, markPending: true);
if (!_isGuestMode) {
  _syncService.syncNow();
}
```

### ChildProfile Model Structure
- `id`: String UUID
- `userId`: String (owner)
- `displayName`: String
- `birthDate`: DateTime?
- `avatar`: String
- `sex`: ChildSex?
- `musicEnabled`: bool
- `vibrationEnabled`: bool
- `createdAt`: DateTime
- `updatedAt`: DateTime

### Database Schema Pattern
SQLite columns for children table:
```sql
id TEXT PRIMARY KEY,
user_id TEXT,
display_name TEXT NOT NULL,
birth_date TEXT,
avatar TEXT NOT NULL,
sex TEXT,
music_enabled INTEGER NOT NULL DEFAULT 1,
vibration_enabled INTEGER NOT NULL DEFAULT 1,
comfort_settings TEXT,
sync_status TEXT NOT NULL DEFAULT 'pending',
last_synced_at TEXT,
deleted_at TEXT,
updated_at TEXT NOT NULL,
local_created_at TEXT NOT NULL,
owner_id TEXT
```

## Key Files Reference

### Model
- `lib/model/child_profile.dart`: ChildProfile class, toMap(), fromMap()

### Data Layer
- `lib/core/services/local_db_service.dart`: SQLite operations, migrations
- `lib/core/repositories/child_repository.dart`: CRUD operations with sync
- `lib/providers/child_provider.dart`: UI state management

### UI
- `lib/features/splash/auth/child_profile_setup_screen.dart`: Child creation UI
- `lib/features/home/home_screen.dart`: SettingsModal for parent settings
- `lib/features/games/*/`: Game screens that need reward integration

## Animation Approach

Using Flutter's built-in animation:
- `AnimationController` for timing
- `AnimatedBuilder` for performance
- `Tween` for value interpolation
- `CustomPainter` for complex shapes (balloons, stars)
- GestureDetector for tap detection

## Reward Effect Design

### Balloons
- Colors: Red, Blue, Yellow, Green, Pink, Orange, Purple
- Patterns: Stars, Polka dots, Checkered, Stripes, Solid
- Animation: Float up with sine wave horizontal drift
- Interaction: Tap to pop (scale to 0 with particle burst)

### Fireworks
- Rockets: Launch from bottom, explode at apex
- Stars: Burst radially, fade while falling
- Colors: Pink, Blue, Green, Yellow, Purple, Orange
- Patterns: Striped rockets, solid rockets
- Interaction: Tap rocket to trigger early explosion

### Bubbles
- Transparent with iridescent shimmer
- Various sizes (small, medium, large)
- Animation: Float up with wobble
- Interaction: Tap to pop (splash ripple effect)

### Candy
- Types: Swirl lollipops, jelly beans, wrapped candy, gummy bears
- Colors: Pink, Blue, Green, Yellow, Orange, Red
- Animation: Fall from top with rotation
- Interaction: Tap to collect (sparkle effect)

## Game Integration Points

All games use this completion pattern:
```dart
void _onGameComplete({...}) {
  setState(() => _gameComplete = true);
  assessmentProvider.recordGameSession(...);
  _showCompletionDialog(...);  // Replace with reward + dialog
}
```

New flow:
```dart
void _onGameComplete({...}) {
  setState(() => _gameComplete = true);
  assessmentProvider.recordGameSession(...);
  _showRewardThenCompletion(...);
}

void _showRewardThenCompletion(...) {
  final rewardType = RewardSelector.getRewardForChild(childProvider.profile!);
  showDialog(
    barrierDismissible: false,
    builder: (_) => RewardOverlay(
      rewardType: rewardType,
      onComplete: () => _showCompletionDialog(...),
    ),
  );
}
```

## Drag-and-Drop for Match It

Use Flutter's built-in drag-and-drop:
- `Draggable` widget for draggable items
- `DragTarget` widget for drop zones
- Visual feedback: `feedback` parameter for drag preview
- Data transfer: Pass shape data via draggable

## Voice Over for Buddy Game

Use `shared_audio` package (already in project):
```dart
final audioService = context.read<AudioService>();
audioService.playVoiceOver('buddy_your_turn');
audioService.playVoiceOver('buddy_wait');
```

## Error Detection Pattern

In MyTurnYourTurn game:
```dart
enum TurnState { childTurn, buddyTurn, transition }

void onChildPress() {
  if (currentTurn == TurnState.buddyTurn) {
    // Wrong turn - increment error
    errorCount++;
    playErrorSound();
    showErrorFeedback();
  } else {
    // Correct turn - process normally
    processCorrectPress();
  }
}
```

## Supabase Migration

```sql
-- Add reward preference columns
ALTER TABLE children 
ADD COLUMN IF NOT EXISTS reward_preference TEXT DEFAULT 'bubbles';

ALTER TABLE children 
ADD COLUMN IF NOT EXISTS use_random_reward BOOLEAN DEFAULT FALSE;

-- Add check constraint for valid reward types
ALTER TABLE children
ADD CONSTRAINT valid_reward_preference 
CHECK (reward_preference IN ('balloons', 'fireworks', 'bubbles', 'candy', 'random'));
```

## Testing Strategy

1. **Unit Tests**: RewardSelector logic, serialization
2. **Widget Tests**: Reward effect rendering, tap handling
3. **Integration Tests**: Complete flow from game to reward to dialog
4. **Manual**: Visual verification of all reward types

## Commit Strategy

Following conventional commits:
- `feat(main_app): add reward preference to child profile model`
- `feat(main_app): add reward database migration`
- `feat(main_app): create balloon reward effect`
- `feat(main_app): create fireworks reward effect`
- `feat(main_app): create bubbles reward effect`
- `feat(main_app): create candy reward effect`
- `feat(main_app): add reward overlay for game completion`
- `feat(main_app): integrate rewards into all game screens`
- `feat(main_app): add reward preference to child setup and settings`
- `feat(game_core): convert match it to drag-and-drop`
- `feat(main_app): add voice over and error detection to buddy game`

## Risk Mitigation

1. **Sensory Sensitivity**: Bubbles as default is gentle; respect animationIntensity setting
2. **Performance**: Use AnimatedBuilder to avoid rebuilding entire widget tree
3. **Persistence**: Follow offline-first pattern strictly
4. **Compatibility**: Test on both mobile orientations
