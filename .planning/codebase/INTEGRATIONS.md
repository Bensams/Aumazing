# External Integrations

## Supabase (Primary Backend)

**Configuration**: `lib/core/config/supabase_config.dart`
- URL and anon key configured for development
- Initialized in `main.dart` before app launch

**Services**:
- `SupabaseService`: Centralized Supabase client access
- `AuthService`: Authentication operations (sign in/up, OTP, password reset)
- `SyncService`: Local-to-cloud data synchronization

**Data Flow**:
1. All writes go to SQLite first (offline-first)
2. When online, sync service pushes to Supabase
3. Same UUIDs used locally and in cloud for seamless backfill

## Social Authentication

**Google Sign-In**: 
- Package: `google_sign_in: ^7.2.0`
- Integration with Supabase auth

**Facebook Auth**:
- Package: `flutter_facebook_auth: ^7.1.1`
- Integration with Supabase auth

## Local Database

**SQLite (sqflite)**:
- `LocalDbService`: Database initialization and schema
- Tables: children, assessments, game_sessions, progress, etc.
- Supports offline guest mode

**SharedPreferences**:
- Session tokens
- User preferences
- App state caching

## Game Engine

**Flame**:
- `game_core` package abstracts Flame dependency
- Game screens: MatchIt, CopyMe, DoWhatISay, MyTurnYourTurn
- Each game extends Flame Game class

## Device Integration

**Orientation**:
- Locked to landscape (left/right)
- `SystemChrome.setPreferredOrientations()`

**Fullscreen**:
- `SystemUiMode.immersiveSticky` hides status bar
- Re-applied on app resume

**Connectivity**:
- `ConnectivityService` monitors network state
- Triggers sync when connection restored
