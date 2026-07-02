# Supabase Database Schema - Aumazing AI Assessment

**Project Reference:** `lzvvjlcfoyczikaszrbp`  
**URL:** `https://lzvvjlcfoyczikaszrbp.supabase.co`  
**Discovery Date:** April 23, 2026  
**Status:** All tables are currently empty (0 rows)

---

## Overview

This database appears to be designed for a **child sensory assessment and learning platform** — likely focused on autism/developmental assessments. The schema supports:

- **Child profiles** with sensory assessments
- **Game-based assessments** with sessions, rounds, and events
- **Learning modules** organized into paths
- **Caregiver questionnaires** for supplementary data
- **Assessment comparisons** for tracking progress over time
- **Module recommendations** based on assessment results

---

## Tables (13 total)

### 1. `children`
Core table for child profiles.

| Column | Description (inferred) |
|--------|----------------------|
| `id` | Primary key |
| `created_at` | Record creation timestamp |
| `updated_at` | Last update timestamp |
| `display_name` | Child's display name |
| `birth_date` | Date of birth |
| `notes` | Free-text notes |

---

### 2. `sensory_profiles`
Stores sensory profile data for each child, linked to assessment runs.

| Column | Description (inferred) |
|--------|----------------------|
| `id` | Primary key |
| `created_at` | Record creation timestamp |
| `child_id` | FK → `children.id` |
| `notes` | Free-text notes |
| `assessment_run_id` | FK → `assessment_runs.id` |

---

### 3. `learning_modules`
Defines available learning/game modules.

| Column | Description (inferred) |
|--------|----------------------|
| `id` | Primary key |
| `created_at` | Record creation timestamp |
| `updated_at` | Last update timestamp |
| `title` | Module title |
| `description` | Module description |
| `active` | Whether the module is active |
| `difficulty_level` | Difficulty level setting |

---

### 4. `module_paths`
Defines learning paths (ordered sequences of modules).

| Column | Description (inferred) |
|--------|----------------------|
| `id` | Primary key |
| `created_at` | Record creation timestamp |
| `updated_at` | Last update timestamp |
| `name` | Path name |
| `description` | Path description |

---

### 5. `module_path_items`
Junction table linking modules to paths (many-to-many).

| Column | Description (inferred) |
|--------|----------------------|
| `id` | Primary key |
| `created_at` | Record creation timestamp |
| `module_id` | FK → `learning_modules.id` |
| `path_id` | FK → `module_paths.id` |

---

### 6. `assessment_runs`
Tracks individual assessment sessions/runs for a child.

| Column | Description (inferred) |
|--------|----------------------|
| `id` | Primary key |
| `created_at` | Record creation timestamp |
| `updated_at` | Last update timestamp |
| `child_id` | FK → `children.id` |
| `notes` | Free-text notes |
| `started_at` | Assessment start time |
| `ended_at` | Assessment end time |
| `completed` | Whether the assessment was completed |
| `version` | Assessment version |

---

### 7. `game_sessions`
Tracks individual game sessions within an assessment.

| Column | Description (inferred) |
|--------|----------------------|
| `id` | Primary key |
| `created_at` | Record creation timestamp |
| `updated_at` | Last update timestamp |
| `child_id` | FK → `children.id` |
| `game_id` | Game identifier |
| `module_id` | FK → `learning_modules.id` |
| `assessment_run_id` | FK → `assessment_runs.id` |
| `started_at` | Session start time |
| `ended_at` | Session end time |
| `duration_seconds` | Session duration in seconds |
| `completed` | Whether the session was completed |
| `difficulty_level` | Difficulty level used |
| `accuracy` | Accuracy score/percentage |

---

### 8. `game_rounds`
Individual rounds within a game session.

| Column | Description (inferred) |
|--------|----------------------|
| `id` | Primary key |
| `created_at` | Record creation timestamp |
| `session_id` | FK → `game_sessions.id` |
| `completed` | Whether the round was completed |
| `correct` | Whether the response was correct |
| `stimulus_type` | Type of stimulus presented |
| `response_time` | Response time (likely in ms) |

---

### 9. `session_events`
Granular event tracking within sessions.

| Column | Description (inferred) |
|--------|----------------------|
| `id` | Primary key |
| `created_at` | Record creation timestamp |
| `session_id` | FK → `game_sessions.id` |
| `round_id` | FK → `game_rounds.id` |
| `event_type` | Type of event |

---

### 10. `assessment_results`
Stores results/scores from assessments.

#### Base columns (original)

| Column | Description (inferred) |
|--------|----------------------|
| `id` | Primary key |
| `created_at` | Record creation timestamp |
| `updated_at` | Last update timestamp |
| `child_id` | FK → `children.id` |
| `notes` | Free-text notes |
| `assessment_run_id` | FK → `assessment_runs.id` |
| `sensory_score` | Computed sensory score |

#### Legacy single-profile AI columns (added 2026-04-24)

Added by `supabase/migrations/20260424_ai_assessment_columns.sql`. **Retained** for backwards compatibility but are now derived fields populated alongside the per-area columns below.

| Column | Type | Description |
|--------|------|-------------|
| `predicted_profile` | TEXT | Legacy 5-class label (`communication_support` / `social_support` / `play_support` / `attention_support` / `balanced_profile`). Derived from per-area levels via tie-break in `app/rules.py`. |
| `confidence` | REAL | Confidence of the dominant area's prediction (0.0–1.0). |
| `support_level` | TEXT | `high` / `moderate` / `low` derived from `confidence`. |
| `type` | TEXT | `pre` / `post` / `progress` (defaults to `pre`). |
| `game_id` | TEXT | Optional game identifier when the row reflects a single game. |
| `score`, `total_items`, `error_count`, `avg_response_time_ms` | INT | Per-game raw metrics when applicable. |
| `raw_metrics` | JSONB | Free-form JSON for additional metrics. |

#### Per-area ordinal columns (added 2026-05-12 — Path B)

Added by `supabase/migrations/20260512_per_area_levels.sql`. **These are now the canonical AI output.** Each level column stores `0` (Needs Support), `1` (Emerging), or `2` (Strength) for the corresponding developmental skill area.

| Column | Type | Description |
|--------|------|-------------|
| `communication_level` | SMALLINT | Ordinal level for the Communication skill area. |
| `social_level` | SMALLINT | Ordinal level for the Social Interaction skill area. |
| `play_level` | SMALLINT | Ordinal level for the Play Skills area. |
| `attention_level` | SMALLINT | Ordinal level for the Attention & Focus area. |
| `communication_confidence` | REAL | Model confidence for `communication_level` (0.0–1.0). |
| `social_confidence` | REAL | Model confidence for `social_level`. |
| `play_confidence` | REAL | Model confidence for `play_level`. |
| `attention_confidence` | REAL | Model confidence for `attention_level`. |

Constraints enforce `level ∈ {0, 1, 2}` and `confidence ∈ [0, 1]`. Indexes exist on each individual level column and on the composite `(communication_level, social_level, play_level, attention_level)` tuple to support analytical queries (e.g., "all children with two or more areas at Needs Support").

The semantics of the four levels are documented in `ai_assessment/training/LABELING_RUBRIC.md` (the single source of truth for the labeling scheme).

---

### 11. `assessment_comparisons`
Enables comparing assessment runs over time (progress tracking).

| Column | Description (inferred) |
|--------|----------------------|
| `id` | Primary key |
| `created_at` | Record creation timestamp |
| `child_id` | FK → `children.id` |

> **Note:** This table likely has additional columns with domain-specific names that weren't discovered via probing.

---

### 12. `caregiver_questionnaires`
Questionnaire responses from caregivers.

| Column | Description (inferred) |
|--------|----------------------|
| `id` | Primary key |
| `created_at` | Record creation timestamp |
| `updated_at` | Last update timestamp |
| `child_id` | FK → `children.id` |
| `assessment_run_id` | FK → `assessment_runs.id` |
| `sensory_score` | Computed sensory score from questionnaire |
| `questionnaire_type` | Type of questionnaire |

---

### 13. `module_recommendations`
AI/system-generated module recommendations for children.

| Column | Description (inferred) |
|--------|----------------------|
| `id` | Primary key |
| `created_at` | Record creation timestamp |
| `updated_at` | Last update timestamp |
| `child_id` | FK → `children.id` |
| `status` | Recommendation status |

> **Note:** This table likely has additional columns linking to recommended modules.

---

## Entity Relationship Diagram (Text)

```
children (1) ──────┬──── (N) sensory_profiles
                   ├──── (N) assessment_runs ──── (N) assessment_results
                   │                          ├── (N) game_sessions ──── (N) game_rounds
                   │                          │                     └── (N) session_events
                   │                          ├── (N) sensory_profiles
                   │                          └── (N) caregiver_questionnaires
                   ├──── (N) assessment_comparisons
                   ├──── (N) caregiver_questionnaires
                   └──── (N) module_recommendations

learning_modules (N) ──── module_path_items ──── (N) module_paths
                     └──── (N) game_sessions
```

---

## Key Relationships

| From Table | Column | → To Table | Column |
|-----------|--------|-----------|--------|
| `sensory_profiles` | `child_id` | `children` | `id` |
| `sensory_profiles` | `assessment_run_id` | `assessment_runs` | `id` |
| `assessment_runs` | `child_id` | `children` | `id` |
| `game_sessions` | `child_id` | `children` | `id` |
| `game_sessions` | `module_id` | `learning_modules` | `id` |
| `game_sessions` | `assessment_run_id` | `assessment_runs` | `id` |
| `game_rounds` | `session_id` | `game_sessions` | `id` |
| `session_events` | `session_id` | `game_sessions` | `id` |
| `session_events` | `round_id` | `game_rounds` | `id` |
| `assessment_results` | `child_id` | `children` | `id` |
| `assessment_results` | `assessment_run_id` | `assessment_runs` | `id` |
| `assessment_comparisons` | `child_id` | `children` | `id` |
| `caregiver_questionnaires` | `child_id` | `children` | `id` |
| `caregiver_questionnaires` | `assessment_run_id` | `assessment_runs` | `id` |
| `module_recommendations` | `child_id` | `children` | `id` |
| `module_path_items` | `module_id` | `learning_modules` | `id` |
| `module_path_items` | `path_id` | `module_paths` | `id` |

---

## Notes

- **All tables are currently empty** (0 rows of data).
- Column discovery was performed by probing ~130 common column names against each table. Some tables may have additional columns with unique/domain-specific names not covered by the probe list.
- Tables like `assessment_comparisons` and `module_recommendations` appear to have fewer discovered columns, suggesting they may have domain-specific column names not yet identified.
- The database uses the `public` schema with Row Level Security (RLS) likely enabled.
- The `sb_publishable` API key was used for discovery, which may restrict visibility of some columns/tables.
