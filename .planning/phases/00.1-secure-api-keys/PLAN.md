# Phase 00.1: Secure API Keys

## Goal
Move all hardcoded API keys and secrets from source code to environment variables, preventing exposure in version control.

## Current State
- Supabase URL, anon key hardcoded in `lib/core/config/supabase_config.dart`
- Google OAuth client ID hardcoded
- Facebook App ID and client token hardcoded
- No `.env` file or environment configuration exists

## Target State
- All secrets loaded from `.env` file
- `.env` added to `.gitignore`
- `.env.example` template created for developers
- Application fails gracefully if env vars missing
- README updated with setup instructions

## Implementation Steps

### 1. Add flutter_dotenv Dependency
**File**: `apps/main_app/pubspec.yaml`
- Add `flutter_dotenv: ^5.2.1` to dependencies
- Run `flutter pub get`

### 2. Create .env File
**File**: `apps/main_app/.env` (add to .gitignore)
```
SUPABASE_URL=https://lzvvjlcfoyczikaszrbp.supabase.co
SUPABASE_ANON_KEY=sb_publishable_LmDmXen9C_J8G_SDMi-LCA_sD23uwZv
GOOGLE_WEB_CLIENT_ID=200541942189-dqsgoge37md2umri21qu8p699qr26rjd.apps.googleusercontent.com
GOOGLE_IOS_CLIENT_ID=YOUR_GOOGLE_IOS_CLIENT_ID
FACEBOOK_APP_ID=4458074451092574
FACEBOOK_CLIENT_TOKEN=594a43ec476f200bd4f77bad8b160006
```

### 3. Create .env.example Template
**File**: `apps/main_app/.env.example`
```
SUPABASE_URL=your_supabase_url
SUPABASE_ANON_KEY=your_supabase_anon_key
GOOGLE_WEB_CLIENT_ID=your_google_web_client_id
GOOGLE_IOS_CLIENT_ID=your_google_ios_client_id
FACEBOOK_APP_ID=your_facebook_app_id
FACEBOOK_CLIENT_TOKEN=your_facebook_client_token
```

### 4. Update .gitignore
**File**: `apps/main_app/.gitignore`
Add:
```
# Environment variables
.env
*.env
```

### 5. Update SupabaseConfig
**File**: `lib/core/config/supabase_config.dart`
- Import `flutter_dotenv`
- Load `.env` in main.dart before Supabase.initialize()
- Change from `static const String` to `static String get`
- Read from `dotenv.env[]`
- Add validation that throws clear error if env var missing

### 6. Update main.dart
**File**: `lib/main.dart`
- Add `await dotenv.load()` before `Supabase.initialize()`
- Import `package:flutter_dotenv/flutter_dotenv.dart`

### 7. Update README
**File**: `README.md`
- Add section: "Environment Setup"
- Instructions to copy `.env.example` to `.env` and fill in values
- Note that keys are required for build

## Verification Criteria
- [ ] `flutter build` fails with clear error if `.env` missing
- [ ] App runs successfully with `.env` present
- [ ] No hardcoded secrets in any committed files
- [ ] `git grep -i "sb_publishable\|supabase.co\|googleusercontent"` returns only `.env` and `.env.example`
- [ ] `.env` is in `.gitignore` and not tracked by git

## Rollback Plan
If issues occur:
1. Revert `supabase_config.dart` to const strings temporarily
2. Fix environment loading issue
3. Re-apply env var approach

## References
- Code review finding: REVIEW.md #1 (Critical)
- flutter_dotenv package: https://pub.dev/packages/flutter_dotenv
