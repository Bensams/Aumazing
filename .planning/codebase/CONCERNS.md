# Known Concerns & Technical Debt

## Critical Issues

### 1. JVM Crash Logs (URGENT)
**Location**: Multiple directories contain JVM crash logs
- `hs_err_pid*.log` (40 crash dumps total)
  - 20 in root directory
  - 11 in `apps/main_app/android/`
  - 8 in `apps/main_app/`
  - 8 in `apps/game_lab/android/`
- `replay_pid*.log` (16 replay logs in root)

**Impact**: JVM crashes during development/testing
**Files**: ~15MB of crash logs in root directory

**Possible Causes**:
- Android emulator issues
- Memory pressure during Flutter builds
- Native code crashes in Flame/engine

**Action**: Review logs, identify root cause, fix underlying issue

### 2. Missing Environment Configuration
**Files Not Tracked**:
- `lib/core/config/supabase_config.dart` (contains API keys)

**Risk**: Secrets may be committed or missing in CI
**Solution**: Use `.env` file or environment variables with `flutter_config`

## Testing Gaps (High Priority)

**Current State**: Near-zero test coverage
- Only default `widget_test.dart` exists
- No unit tests for scoring algorithms
- No widget tests for critical user flows
- No integration tests

**Risk**: Regressions in assessment logic, auth flows

## Architecture Concerns

### 1. Service Duplication
**Issue**: Two `LocalDbService` files exist
- `lib/core/services/local_db_service.dart`
- `lib/services/local_db_service.dart`

**Risk**: Confusion about which to use, potential drift
**Action**: Consolidate to single location

### 2. Assets Organization
**Issue**: Duplicate assets folder
- `assets/` 
- `assets copy/`

**Action**: Remove duplicate, verify all references

### 3. Import Inconsistencies
**Pattern Observed**: Some files use barrel imports, others direct

```dart
// Mixed patterns found:
import 'package:shared_audio/shared_audio.dart';  // Package
import '../services/local_db_service.dart';       // Relative
```

**Standard**: Use package imports for shared packages, relative for same-app

## Data & Sync Concerns

### 1. Sync Conflict Resolution
**Question**: How are conflicts resolved when offline changes overlap?
**Current**: Not explicitly implemented
**Risk**: Data loss when multiple devices sync

### 2. Guest Mode Data Migration
**Question**: What happens to guest data after login?
**Current**: Backfill exists but edge cases unclear
**Risk**: Data orphaned or lost during account creation

## Security Concerns

### 1. API Keys in Source
**Issue**: `supabase_config.dart` contains hardcoded keys
**Risk**: Keys exposed in version control
**Solution**: Environment-based configuration

### 2. Local Database Encryption
**Question**: Is SQLite database encrypted?
**Current**: Unknown
**Risk**: Sensitive child data accessible if device compromised

## Performance Concerns

### 1. Game Engine
**Flame**: Running on Flutter may have performance limits for complex games
**Target**: Ages 2-6 with potential sensory sensitivities
**Risk**: Frame drops could cause distress

### 2. Memory Leaks
**Observation**: JVM crashes suggest potential memory issues
**Areas to Review**:
- Image/asset loading in games
- Provider disposal
- Audio service cleanup

## Scalability Concerns

### 1. Assessment Algorithm
**Current**: Likely rule-based
**Future**: AI-driven personalization mentioned in vision
**Gap**: No ML infrastructure in place

### 2. Content Delivery
**Current**: Bundled assets
**Future**: May need dynamic content loading
**Gap**: No CDN or content management system

## Platform-Specific Concerns

### 1. Multi-Platform Support
**Configured**: Android, iOS, Web, Linux, macOS, Windows
**Reality**: Only Android/iOS likely tested
**Risk**: Desktop/web builds may have issues

### 2. Orientation Lock
**Current**: Locked to landscape only
**Potential Issue**: Some tablets/phones may not support both directions

## Dependencies

### Outdated or Vulnerable
**Check Required**: Run `flutter pub outdated`
**Known**: Using Flutter 3.7.2, current is newer
**Risk**: Security patches, bug fixes missed

### Heavy Dependencies
- `flame: ^1.30.1` (game engine)
- `supabase_flutter: ^2.12.2` (full backend SDK)
- `video_player: ^2.9.3` (native video)

**Impact**: App size, build times

## Documentation Gaps

### 1. API Documentation
**Missing**: Backend schema documentation
**Missing**: API endpoint documentation
**Impact**: Onboarding new developers

### 2. Game Logic Documentation
**Missing**: Scoring algorithm details
**Missing**: Assessment flow documentation
**Impact**: Difficult to modify or debug

## Recommended Actions (Priority Order)

1. **Fix JVM crashes** - investigate and resolve root cause
2. **Add tests** - start with scoring service unit tests
3. **Secure configuration** - move secrets to environment
4. **Consolidate services** - remove duplicate LocalDbService
5. **Clean up assets** - remove duplicate folder and crash logs
