# Testing

## Current Test State

**Status**: Minimal test coverage
**Files**: 3 test files in `apps/main_app/test/`
**Coverage**: Framework setup only

## Test Structure

```
test/
└── widget_test.dart           # Default Flutter test
```

**Content**:
- Basic Flutter framework test
- Only verifies that the app builds and pumps

## Test Dependencies

```yaml
dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^5.0.0
```

## Testing Gaps

### No Unit Tests For:
- `AssessmentService` (scoring algorithms)
- `ScoringService` (calculation logic)
- `AuthService` (authentication flows)
- `SyncService` (synchronization logic)
- `LocalDbService` (database operations)
- `ConnectivityService` (network monitoring)

### No Widget Tests For:
- `LoginScreen`
- `SplashScreen`
- `HomeScreen`
- Game screens (`MatchItScreen`, `CopyMeScreen`, etc.)
- Assessment screens
- `ChildProfileSetupScreen`

### No Integration Tests For:
- End-to-end assessment flow
- Offline-first data synchronization
- Authentication flows (login, OTP, reset)
- Game completion and scoring

## Recommended Test Strategy

### 1. Unit Tests (Priority: High)

**Services**:
```dart
// test/services/scoring_service_test.dart
group('ScoringService', () {
  test('calculates correct score for perfect match', () {
    final service = ScoringService();
    final result = service.calculate(perfectSession);
    expect(result.score, equals(100));
  });
  
  test('adjusts difficulty based on history', () {
    // Test difficulty algorithm
  });
});
```

**Repositories**:
- Mock SQLite operations
- Test offline-first write pattern
- Test sync queue behavior

### 2. Widget Tests (Priority: High)

**Critical User Flows**:
- Authentication (login, OTP, forgot password)
- Child profile creation
- Assessment navigation
- Game interaction

### 3. Integration Tests (Priority: Medium)

**End-to-End Scenarios**:
```dart
// integration_test/app_test.dart
testWidgets('complete assessment flow', (tester) async {
  await app.launch();
  await tester.tap(find.text('Start Assessment'));
  // Complete each assessment step
  expect(find.text('Assessment Complete'), findsOneWidget);
});
```

## Testing Challenges

### Flame Games
- Complex to widget test
- May require custom test harness
- Consider screenshot/golden tests for visual regression

### Offline-First Logic
- Requires mocking connectivity states
- Test both online and offline scenarios
- Verify sync behavior when connectivity returns

### Authentication
- Mock Supabase responses
- Test token refresh logic
- Test guest mode → authenticated transition

## CI/CD Considerations

**Not Currently Configured**

When implementing CI/CD:
1. Run `flutter test` on PR
2. Enforce minimum coverage thresholds
3. Run integration tests on merge to main
4. Generate coverage reports
