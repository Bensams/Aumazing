# Aumazing Pre-Assessment Labeling Rubric

**Version:** 1.0
**Last updated:** May 2026
**Owners:** Aumazing capstone project proponents
**Audience:** Subject-matter expert (SME) validators, capstone panelists, future maintainers of `ai_assessment/`.

---

## 1. Purpose

This rubric is the **single source of truth** for how a child's gameplay metrics are translated into developmental skill-area labels in the Aumazing Pre-Assessment system.

The same rubric is used in **three places**, and they must remain consistent:

1. **Synthetic dataset generation** — implemented as `derive_labels()` in `training/generate_training_data.py`.
2. **SME content validation** — printed/handed to validators when they label held-out gameplay rows.
3. **Model behavior** — the trained `MultiOutputClassifier` learns to reproduce these rules from the 12 input features.

If the rubric is ever changed, **all three** must be updated together.

---

## 2. Skill areas and target encoding

Each child receives **one ordinal label per area** (4 total).

| Skill area | Target column | Levels (integer encoding) |
|---|---|---|
| Communication | `communication_level` | 0 = Needs Support, 1 = Emerging, 2 = Strength |
| Social Interaction | `social_level` | 0 = Needs Support, 1 = Emerging, 2 = Strength |
| Play Skills | `play_level` | 0 = Needs Support, 1 = Emerging, 2 = Strength |
| Attention & Focus | `attention_level` | 0 = Needs Support, 1 = Emerging, 2 = Strength |

A child with weakness in two or more areas (e.g., communication = 0, social = 0) is captured **natively** by the multi-output design — there is no "pick one weakness" forced choice.

---

## 3. Driving features per area

The 12 aggregated input features come from the four mini-games (`Copy Me`, `Match It`, `My Turn, Your Turn`, `Do What I Say`) plus session-level behavioral metrics. Each skill area is driven by a specific subset:

| Area | Driving feature(s) | Operationalization |
|---|---|---|
| **Communication** | `copy_me_accuracy`, `do_what_i_say_accuracy` | Mean of the two (imitation + receptive instructions) |
| **Social Interaction** | `my_turn_your_turn_accuracy` | Single-game accuracy (turn-taking) |
| **Play Skills** | `match_it_accuracy` | Single-game accuracy (matching) |
| **Attention & Focus** | `overall_idle_time_seconds`, `overall_invalid_touch_count`, `overall_avg_response_time`, `overall_prompt_dependency_score` | Count of *elevated markers* (4 binary checks; threshold-based) |

The accuracy-based areas (Communication, Social, Play) are deliberately *independent of* the attention markers, so a child can be labeled "Needs Support" in Attention without their accuracy labels collapsing in lockstep.

---

## 4. Threshold table (the rules)

### 4.1 Accuracy areas (Communication, Social, Play)

| Score | Level (integer) | Label |
|---|---|---|
| ≥ 0.70 | 2 | Strength |
| 0.40 – 0.69 | 1 | Emerging |
| < 0.40 | 0 | Needs Support |

For Communication, the score is the **mean** of `copy_me_accuracy` and `do_what_i_say_accuracy`. For Social and Play, the score is the single driving feature directly.

### 4.2 Attention area

A behavioral marker is **elevated** if any of the following hold:

| Marker | Elevated when |
|---|---|
| `overall_idle_time_seconds` | > 15 seconds |
| `overall_invalid_touch_count` | > 6 invalid touches |
| `overall_avg_response_time` | > 5.0 seconds |
| `overall_prompt_dependency_score` | > 0.50 (i.e. hints needed on more than half the items) |

Then `attention_level` is determined by the **count of elevated markers** (0–4):

| Elevated markers | Level | Label |
|---|---|---|
| 0 or 1 | 2 | Strength |
| Exactly 2 | 1 | Emerging |
| 3 or 4 | 0 | Needs Support |

### 4.3 Tie-breaks

The rubric is deterministic; no tie-break is needed for the per-area labels themselves. The legacy `predicted_profile` derivation (used only for backwards compatibility with old Flutter clients) follows a separate priority order documented in `app/rules.py` and is **not** part of this rubric.

---

## 5. Worked examples

These three rows are sampled from `sample_preassessment_data.csv` patterns. They illustrate the boundary cases SMEs are most likely to grill.

### Example A — Communication-only weakness

| Feature | Value |
|---|---|
| `copy_me_accuracy` | 0.20 |
| `do_what_i_say_accuracy` | 0.25 |
| `match_it_accuracy` | 0.65 |
| `my_turn_your_turn_accuracy` | 0.55 |
| `overall_idle_time_seconds` | 14 |
| `overall_invalid_touch_count` | 5 |
| `overall_avg_response_time` | 5.2 |
| `overall_prompt_dependency_score` | 0.62 |

**Labels:**
- Communication: mean(0.20, 0.25) = 0.225 < 0.40 → **0 (Needs Support)**
- Social: 0.55 in [0.40, 0.70) → **1 (Emerging)**
- Play: 0.65 in [0.40, 0.70) → **1 (Emerging)**
- Attention: idle 14 (no), invalid 5 (no), response 5.2 (yes), prompt 0.62 (yes) = 2 markers → **1 (Emerging)**

### Example B — Co-occurring communication + social weakness

| Feature | Value |
|---|---|
| `copy_me_accuracy` | 0.25 |
| `do_what_i_say_accuracy` | 0.30 |
| `match_it_accuracy` | 0.75 |
| `my_turn_your_turn_accuracy` | 0.20 |
| Attention markers | 1 elevated |

**Labels:**
- Communication: mean(0.25, 0.30) = 0.275 → **0 (NS)**
- Social: 0.20 → **0 (NS)**
- Play: 0.75 → **2 (Strength)**
- Attention: 1 marker → **2 (Strength)**

This is exactly the case a single-label classifier cannot represent. The per-area design recommends modules for both the communication and social areas in one assessment cycle.

### Example C — Attention-only weakness

| Feature | Value |
|---|---|
| `copy_me_accuracy` | 0.55 |
| `do_what_i_say_accuracy` | 0.50 |
| `match_it_accuracy` | 0.52 |
| `my_turn_your_turn_accuracy` | 0.48 |
| `overall_idle_time_seconds` | 28 |
| `overall_invalid_touch_count` | 11 |
| `overall_avg_response_time` | 7.2 |
| `overall_prompt_dependency_score` | 0.55 |

**Labels:**
- Communication: mean(0.55, 0.50) = 0.525 → **1 (Emerging)**
- Social: 0.48 → **1 (Emerging)**
- Play: 0.52 → **1 (Emerging)**
- Attention: 28 > 15 (yes), 11 > 6 (yes), 7.2 > 5 (yes), 0.55 > 0.50 (yes) = 4 markers → **0 (NS)**

The child's accuracies are all in the Emerging band, but four behavioral markers are elevated, so attention dominates as the primary support need.

---

## 6. Mapping to recommended modules

This is downstream of the rubric — included here for completeness only. The recommendation engine (`app/rules.py`) suggests a module for **every area not labeled Strength**, with starting difficulty driven by the level:

| Area | Module(s) |
|---|---|
| Communication | Copy Me, Do What I Say |
| Social Interaction | My Turn, Your Turn |
| Play Skills | Match It |
| Attention & Focus | Do What I Say, Match It (cross-domain) |

| Level | Starting difficulty |
|---|---|
| 0 (Needs Support) | 1 (easiest) |
| 1 (Emerging) | 2 |
| 2 (Strength) | not recommended |

When a module is driven by multiple areas (e.g., Do What I Say is recommended for both Communication and Attention), the **lowest** starting level wins so the child gets enough scaffolding.

---

## 7. Reference frameworks

The rubric was authored by the proponents based on the following constructs and frameworks. All citations are within the capstone's 5-year currency requirement (2021–2026) except where a foundational methodological reference is unavoidable.

| Concept | Reference |
|---|---|
| Social-communication vs. attention domain split | American Psychiatric Association (2022). *Diagnostic and Statistical Manual of Mental Disorders* (5th ed., text rev.; DSM-5-TR). |
| International developmental domain framework | World Health Organization (2022). *International Classification of Diseases* (11th rev.; ICD-11). |
| Domain-based assessment approach | Lord, C., Charman, T., Havdahl, A., et al. (2022). The Lancet Commission on the future of care and clinical research in autism. *The Lancet*, 399(10321), 271–334. |
| Prompt dependency as a measurable behavioral construct | Contemporary applied behavior analysis literature (e.g., Leaf, J. B., Cihon, J. H., Ferguson, J. L., et al., 2022, *Behavior Analysis in Practice*; *Education and Treatment of Children*). |
| Digital behavioral phenotyping precedent (gameplay-as-screening rationale) | Perochon, S., Di Martino, J. M., Carpenter, K. L. H., et al. (2023). *Nature Medicine*, 29(10), 2489–2497. — Megerian, J. T., Dey, S., Melmed, R. D., et al. (2022). *npj Digital Medicine*, 5(1), 57. — Washington, P., Park, N., Srivastava, P., et al. (2021). *Biological Psychiatry: CNNI*, 6(8), 759–769. |
| Inter-rater reliability statistic (κ) | Cohen, J. (1960). A coefficient of agreement for nominal scales. *Educational and Psychological Measurement*, 20(1), 37–46. *(Foundational methodology — typically exempt from currency rules.)* |

---

## 8. Validation procedure

1. **Recruit** 2–3 SMEs with relevant credentials (SPED teacher, developmental pediatrician, OT, or BCBA).
2. **Hand them this document.** They label a held-out set of *N* (recommended ≥ 30) rows independently and blind to each other and to the synthetic gold labels.
3. **Compute inter-rater reliability** per area using Cohen's κ (2 raters) or Fleiss' κ (3+ raters).
4. **Hold a consensus meeting** for disagreements; the consensus labels become the gold-standard validation set.
5. **Report** in Chapter 4: per-area κ, percent agreement, and the model's accuracy on the consensus-labeled validation set.

---

## 9. Change log

| Version | Date | Author | Notes |
|---|---|---|---|
| 1.0 | 2026-05-12 | Capstone proponents | Initial rubric for Path B per-area ordinal design. Mirrors `derive_labels()` in `training/generate_training_data.py` and the threshold constants in that file. |

---

## 10. Implementation cross-reference

| Concept in this rubric | Code location |
|---|---|
| Accuracy thresholds (0.40, 0.70) | `ACC_EMERGING_MIN`, `ACC_STRENGTH_MIN` in `training/generate_training_data.py` |
| Attention marker thresholds | `ATTN_IDLE_THRESHOLD`, `ATTN_INVALID_TOUCH_THRESHOLD`, `ATTN_RESPONSE_TIME_THRESHOLD`, `ATTN_PROMPT_DEP_THRESHOLD` in `training/generate_training_data.py` |
| Marker-count rule (3+ → NS, 2 → Emerging, ≤1 → Strength) | `ATTN_NEEDS_SUPPORT_MIN_MARKERS`, `ATTN_EMERGING_MIN_MARKERS` in same file |
| Label derivation function | `derive_labels()` in `training/generate_training_data.py` |
| Module mapping | `AREA_MODULE_MAP` in `app/rules.py` |
| Level → starting difficulty | `LEVEL_TO_STARTING_LEVEL` in `app/rules.py` |
| Database storage | `assessment_results.{communication,social,play,attention}_level` columns added by `supabase/migrations/20260512_per_area_levels.sql` |

If you change a threshold in this document, you **must** update the matching constant in `generate_training_data.py` and regenerate the dataset + retrain the model. The rubric and the code are intentionally redundant so the panel can audit either side independently.
