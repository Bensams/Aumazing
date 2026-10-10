# Pre-final defense notes — analysis

Analysis of the panel's pre-final defense notes and the SPED teachers'
suggestion (Ma'am Lea Famor and Ma'am Mary Ann), measured against what the
repository and the live database hold as of 2026-09-27. **Nothing here has
been implemented yet.** Each item gives what was asked, what exists, the gap,
a recommendation, a rough size, and the decisions only the proponents can
make.

Size: **S** ≈ under a day · **M** ≈ 2–4 days · **L** ≈ a week or more.

---

## Summary

| # | Note | Type | Exists today | Size | Priority |
|---|---|---|---|---|---|
| 1 | Basic learning before the pre-assessment (SPED teachers + panel) | Impl. | Assets and voice lines yes; screen no | M | **High** — affects assessment validity |
| 2 | Parent survey/questionnaire during pre- and post-assessment | Impl. | Storage exists (local + live table, 0 rows); no UI, no instrument | M–L | **High** |
| 3 | Practitioner/therapist role that adds pre/post surveys | Impl. | Parent and admin only | L | Medium — build on #2 |
| 4 | Custom screen-time limits | Impl. | Presets only | S | High — quick win |
| 5 | Child profiles tied to payment (1 free, ₱30 each extra, Premium only) | Impl. | Unlimited, free | M | Medium — needs a pricing decision |
| 6 | Synthetic data based on real pre-assessment results and ASD gameplay data | Testing | Generator uses independent uniform draws | M | **High** — defense-critical |
| 7 | Cost includes developer labour at industry rates | Docs | Only a ₱1,200 testing budget found | S | High |
| 8 | Problem statement quotes the reference directly | Docs | — (manuscript not in repo) | S | High |
| 9 | Highlight the PWA / web app and that it does not interrupt children | Docs | Offline web build exists (AUM-334) | S | Medium |
| 10 | Future recommendation: mechanism for practitioners to update materials | Docs | Not present | S | Medium |
| 11 | Kanban backlog shown phase by phase, including pending items | Docs | Board only | S | Medium |
| 12 | Kanban figures (screenshots of the board) | Docs | None in repo | S | Medium |
| 13 | Transcriptions of interviews and other testing artifacts, licenses | Addition | Audio licensing doc only | S–M | Medium |
| 14 | Align each backlog item to an objective | Docs | — | S | Medium |

Recommended order: **#4 → #1 → #2 → #6 → #5 → #3**. Docs items (#7–#14) can
run in parallel with the implementation work.

---

## 1. Basic learning before the pre-assessment

> "Add basic learning — shapes, colors, objects, or assets used in the game —
> so later on children know what the colors, objects, shapes, etc. are. This
> feature is before starting pre-assessment." — SPED teachers
>
> "Very basic learning material for kids before pre-assessment and doing
> registered activities in the game, so they have understanding of the
> shapes, colors, objects included in the game." — panel

### Why it matters more than it looks

It is not just a nice extra. It protects what the pre-assessment measures.

The pre-assessment is four games, in this order: **Copy Me → Do What I Say →
My Turn, Your Turn → Match It**.

- **Do What I Say** speaks composite instructions such as "Tap the *red*
  *star*". It uses six colour words (red, blue, green, yellow, purple,
  orange) and five shape words (circle, star, triangle, diamond, heart).
- **Match It** and **Copy Me** use the same shapes and colours.

A child who does not yet know the word "purple" fails a Do What I Say trial.
The failure comes from vocabulary, not from the skill the game reports
(following instructions, feeding the communication domain). The baseline then
understates the child, and the recommended module is chosen from a wrong
reading. A short familiarisation step before scored trials is standard
practice in child assessment for this reason. It is the strongest argument
for the feature in the manuscript.

### What already exists (no new art or audio needed for the core)

- **Voice lines**: colour names, shape names, and colour+shape phrases
  ("Purple circle") are already recorded in all 18 voice packs, in English,
  Filipino and Cebuano. Item names (Tinapay, Gatas, …), letters, numbers,
  emotions and routine names are recorded too.
- **Drawing**: `ShapePainter3D` already draws every shape the games use.
  Colours are defined in the games themselves.
- **Pictures**: seed cards (animals plus food, fruit, essentials and toys),
  emotion faces and scenes, routine cards, and the two buddy characters, all
  under `packages/shared_ui/assets/`.
- **No viewer exists**: there is no "learn", flashcard or vocabulary screen.
  The assets are only drawn inside the games.
- **No practice round**: the pre-assessment launches straight into scored
  trials. The Easy-tier guided demo exists, but the assessment profile
  suppresses all hints.

### Risks to design around

1. **Teaching to the test.** Showing the exact items right before scoring
   could be read as coaching. Keep it *familiarisation*, not training:
   - unscored and short
   - the same fixed content for every child
   - never a quiz
2. **Pre/post symmetry.** Give the identical step before the post-assessment
   too. Then any pre → post change cannot be explained by the step.
3. **Record it.** Log whether it was completed or skipped, and how long it
   took, so it can be reported (or used as a covariate) rather than
   invisible.
4. **Do not gate the assessment on it.** The parent can skip it. A child who
   refuses must still be able to start.

### Recommended design (for discussion with the teachers)

A "Let's learn first" step inserted after the sensory set-up. It sits between
`PreAssessmentIntroScreen`'s sensory consent and `PreAssessmentProgressScreen`,
so the child's music, vibration and prompt-speed choices already apply.

1. **Colours** — six swatches. Tapping one speaks its name. A pointing hand
   invites the first tap.
2. **Shapes** — five shapes, same interaction.
3. **Together** — a few colour+shape cards using the existing phrase lines.
4. **How to play** (the panel's "registered activities") — one practice tap
   and one practice drag, since the assessment games use both mechanics.

Each page lasts about 30–60 seconds and is child-paced, with a clear "Next"
for the parent. It works fully offline, because every asset is bundled.

**Objects, emotions and routines** belong to the learning-path games, not to
the pre-assessment. Offer them as an optional "Learn" corner in the child
lobby instead of adding them to the pre-assessment path. That keeps the step
short, which matters for a 2–6-year-old's attention before four games.

### Decisions for the proponents and the teachers

- Is the exact vocabulary list right? Do the teachers want colours and shapes
  in Filipino as well, following the child's language setting?
- Should the step repeat before the post-assessment? (Recommended: yes,
  identically.)
- Is there a time cap, or should the parent end it?
- Should the "Learn" corner in the lobby be in scope now, or listed as a
  future recommendation?

**Size: M.** No asset generation is needed for colours, shapes or phrases. A
"This is a…" carrier line for objects would be the only new audio, and only
if the lobby corner is built.

---

## 2. Parent survey / questionnaire during pre- and post-assessment

### What exists

- **Live table `caregiver_questionnaires`** with columns:
  - `id`, `child_id`, `assessment_run_id`
  - `completed_by_user_id`, `completed_by_role`
  - `questionnaire_type`, `responses_json`
  - `social_communication_score`, `rrb_score`, `sensory_score`
  - `created_at`, `updated_at`

  RLS already restricts rows to the caller's own child and run (AUM-209).
  **0 rows.**
- **Local SQLite table** with the same name, with a `sync_status` index, so
  it is already part of offline-first sync.
- **No UI** writes to either table.
- Not to be confused with the UAT research surveys (Google Forms). Those are
  a separate instrument for the study, not an in-app feature.

### Gap

An instrument (the questions), a parent-facing screen, scoring, and a
pre-vs-post view on the dashboard.

### Recommendation

- **Where**: the natural moment is the hand-off. The child finishes the four
  games and the app already says "give the device to your parent". The parent
  answers there, before seeing results, so the results cannot bias the
  answers. The identical questionnaire runs after the post-assessment with
  `questionnaire_type` = `post`.
- **Instrument**: must be one the proponents may legally use and cite:
  - M-CHAT-R/F allows free clinical, research and educational use under its
    conditions.
  - SRS-2 and SCQ are paid instruments.
  - A checklist authored with the SPED teachers and validated by them is also
    defensible.

  The existing score columns (social communication, restricted/repetitive
  behaviour, sensory) suggest the originally intended instrument.
- **Design for #3 now**: store the questions as a *template* (data, not
  code), so a practitioner-authored questionnaire can later be added without
  an app release.
- **Report**: show parent-reported pre vs post next to the game-measured pre
  vs post. The contrast between the two is valuable for the manuscript.

**Size: M–L.** Storage is done; UI, instrument encoding, scoring and the
dashboard view remain. **Decision:** which instrument, and whether it is
licensed.

---

## 3. Approved practitioner/therapist role for surveys

### What exists

Two roles only:

- **parent**: owns children through `parent_user_id`
- **admin**: `public.is_admin()`, used for research and beta reports

There is no practitioner, therapist, teacher or clinician role. The
`therapy_centers` table is a directory, not accounts.

### What it takes

1. **Accounts** — a practitioner role, plus an approval workflow in which an
   admin verifies credentials (for example a PRC licence) before the role is
   granted.
2. **Templates** — a `questionnaire_templates` table (pre/post, versioned,
   authored by an approved practitioner, active or inactive), with RLS: only
   approved practitioners write; everyone reads active ones.
3. **Authoring UI** — a practitioner screen, likely web, which the web build
   makes cheaper.
4. **Linking** (optional) — whether a practitioner sees the results of the
   families who used their questionnaire. This carries privacy and consent
   implications under RA 10173 and needs explicit parent consent.

### Recommendation

Given the time to the final defense, deliver it in two phases:

- **Phase 1 (with #2)**: template-driven questionnaire. An admin enters a
  practitioner-approved template on their behalf.
- **Phase 2**: self-service practitioner accounts with approval.

Phase 2 can honestly go into Future Recommendations (see #10) if time runs
short.

**Size: L** for both phases, **M** for phase 1 on top of #2.

---

## 4. Custom screen-time limits

### What exists

Presets only:

- **Daily**: Off, 15, 20, 30, 45, 60, 90 minutes
  (`settings_screen.dart:2073`)
- **Per session**: none, 5, 10, 15, 20, 30 minutes

The age-based recommendation (20 / 30 / 45 / 60 minutes) and the "stricter
limit wins" rule stay as they are.

### Recommendation

Add a "Custom…" option that opens a minutes picker (for example 5–180 in
5-minute steps, per day and per session). Keep the presets as one-tap
shortcuts and keep showing the age-based recommendation next to the picker.
Limits are stored in minutes, so storage should not change. Add tests for the
boundaries.

**Size: S.** The easiest item on the list; a good first task.

---

## 5. Number of child profiles tied to payment

> "Strictly one profile per account, and adding another child profile costs
> an additional payment, like ₱30 per new profile, Premium-only."

### What exists

Unlimited sibling profiles, free (`manage_children_screen.dart`). Premium
(₱149/month) unlocks the therapy locator, trends and fresh recommendations,
not profiles. The `entitlements` table holds only `is_premium`, `source`,
`activated_at` and `expires_at`.

### What it takes

- An `extra_profile_slots` (or similar) entitlement field.
- A purchase flow for a slot.
- Gating "Add child" when slots are used.
- A migration rule for families who already have more than one child
  (recommended: keep what they have).

### Points to raise before building

- **Payment model**: is ₱30 one-time or monthly per profile? What happens
  when Premium lapses?
- **Siblings**: siblings of an autistic child have a much higher likelihood
  of autism themselves. Charging per child lands on exactly those families.
  Worth one sentence in the manuscript's cost/ethics discussion, or a free
  second slot.
- **Real payments**: if Premium is currently simulated, the per-profile
  purchase will be too. Say so plainly in the manuscript.

**Size: M.** **Decision:** the pricing model above.

---

## 6. Synthetic data based on real results and ASD gameplay data

### What exists

`ai_assessment/training/generate_training_data.py`:

- Draws every feature **independently from a uniform range** (accuracies
  0.05–0.95, idle 0–50, response time 1.5–12 s, …).
- Labels each row with `derive_labels()`, which is the scoring rubric itself.
- The on-device model is trained on that output.

### Why the panel flagged it

- **Circular**: a model trained on rubric-labelled data learns the rubric
  back, so its accuracy says nothing about real children.
- **Unrealistic**: independent uniform features ignore that real features are
  correlated. A child with low accuracy also tends to take longer and need
  more prompts.

### Real data available

The live database holds **19 assessment runs, 16 assessment results from 11
children** (some are test accounts), and about 268 game sessions. That is
too little to train on, but enough to calibrate a generator.

### Recommendation

1. Exclude test accounts, then estimate means, spreads and **correlations**
   of each feature from the real pre-assessment results and game sessions.
2. Anchor what cannot be estimated from 11 children to published ASD
   gameplay/serious-game studies, and cite them in the manuscript.
3. Generate from a correlated model (for example a Gaussian copula or
   multivariate normal on transformed features), not independent uniforms.
4. **Validate on real data only**: keep every real run as a held-out test
   set, and report synthetic-train → real-test results alongside the rubric
   agreement.
5. Document it all in the manuscript's Testing section, including the
   limitation that n is small.

**Size: M.** Defense-critical, because it answers "how do you know the model
works?".

---

## 7–14. Documentation items

The capstone manuscript is not kept in this repository; these apply to the
manuscript documents.

- **#7 Cost with developer labour.** The only budget found in the repo is the
  ₱1,200 testing budget in `Aumazing_Testing_Plan.md`.
  - Add a development-cost estimate: proponents' hours × prevailing PH
    junior developer rate.
  - Cite a salary survey (for example JobStreet or PhilJobNet data).
  - Keep the actual out-of-pocket costs (kie.ai credits, hosting, devices)
    as a separate line.
- **#8 Problem statement.** Quote the source sentence directly, with
  citation, instead of computing or paraphrasing figures. Keep any derived
  figure *after* the quote, labelled as the proponents' computation.
- **#9 PWA.** Document that the web build is installable and works fully
  offline after first load (AUM-334 service worker). A child can play with no
  connection, and nothing interrupts play: no reloads, no network prompts.
  Sync happens in the background when a connection returns.
- **#10 Future recommendations.** Add:
  - a practitioner content-update mechanism (#3 phase 2, if not built)
  - practitioner-authored learning materials
  - a larger real-data retraining of the assessment model
- **#11 Kanban by phase.** Present the backlog phase by phase (Phase 1: n of
  m done, …). Show pending items as pending rather than presenting everything
  as done.
- **#12 Kanban figures.** Add board screenshots as figures, one per phase or
  one per column state. A screenshot pass can be taken once the Atlassian
  connection is re-authorised in the development environment.
- **#13 Transcriptions and artifacts.** Transcribe the SPED teacher and
  parent interviews and include them as appendices. Include the
  audio-licensing record (`docs/audio-licensing.md`) and the research
  consent form.
- **#14 Backlog ↔ objectives.** Add a traceability table: each backlog
  epic/item → the specific objective it serves. Items that map to no
  objective are either cut or justify a new objective.

---

## Facts checked for this analysis

- Pre-assessment order and vocabulary: `pre_assessment_progress_screen.dart`
  (lines 264–267), `do_what_i_say_game.dart` (colour list, lines 144–149).
- Questionnaire storage: live `caregiver_questionnaires` (0 rows),
  `local_db_service.dart:317`, `supabase/migrations/20260816_family_data_rls.sql:367`.
- Roles: live schema has `entitlements`, `therapy_centers`; no role table.
  Only `is_admin()` in migrations.
- Screen time: `settings_screen.dart:2073`.
- Data volume: 19 runs / 16 results / 11 children assessed / 56 child rows.
