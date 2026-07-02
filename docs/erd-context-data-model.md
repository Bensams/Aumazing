# Figure 1: Context Data Model — Aumazing

## Overview

This Entity Relationship Diagram shows the **context-level data model** for the Aumazing educational app for children with autism. It displays only entity names and their relationships with cardinality — no attributes are shown. This view is useful for understanding the high-level structure and how the 16 Supabase (remote) entities relate to each other.

> **Note:** Only Supabase (remote/canonical) tables are represented. SQLite local tables are offline mirrors and are not included as separate entities.

---

```mermaid
---
title: "Figure 1: Context Data Model — Aumazing"
---
erDiagram
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
| `\|\|` | Exactly one (mandatory) |
| `o{` | Zero or many (optional) |
| `\|\|--o{` | One-to-many relationship |
| Entity box | A Supabase remote table |

### Key Observations

- **Children** is the central entity, connected to most other entities either directly or through **Assessment_Runs**.
- **Assessment_Runs** acts as a hub for assessment-related data: it links to **Game_Sessions**, **Assessment_Results**, **Sensory_Profiles**, **Caregiver_Questionnaires**, and **Module_Recommendations**.
- **Game_Sessions** capture gameplay data and are linked to both **Game_Rounds** and **Session_Events** for granular tracking.
- **Learning_Modules** connect to the curriculum structure via **Module_Path_Items** and to recommendations via **Module_Recommendations**.
- **Games** and **Skill_Categories** are linked through the junction table **Game_Skill_Categories**.
- **Module_Paths** organize learning modules into ordered sequences via **Module_Path_Items**.
