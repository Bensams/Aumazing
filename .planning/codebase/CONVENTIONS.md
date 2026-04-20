# Code Conventions

## Naming Conventions

### Files
- **Dart**: `snake_case.dart`
- **Screens**: `*_screen.dart` (e.g., `login_screen.dart`)
- **Services**: `*_service.dart` (e.g., `auth_service.dart`)
- **Providers**: `*_provider.dart` (e.g., `child_provider.dart`)
- **Models**: `*.dart` named after entity (e.g., `child_profile.dart`)

### Classes
- **PascalCase** for all class names
- **Screens**: `*Screen` (e.g., `LoginScreen`)
- **Services**: `*Service` (e.g., `AuthService`)
- **Providers**: `*Provider` (e.g., `ChildProvider`)
- **Models**: Descriptive nouns (e.g., `ChildProfile`, `AssessmentResult`)

### Variables & Methods
- **camelCase** for variables and methods
- **Private**: `_camelCase` for private members
- **Constants**: `camelCase` or `kCamelCase` for constants
- **Boolean**: Prefixed with `is`, `has`, `should` (e.g., `isOnline`)

## Code Organization

### Imports Order
1. Dart SDK imports (`dart:*`)
2. Flutter SDK imports (`package:flutter/*`)
3. External packages (`package:flame/*`, etc.)
4. Internal packages (`package:shared_ui/*`, etc.)
5. Relative imports (`../`, `./`)

```dart
import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flame/game.dart';
import 'package:provider/provider.dart';

import 'package:shared_ui/shared_ui.dart';

import '../services/auth_service.dart';
```

### Class Structure
1. Static fields
2. Instance fields
3. Constructor(s)
4. Public methods
5. Private methods
6. Build method (for widgets)

## Architecture Patterns

### Repository Pattern
```dart
class ChildRepository {
  final LocalDbService _local;
  final SupabaseService _remote;
  
  // Always write local first
  Future<Child> create(Child data) async {
    final withId = data.copyWith(id: generateUuid());
    await _local.insert(withId);
    await _sync.queueForSync(withId);
    return withId;
  }
}
```

### Provider Pattern
```dart
class ChildProvider extends ChangeNotifier {
  Child? _currentChild;
  Child? get currentChild => _currentChild;
  
  void setChild(Child child) {
    _currentChild = child;
    notifyListeners();
  }
}
```

### Service Pattern
```dart
class AssessmentService {
  final AssessmentRepository _repository;
  final ScoringService _scoring;
  
  Future<AssessmentResult> evaluate(GameplaySession session) async {
    final score = _scoring.calculate(session);
    return _repository.saveResult(session, score);
  }
}
```

## Flutter-Specific Conventions

### Widgets
- Prefer `StatelessWidget` where possible
- Use `const` constructors for performance
- Extract large widgets into private methods or separate files

### State Management
- Use Provider for shared state
- Keep widgets reactive with `Consumer` or `context.watch()`
- Business logic in services, UI state in providers

### Keys
- Use `const Key('descriptive_name')` for testing
- Use `ValueKey` for list items

## Documentation

### Comments
- **Public APIs**: Document with `///`
- **Complex logic**: Explain with `//`
- **TODOs**: Use `// TODO(username): description`

### Example
```dart
/// Manages child profile data with offline-first synchronization.
/// 
/// All operations write to SQLite first, then sync to Supabase when online.
class ChildRepository {
  /// Creates a new child profile.
  /// 
  /// Generates a UUID locally that will be used in both local and cloud storage.
  Future<Child> createChild(ChildData data) async {
    // Implementation
  }
}
```
