# Sabay Tayo! — full game spec

**Social Interaction · joint attention · `sabay_tayo`**

This is the one of the four Social Interaction candidates worked up in full.
It was picked over the other three for two reasons:

1. **Therapeutic weight.** Joint attention — following another person's gaze or
   point to a shared referent — is the earliest social-interaction skill on the
   developmental ladder and a primary early-intervention target in ASD. Every
   other social skill in the catalog (turn-taking, greetings, sharing) assumes
   the child can already share attention with a partner. Right now nothing in
   the app trains it.
2. **Zero new art.** The buddy's entire 3×3 gaze grid already ships:
   `packages/shared_ui/assets/characters/{bps,reiz}_look_{up,down,left,right,up_left,…}.png`,
   plus `_point`, `_present`, `_celebrate`, `_idle`. `CharacterSprites.gazeFrameFor(x, y)`
   already maps a screen point to the right pose, and `scripts/check_gaze.py`
   already validates the set. The mechanic is, almost exactly, a game built on
   an API that exists.

The remaining three concepts are in [`docs/games/prompts/`](prompts/) as
paste-ready prompts for separate worktrees.

---

## Game spec

- **id**: `sabay_tayo`
- **Display name**: `Sabay Tayo!` (Tagalog, roughly *"Let's do it together!"*)
- **One-line description**: `Look where your buddy is looking, then tap what they see!`
- **Skill categories**: `socialInteraction` (primary), `playSkills` (secondary,
  weight 0.5 — the tap-the-object layer is a play-skill task)
- **Sort order**: `9`

### Core mechanic

A buddy character (BPS or Reiz, one per session — never both, for the same
reason `generate_routine_cards.py` casts one character across the whole routine
set) sits at the bottom-centre of a landscape scene. Two to four objects are
arranged around the upper arc of the screen.

Each trial:

1. Buddy is at rest, facing the child. A soft chime asks for attention.
2. Buddy **turns to look at one object** — the pose comes from
   `gazeFrameFor(objectX / width, objectY / height)`, so the eyes actually
   aim at that object's real position rather than a canned direction.
3. On tier 1 the buddy also **points** (`_point` sheet, arm toward the object)
   and the object gives a gentle pulse.
4. The child taps the object the buddy is attending to.
5. Correct → the object lifts, buddy plays `_celebrate`, praise VO. Wrong →
   the tapped object dims and settles back, buddy plays `_oops` then
   `_encourage`, gentle-retry VO, and the trial repeats with the prompt
   escalated one level (see hint policy). **The trial never fails**; it just
   gets easier until the child gets it.

What is being trained is specifically *following someone else's attention* —
which is why the correct object is never the visually loudest one, and why
distractors on tier 2+ are given their own idle motion. A child who taps the
wiggliest thing on screen is not doing joint attention, and the design has to
be able to tell the difference.

### Round structure

3 rounds (standard), `config.itemsPerRound` trials per round.

### Difficulty tiers

| | tier 1 (Easy) | tier 2 (Medium) | tier 3 (Hard) |
|---|---|---|---|
| objects | 2, far apart, opposite sides | 3 | 4, incl. one adjacent to the target |
| buddy cue | gaze **+** point **+** target pulse | gaze **+** point, no pulse | **gaze only** — no arm, no pulse |
| distractor motion | none | one distractor idles | two distractors idle |
| attention shift | none | none | buddy glances at a decoy for ~600 ms, then settles on the real target; only the *final* gaze counts |

Tier 3's shift is the interesting one clinically: it separates children who
follow a gaze from those who react to the first movement they see. Log it (see
metrics) rather than just scoring it.

### Correctness rule

The tap must land on the object the buddy's **final** gaze targets. Hit-testing
is generous — the tap region is the object's visual bounds inflated by 20%,
matching `sari_sari_sort`'s drop tolerance, because an imprecise tap is a motor
miss, not a social-cognition miss, and this game must not measure the wrong
thing. No timers are visible to the child and there is no fail state; a trial
ends only when the child taps the right object.

### Hint policy

Follows the ABA prompt hierarchy through `DifficultyProfile`, escalating on each
wrong tap (Easy: unlimited, and a guided `GhostHand` demo before trial 1 of
round 1; Medium: budget of 2 escalations then the ghost hand; Hard: none —
the trial simply repeats with the same gaze cue; `DifficultyProfile.assessment`
suppresses all of it):

1. Buddy repeats the gaze, held longer.
2. Buddy adds the point (`_point`) if the tier had suppressed it.
3. Target pulses.
4. `GhostHand` travels from the buddy to the target and taps it (`shared/ghost_hand.dart`).

### Extra analytics metrics

Beyond score / errors / response time, record per trial:

- `gazeFollowLatencyMs` — buddy's gaze settling → first tap. The joint-attention
  measure proper; distinct from response time, which starts at trial open.
- `firstTapWasDecoy` (tier 3) — did the child chase the decoy glance?
- `promptLevelUsed` — highest rung of the hierarchy reached, 0 = independent.
  This is the number a therapist actually reads.
- `angularErrorDeg` — angle between (buddy → tapped object) and
  (buddy → target). Distinguishes "tapped the thing beside it" from "tapped the
  opposite side of the screen"; only the latter means the gaze wasn't followed.

---

## Implementation checklist

### 1. Flame game — `packages/game_core/lib/src/games/sabay_tayo/`

- `sabay_tayo_game.dart`: `class SabayTayoGame extends FlameGame with TapCallbacks, EnhancedGameplayAnalyticsMixin`
- Constructor params mirroring `SariSariSortGame` / `HintayGame`: `onStepChanged`,
  `onGameComplete` (named args incl. `GameSessionMetrics? analytics`), `childId`,
  `totalRounds`, `itemsPerRound`, `gameVersion`, `strings`, `profile`, `onCorrect*`,
  `onWrongAnswer`, and the full audio/VO callback set (`onPlayCorrectSfx`,
  `onPlayWrongSfx`, `onPlayTapSfx`, `onPlayLevelCompleteSfx`,
  `onPlayGameCompleteSfx`, `onPlayCorrectVo`, `onPlayWrongVo`,
  `onPlayInstructionVo`, `onPlayTransitionVo`, `onPlayCelebrationVo`).
- Components under `components/`:
  - `buddy_character.dart` — draws the buddy from the sprite sheets, exposes
    `lookAt(Vector2 worldPoint)`, `point(...)`, `celebrate()`, `oops()`.
  - `attention_object.dart` — a tappable object card (emoji glyph on a rounded
    card, exactly like `sari_sari_sort/components/draggable_item.dart`, which
    uses emoji rather than generated art — reuse that, it costs nothing).
  - `scene_backdrop.dart` — modelled on `store_backdrop.dart`.
- Use `shared/game_layout.dart`, `shared/ghost_hand.dart`, `AdaptiveDifficulty`,
  and respect `GameMotion.reduced` (under reduced motion the gaze *snaps*
  between poses instead of easing, and the tier-3 decoy glance is skipped — a
  600 ms feint is exactly the kind of motion the setting exists to remove).
- Export the game and its public components from
  `packages/game_core/lib/game_core.dart`.

**Loading the buddy art into Flame.** `CharacterSprites` is Flutter-side
(`ImageProvider`) and cannot be used from a Flame component. The established
pattern for pulling `shared_ui` art into a Flame game is
`packages/game_core/lib/src/games/anong_susunod/routine_art_cache.dart`:
an `Images(prefix: '')` cache with full package paths
(`packages/shared_ui/assets/characters/bps_look_up_left.png`), best-effort
loading, and a painted fallback so a missing asset never ends a session.
Copy that file's shape into `components/buddy_art_cache.dart`. Mirror
`CharacterSprites.gazeFrameFor`'s banding (a full middle third on each axis)
rather than reinventing it — and note the sheets are single-cell stills for
`look_*`, while `point`/`celebrate`/`oops` are grids per
`CharacterSprites.layout` (`point`: 3×2/6 frames, `celebrate`: 4×3/12,
`oops`: 3×2/6).

If the fallback ever renders, the buddy should still be able to *aim* — draw a
simple painted head with an offset pupil. A joint-attention game whose fallback
can't indicate direction has no fallback.

### 2. Registry — `packages/game_core/lib/src/registry/game_registry.dart`

Add a `GameEntry` with `id: 'sabay_tayo'`, `name: 'Sabay Tayo!'`,
`description`, `icon: Icons.visibility_rounded`, `logoAsset: _logo('sabay_tayo')`,
`categories: [SkillCategory.socialInteraction, SkillCategory.playSkills]`,
`gradientColors` (suggest a warm-to-cool trio distinct from the existing seven),
and a `create:` factory adapting `onGameComplete` to the registry signature.

### 3. Logo asset

`packages/shared_ui/assets/game_logos/sabay_tayo.svg`, matching the existing
eight tiles. Hand-authored SVG in the house style — do not generate this one.

### 4. Screen wrapper — `apps/main_app/lib/features/games/sabay_tayo/sabay_tayo_screen.dart`

Copy `match_it_screen.dart`'s structure exactly: landscape lock in `initState`,
`VoiceOverService` from `ChildProvider.voiceAssetFolder`,
`sensoryController?.applyRoundConfig`, `MascotHost.maybeOf(context)` on
correct/wrong/complete, `assessmentProvider.recordGameSession(gameId: 'sabay_tayo', …)`,
`onComplete` short-circuit for game-flow mode, `RewardOverlay.forChild` →
`GameEndChoiceDialog.show(currentGameId: 'sabay_tayo')` for practice,
`ChildModeTopBar` (retry/menu only in practice), `VoiceOverPromptBubble`,
background from `activePalette.gameBackgroundFor('sabay_tayo')`, `_retryGame`
wrapping the replacement screen in its own `MascotHost`.

**One deviation to think about:** the app mascot (`MascotHost`) and the in-game
buddy are two characters on screen at once. Pick the *same* character for both,
or explicitly pick different ones — but decide it, don't let it happen. The
routine-card rationale applies: a child asked "where is he looking?" should not
have to work out how many people are in the room first.

### 5. Wiring

- `apps/main_app/lib/features/child_mode/game_launcher.dart`: add to
  `supportedGameIds` and to `_gameFor`'s switch.
- `apps/main_app/lib/services/active_games_service.dart`: add
  `'Sabay Tayo!': 'sabay_tayo'` to `_titleToGameId`.
- `apps/main_app/lib/services/recommendation_filter.dart`: same title→id entry.
- `ai_assessment/app/rules.py`: add `{"game_id": "sabay_tayo", "name": "Sabay Tayo!"}`
  to `AREA_MODULE_MAP["social"]` — **listed first**, ahead of `my_turn_your_turn`,
  since joint attention precedes turn-taking developmentally and this is the
  only module that trains it directly. (`"social"` currently holds exactly one
  game; that is the gap this game closes.)

### 6. Voice-over

Reuse existing `VoiceOverCue`s where they fit — `eyesHere`, `watchCarefully`,
`lookAtMe` (if present), the Core Praise and Gently Retry sets, and
`goodLooking` for the correct case, which is close to purpose-built for this.

One genuinely new cue is likely needed for the instruction, because nothing in
the enum says *look where your buddy is looking*: propose
`lookWhereIAmLooking`. Follow the precedent set by `waitForTheStar` — Hintay!
added a dedicated line rather than reusing `eyesHere` precisely because
`eyesHere` orients attention without naming the task. Same argument here.

**Generate the recordings with kie.ai** via `tools/voice_gen/generate_kie.py`
(`--backend gemini`, the default and the only one currently working; ElevenLabs
on kie has been failing with `failCode 500` since 2026-07-31). It renders en /
tl / ceb across all three age tiers. Read `tools/voice_gen/README.md` first;
export `KIE_API_KEY` (from <https://kie.ai/api-key>) and **never commit it**.
Output lands in `out/`, not the live asset folder — conform and install it with
the existing scripts rather than copying by hand.

### 7. Supabase migration — `supabase/migrations/<YYYYMMDD>_add_sabay_tayo_game.sql`

Follow `20260810_add_hintay_game.sql`:

- `public.games`: slug `sabay_tayo`, name `Sabay Tayo!`, the description above,
  `sort_order` **9**.
- `public.game_skill_categories`: `social_interaction` weight 1.0,
  `play_skills` weight 0.5 — mirroring the registry categories.
- `public.learning_modules`: `module_code = 'sabay_tayo'`,
  `title = 'Sabay Tayo!'` (**must match `_titleToGameId` exactly**, exclamation
  mark included, or the game silently never appears anywhere),
  `target_domain = 'social'`, `difficulty_level = 'beginner'`, `active = true`.
- `ON CONFLICT … DO NOTHING` throughout.

**Write the migration file only — do not apply it.**

### 8. Tests

Follow `packages/game_core/test/sari_sari_sort_test.dart`: trial generation
never places the target and a distractor in the same gaze band, tier 3's decoy
is never the same object as the target, the gaze pose chosen for a target
actually corresponds to that target's quadrant, and a wrong tap escalates the
prompt without ending the trial.

## Constraints

- No new dependencies without asking.
- **All generated assets go through kie.ai** — voice via
  `tools/voice_gen/generate_kie.py`, any character art via
  `scripts/generate_sprites.py` (`bytedance/seedance-2`), any card art via
  `scripts/generate_routine_cards.py` (`google/nano-banana-edit`), music via
  `tools/bgm_gen/generate_bgm.py`. Don't introduce another provider, and don't
  hand-place files into asset folders that a pipeline owns.
- This game should need **no** new generated art — the gaze grid already ships.
  If you find yourself about to run `generate_sprites.py`, stop and say why.
- Match surrounding comment density and tone: explain the *why*, especially for
  therapeutic/ABA decisions.
- Landscape-only, child-safe: no text-dependent instructions, no failure states,
  no timers visible to the child.
- Run `flutter analyze` for `packages/game_core` and `apps/main_app` when done
  and report the output.
- Report anything you couldn't wire up.
