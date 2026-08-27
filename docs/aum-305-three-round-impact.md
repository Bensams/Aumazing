# AUM-305 — Reduce all game modes from 4 rounds to 3: impact analysis

Branch: `claude/aum-305-three-round-flow` · Date: 2026-08-27
Card: [AUM-305] [Investigation/Implementation] Reduce all game modes from 4 rounds to 3

## 1. What changed

A single central policy now owns round counts instead of per-screen hard-coded
`4`s:

- `packages/game_core/lib/src/config/round_policy.dart` (`GameRoundPolicy`):
  - `standardRoundCount = 3` for every mode except pre-assessment.
  - `sensoryAssessmentRoundCount = 4` — pre-assessment keeps four rounds so the
    `combined` sensory condition (music + haptic, round 4) stays reachable.
  - `roundsForContext(context)` / `configurationVersionForContext(context)`
    return `three-round-v1` / `sensory-four-round-v1`.
- All game screens (pre/post assessment, practice, My Path, game_lab) and all
  `packages/game_core` game engines now derive round count from the policy;
  engine defaults moved from `4` to `GameRoundPolicy.standardRoundCount`.
- Pre-assessment is no longer uniformly four rounds. A per-game plan
  (`apps/main_app/lib/features/pre_assessment/sensory/pre_assessment_round_plan.dart`,
  `PreAssessmentRoundPlan`) splits the phase: game 1 (`copy_me`) keeps the
  full four-round evidence cycle (music / haptic / baseline / combined);
  games 2–4 (`do_what_i_say`, `my_turn_your_turn`, `match_it`) play three
  rounds (music / haptic / baseline). This is the maximal reduction that is
  provably label- and recommendation-identical to the legacy flow — see §2.2.
- Per-row stamps are truthful per game:
  - Game 1 rows: `sensory-four-round-v1` (it genuinely plays four rounds).
  - Games 2–4 rows: `sensory-three-round-v1` (new constant in
    `GameRoundPolicy`).
- The four pre-assessment game screens accept optional `roundsOverride` /
  `configurationVersionOverride` (used only by `PreAssessmentProgressScreen`);
  every other caller keeps the shared policy default.

No scoring, AI, sensory, mastery, or recommendation thresholds were changed.

## 2. Impact analysis

### 2.1 AI result/prediction inputs and confidence

The AI result pipeline consumes session-level aggregates (score, response
times, hints, retries, off-task counts) plus per-area levels computed by
`AdaptiveDifficulty`. All aggregates are sums/means over rounds — structurally
identical with 3 rounds; inputs are simply drawn from one fewer round. No
feature vector, model, or prompt changes.

Live historical evidence (Supabase `game_rounds`, completed rounds grouped by
`round_no` across sessions that reached round 4, n=102 per round):

| round_no | correct_rate | avg response_time | avg hints | avg retries | strong_prompt_rate |
|------|----------|------|------|------|------|
| 1 | 1.000 | 2.95 | 2.14 | 0.24 | 0.088 |
| 2 | 1.000 | 1.10 | 1.46 | 0.20 | 0.069 |
| 3 | 1.000 | 0.38 | 1.21 | 0.28 | 0.088 |
| 4 | 1.000 | 11.59 | 2.77 | 0.33 | 0.059 |

Round 4 is systematically the worst round: 4–30× the response time of rounds
1–3, highest hint and retry counts. Removing it therefore shifts session
averages toward the sharper early rounds — mean response time and hint rate
drop, and later-vs-earlier improvement scores rise (the weak final round no
longer drags the "later" window). **Direction of the shift is favorable, not a
quality decline.** Remaining risk is statistical only: improvement/consistency
metrics are estimated from 3 points instead of 4; variance of the
improvement score will be slightly higher at small n.

**The label path is byte-identical to legacy.** The live recommendation input
is `SensoryLabelAnalyzer` (used by `assessmentProvider.finalizePreAssessment`);
it picks the **first** metric per sensory purpose (`_findByPurpose`), then
compares music/haptic/combined deltas against the first baseline. Legacy
first matches all come from game 1: music = game 1 round 1, haptic = game 1
round 2, baseline = game 1 round 3, combined = game 1 round 4. Keeping game 1
on four rounds reproduces exactly that evidence set; games 2–4's rounds are
never consulted by the label analyzer (first-match), so dropping their
combined round changes **no** label outcome. Proof of the cutover's two live
paths:

documented for the stored-result consumers.

### 2.3 Scoring, normalization, thresholds, mastery, completion

No scoring code references a round count (verified by search across
`apps/main_app`, `packages/game_core`). Scores are aggregates over whatever
rounds were played; per-round thresholds (hint counts, strong-prompt
triggers, assistance tiers) are round-local and unchanged. Mastery is
completion- and day-keyed, not length-keyed. Completion remains "all rounds of
the flow finished."

### 2.4 Recommendation ranking / path generation

`AdaptiveDifficulty` recomputes per-area levels from the rounds of each game;
every game still plays all its areas within 3 rounds, so per-area level
coverage is preserved. Ranking consumes the same levels + total score. No
structural change.

### 2.5 Progress, rewards, analytics, reports, historical comparison

- Sessions now carry `configuration_version`, stamped per game at record
  time:
  - `three-round-v1` — every mode except pre-assessment (post-assessment,
    Practice, My Path/game_lab, game_flow).
  - `sensory-four-round-v1` — pre-assessment game 1 (`copy_me`), which
    genuinely plays the four-round evidence cycle.
  - `sensory-three-round-v1` — pre-assessment games 2–4.
- Analytics therefore record the round-count/configuration version per row,
  which lets dashboards/cohorts split legacy (NULL), four-round evidence-game,
  and three-round rows.
- Progress bars/step counters render `currentStep/totalRounds` from the
  live flow — no hard-coded "of 4" copy anywhere (verified by search).
- Rewards (stars, unlocks) key on completion and day, not round count.
- Reports read stored session/round rows; legacy rows are self-describing
  (round_no sequence) and `configuration_version IS NULL` marks them
  legacy/unknown. Historical comparisons can separate v1 from v2 by the stamp.

### 2.6 Backend validation, DB assumptions, APIs, fixtures, tests

- No backend logic couples to a round count; the server stores what it
  receives. The only DB change is the additive migration above (applied live).
- `game_rounds` rows are version-agnostic; no `round_no` constraints.
- Existing engine tests parametrize `totalRounds` explicitly (4 in some) —
  they test the engine at an arbitrary N and remain valid. No fixtures assume
  a default of 4.
- UI copy: dynamic step counters everywhere; no "4 rounds" strings found.

### 2.7 Resume/retry behavior

No partial-session resume exists: `game_sessions` rows are written when a game
completes, and in-game retry (`_retryGame`) / "Again" push a fresh screen that
restarts under the current policy. Consequences:

- A retry/replay of a legacy 4-round session starts a new session under
  the current policy (correct: it is a new run).
- Legacy completed rows are never re-derived; they remain readable with their
  stored round sequence and NULL configuration version, labeled legacy.
- Resuming a pre-assessment run mid-phase applies `PreAssessmentRoundPlan`
  per game as the phase progresses: games 2–4 that were never started in the
  legacy run now play three rounds, while the evidence game is never
  re-entered (`_completedGames`), so a resumed phase is internally
  consistent. The configuration version recorded matches what each game
  actually played.

### 2.8 Historical four-round vs three-round comparison

There is no live three-round data yet, so the comparison is per-round
behavioral (table in 2.1): 4-round sessions' final round is materially
weaker (response time 11.59 vs 0.38–2.95; hints 2.77 vs 1.21–2.14), while all
rounds show 100% completion-correct regardless of count (the errorless-learning
design). Dropping the weakest round does not degrade remaining evidence.

## 3. Rollout recommendation

1. **Proceed with global 3-round rollout as designed.** No scoring/AI
   threshold change is warranted by the evidence, so none was made (per
   decision gate).
2. **Do not add** adaptive extra rounds or minimum-evidence rules yet: per-area
   coverage is retained within 3 rounds; added complexity is not justified by
   any observed decline.
3. **Post-rollout monitoring:** after ≥50 live `three-round-v1` sessions,
   compare improvement-score and consistency-score variance against the
   4-round cohort. If improvement-score variance is materially worse, the
   follow-up options are (a) more rounds only for the practice modes that feed
   mastery, or (b) widen the improvement-score window — both need product-owner
   approval before implementation.
4. **Product-owner gate item (not implemented; needs explicit approval):** the
   maximal reduction shipped by this branch is the per-game split (game 1
   keeps four rounds; games 2–4 play three) — provably label- and
   recommendation-identical via the first-match proof in §2.2. The remaining
   option — game 1 also playing three rounds — is NOT implemented because
   removing game 1's round-4 `combined` sample changes the first-match
   evidence set: the first combined sample would come from game 2's round 4,
   flipping `musicAndHapticHelp` to `noSensorySupportNeeded` for the cohort
   where game 1's combined round passed the ±0.10 threshold but game 2's did
   not. If the product owner accepts that outcome, the proposed mechanism is
   a conservative adaptive-evidence rule (keep `combined` as an extra fourth
   round only when a trigger fires), with any new thresholds needing
   product-owner approval first. Until then, game 1 keeps four rounds.

## 4. Verification

- `flutter analyze` apps/main_app: 6 issues, all pre-existing on base dev
  (3× `SupabaseAuthClient` abstract-member errors in untouched test files,
  `_isBuddyTurn` unused-field warning, 2× info-level deprecations). Zero
  issues from this change.
- `flutter analyze` packages/game_core: 29 issues, all pre-existing and
  identical on base dev (deprecations in `match_it_game.dart` /
  `shape_painter_3d.dart`, `ObjectEmphasis` compile error in untouched
  `object_emphasis_test.dart` + test-level infos). Zero issues from this
  change.
- `flutter test` packages/game_core (full): 230 passed, 6 failed. The same 6
  failures (object_emphasis load + 5 shape_emphasis contour assertions) were
  re-run on pristine base dev in a temporary worktree and reproduce
  identically (`+1 -6`) — pre-existing, unrelated to round counts.
- `flutter test` apps/main_app (targeted: providers/, features/pre_assessment,
  rubric_threshold, session_recording_no_profile, developer_tools_service):
  97 passed, 4 failed-to-load — the 4 are `child_provider*` /
  `dashboard_child_isolation` files whose load breaks on the pre-existing
  `SupabaseAuthClient` abstract-member error in `support/fake_auth.dart`
  (untouched).
- Post-review fixes (branch review found one real regression):
  `offTaskActionCount` had been silently dropped from both
  `GameplaySession` constructions (`AssessmentService.recordSession`,
  `AssessmentRepository.fromGameplay`) when the configurationVersion
  parameter was inserted — every session recorded after the slice reported
  0 off-task actions to the local DB, sync, parent report and AI payload.
  Restored verbatim from base dev; new regression test
  `test/services/assessment_record_session_test.dart` guards the mapping
  (3/3 passing) and also asserts `configurationVersionOverride` stamping
  and policy-default stamping.
  Cloud→local hydration (`_mapGameSessionToLocal`) now maps
  `configuration_version` symmetrically with the push mapping, so sessions
  pulled via `hydrateFromCloud` keep their configuration stamp.
- Final affected-suite run on the rebased branch (base 62512fb9):
  102/102 passed across pre-assessment, post-assessment, assessment
  providers, developer tools, session recording (no-profile),
  recordSession mapping and rubric thresholds; game_core config tests 5/5;
  analyses unchanged (6 and 29 issues, all pre-existing).
- Runtime: widget-level screens and recording path exercised by the above;
  no device-live run in this slice. Prior slice's device smoke evidence
  remains on record for the base implementation commit.
- Migration applied to live Supabase (additive, `IF NOT EXISTS`), column
  verified present; local v18 migration matches it byte-for-byte in effect.
- The 4 test fakes implementing `AssessmentGateway` were updated for the new
  optional `configurationVersionOverride` parameter — that was the only
  compile break the interface change introduced, caught by analyze and fixed.
