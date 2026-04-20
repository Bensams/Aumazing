# Code Review Report - Aumazing

**Date**: 2026-04-21  
**Scope**: Core services, configuration, game screens  
**Lines Reviewed**: ~2,500  

## Summary

| Severity | Count | Categories |
|----------|-------|------------|
| 🔴 **Critical** | 1 | Security |
| 🟠 **High** | 1 | Architecture |
| 🟡 **Medium** | 4 | Bugs, Resource Leaks |
| 🟢 **Low** | 2 | Code Quality |

---

## 🔴 Critical Issues

### 1. Hardcoded API Keys in Source Code
**File**: `lib/core/config/supabase_config.dart:4-18`  
**Severity**: CRITICAL  
**Category**: Security

**Issue**: Supabase URL, anon key, Google OAuth client ID, and Facebook credentials are hardcoded in source.

```dart
static const String supabaseUrl = 'https://lzvvjlcfoyczikaszrbp.supabase.co';
static const String supabaseAnonKey = 'sb_publishable_LmDmXen9C_J8G_SDMi-LCA_sD23uwZv';
static const String googleWebClientId = '200541942189-dqsgoge37md2umri21qu8p699qr26rjd.apps.googleusercontent.com';
static const String facebookAppId = '4458074451092574';
static const String facebookClientToken = '594a43ec476f200bd4f77bad8b160006';
```

**Risk**: 
- Keys exposed in version control
- Cannot rotate keys without code deployment
- Violates security best practices
- Facebook token appears to be a secret (not meant for client-side)

**Fix**: 
```dart
// Use environment variables
import 'package:flutter_dotenv/flutter_dotenv.dart';

class SupabaseConfig {
  static String get supabaseUrl => dotenv.env['SUPABASE_URL']!;
  static String get supabaseAnonKey => dotenv.env['SUPABASE_ANON_KEY']!;
  // ... etc
}
```

---

## 🟠 High Issues

### 2. Duplicate LocalDbService with Incompatible Schemas
**Files**: 
- `lib/core/services/local_db_service.dart` (810 lines, v2 schema)
- `lib/services/local_db_service.dart` (221 lines, v1 schema)

**Severity**: HIGH  
**Category**: Architecture

**Issue**: Two separate `LocalDbService` classes exist with:
- Different database names (`aumazing_offline.db` vs `aumazing.db`)
- Different schemas (v2 with sync columns vs v1 basic)
- Different table structures

**Risk**:
- Data inconsistency - which database is actually used?
- Import confusion - which one to import?
- Schema drift - v2 has sync_status, owner_id, deleted_at that v1 lacks
- Code maintenance nightmare

**Fix**: 
1. Audit which file is actually imported in the codebase
2. Migrate all usage to `lib/core/services/local_db_service.dart` (the enhanced version)
3. Delete the duplicate in `lib/services/`
4. Verify all imports point to the correct location

---

## 🟡 Medium Issues

### 3. Resource Leak: MatchItGame Not Disposed
**File**: `lib/features/games/match_it/match_it_screen.dart:56-58`  
**Severity**: MEDIUM  
**Category**: Resource Leak

**Issue**: `dispose()` method is empty but `_game` (Flame Game) is never disposed.

```dart
@override
void dispose() {
  super.dispose();  // Missing _game disposal
}
```

**Risk**:
- Memory leak when navigating away from game
- Flame engine continues running in background
- Audio/animation resources not released

**Fix**:
```dart
@override
void dispose() {
  _game.dispose();  // Or however Flame games are cleaned up
  super.dispose();
}
```

**Applies to**: All game screens (CopyMe, DoWhatISay, MyTurnYourTurn)

---

### 4. Division by Zero in Scoring Service
**File**: `lib/services/scoring_service.dart:140-141`  
**Severity**: MEDIUM  
**Category**: Logic Error

**Issue**: `_avg()` method doesn't handle empty list.

```dart
double _avg(List<double> values) =>
    values.reduce((a, b) => a + b) / values.length;
```

Called with potentially empty lists at lines 24, 48 (via `_avg(commScores)` and `_avg(playScores)` when games are null).

**Risk**: Runtime exception when all games return null results.

**Fix**:
```dart
double _avg(List<double> values) {
  if (values.isEmpty) return 0.0;
  return values.reduce((a, b) => a + b) / values.length;
}
```

---

### 5. StreamController Not Closed on Dispose
**File**: `lib/core/services/sync_service.dart:567-570`  
**Severity**: MEDIUM  
**Category**: Resource Leak

**Issue**: `_syncStateController.close()` is called in `dispose()`, but the method may not be called if the service is a singleton.

**Risk**:
- Memory leak if SyncService is recreated
- Stream listeners never cleaned up

**Fix**: Ensure `dispose()` is called in app lifecycle or use `WidgetsBindingObserver` pattern.

---

### 6. Missing Null Check in Assessment Provider Context Read
**File**: `lib/features/games/match_it/match_it_screen.dart:46`  
**Severity**: MEDIUM  
**Category**: Null Safety

**Issue**: Reading child ID without null check before game initialization.

```dart
final childId = context.read<ChildProvider>().profile?.id ?? 'unknown';
_game = MatchItGame(
  childId: childId,  // 'unknown' is not a valid ID format
```

**Risk**: Passing invalid 'unknown' ID to analytics and database.

**Fix**: Handle missing child profile properly - either require it or show error screen.

---

## 🟢 Low Issues

### 7. Race Condition in SyncService
**File**: `lib/core/services/sync_service.dart:33`  
**Severity**: LOW  
**Category**: Concurrency

**Issue**: `_isSyncing` boolean flag not thread-safe. In Dart single-threaded model this is less critical but still could race with async/await.

**Fix**: Use an `AtomicBool` pattern or ensure all state changes happen in controlled async blocks.

---

### 8. Missing Index on gameplay_sessions.child_id
**File**: `lib/services/local_db_service.dart:62-76`  
**Severity**: LOW  
**Category**: Performance

**Issue**: `gameplay_sessions` table has no index on `child_id` despite frequent queries.

**Fix**:
```sql
CREATE INDEX idx_gameplay_sessions_child_id ON gameplay_sessions(child_id);
```

---

## Pre-existing Issues (from CONCERNS.md)

1. **40 JVM Crash Logs** - Likely Android emulator/memory issues unrelated to Flutter code
2. **0% Test Coverage** - No automated tests for critical scoring/assessment logic

---

## Recommendations

### Immediate (This Week)
1. 🔴 **Move API keys to environment variables** - Security critical
2. 🟠 **Consolidate LocalDbService** - Pick one, delete the other

### Short Term (This Sprint)
3. 🟡 **Add game disposal** - Fix memory leaks in all game screens
4. 🟡 **Fix division by zero** - Add empty list check to `_avg()`
5. 🟡 **Add null checks** - Validate child profile exists before games

### Medium Term
6. 🟢 **Add database indexes** - Query performance
7. 🟢 **Review async patterns** - Ensure proper cleanup
8. 🟢 **Add unit tests** - Start with ScoringService

---

## Positive Findings

✅ **Clean architecture** - Well-structured offline-first pattern  
✅ **Good error handling** - Try-catch with debug logging  
✅ **Type safety** - Proper use of Dart null safety  
✅ **Provider pattern** - Appropriate state management  
✅ **Sync logic** - Robust batch sync with fallback  
✅ **Guest mode** - Proper backfill implementation  

---

## Files Requiring Attention

| File | Issues | Priority |
|------|--------|----------|
| `supabase_config.dart` | Hardcoded secrets | CRITICAL |
| `services/local_db_service.dart` | Duplicate | HIGH |
| `games/*/match_it_screen.dart` | Resource leak | MEDIUM |
| `scoring_service.dart` | Division by zero | MEDIUM |
| `sync_service.dart` | Resource cleanup | MEDIUM |
