# Project Structure

## Monorepo Layout

```
d:\Projects\aumazing/
├── apps/
│   ├── main_app/              # Primary Flutter application
│   │   ├── android/           # Android platform code
│   │   ├── ios/               # iOS platform code
│   │   ├── lib/               # Dart source code
│   │   ├── test/              # Unit tests
│   │   ├── assets/            # Images, videos
│   │   └── pubspec.yaml       # Dependencies
│   └── game_lab/              # Game experimentation
├── packages/
│   ├── assets/                # Shared static assets
│   ├── game_core/             # Game engine (Flame wrapper)
│   ├── shared_audio/          # Audio management
│   └── shared_ui/             # Reusable UI components
├── docs/                      # Documentation
├── Documents/                 # Additional docs
└── .planning/                 # GSD planning (new)
    ├── PROJECT.md
    └── codebase/
```

## main_app/lib/ Structure

```
lib/
├── main.dart                  # Entry point
├── core/                      # Infrastructure layer
│   ├── config/
│   │   └── supabase_config.dart
│   ├── offline_first_integration.dart   # System integration
│   ├── repositories/
│   │   ├── assessment_repository.dart
│   │   └── child_repository.dart
│   ├── services/
│   │   ├── auth_service.dart
│   │   ├── connectivity_service.dart
│   │   ├── local_db_service.dart
│   │   ├── supabase_service.dart
│   │   └── sync_service.dart
│   └── sync/
│       └── sync_status.dart
├── features/                  # Feature modules
│   ├── games/
│   │   ├── copy_me/
│   │   │   └── copy_me_screen.dart
│   │   ├── do_what_i_say/
│   │   │   └── do_what_i_say_screen.dart
│   │   ├── match_it/
│   │   │   └── match_it_screen.dart
│   │   └── my_turn_your_turn/
│   │       └── my_turn_your_turn_screen.dart
│   ├── home/
│   │   └── home_screen.dart
│   ├── pre_assessment/
│   │   ├── pre_assessment_intro_screen.dart
│   │   ├── pre_assessment_progress_screen.dart
│   │   ├── pre_assessment_result_screen.dart
│   │   └── sensory_preferences_screen.dart
│   └── splash/
│       ├── auth/
│       │   ├── child_profile_setup_screen.dart
│       │   ├── forgot_password_screen.dart
│       │   ├── login_screen.dart
│       │   ├── otp_verification_screen.dart
│       │   └── reset_password_screen.dart
│       ├── loading_screen.dart
│       └── splash_screen.dart
├── model/                     # Data models
│   ├── assessment_result.dart
│   ├── child_profile.dart
│   ├── gameplay_session.dart
│   ├── module_progress.dart
│   └── support_profile.dart
├── providers/                 # State management
│   ├── assessment_provider.dart
│   ├── child_provider.dart
│   └── progress_provider.dart
└── services/                  # Business logic
    ├── assessment_service.dart
    ├── local_db_service.dart
    └── scoring_service.dart
```

## Package Structure

### game_core/
```
lib/
├── src/
│   ├── game_registry.dart     # Activity registration
│   ├── flame_components/      # Reusable Flame components
│   └── games/                 # Game implementations
└── game_core.dart             # Public API
```

### shared_ui/
```
lib/
├── src/
│   ├── theme/
│   │   ├── app_theme.dart     # Theme configuration
│   │   └── colors.dart        # ASD-friendly palette
│   ├── components/
│   │   ├── buttons.dart       # Large touch targets
│   │   ├── cards.dart
│   │   └── feedback.dart      # Sound/visual feedback
│   └── widgets/
└── shared_ui.dart
```

### shared_audio/
```
lib/
├── src/
│   └── audio_service.dart     # Audio management
└── shared_audio.dart
```

## File Count Summary
- **main_app/lib**: 39 Dart files
- **Features**: 4 game screens, auth flows, assessment, home
- **Core**: 10 service/repository files
- **Models**: 5 data classes
- **Providers**: 3 state managers
