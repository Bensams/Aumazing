# Technology Stack

## Core Framework
- **Flutter**: 3.7.2+ (Dart SDK ^3.7.2)
- **Flame**: ^1.30.1 (2D game engine for learning activities)

## State Management
- **Provider**: ^6.1.2 (ChangeNotifier pattern for reactive state)
- Pattern: Multi-provider setup with separate providers for Child, Assessment, and Progress

## Backend & Data
- **Supabase**: ^2.12.2 (Backend-as-a-Service)
  - PostgreSQL database
  - Real-time subscriptions
  - Authentication
- **SQLite**: sqflite ^2.3.3+1 (Local/offline database)
- **SharedPreferences**: ^2.2.3 (Local key-value storage)

## Authentication
- **Supabase Auth** (email/password)
- **Google Sign-In**: ^7.2.0
- **Facebook Auth**: ^7.1.1 (flutter_facebook_auth)
- **Guest Mode**: Local-first with later backfill to cloud

## UI & Design
- **Material Design 3** (uses-material-design: true)
- **go_router**: ^14.2.0 (Declarative routing)
- **fl_chart**: ^0.68.0 (Data visualization for progress)
- **flutter_svg**: ^2.0.17 (Vector graphics)
- **google_fonts**: ^6.3.2 (Typography)
- **shared_ui**: Local package for reusable components

## Audio
- **shared_audio**: Local package for audio management
- Background music with lifecycle-aware pause/resume
- UI sound effects (button taps)

## Game Engine
- **game_core**: Local package for Flame-based games
- 2D interactive activities (Match It, Copy Me, Do What I Say, My Turn Your Turn)
- Game registry pattern for activity management

## Networking & Sync
- **connectivity_plus**: ^6.1.3 (Network state monitoring)
- Offline-first architecture with automatic sync when online
- Sync service for local-to-cloud data synchronization

## Utilities
- **intl**: ^0.19.0 (Internationalization)
- **uuid**: ^4.4.0 (UUID generation for local/remote ID consistency)
- **path_provider**: ^2.1.3 (File system access)
- **video_player**: ^2.9.3 (Video content)

## Testing
- **flutter_test**: SDK testing framework
- **flutter_lints**: ^5.0.0 (Code quality)
