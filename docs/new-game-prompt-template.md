# New-game prompt template

Copy the block below into a fresh Claude Code session (or paste it as a task) and
fill in the `<…>` placeholders to add a new child mini-game to Aumazing.

The checklist is the *union* of everything the six existing games ended up
needing. Two gotchas worth knowing before you start:

- `trace_it`'s original commit only touched the registry, the game, the screen,
  and the migration. The launcher/service wiring (step 5) landed later — that is
  exactly where a new game silently fails to show up in the lobby.
- `learning_modules.title` is a hard join key against
  `ActiveGamesService._titleToGameId`. A mismatch makes the game invisible with
  no error anywhere.

---

````markdown
# New Aumazing mini-game: <GAME NAME>

Add a new child mini-game to the Aumazing monorepo, following the exact
conventions of the existing games (read `trace_it` and `match_it` end-to-end
first — game logic in `packages/game_core`, screen wrapper in `main_app`).

## Game spec
- **id**: `<snake_case_id>`  (used everywhere: registry, DB, AI, analytics)
- **Display name**: `<Title Case Name>`
- **One-line description**: `<shown on the game card / DB catalog>`
- **Skill categories**: `<playSkills | communication | socialInteraction>` (one or more)
- **Core mechanic**: <what the child sees, does, and what counts as correct>
- **Round structure**: 3 rounds (standard; pre-assessment keeps 4 for the sensory phase)
- **Difficulty tiers 1–3**: <what changes per tier: item count, distractors, speed>
- **Correctness rule**: <be explicit — errorless-learning friendly, tolerant of
  wobble/imprecision, never punishes>
- **Hint policy**: follow the ABA prompt hierarchy via `DifficultyProfile`
  (Easy: unlimited + guided demo, Medium: small budget, Hard: none;
  `DifficultyProfile.assessment` for assessment context)
- **Extra metrics for analytics**: <e.g. deviation, lifts, hesitation — beyond
  score/errors/response time>

## Implementation checklist

### 1. Flame game — `packages/game_core/lib/src/games/<id>/`
- `<id>_game.dart`: `class <Name>Game extends FlameGame with TapCallbacks,
  [DragCallbacks,] EnhancedGameplayAnalyticsMixin`
- Constructor params mirroring `TraceItGame`: `onStepChanged`, `onGameComplete`
  (named args incl. `GameSessionMetrics? analytics`), `childId`, `totalRounds`,
  `gameVersion`, `profile`, `onCorrect*`, `onWrongAnswer`, and the full audio/VO
  callback set (`onPlayCorrectSfx`, `onPlayWrongSfx`, `onPlayTapSfx`,
  `onPlayLevelCompleteSfx`, `onPlayGameCompleteSfx`, `onPlayCorrectVo`,
  `onPlayWrongVo`, `onPlayInstructionVo`, `onPlayTransitionVo`,
  `onPlayCelebrationVo`)
- Components under `components/`; use `shared/game_layout.dart`,
  `shared/ghost_hand.dart` for demos, `AdaptiveDifficulty`, and respect
  `GameMotion.reduced`
- Export the game + its public components from `packages/game_core/lib/game_core.dart`

### 2. Registry — `packages/game_core/lib/src/registry/game_registry.dart`
Add a `GameEntry` with `id`, `name`, `description`, `icon`, `logoAsset: _logo('<id>')`,
`gradientColors`, `categories`, and a `create:` factory adapting the game's
`onGameComplete` to the registry signature.

### 3. Logo asset
Add `packages/shared_ui/assets/game_logos/<id>.svg` matching the style of the
existing six tiles.

### 4. Screen wrapper — `apps/main_app/lib/features/games/<id>/<id>_screen.dart`
Copy the structure of `match_it_screen.dart` exactly:
landscape lock in `initState`, `VoiceOverService` from `ChildProvider.voiceAssetFolder`,
`sensoryController?.applyRoundConfig`, `MascotHost.maybeOf(context)` on
correct/wrong/complete, `assessmentProvider.recordGameSession(gameId: '<id>', …)`,
`onComplete` short-circuit for game-flow mode, `RewardOverlay.forChild` →
`GameEndChoiceDialog.show(currentGameId: '<id>')` for practice,
`ChildModeTopBar` (retry/menu only in practice), `VoiceOverPromptBubble`,
background from `activePalette.gameBackgroundFor('<id>')`, `_retryGame` wrapping
the replacement screen in its own `MascotHost`.

### 5. Wiring
- `apps/main_app/lib/features/child_mode/game_launcher.dart`: add to
  `supportedGameIds` and to `_gameFor`'s switch.
- `apps/main_app/lib/services/active_games_service.dart`: add
  `'<Title Case Name>': '<id>'` to `_titleToGameId`.
- `apps/main_app/lib/services/recommendation_filter.dart`: same title→id entry.
- `ai_assessment/app/rules.py`: add `{"game_id": "<id>", "name": "<Name>"}`.
- Voice-over: reuse an existing `VoiceOverCue` if one fits; only add a new cue
  (and the recorded assets) if none does — say which you chose and why.

### 6. Supabase migration — `supabase/migrations/<YYYYMMDD>_add_<id>_game.sql`
Follow `20260702_add_trace_it_game.sql`: insert into `public.games`
(slug/name/description/sort_order), map `game_skill_categories` (mirroring the
registry categories), and insert `learning_modules` (`module_code` = `<id>`,
`title` must match `_titleToGameId` exactly, `target_domain`, text
`difficulty_level`, `active`). Use `ON CONFLICT … DO NOTHING`.
**Write the migration file only — do not apply it.**

## Constraints
- No new dependencies without asking.
- Match surrounding comment density and tone (explain the *why*, especially for
  therapeutic/ABA decisions).
- Landscape-only, child-safe: no text-dependent instructions, no failure states,
  no timers visible to the child.
- Run `flutter analyze` for `packages/game_core` and `apps/main_app` when done
  and report the output.
- Report anything you couldn't wire up (e.g. missing VO recordings or SVG art).
````
