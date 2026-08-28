# Child Birth Date Offline-First Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace age entry with a birth date picker, enforce 2 to 6 year validation, move child profile runtime reads to SQLite, and use Supabase `public.children` only as the remote sync target with startup preload routed through `loading_screen.dart`.

**Architecture:** Introduce a small child-profile policy helper for age derivation and validity checks, plus a bootstrap service that hydrates SQLite from Supabase when online and resolves startup destination from local state. Update the child model, repository, local DB, setup screen, home screen, and sync mapping to persist `birth_date` locally first and sync it later.

**Tech Stack:** Flutter, Provider, sqflite, Supabase Flutter, flutter_test

---

## File Map

### Existing files to modify

- `apps/main_app/lib/model/child_profile.dart`
  Runtime child model; replace canonical `age` storage with `birthDate` and derived age helpers.
- `apps/main_app/lib/core/services/local_db_service.dart`
  Local SQLite schema and CRUD for child records; store `display_name` and `birth_date`.
- `apps/main_app/lib/core/services/supabase_service.dart`
  Fetch and upsert against `public.children`.
- `apps/main_app/lib/core/services/sync_service.dart`
  Map local child rows to Supabase `public.children`.
- `apps/main_app/lib/core/repositories/child_repository.dart`
  Local-first create/update/get child operations using birth date.
- `apps/main_app/lib/providers/child_provider.dart`
  Load and cache child profile from SQLite only; stop fallback to auth metadata.
- `apps/main_app/lib/features/splash/loading_screen.dart`
  Startup preload owner; call bootstrap service and route from local state.
- `apps/main_app/lib/features/splash/auth/child_profile_setup_screen.dart`
  Replace age chips with birth date picker and validation.
- `apps/main_app/lib/features/home/home_screen.dart`
  Defensive dashboard gate; render derived age from local `birth_date`.
- `apps/main_app/test/features/home/home_screen_test.dart`
  Update fixtures and add invalid-profile routing coverage.

### New files to create

- `apps/main_app/lib/core/child_profile_policy.dart`
  Pure helper for age derivation, future-date checks, and dashboard eligibility.
- `apps/main_app/lib/core/services/child_bootstrap_service.dart`
  Online hydration + offline fallback + startup destination resolution.
- `apps/main_app/test/core/child_profile_policy_test.dart`
  Unit coverage for age derivation and validity boundaries.
- `apps/main_app/test/core/services/child_bootstrap_service_test.dart`
  Online/offline bootstrap and legacy-child routing coverage.
- `apps/main_app/test/features/splash/auth/child_profile_setup_screen_test.dart`
  Birth date validation and continue-blocking widget tests.
- `apps/main_app/test/features/splash/loading_screen_test.dart`
  Loading screen routing coverage through the bootstrap service seam.

## Task 1: Add Child Profile Policy Helpers

**Files:**
- Create: `apps/main_app/lib/core/child_profile_policy.dart`
- Test: `apps/main_app/test/core/child_profile_policy_test.dart`

- [ ] **Step 1: Write the failing unit tests for birth date rules**

```dart
import 'package:aumazing/core/child_profile_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('calculateAgeYears returns 2 on the second birthday', () {
    final today = DateTime(2026, 4, 20);
    final birthDate = DateTime(2024, 4, 20);

    expect(calculateAgeYears(birthDate, today: today), 2);
  });

  test('calculateAgeYears returns 6 before the seventh birthday', () {
    final today = DateTime(2026, 4, 20);
    final birthDate = DateTime(2019, 4, 21);

    expect(calculateAgeYears(birthDate, today: today), 6);
  });

  test('validateBirthDate rejects future dates', () {
    final today = DateTime(2026, 4, 20);
    final result = validateBirthDate(DateTime(2026, 4, 21), today: today);

    expect(result, ChildBirthDateValidation.futureDate);
  });

  test('validateBirthDate rejects children younger than two', () {
    final today = DateTime(2026, 4, 20);
    final result = validateBirthDate(DateTime(2025, 4, 21), today: today);

    expect(result, ChildBirthDateValidation.tooYoung);
  });

  test('validateBirthDate rejects children older than six', () {
    final today = DateTime(2026, 4, 20);
    final result = validateBirthDate(DateTime(2018, 4, 19), today: today);

    expect(result, ChildBirthDateValidation.tooOld);
  });

  test('validateBirthDate accepts children between two and six inclusive', () {
    final today = DateTime(2026, 4, 20);

    expect(
      validateBirthDate(DateTime(2020, 4, 20), today: today),
      ChildBirthDateValidation.valid,
    );
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd apps/main_app && flutter test test/core/child_profile_policy_test.dart`
Expected: FAIL with `Target of URI doesn't exist: 'package:aumazing/core/child_profile_policy.dart'`

- [ ] **Step 3: Write the minimal policy helper**

```dart
enum ChildBirthDateValidation {
  valid,
  missing,
  futureDate,
  tooYoung,
  tooOld,
}

int calculateAgeYears(DateTime birthDate, {DateTime? today}) {
  final now = today ?? DateTime.now();
  var years = now.year - birthDate.year;
  final hadBirthday =
      now.month > birthDate.month ||
      (now.month == birthDate.month && now.day >= birthDate.day);

  if (!hadBirthday) {
    years -= 1;
  }

  return years;
}

ChildBirthDateValidation validateBirthDate(
  DateTime? birthDate, {
  DateTime? today,
}) {
  if (birthDate == null) {
    return ChildBirthDateValidation.missing;
  }

  final now = today ?? DateTime.now();
  final dateOnlyNow = DateTime(now.year, now.month, now.day);
  final dateOnlyBirth = DateTime(birthDate.year, birthDate.month, birthDate.day);

  if (dateOnlyBirth.isAfter(dateOnlyNow)) {
    return ChildBirthDateValidation.futureDate;
  }

  final age = calculateAgeYears(dateOnlyBirth, today: dateOnlyNow);

  if (age < 2) {
    return ChildBirthDateValidation.tooYoung;
  }

  if (age > 6) {
    return ChildBirthDateValidation.tooOld;
  }

  return ChildBirthDateValidation.valid;
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd apps/main_app && flutter test test/core/child_profile_policy_test.dart`
Expected: PASS with 6 tests passed

- [ ] **Step 5: Commit**

```bash
git add apps/main_app/lib/core/child_profile_policy.dart apps/main_app/test/core/child_profile_policy_test.dart
git commit -m "feat(main_app): add child birth date policy"
```

## Task 2: Convert Child Model, Local DB, And Sync Mapping To Birth Date

**Files:**
- Modify: `apps/main_app/lib/model/child_profile.dart`
- Modify: `apps/main_app/lib/core/services/local_db_service.dart`
- Modify: `apps/main_app/lib/core/services/sync_service.dart`
- Modify: `apps/main_app/lib/core/repositories/child_repository.dart`
- Test: `apps/main_app/test/core/child_profile_policy_test.dart`

- [ ] **Step 1: Extend the unit test with a derived-age fixture shape**

```dart
import 'package:aumazing/model/child_profile.dart';

test('child profile derives age from birth date', () {
  final profile = ChildProfile(
    id: 'child-1',
    userId: 'user-1',
    displayName: 'Mika',
    birthDate: DateTime(2022, 4, 20),
    avatar: '🐻',
    createdAt: DateTime(2026, 4, 20),
    updatedAt: DateTime(2026, 4, 20),
  );

  expect(profile.ageYears(today: DateTime(2026, 4, 20)), 4);
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd apps/main_app && flutter test test/core/child_profile_policy_test.dart`
Expected: FAIL because `displayName`, `birthDate`, or `ageYears` do not exist yet

- [ ] **Step 3: Update the model, local DB fields, repository API, and child sync mapping**

```dart
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

  Map<String, dynamic> toMap() => {
        'id': id,
        'user_id': userId,
        'display_name': displayName,
        'birth_date': birthDate.toIso8601String(),
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
}
```

```dart
await db.execute('''
  CREATE TABLE ${LocalTables.children} (
    id TEXT PRIMARY KEY,
    user_id TEXT,
    display_name TEXT NOT NULL,
    birth_date TEXT NOT NULL,
    avatar TEXT NOT NULL,
    music_enabled INTEGER NOT NULL DEFAULT 1,
    vibration_enabled INTEGER NOT NULL DEFAULT 1,
    comfort_settings TEXT,
    $_syncColumns
  )
''');
```

```dart
Map<String, dynamic> _mapChildToSupabase(Map<String, dynamic> local) {
  return {
    'id': local['id'],
    'parent_user_id': local['user_id'],
    'display_name': local['display_name'],
    'birth_date': DateTime.parse(local['birth_date'] as String)
        .toIso8601String()
        .split('T')
        .first,
    'created_at': local['local_created_at'],
    'updated_at': local['updated_at'],
  };
}
```

```dart
Future<ChildProfile> createChild({
  required String displayName,
  required DateTime birthDate,
  required String avatar,
  bool musicEnabled = true,
  bool vibrationEnabled = true,
}) async {
  final now = DateTime.now();
  final userId = _effectiveUserId;

  final child = ChildProfile(
    id: _uuid.v4(),
    userId: userId,
    displayName: displayName,
    birthDate: birthDate,
    avatar: avatar,
    musicEnabled: musicEnabled,
    vibrationEnabled: vibrationEnabled,
    createdAt: now,
    updatedAt: now,
  );

  await _localDb.upsertChild(child, ownerId: userId, markPending: true);

  if (!_isGuestMode) {
    _syncService.syncNow();
  }

  return child;
}
```

- [ ] **Step 4: Run the test suite focused on child policy/model behavior**

Run: `cd apps/main_app && flutter test test/core/child_profile_policy_test.dart`
Expected: PASS with child profile derived-age coverage included

- [ ] **Step 5: Commit**

```bash
git add apps/main_app/lib/model/child_profile.dart apps/main_app/lib/core/services/local_db_service.dart apps/main_app/lib/core/services/sync_service.dart apps/main_app/lib/core/repositories/child_repository.dart apps/main_app/test/core/child_profile_policy_test.dart
git commit -m "feat(main_app): store child birth dates locally"
```

## Task 3: Add Bootstrap Service For Online Hydration And Offline Routing

**Files:**
- Create: `apps/main_app/lib/core/services/child_bootstrap_service.dart`
- Modify: `apps/main_app/lib/core/services/supabase_service.dart`
- Modify: `apps/main_app/lib/providers/child_provider.dart`
- Test: `apps/main_app/test/core/services/child_bootstrap_service_test.dart`

- [ ] **Step 1: Write failing tests for online hydration and offline fallback**

```dart
import 'package:aumazing/core/services/child_bootstrap_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bootstrap hydrates SQLite from Supabase when online', () async {
    final localDb = _FakeLocalDb();
    final service = ChildBootstrapService(
      authService: _FakeAuthService.loggedIn(),
      connectivityService: _FakeConnectivityService(online: true),
      supabaseService: _FakeSupabaseService(
        children: [
          {
            'id': 'child-1',
            'parent_user_id': 'user-1',
            'display_name': 'Mika',
            'birth_date': '2022-04-20',
            'created_at': '2026-04-20T00:00:00Z',
            'updated_at': '2026-04-20T00:00:00Z',
          },
        ],
      ),
      localDbService: localDb,
    );

    final result = await service.bootstrap();

    expect(result.destination, BootstrapDestination.home);
    expect(localDb.upsertedChildren, hasLength(1));
  });

  test('bootstrap routes legacy local records to child setup while offline', () async {
    final service = ChildBootstrapService(
      authService: _FakeAuthService.loggedIn(),
      connectivityService: _FakeConnectivityService(online: false),
      supabaseService: _FakeSupabaseService(children: const []),
      localDbService: _FakeLocalDb.legacyAgeOnly(),
    );

    final result = await service.bootstrap();

    expect(result.destination, BootstrapDestination.childProfileSetup);
    expect(result.errorMessage, isNotEmpty);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd apps/main_app && flutter test test/core/services/child_bootstrap_service_test.dart`
Expected: FAIL because `ChildBootstrapService` and its bootstrap result types do not exist

- [ ] **Step 3: Implement the bootstrap service seam and Supabase fetch method**

```dart
enum BootstrapDestination {
  login,
  childProfileSetup,
  home,
}

class BootstrapResult {
  const BootstrapResult({
    required this.destination,
    this.errorMessage,
  });

  final BootstrapDestination destination;
  final String? errorMessage;
}

class ChildBootstrapService {
  ChildBootstrapService({
    required AuthService authService,
    required ConnectivityService connectivityService,
    required SupabaseService supabaseService,
    required LocalDbService localDbService,
  })  : _authService = authService,
        _connectivityService = connectivityService,
        _supabaseService = supabaseService,
        _localDbService = localDbService;

  final AuthService _authService;
  final ConnectivityService _connectivityService;
  final SupabaseService _supabaseService;
  final LocalDbService _localDbService;

  Future<BootstrapResult> bootstrap() async {
    if (!_authService.isLoggedIn) {
      return const BootstrapResult(destination: BootstrapDestination.login);
    }

    if (_connectivityService.isOnline) {
      await _hydrateChildrenFromSupabase();
    }

    final children = await _localDbService.getChildren(
      userId: _authService.currentUser!.id,
    );

    if (children.isEmpty) {
      return const BootstrapResult(
        destination: BootstrapDestination.childProfileSetup,
        errorMessage: 'Please complete Initial Child Info.',
      );
    }

    final child = children.first;
    final validation = validateBirthDate(child.birthDate);
    if (validation != ChildBirthDateValidation.valid) {
      return const BootstrapResult(
        destination: BootstrapDestination.childProfileSetup,
        errorMessage: 'Aumazing currently supports children ages 2 to 6.',
      );
    }

    return const BootstrapResult(destination: BootstrapDestination.home);
  }

  Future<void> _hydrateChildrenFromSupabase() async {
    final userId = _authService.currentUser!.id;
    final remoteChildren = await _supabaseService.getChildren(userId);

    for (final remote in remoteChildren) {
      await _localDbService.upsertChild(
        ChildProfile.fromSupabase(remote),
        ownerId: userId,
        markPending: false,
      );
    }
  }
}
```

```dart
Future<List<Map<String, dynamic>>> getChildren(String userId) async {
  final response = await _client
      .from(RemoteTables.children)
      .select()
      .eq('parent_user_id', userId)
      .order('updated_at', ascending: false);

  return List<Map<String, dynamic>>.from(response);
}
```

```dart
Future<void> loadProfile() async {
  _isLoading = true;
  notifyListeners();

  try {
    final user = _authService.currentUser;
    if (user == null) return;

    final children = await _localDb.getChildren(userId: user.id);
    _profile = children.isEmpty ? null : children.first;
  } finally {
    _isLoading = false;
    notifyListeners();
  }
}
```

- [ ] **Step 4: Run the bootstrap tests**

Run: `cd apps/main_app && flutter test test/core/services/child_bootstrap_service_test.dart`
Expected: PASS with online hydration and offline legacy fallback covered

- [ ] **Step 5: Commit**

```bash
git add apps/main_app/lib/core/services/child_bootstrap_service.dart apps/main_app/lib/core/services/supabase_service.dart apps/main_app/lib/providers/child_provider.dart apps/main_app/test/core/services/child_bootstrap_service_test.dart
git commit -m "feat(main_app): add child bootstrap preload service"
```

## Task 4: Make Loading Screen The Startup Preload Owner

**Files:**
- Modify: `apps/main_app/lib/features/splash/loading_screen.dart`
- Test: `apps/main_app/test/features/splash/loading_screen_test.dart`

- [ ] **Step 1: Write failing widget tests for startup routing**

```dart
import 'package:aumazing/features/splash/loading_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('loading screen routes to home for valid local child state', (
    tester,
  ) async {
    final bootstrapService = _FakeBootstrapService(
      const BootstrapResult(destination: BootstrapDestination.home),
    );

    await tester.pumpWidget(buildLoadingScreenTestApp(bootstrapService));
    await tester.pumpAndSettle();

    expect(find.text("Child's Dashboard"), findsOneWidget);
  });

  testWidgets('loading screen routes to child setup for invalid local child state', (
    tester,
  ) async {
    final bootstrapService = _FakeBootstrapService(
      const BootstrapResult(
        destination: BootstrapDestination.childProfileSetup,
        errorMessage: 'Aumazing currently supports children ages 2 to 6.',
      ),
    );

    await tester.pumpWidget(buildLoadingScreenTestApp(bootstrapService));
    await tester.pumpAndSettle();

    expect(find.text('Tell us about your child'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd apps/main_app && flutter test test/features/splash/loading_screen_test.dart`
Expected: FAIL because `LoadingScreen` is not injectable through a bootstrap service

- [ ] **Step 3: Inject the bootstrap service and route from local bootstrap result**

```dart
class LoadingScreen extends StatefulWidget {
  const LoadingScreen({
    super.key,
    ChildBootstrapService? bootstrapService,
    AuthService? authService,
  })  : _bootstrapService = bootstrapService,
        _authService = authService;

  final ChildBootstrapService? _bootstrapService;
  final AuthService? _authService;

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen> {
  late final AuthService _authService;
  late final ChildBootstrapService _bootstrapService;

  @override
  void initState() {
    super.initState();
    _authService = widget._authService ?? AuthService();
    _bootstrapService = widget._bootstrapService ??
        ChildBootstrapService(
          authService: _authService,
          connectivityService: connectivityService,
          supabaseService: supabaseService,
          localDbService: localDbService,
        );
    _initLoading();
  }

  Future<void> _navigateBasedOnAuth() async {
    final result = await _bootstrapService.bootstrap();
    if (!mounted) return;

    final destination = switch (result.destination) {
      BootstrapDestination.login => const LoginScreen(),
      BootstrapDestination.childProfileSetup => ChildProfileSetupScreen(
          initialErrorMessage: result.errorMessage,
        ),
      BootstrapDestination.home => const HomeScreen(),
    };

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => destination,
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }
}
```

- [ ] **Step 4: Run the loading screen tests**

Run: `cd apps/main_app && flutter test test/features/splash/loading_screen_test.dart`
Expected: PASS with both home and setup routing covered

- [ ] **Step 5: Commit**

```bash
git add apps/main_app/lib/features/splash/loading_screen.dart apps/main_app/test/features/splash/loading_screen_test.dart
git commit -m "feat(main_app): route startup through local child bootstrap"
```

## Task 5: Replace Age Selector With Birth Date Picker In Initial Child Info

**Files:**
- Modify: `apps/main_app/lib/features/splash/auth/child_profile_setup_screen.dart`
- Modify: `apps/main_app/lib/core/repositories/child_repository.dart`
- Test: `apps/main_app/test/features/splash/auth/child_profile_setup_screen_test.dart`

- [ ] **Step 1: Write failing widget tests for birth date validation**

```dart
import 'package:aumazing/features/splash/auth/child_profile_setup_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('continue is blocked when no birth date is selected', (tester) async {
    await tester.pumpWidget(buildChildSetupTestApp());

    await tester.enterText(find.byType(TextFormField), 'Mika');
    await tester.tap(find.text('Continue to Dashboard'));
    await tester.pumpAndSettle();

    expect(find.text("Please select your child's birth date."), findsOneWidget);
  });

  testWidgets('continue is blocked when selected birth date is outside 2 to 6', (tester) async {
    await tester.pumpWidget(buildChildSetupTestApp(initialNow: DateTime(2026, 4, 20)));

    await tester.enterText(find.byType(TextFormField), 'Mika');
    await tester.tap(find.byKey(const Key('birth-date-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('21'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue to Dashboard'));
    await tester.pumpAndSettle();

    expect(find.text('Aumazing currently supports children ages 2 to 6.'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd apps/main_app && flutter test test/features/splash/auth/child_profile_setup_screen_test.dart`
Expected: FAIL because there is no birth-date picker or matching validation message

- [ ] **Step 3: Replace `_selectedAge` with `DateTime? _selectedBirthDate` and save locally first**

```dart
DateTime? _selectedBirthDate;

Future<void> _saveProfile() async {
  if (!_formKey.currentState!.validate()) return;

  final validation = validateBirthDate(_selectedBirthDate);
  if (validation == ChildBirthDateValidation.missing) {
    _showError("Please select your child's birth date.");
    return;
  }
  if (validation == ChildBirthDateValidation.futureDate) {
    _showError('Birth date cannot be in the future.');
    return;
  }
  if (validation != ChildBirthDateValidation.valid) {
    _showError('Aumazing currently supports children ages 2 to 6.');
    return;
  }

  setState(() => _isLoading = true);

  try {
    await childRepository.createChild(
      displayName: _nameController.text.trim(),
      birthDate: _selectedBirthDate!,
      avatar: _avatars[_selectedAvatarIndex].emoji,
    );

    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (_) => false,
      );
    }
  } finally {
    if (mounted) setState(() => _isLoading = false);
  }
}
```

```dart
Widget _buildBirthDateSelector() {
  final ageText = _selectedBirthDate == null
      ? 'Select birth date'
      : 'Age ${calculateAgeYears(_selectedBirthDate!)}';

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Birth Date',
        style: AppTextStyles.titleMedium.copyWith(color: AppColors.foreground),
      ),
      const SizedBox(height: AppSpacing.sm),
      AppSecondaryButton(
        key: const Key('birth-date-button'),
        label: ageText,
        onPressed: _isLoading ? null : _pickBirthDate,
      ),
    ],
  );
}
```

- [ ] **Step 4: Run the widget tests**

Run: `cd apps/main_app && flutter test test/features/splash/auth/child_profile_setup_screen_test.dart`
Expected: PASS with birth date validation and continue-blocking coverage

- [ ] **Step 5: Commit**

```bash
git add apps/main_app/lib/features/splash/auth/child_profile_setup_screen.dart apps/main_app/lib/core/repositories/child_repository.dart apps/main_app/test/features/splash/auth/child_profile_setup_screen_test.dart
git commit -m "feat(main_app): collect child birth date in setup"
```

## Task 6: Gate Dashboard Access From Local SQLite State

**Files:**
- Modify: `apps/main_app/lib/features/home/home_screen.dart`
- Modify: `apps/main_app/test/features/home/home_screen_test.dart`

- [ ] **Step 1: Write the failing widget test for invalid local child data**

```dart
testWidgets('home screen redirects to child setup when local child is invalid', (
  tester,
) async {
  final invalidProfile = ChildProfile(
    id: 'child-1',
    userId: 'user-1',
    displayName: 'Test',
    birthDate: DateTime(2018, 4, 19),
    avatar: '🐻',
    createdAt: DateTime(2026, 4, 20),
    updatedAt: DateTime(2026, 4, 20),
  );

  await tester.pumpWidget(
    _buildTestApp(
      authService: AuthService(supabaseAuth: _FakeSupabaseAuthClient()),
      childProvider: _TestChildProvider(initialProfile: invalidProfile),
    ),
  );
  await tester.pumpAndSettle();

  expect(find.text('Tell us about your child'), findsOneWidget);
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd apps/main_app && flutter test test/features/home/home_screen_test.dart`
Expected: FAIL because `HomeScreen` still renders for invalid child data

- [ ] **Step 3: Add a defensive local validity gate to `HomeScreen`**

```dart
Future<void> _loadData() async {
  final childProvider = context.read<ChildProvider>();
  await childProvider.loadProfile();

  if (!mounted) return;
  final profile = childProvider.profile;
  if (profile == null ||
      validateBirthDate(profile.birthDate) != ChildBirthDateValidation.valid) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const ChildProfileSetupScreen(
          initialErrorMessage: 'Aumazing currently supports children ages 2 to 6.',
        ),
      ),
      (_) => false,
    );
    return;
  }

  final childId = profile.id;
  context.read<AssessmentProvider>().loadAssessments(childId);
  context.read<ProgressProvider>().loadProgress(childId);
}
```

```dart
final age = profile == null ? '?' : profile.ageYears().toString();
final name = profile?.displayName ?? 'Child';
```

- [ ] **Step 4: Run the home screen tests**

Run: `cd apps/main_app && flutter test test/features/home/home_screen_test.dart`
Expected: PASS with existing tests updated for `displayName` and new invalid-profile redirect coverage

- [ ] **Step 5: Commit**

```bash
git add apps/main_app/lib/features/home/home_screen.dart apps/main_app/test/features/home/home_screen_test.dart
git commit -m "feat(main_app): block dashboard for invalid child ages"
```

## Task 7: Full Verification And Cleanup

**Files:**
- Modify: `apps/main_app/lib/core/services/supabase_service.dart`
- Modify: `apps/main_app/lib/core/services/child_bootstrap_service.dart`
- Modify: `apps/main_app/test/core/services/child_bootstrap_service_test.dart`
- Modify: `apps/main_app/test/features/splash/loading_screen_test.dart`
- Modify: `apps/main_app/test/features/splash/auth/child_profile_setup_screen_test.dart`
- Modify: `apps/main_app/test/features/home/home_screen_test.dart`

- [ ] **Step 1: Add a final sync regression test for `public.children` field mapping**

```dart
test('upsertChild sends display_name and birth_date to public children', () async {
  final supabase = _RecordingSupabaseClient();
  final service = SupabaseService(client: supabase);

  await service.upsertChild({
    'id': 'child-1',
    'parent_user_id': 'user-1',
    'display_name': 'Mika',
    'birth_date': '2022-04-20',
  }, 'child-1');

  expect(supabase.lastTable, RemoteTables.children);
  expect(supabase.lastPayload['display_name'], 'Mika');
  expect(supabase.lastPayload['birth_date'], '2022-04-20');
});
```

- [ ] **Step 2: Run the focused tests first**

Run: `cd apps/main_app && flutter test test/core/child_profile_policy_test.dart test/core/services/child_bootstrap_service_test.dart test/features/splash/auth/child_profile_setup_screen_test.dart test/features/splash/loading_screen_test.dart test/features/home/home_screen_test.dart`
Expected: PASS with all targeted birth-date and bootstrap tests green

- [ ] **Step 3: Run the full app test suite**

Run: `cd apps/main_app && flutter test`
Expected: PASS with all `main_app` tests green

- [ ] **Step 4: Run static analysis**

Run: `cd apps/main_app && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add apps/main_app/lib/core/services/supabase_service.dart apps/main_app/lib/core/services/child_bootstrap_service.dart apps/main_app/test/core/services/child_bootstrap_service_test.dart apps/main_app/test/features/splash/loading_screen_test.dart apps/main_app/test/features/splash/auth/child_profile_setup_screen_test.dart apps/main_app/test/features/home/home_screen_test.dart
git commit -m "test(main_app): cover offline child bootstrap flow"
```

## Self-Review Notes

### Spec coverage

Covered requirements:

1. Birth date picker replaces age selector: Task 5
2. Age auto-calculation and 2 to 6 validation: Tasks 1 and 5
3. Future dates blocked: Tasks 1 and 5
4. Dashboard access blocked when local profile invalid: Task 6
5. Supabase `public.children` as remote sync target: Tasks 2, 3, and 7
6. `SQLite-first runtime, Supabase children as sync target`: Tasks 2, 3, 4, and 6
7. `loading_screen.dart` owns preload responsibilities: Task 4
8. Existing age-only users forced back to Initial Child Info: Tasks 3 and 4
9. Offline gameplay/performance still syncs later: preserved and regression-covered in Task 7

### Placeholder scan

No `TODO`, `TBD`, or deferred implementation markers remain. All steps include explicit files, commands, and code snippets.

### Type consistency

Consistent names used throughout:

1. `displayName`
2. `birthDate`
3. `ageYears()`
4. `ChildBootstrapService`
5. `BootstrapResult`
6. `BootstrapDestination`
7. `validateBirthDate`

