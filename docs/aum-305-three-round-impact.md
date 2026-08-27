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
- Every recorded session stamps `configuration_version`:
  - Local DB migration v18 adds `configuration_version TEXT` to
    `game_sessions` (additive; legacy rows keep NULL).
  - Identical additive migration applied to live Supabase
    (`20260827_add_configuration_version_to_game_sessions.sql`) — verified the
    live column exists before wiring the upload.
  - Sync upload mapper now sends `configuration_version` so the stamp reaches
    analytics.

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

### 2.2 Sensory-preference calculations

Unaffected. Pre-assessment deliberately keeps 4 rounds (the product-owner-gated
exception); `SensoryRoundConfig` rounds 1–4 (musicOnly / hapticOnly / baseline
/ combined) all still occur, so the composite sensory model sees every
condition it already sees. The analyzer attributes metrics by round purpose,
not by round count. Practice and My Path modes play no sensory rounds.

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

- Sessions now carry `configuration_version`: `three-round-v1` (all modes
  except pre-assessment) or `sensory-four-round-v1` (pre-assessment).
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

- A retry/replay of a legacy 4-round session starts a new 3-round session
  (correct: it is a new run).
- Legacy completed rows are never re-derived; they remain readable with their
  stored round sequence and NULL configuration version, labeled legacy.

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
4. **Product-owner gate still open:** reducing the pre-assessment sensory phase
   from 4 to 3 rounds remains NOT implemented because round 4 carries the
   unique `combined` sensory evidence; a change would need the product owner to
   accept a shortened sensory comparison or a different evidence rule.

## 4. Verification

- `flutter analyze` (main_app + game_core): clean.
- Existing game-engine and sensory tests: passing (round count parametrized).
- Migration applied to live Supabase (additive, `IF NOT EXISTS`), column
  verified present; local v18 migration matches it byte-for-byte in effect.
