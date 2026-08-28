# Architecture

## Overview

**Pattern**: Feature-based Clean Architecture with Offline-First Design
**Structure**: Monorepo with shared packages

## Monorepo Structure

```
Aumazing/
├── apps/
│   ├── main_app/         # Main Flutter application
│   └── game_lab/         # Game development sandbox
├── packages/
│   ├── game_core/        # Flame game engine abstraction
│   ├── shared_ui/        # Reusable UI components
│   ├── shared_audio/     # Audio management
│   └── assets/           # Shared assets
└── .planning/            # GSD planning artifacts
```

## Layered Architecture (main_app)

### 1. Presentation Layer (UI)
**Location**: `lib/features/`

**Features**:
- `splash/`: Auth flows, onboarding, loading
- `home/`: Main dashboard
- `pre_assessment/`: ASD assessment screens
- `games/`: Learning activities (MatchIt, CopyMe, etc.)

**Pattern**: Screen widgets + Feature-specific providers

### 2. Domain Layer (Business Logic)
**Location**: `lib/providers/`, `lib/services/`

**Providers** (State Management):
- `ChildProvider`: Child profile state
- `AssessmentProvider`: Assessment flow state
- `ProgressProvider`: Learning progress state

**Services** (Business Logic):
- `AssessmentService`: Assessment scoring and evaluation
- `ScoringService`: Game session scoring algorithms
- `LocalDbService`: Local database operations

### 3. Data Layer
**Location**: `lib/core/`

**Repositories** (Data Access):
- `ChildRepository`: Child CRUD with offline-first
- `AssessmentRepository`: Assessment data management

**Services** (Infrastructure):
- `SupabaseService`: Cloud backend client
- `SyncService`: Local-to-cloud synchronization
- `ConnectivityService`: Network monitoring

### 4. Models
**Location**: `lib/model/`
- `child_profile.dart`
- `assessment_result.dart`
- `gameplay_session.dart`
- `module_progress.dart`
- `support_profile.dart`

## Key Architectural Patterns

### Offline-First Design
```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   UI Layer  │────▶│ Repository  │────▶│   SQLite    │
│             │     │             │     │   (Local)   │
└─────────────┘     └─────────────┘     └──────┬──────┘
       │                                         │
       │         ┌─────────────┐                │
       └────────▶│ SyncService │◀───────────────┘
                 └──────┬──────┘
                        │
                        ▼
                 ┌─────────────┐
                 │   Supabase  │
                 │   (Cloud)   │
                 └─────────────┘
```

### Provider Pattern
- MultiProvider at root level
- Feature-specific providers
- AudioService as singleton with Provider.value

### Repository Pattern
- Abstracts data source (local vs remote)
- UUID generation happens in repositories
- Same IDs across local and cloud

## Shared Packages

### game_core
- Flame game engine wrapper
- Game registry for activity management
- Shared game configuration

### shared_ui
- Theme definitions
- Reusable components (buttons, cards, etc.)
- ASD-friendly UI patterns

### shared_audio
- AudioService for background music
- UI sound effects
- Lifecycle-aware audio management
