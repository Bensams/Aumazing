# Figure 3: Fully Attributed Data Model — Aumazing

## Overview

This Entity Relationship Diagram shows the **fully attributed data model** for the Aumazing educational app for children with autism. Every entity includes **all columns** with their data types and PK/FK markers. This is the most detailed view, suitable for implementation reference and database documentation.

> **Note:** Only Supabase (remote/canonical) tables are represented. SQLite local tables are offline mirrors and are not included as separate entities.

---

```mermaid
---
title: "Figure 3: Fully Attributed Data Model — Aumazing"
---
erDiagram
    Children {
        uuid id PK
        timestamptz created_at
        timestamptz updated_at
        text display_name
        date birth_date
        text notes
        uuid parent_user_id FK "FK to auth.users"
    }

    Sensory_Profiles {
        uuid id PK
        timestamptz created_at
        uuid child_id FK
        text notes
        uuid assessment_run_id FK
    }

    Learning_Modules {
        uuid id PK
        timestamptz created_at
        timestamptz updated_at
        text title
        text description
        boolean active
        integer difficulty_level
    }

    Module_Paths {
        uuid id PK
        timestamptz created_at
        timestamptz updated_at
        text name
        text description
    }

    Module_Path_Items {
        uuid id PK
        timestamptz created_at
        uuid module_id FK
        uuid path_id FK
    }

    Assessment_Runs {
        uuid id PK
        timestamptz created_at
        timestamptz updated_at
        uuid child_id FK
        text notes
        timestamptz started_at
        timestamptz ended_at
        boolean completed
        text version
    }

    Game_Sessions {
        uuid id PK
        timestamptz created_at
        timestamptz updated_at
        uuid child_id FK
        text game_id
        uuid module_id FK
        uuid assessment_run_id FK
        timestamptz started_at
        timestamptz ended_at
        real duration_seconds
        boolean completed
        integer difficulty_level
        real accuracy
        real task_completion_rate
        real prompt_dependency_score
        real turn_taking_success_rate
        integer interruption_count
        real waiting_tolerance_seconds
        real time_to_first_touch
        real time_to_first_valid_action
        real time_to_completion
        text sensory_condition
    }

    Game_Rounds {
        uuid id PK
        timestamptz created_at
        uuid session_id FK
        boolean completed
        boolean correct
        text stimulus_type
        real response_time
    }

    Session_Events {
        uuid id PK
        timestamptz created_at
        uuid session_id FK
        uuid round_id FK
        text event_type
    }

    Assessment_Results {
        uuid id PK
        timestamptz created_at
        timestamptz updated_at
        uuid child_id FK
        text notes
        uuid assessment_run_id FK
        real sensory_score
        text type
        text game_id
        integer score
        integer total_items
        integer error_count
        integer random_touch_count
        integer avg_response_time_ms
        jsonb raw_metrics
        text predicted_profile
        real confidence
        text support_level
        text play_skills_label
        text communication_label
        text social_interaction_label
        text behavior_attention_label
        text sensory_preference_label
        text recommended_module
        text overall_summary
        text model_source
        boolean xgboost_ready
    }

    Assessment_Comparisons {
        uuid id PK
        timestamptz created_at
        uuid child_id FK
    }

    Caregiver_Questionnaires {
        uuid id PK
        timestamptz created_at
        timestamptz updated_at
        uuid child_id FK
        uuid assessment_run_id FK
        real sensory_score
        text questionnaire_type
    }

    Module_Recommendations {
        uuid id PK
        timestamptz created_at
        timestamptz updated_at
        uuid child_id FK
        text status
        uuid assessment_run_id FK
        uuid module_id FK
        text module_name
        text game_id
        integer starting_level
        real confidence
        text predicted_profile
        text rationale
        text_array skill_areas
    }

    Games {
        uuid id PK
        text slug
        text name
        text description
        text icon
        integer sort_order
        timestamptz created_at
    }

    Skill_Categories {
        uuid id PK
        text slug
        text name
        text description
        integer sort_order
        timestamptz created_at
    }

    Game_Skill_Categories {
        uuid id PK
        uuid game_id FK
        uuid skill_category_id FK
        real weight
        timestamptz created_at
    }

    Children ||--o{ Sensory_Profiles : "has"
    Children ||--o{ Assessment_Runs : "undergoes"
    Children ||--o{ Game_Sessions : "plays"
    Children ||--o{ Assessment_Results : "receives"
    Children ||--o{ Assessment_Comparisons : "has"
    Children ||--o{ Caregiver_Questionnaires : "has"
    Children ||--o{ Module_Recommendations : "receives"

    Assessment_Runs ||--o{ Game_Sessions : "contains"
    Assessment_Runs ||--o{ Assessment_Results : "produces"
    Assessment_Runs ||--o{ Sensory_Profiles : "generates"
    Assessment_Runs ||--o{ Caregiver_Questionnaires : "includes"
    Assessment_Runs ||--o{ Module_Recommendations : "triggers"

    Game_Sessions ||--o{ Game_Rounds : "contains"
    Game_Sessions ||--o{ Session_Events : "logs"

    Game_Rounds ||--o{ Session_Events : "triggers"

    Learning_Modules ||--o{ Game_Sessions : "used in"
    Learning_Modules ||--o{ Module_Path_Items : "included in"
    Learning_Modules ||--o{ Module_Recommendations : "recommended via"

    Module_Paths ||--o{ Module_Path_Items : "contains"

    Games ||--o{ Game_Skill_Categories : "categorized by"
    Skill_Categories ||--o{ Game_Skill_Categories : "applied to"
```

---

## Legend & Conventions

| Symbol | Meaning |
|--------|---------|
| `PK` | Primary Key — uniquely identifies each row |
| `FK` | Foreign Key — references a PK in another entity |
| `\|\|--o{` | One-to-many relationship |

### Data Type Reference

| Type | Description |
|------|-------------|
| `uuid` | Universally Unique Identifier (v4) |
| `timestamptz` | Timestamp with time zone |
| `text` | Variable-length string |
| `date` | Calendar date (no time component) |
| `boolean` | True/false value |
| `integer` | 32-bit signed integer |
| `real` | Single-precision floating-point number |
| `jsonb` | Binary JSON for flexible/nested data |
| `text_array` | Array of text values (PostgreSQL `text[]`) |

### Entity Descriptions

| Entity | Purpose | Row Count Expectation |
|--------|---------|-----------------------|
| **Children** | Core entity representing each child user in the system | Low (tens to hundreds) |
| **Sensory_Profiles** | Stores sensory profile snapshots generated per assessment run | Low–Medium |
| **Learning_Modules** | Defines available learning modules/games in the curriculum | Low (reference data) |
| **Module_Paths** | Named sequences of learning modules for structured progression | Low (reference data) |
| **Module_Path_Items** | Junction table linking modules to paths with ordering | Low (reference data) |
| **Assessment_Runs** | Represents a complete assessment session for a child | Medium |
| **Game_Sessions** | Individual game play sessions with rich behavioral metrics | High |
| **Game_Rounds** | Individual rounds within a game session | Very High |
| **Session_Events** | Granular event log for each session/round interaction | Very High |
| **Assessment_Results** | ML-generated assessment outcomes with scores and labels | Medium |
| **Assessment_Comparisons** | Tracks comparisons between assessment runs over time | Low–Medium |
| **Caregiver_Questionnaires** | Caregiver-submitted questionnaire responses per assessment | Medium |
| **Module_Recommendations** | AI-generated module recommendations based on assessment results | Medium |
| **Games** | Reference table of all available games | Low (reference data) |
| **Skill_Categories** | Reference table of skill categories for game classification | Low (reference data) |
| **Game_Skill_Categories** | Junction table mapping games to skill categories with weights | Low (reference data) |

### Notable Design Patterns

1. **Behavioral Metrics on Game_Sessions**: The `Game_Sessions` entity is the richest, containing 22 columns including detailed behavioral metrics (`prompt_dependency_score`, `turn_taking_success_rate`, `waiting_tolerance_seconds`, etc.) that feed into the ML assessment pipeline.

2. **ML Pipeline Outputs on Assessment_Results**: Contains both raw scores and ML-predicted labels (`predicted_profile`, `confidence`, `support_level`) along with domain-specific labels for play skills, communication, social interaction, behavior/attention, and sensory preferences.

3. **Dual Timestamp Pattern**: Most entities use `created_at` / `updated_at` for audit tracking. Some entities (like `Assessment_Runs` and `Game_Sessions`) also have domain-specific timestamps (`started_at` / `ended_at`).

4. **Junction Tables**: `Module_Path_Items` and `Game_Skill_Categories` serve as many-to-many bridge tables with additional metadata (`weight` on Game_Skill_Categories).

5. **External FK**: `Children.parent_user_id` references `auth.users` in Supabase Auth, which is outside this schema but enforces that each child belongs to an authenticated parent/caregiver.
