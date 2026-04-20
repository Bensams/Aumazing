# Aumazing Unified Gameplay Analytics System

A comprehensive, XGBoost-ready analytics layer for tracking child gameplay performance across all games in the Aumazing Flutter app.

## Overview

This system provides:
- **Standardized metrics** across all games
- **XGBoost-compatible data structure** for ML training
- **Firestore-ready serialization** for cloud storage
- **Real-time event tracking** for live monitoring
- **Modular architecture** for easy game integration

## Quick Start

### For Flame Games (e.g., Copy Me, Match It)

```dart
import 'package:game_core/game_core.dart';

class MyGame extends FlameGame
    with TapCallbacks, EnhancedGameplayAnalyticsMixin {
  
  @override
  Future<void> onLoad() async {
    await super.onLoad();
    
    // 1. Initialize analytics
    analyticsInitialize(
      gameId: 'my_game',
      childId: 'child_123',
      totalRounds: 5,
    );
    
    // 2. Start session
    analyticsStartSession();
  }
  
  void onCorrect() {
    analyticsRecordCorrect();
    analyticsRecordValidAction();
  }
  
  void onGameComplete() {
    analyticsCompleteSession();
    
    // Get Firestore-ready data
    final firestoreData = analyticsToFirestoreMap();
    // Save to Firestore...
    
    // Get XGBoost-ready data
    final xgboostData = analyticsToXgboostMap();
    // Export for ML training...
  }
}
```

### For Non-Flame Games (e.g., Do What I Say)

```dart
class MyGameController extends ChangeNotifier {
  final _analytics = GameMetricsController();
  
  void startGame() {
    _analytics.initialize(
      gameId: 'do_what_i_say',
      childId: 'child_123',
      totalRounds: 10,
    );
    _analytics.startSession();
  }
  
  void onCorrect() {
    _analytics.recordCorrect();
  }
  
  void endGame() {
    _analytics.completeSession();
    final data = _analytics.toFirestoreMap();
    // Save to Firestore...
  }
}
```

## Tracked Metrics

### Core Performance Metrics

| Metric | Type | Description | XGBoost Use |
|--------|------|-------------|-------------|
| `accuracy` | double (0-1) | correct / total interactions | Target variable for skill assessment |
| `taskCompletionRate` | double (0-1) | completedRounds / totalRounds | Target for completion prediction |
| `correctCount` | int | Number correct | Feature for performance analysis |
| `wrongCount` | int | Number incorrect | Feature for error pattern detection |

### Timing Metrics

| Metric | Type | Description | XGBoost Use |
|--------|------|-------------|-------------|
| `timeToFirstTouch` | double (seconds) | Time from stimulus to first screen touch | Feature for engagement assessment |
| `timeToFirstValidAction` | double (seconds) | Time to first task-related action | Feature for comprehension speed |
| `avgResponseTime` | double (seconds) | Average stimulus-to-touch time | Feature for processing speed |
| `avgValidResponseTime` | double (seconds) | Average stimulus-to-valid-action time | Feature for task efficiency |
| `timeToCompletion` | double (seconds) | Total session duration | Feature for endurance/persistence |

### Assistance Metrics

| Metric | Type | Description | XGBoost Use |
|--------|------|-------------|-------------|
| `hintCount` | int | Hints provided | Feature for help needed |
| `promptCount` | int | Prompts given | Feature for guidance dependency |
| `retryCount` | int | Retries/attempts | Feature for persistence |
| `promptDependencyScore` | double | Calculated dependency metric | Feature for independence level |
| `assistanceLevel` | categorical | independent/minimal/guided | Target for recommendation |

### Engagement Metrics

| Metric | Type | Description | XGBoost Use |
|--------|------|-------------|-------------|
| `idleTimeSeconds` | int | Time without interaction | Feature for attention/engagement |
| `randomTouchCount` | int | Non-task touches | Feature for exploratory behavior |
| `offTaskActionCount` | int | Distracted actions | Feature for focus assessment |
| `earlyExit` | boolean | Exited before completion | Feature for persistence |

### Progress Metrics

| Metric | Type | Description | XGBoost Use |
|--------|------|-------------|-------------|
| `improvementScore` | double (-1 to 1) | Performance trend | Target for learning rate |
| `consistencyScore` | double (0-1) | Performance stability | Feature for reliability |

## XGBoost Data Preparation

### Firestore Structure

```javascript
// Collection: gameplay_sessions
{
  // Identification
  game_id: "copy_me",
  session_id: "copy_me_child_123_1698765432_4567",
  child_id: "child_123",
  
  // Timing
  start_time: "2024-01-15T10:30:00.000Z",
  end_time: "2024-01-15T10:35:24.000Z",
  duration_seconds: 324,
  
  // Performance
  accuracy: 0.75,
  task_completion_rate: 0.8,
  correct_count: 12,
  wrong_count: 4,
  
  // Response Times
  time_to_first_touch: 2.3,
  time_to_first_valid_action: 4.1,
  avg_response_time: 3.5,
  avg_valid_response_time: 5.2,
  time_to_completion: 324.0,
  
  // Assistance
  hint_count: 3,
  prompt_count: 5,
  retry_count: 2,
  prompt_dependency_score: 1.6,
  assistance_level: "minimal",
  
  // Engagement
  idle_time_seconds: 45,
  random_touch_count: 8,
  off_task_action_count: 3,
  early_exit: false,
  
  // Progress
  improvement_score: 0.25,
  consistency_score: 0.82,
  
  // Game-Specific
  game_specific: {
    overall_imitation_success: 0.8,
    total_demonstrations_needed: 5,
    sequence_lengths: [1, 2, 2, 3, 3]
  },
  
  // Round Details (optional, for deep analysis)
  rounds: [
    {
      round_number: 1,
      accuracy: 1.0,
      time_to_completion: 45.0,
      hint_count: 0,
      is_successful: true,
      game_specific: {
        sequence_length: 1,
        imitation_success: 1.0
      }
    },
    // ... more rounds
  ],
  
  recorded_at: "2024-01-15T10:35:24.000Z"
}
```

### XGBoost Preprocessing

```python
import pandas as pd
import xgboost as xgb
from sklearn.preprocessing import OneHotEncoder
from sklearn.model_selection import train_test_split

# Load data from Firestore/CSV
df = pd.read_csv('gameplay_sessions.csv')

# One-hot encode categorical features
df = pd.get_dummies(df, columns=['assistance_level', 'game_id'])

# Select features
features = [
    'duration_seconds',
    'correct_count',
    'wrong_count',
    'retry_count',
    'hint_count',
    'prompt_count',
    'prompt_dependency_score',
    'avg_response_time',
    'avg_valid_response_time',
    'time_to_first_touch',
    'time_to_first_valid_action',
    'idle_time_seconds',
    'random_touch_count',
    'off_task_action_count',
    'early_exit',
    'improvement_score',
    'consistency_score',
    # One-hot encoded
    'assistance_level_independent',
    'assistance_level_minimal',
    'assistance_level_guided',
]

# Target variables (different models for different purposes)
# Model 1: Predict needed assistance level
X = df[features]
y_assistance = df[['assistance_level_independent', 
                   'assistance_level_minimal', 
                   'assistance_level_guided']]

# Model 2: Predict completion rate
y_completion = df['task_completion_rate']

# Model 3: Predict accuracy
y_accuracy = df['accuracy']

# Train/test split
X_train, X_test, y_train, y_test = train_test_split(X, y_assistance, test_size=0.2)

# Train XGBoost model
model = xgb.XGBClassifier(
    objective='multi:softprob',
    num_class=3,
    max_depth=6,
    learning_rate=0.1,
    n_estimators=100
)
model.fit(X_train, y_train)

# Predict assistance level for new child
new_session = X_test.iloc[0:1]
prediction = model.predict(new_session)
probabilities = model.predict_proba(new_session)
```

### CSV Export

```dart
// Export all sessions for batch ML training
void exportForTraining(List<GameSessionMetrics> sessions) {
  final rows = sessions.map((s) => s.toXgboostMap()).toList();
  
  // Convert to CSV using csv package
  // Headers from first row keys
  // Values as comma-separated
  
  // Upload to ML pipeline
}
```

## Game-Specific Metric Mapping

### Copy Me (Sequence Memory)

```dart
// Game-specific metrics to track
analyticsAddGameSpecificMetric('imitation_success', 0.8);
analyticsAddGameSpecificMetric('demonstrations_needed', 3);
analyticsAddGameSpecificMetric('avg_sequence_length', 3.2);
analyticsAddGameSpecificMetric('pattern_complexity', 'medium');

// Per-round data
analyticsAddRoundData('sequence_length', 4);
analyticsAddRoundData('pattern_correct', true);
```

### Match It / Sorting

```dart
analyticsAddGameSpecificMetric('avg_match_time', 4.5);
analyticsAddGameSpecificMetric('category_accuracy', 0.9);
analyticsAddGameSpecificMetric('color_confusion_count', 2);

analyticsAddRoundData('item_type', 'shape');
analyticsAddRoundData('distractor_count', 3);
```

### Do What I Say (Instruction Following)

```dart
analyticsAddGameSpecificMetric('instruction_accuracy', 0.75);
analyticsAddGameSpecificMetric('repeated_instruction_count', 5);
analyticsAddGameSpecificMetric('complex_instruction_success', 0.6);

analyticsAddRoundData('instruction_complexity', 2); // 1-3 scale
analyticsAddRoundData('action_delay_seconds', 3.5);
```

### My Turn, Your Turn (Turn Taking)

```dart
analyticsAddGameSpecificMetric('waiting_tolerance_seconds', 8.5);
analyticsAddGameSpecificMetric('interrupt_frequency', 0.3);
analyticsAddGameSpecificMetric('turn_completion_rate', 0.85);

analyticsAddRoundData('wait_time', 5);
analyticsAddRoundData('interrupted', false);
```

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     Game Layer (Your Game)                     │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐            │
│  │  Copy Me    │  │  Match It   │  │  Do What I  │            │
│  │             │  │             │  │  Say        │            │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘            │
│         │                │                │                    │
│         └────────────────┼────────────────┘                    │
│                        │                                       │
├────────────────────────┼───────────────────────────────────────┤
│      Analytics Layer   │                                       │
│  ┌─────────────────────┴─────────────────────┐                  │
│  │   EnhancedGameplayAnalyticsMixin         │  (Flame Games)  │
│  │   GameMetricsController                  │  (Non-Flame)   │
│  └─────────────────────┬─────────────────────┘                  │
│                        │                                       │
│         ┌──────────────┼──────────────┐                       │
│         │              │              │                       │
│  ┌──────▼──────┐ ┌────▼─────┐ ┌──────▼──────┐                │
│  │GameSession  │ │GameRound │ │ GameEvent   │                │
│  │Metrics      │ │Metrics   │ │ Tracker     │                │
│  └──────┬──────┘ └────┬─────┘ └──────┬──────┘                │
│         │             │            │                          │
└─────────┼─────────────┼────────────┼──────────────────────────┘
          │             │            │
          ▼             ▼            ▼
┌────────────────────────────────────────────────────────────────┐
│                    Data Storage Layer                          │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐            │
│  │  Firestore  │  │   Local     │  │  CSV Export │            │
│  │  (Real-time)│  │  (SQLite)   │  │  (Training) │            │
│  └─────────────┘  └─────────────┘  └─────────────┘            │
└────────────────────────────────────────────────────────────────┘
```

## API Reference

### EnhancedGameplayAnalyticsMixin

**Lifecycle Methods:**
- `analyticsInitialize()` - Set up session metadata
- `analyticsStartSession()` - Begin tracking
- `analyticsCompleteSession()` - End and calculate metrics
- `analyticsRecordExit()` - Mark early exit

**Round Methods:**
- `analyticsStartRound()` - Begin round tracking
- `analyticsCompleteRound()` - End round tracking
- `analyticsMarkCompleted()` - Mark session success

**Stimulus & Response:**
- `analyticsShowStimulus()` - Record stimulus presentation
- `analyticsRecordTouch()` - Record any screen touch
- `analyticsRecordValidAction()` - Record task-related action
- `analyticsHandleTapDown()` - Flame tap handler helper

**Performance:**
- `analyticsRecordCorrect()` - Record success
- `analyticsRecordWrong()` - Record error
- `analyticsRecordRetry()` - Record retry/reset

**Assistance:**
- `analyticsRecordHint()` - Record hint provided
- `analyticsRecordPrompt()` - Record prompt given

**Engagement:**
- `analyticsRecordIdleTime()` - Record inactivity
- `analyticsRecordOffTaskAction()` - Record distraction

**Data Export:**
- `analyticsToFirestoreMap()` - Firestore-compatible map
- `analyticsToXgboostMap()` - ML-ready flat map
- `analyticsExportEvents()` - Event log export

### GameMetricsController (Non-Flame)

Same API pattern but as a controller class:
- `initialize()` / `startSession()` / `completeSession()`
- `startRound()` / `completeRound()`
- `recordCorrect()` / `recordWrong()` / `recordRetry()`
- `recordHint()` / `recordPrompt()`
- `toFirestoreMap()` / `toXgboostMap()`

## Best Practices

1. **Always call `analyticsInitialize()` before `analyticsStartSession()`**

2. **Call `analyticsShowStimulus()` whenever presenting new information**
   - Before each round
   - Before each new task
   - Before instructions

3. **Distinguish between touches and valid actions**
   - `analyticsRecordTouch()` for any screen contact
   - `analyticsRecordValidAction()` only for task-progressing actions

4. **Record hints and prompts accurately**
   - These drive the `promptDependencyScore` and `assistanceLevel`

5. **Add game-specific metrics for richer analysis**
   - Use `analyticsAddGameSpecificMetric()` for unique indicators

6. **Handle early exits gracefully**
   - Call `analyticsRecordExit()` when user leaves before completion

7. **Export regularly for ML training**
   - Batch export sessions weekly/monthly for model retraining

## Testing

```dart
void main() {
  test('analytics calculates metrics correctly', () {
    final metrics = GameSessionMetrics(
      gameId: 'test',
      sessionId: 'test_123',
      childId: 'child_1',
      totalRounds: 5,
    );
    
    metrics.startSession();
    
    // Simulate gameplay
    metrics.recordCorrect();
    metrics.recordCorrect();
    metrics.recordWrong();
    
    metrics.endSession();
    
    expect(metrics.accuracy, equals(2/3));
    expect(metrics.correctCount, equals(2));
    expect(metrics.wrongCount, equals(1));
  });
}
```

## License

Part of the Aumazing app - internal use only.
