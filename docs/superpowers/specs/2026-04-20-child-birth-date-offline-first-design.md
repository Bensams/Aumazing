# Child Birth Date And Offline-First Bootstrap Design

Date: 2026-04-20
App: `apps/main_app`
Status: Approved design draft

## Summary

Replace the Initial Child Info age selector with a birth date picker, derive age from the selected birth date, and enforce a strict age window of 2 to 6 years inclusive. The app must remain offline-first: local SQLite is the runtime source for startup, dashboard access, and child data reads, while Supabase `public.children` is the remote sync target when internet is available.

Two design rules are mandatory:

1. `SQLite-first runtime, Supabase children as sync target`
2. [`loading_screen.dart`](D:\Projects\aumazing\apps\main_app\lib\features\splash\loading_screen.dart) owns startup preload and routing decisions

## Goals

1. Replace manual age entry with a birth date picker in Initial Child Info.
2. Auto-calculate age from birth date and validate that the child is between 2 and 6 years old.
3. Reject future birth dates.
4. Block dashboard access when the local child profile is missing a valid birth date or derives to an out-of-range age.
5. Store canonical child profile data in Supabase `public.children`.
6. Preserve offline use by reading and writing runtime data from local SQLite first, then syncing later.
7. Force legacy users with age-only child data back through Initial Child Info.

## Non-Goals

1. Continuing auth user metadata as a child-profile source of truth.
2. Building a hybrid runtime that sometimes reads live child data from Supabase and sometimes from SQLite.
3. Backfilling a fake `birth_date` from legacy `age` values.

## Current Problems

1. The current setup screen stores `age` directly instead of collecting a birth date.
2. Startup routing currently depends on auth metadata rather than a fully local runtime model.
3. The local child model and SQLite schema do not match the existing Supabase `public.children` table, which uses `display_name`, `birth_date`, and `parent_user_id`.
4. Legacy age-only data would allow ambiguous or inaccurate child profile state if carried forward.

## Canonical Data Ownership

### Runtime Source

Local SQLite is the runtime source of truth for:

1. App startup routing
2. Dashboard access checks
3. Displaying child profile information
4. Offline gameplay and performance capture
5. Reading cached startup data when internet is unavailable

### Remote Source

Supabase `public.children` is the remote synchronization target for canonical child profile persistence when internet is available.

### Explicit Rule

The app must not require a live Supabase read to determine whether a user can enter the dashboard. Supabase may hydrate SQLite during startup, but all routing decisions are made from the post-hydration local state.

## Data Model Design

### Supabase `public.children`

The app will use the existing table and owned fields:

1. `id`
2. `parent_user_id`
3. `display_name`
4. `birth_date`
5. `created_at`
6. `updated_at`

Optional table fields not owned by this feature, such as `sex`, `diagnosis_status`, and `notes`, remain untouched unless already managed elsewhere.

### Local Child Model

The local child profile model should be updated to store:

1. `id`
2. `userId` or equivalent parent owner id
3. `displayName`
4. `birthDate`
5. `avatar`
6. comfort settings
7. sync metadata
8. timestamps

`age` stops being persisted as canonical profile state. It becomes a derived property calculated from `birthDate`.

### Local SQLite Schema

The local children table should move from the current age-based structure to a birth-date-based structure. At minimum, the schema should support:

1. `display_name`
2. `birth_date`
3. `avatar`
4. `music_enabled`
5. `vibration_enabled`
6. sync metadata fields already used by the offline-first system

If temporary compatibility code is needed during migration, it must still route any legacy age-only rows back to Initial Child Info rather than treating them as valid profiles.

## Age Derivation And Validation Rules

### Birth Date Rules

1. Birth date is required.
2. Future dates are invalid.
3. Age is derived from birth date relative to the device date at runtime.
4. Valid age range is 2 to 6 years inclusive.

### Dashboard Eligibility

A local child profile is eligible for dashboard access only when all of the following are true:

1. A local child record exists.
2. `birth_date` is present.
3. Derived age is not less than 2.
4. Derived age is not greater than 6.

If any of these fail, the app must route to Initial Child Info and show an error explaining the problem.

### Legacy Records

Legacy records that only contain `age` and no valid `birth_date` are invalid for dashboard access. They are not auto-migrated. The user is forced back to Initial Child Info to enter a real birth date.

## UI Design

### Initial Child Info Screen

[`child_profile_setup_screen.dart`](D:\Projects\aumazing\apps\main_app\lib\features\splash\auth\child_profile_setup_screen.dart) will change as follows:

1. Replace the age chip selector with a birth date picker.
2. Prevent selecting a future date.
3. Show a derived age summary after selection.
4. Keep the continue CTA disabled or blocked when:
   - no birth date is selected
   - the selected date is in the future
   - derived age is outside 2 to 6
5. Save locally first.
6. Trigger sync to Supabase when online.

Recommended validation messages:

1. `Please select your child's birth date.`
2. `Birth date cannot be in the future.`
3. `Aumazing currently supports children ages 2 to 6.`

### Home Screen

[`home_screen.dart`](D:\Projects\aumazing\apps\main_app\lib\features\home\home_screen.dart) should display age as a derived value from local `birth_date`. Before rendering normal dashboard content, it should defensively re-check local child validity. If the local profile is invalid, it redirects to Initial Child Info instead of showing dashboard content.

## Startup And Preload Design

### Preload Owner

[`loading_screen.dart`](D:\Projects\aumazing\apps\main_app\lib\features\splash\loading_screen.dart) is the only startup preload coordinator.

### Online Startup Flow

If internet is available and the user is authenticated:

1. Refresh auth/session.
2. Fetch remote child data from Supabase `public.children`.
3. Normalize the remote child row into the local SQLite format.
4. Save the normalized child record into SQLite.
5. Preload any additional startup data already expected by the app.
6. Route based on the local SQLite child state after preload finishes.

### Offline Startup Flow

If internet is unavailable:

1. Skip remote child fetches.
2. Load local child and cached startup data from SQLite.
3. Route only from local SQLite state.

### Routing Contract

After preload completes, startup must route to:

1. `LoginScreen` if the user is not authenticated.
2. `ChildProfileSetupScreen` if:
   - no valid local child exists
   - the local child record is legacy age-only data
   - `birth_date` is missing
   - derived age is outside 2 to 6
3. `HomeScreen` only if the local child record is valid after local evaluation.

## Sync Design

### Child Profile Sync

Local child profile changes are written to SQLite first, marked pending, and synced later. When syncing to Supabase `public.children`, field mapping is:

1. local child `id` -> remote `id`
2. authenticated parent user id -> remote `parent_user_id`
3. local display name -> remote `display_name`
4. local birth date -> remote `birth_date`
5. local timestamps -> remote timestamps where appropriate

### Offline Gameplay And Performance

Gameplay, assessment, and performance data continue following the existing offline-first pattern:

1. write locally first
2. mark pending
3. sync automatically when internet returns

This means children can play offline and their performance should sync to Supabase later after connectivity resumes, as long as the app already records those events into the local offline-first data store.

## Migration Strategy

### Existing Users

Existing users with child data only in auth metadata or only in the old local age-based format are not treated as fully migrated.

Expected behavior:

1. Startup sees the absence of a valid local `birth_date`.
2. User is redirected to Initial Child Info.
3. User enters a real birth date.
4. New local child record is saved in the new structure.
5. Supabase `public.children` becomes the remote source for that child record going forward.

### Auth Metadata

The feature should stop depending on auth metadata for child profile reads and routing. Any leftover metadata may exist temporarily for backward compatibility, but it must not be used as the source of truth for startup access decisions.

## Error Handling

### Setup Screen Errors

The setup screen should show clear local validation errors without requiring network access.

### Startup Errors

If online preload fails:

1. log the remote failure
2. continue with SQLite fallback
3. route based on local child validity

Startup should fail closed for invalid child data but not fail hard because Supabase is unavailable.

## Testing Strategy

### Unit Tests

1. Derive age correctly from birth date.
2. Reject future birth dates.
3. Accept exactly 2 years old.
4. Accept exactly 6 years old.
5. Reject younger than 2.
6. Reject older than 6.

### Integration And Widget Tests

1. Initial Child Info blocks continue when birth date is missing.
2. Initial Child Info blocks continue when birth date is in the future.
3. Initial Child Info blocks continue when derived age is outside 2 to 6.
4. Initial Child Info saves locally first when valid.
5. Loading screen routes to home from a valid local child while offline.
6. Loading screen routes to child setup for legacy age-only local data.
7. Loading screen hydrates SQLite from Supabase when online.
8. Home screen blocks dashboard rendering when local child validity fails.

### Sync Tests

1. Local child changes are marked pending for sync.
2. Supabase sync uses the existing `public.children` table and expected field mapping.
3. Offline gameplay/performance records sync when connectivity returns.

## Implementation Boundaries

### Child Setup Screen

Owns:

1. birth date input
2. inline validation
3. local save
4. triggering sync

### Local Model And Repository Layer

Owns:

1. birth-date storage
2. age derivation helpers
3. local validity checks
4. mapping to Supabase `public.children`

### Loading Screen

Owns:

1. startup preload sequencing
2. online hydration into SQLite
3. offline fallback behavior
4. routing based on local state

### Home Screen

Owns:

1. defensive access re-check
2. rendering derived age from local `birth_date`

## Risks And Mitigations

### Risk: Mixed legacy and new data paths

Mitigation:
Route legacy records back to setup instead of trying to infer a birth date.

### Risk: Remote and local schema mismatch

Mitigation:
Introduce explicit mapping functions between the local child model and Supabase `public.children`.

### Risk: Online fetch failures during startup

Mitigation:
Treat online hydration as an enhancement, not a runtime requirement. Continue from SQLite fallback.

## Acceptance Criteria

1. Initial Child Info uses a birth date picker instead of direct age entry.
2. Future birth dates are blocked.
3. Age is auto-derived and must be between 2 and 6 inclusive.
4. Dashboard access is blocked when the local child profile is invalid.
5. Existing age-only users are forced back through Initial Child Info.
6. Local SQLite remains the runtime source for startup and dashboard reads.
7. Supabase `public.children` is the remote sync target for child profile data.
8. [`loading_screen.dart`](D:\Projects\aumazing\apps\main_app\lib\features\splash\loading_screen.dart) performs online preload when internet is available and falls back to SQLite when it is not.
9. Offline gameplay and performance updates continue syncing to Supabase after connectivity returns.
