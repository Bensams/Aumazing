# Prompt — Tulong, Kaibigan! (sharing & requesting)

Paste everything inside the fence into a fresh Claude Code session in its own
worktree. Nothing needs filling in.

This is the cheapest of the four to build: the drag mechanic, the item cards and
the item voice lines all already exist in `sari_sari_sort`.

````markdown
# New Aumazing mini-game: Tulong, Kaibigan!

Add a new child mini-game to the Aumazing monorepo, following the exact
conventions of the existing games (read `sari_sari_sort` end-to-end first —
it is the direct ancestor of this game — then `anong_susunod`. Game logic in
`packages/game_core`, screen wrapper in `main_app`, and
`docs/new-game-prompt-template.md` for the full checklist).

## Game spec
- **id**: `tulong_kaibigan`
- **Display name**: `Tulong, Kaibigan!`
- **One-line description**: `Your friend needs something — give it to them!`
- **Skill categories**: `socialInteraction`, `communication`
- **Sort order** (DB): `12`
- **Core mechanic**: A buddy character stands to one side with a speech bubble
  showing a picture of what they want (a ball, a banana, a toothbrush). A tray
  of item cards sits along the bottom. The child drags the requested item into
  the buddy's hands. The buddy takes it, plays a thank-you animation, and the
  item stays with them.
  This is `sari_sari_sort`'s drag-to-target loop with the bins replaced by a
  *person* — which is the whole point. Sorting into a basket is a play skill;
  giving to someone who asked is a social one, and the difference the child
  experiences is that the target reacts.
- **Round structure**: 3 rounds (standard), `config.itemsPerRound`
  requests per round.
- **Difficulty tiers 1–3**:
  - tier 1: one item on the tray, no distractors — errorless. The buddy's bubble
    shows the item exactly as it appears on the tray.
  - tier 2: 2–3 items on the tray; the bubble picture stays visible throughout.
  - tier 3: 4 items, **two buddies** who request in sequence (buddy A asks,
    then buddy B asks), and each bubble fades after ~2 s. The child must track
    who asked for what. Tracking a request back to a person is the step that
    turns fetching into sharing.
- **Correctness rule**: the dropped item must match the requesting buddy's
  bubble, and on tier 3 must go to the buddy who asked for it. Drop tolerance
  mirrors `sari_sari_sort`'s (visual bounds inflated ~20%) — an imprecise drag
  is a motor miss, not a social miss, and must not be scored as one. No timers
  visible to the child, no fail state: a wrong item springs gently back to the
  tray, the buddy re-shows the bubble, and the trial continues until it lands.
- **Hint policy**: ABA prompt hierarchy via `DifficultyProfile`, escalating per
  wrong drop — (1) the bubble re-appears and pulses, (2) on tier 3 the
  requesting buddy leans forward / the other dims, (3) the correct tray item
  pulses, (4) `shared/ghost_hand.dart` drags it across. Easy: unlimited +
  guided demo before the first trial. Medium: budget of 2, then the ghost hand.
  Hard: none. `DifficultyProfile.assessment` suppresses all of it.
- **Extra metrics for analytics**: `wrongRecipientRate` (tier 3 — right item,
  wrong buddy; the single most diagnostic error this game produces, and
  invisible if you only score item correctness), `dragHesitationMs` (item
  lift → drag start, reusing whatever `sari_sari_sort` already records),
  `bubbleRecallErrors` (tier 3 errors made after the bubble faded, separated
  from errors made while it was visible — memory vs comprehension),
  `promptLevelUsed` (0 = independent).

## Assets — IMPORTANT
- **Every generated asset goes through kie.ai.** No other provider.
- **Almost nothing new is needed.**
  - **Item cards**: `sari_sari_sort` draws its items as an emoji glyph on a
    coloured rounded card
    (`packages/game_core/lib/src/games/sari_sari_sort/components/draggable_item.dart`)
    and keeps the catalogue in `sari_sari_sort_game.dart` (`_catalogue`, exposed
    as `SariSariSortGame.catalogue`). **Reuse that catalogue and that component
    directly** — do not author a second item set. If the component needs to be
    shared, lift it to `games/shared/` rather than copying it.
  - **Item voice lines already exist**: `packages/assets/audio/voice_over/
    {folder}/items/{Bola,Saging,Gatas,…}.mp3`, added in commit `97f7f14`
    alongside the store translations. Wire the request bubble to play the item's
    line — the buddy naming what they want is the communication half of this
    game and it costs nothing.
  - **Character art**: none needed. `packages/shared_ui/assets/characters/`
    already ships `{bps,reiz}_{idle,present,celebrate,nod,oops,encourage,
    point,talk}.png` plus the full 8-direction gaze grid. Use `_present`
    (open palm — deliberately an invitation rather than an instruction, per
    `CharacterSprites.layout`'s comment) for the request pose, `_celebrate` for
    the thank-you, `_oops` → `_encourage` for a wrong drop. See
    `CharacterSprites.layout` for each sheet's grid. **Do not run
    `generate_sprites.py`** — if you think you need to, stop and say why.
  - **Loading sprites into Flame**: `CharacterSprites` is Flutter-side
    (`ImageProvider`) and unusable from a Flame component. Copy
    `packages/game_core/lib/src/games/anong_susunod/routine_art_cache.dart` —
    `Images(prefix: '')`, full package paths, best-effort load with a painted
    fallback so a missing asset never ends a child's session.
- **Voice-over**: reuse `dragThe`, `dropThe`, `letsTakeTurns`, `thankYouForWaiting`,
  Core Praise and Gently Retry, plus the per-item lines above. A thank-you cue
  and a request cue are likely missing — propose `thankYouFriend` and
  `canIHaveThe` (the latter composing with the existing item lines, exactly as
  `dragThe`/`tapThe` already do). Follow the `waitForTheStar` precedent in
  `packages/shared_audio/lib/src/voice_over_service.dart` for justifying a new
  cue over a near-miss reuse. Generate with
  `tools/voice_gen/generate_kie.py --backend gemini` (default; ElevenLabs on kie
  has failed with `failCode 500` since 2026-07-31) — en / tl / ceb across three
  age tiers. Read `tools/voice_gen/README.md`; `export KIE_API_KEY=…` (from
  <https://kie.ai/api-key>), **never commit it**. Output lands in `out/` and is
  installed via the existing scripts, never copied by hand. Mind the tight
  lead/tail padding the README describes — `canIHaveThe` is a composed phrase
  and a generous tail becomes a pause mid-sentence.
- **Logo**: hand-author `packages/shared_ui/assets/game_logos/tulong_kaibigan.svg`
  to match the existing eight tiles.

## Implementation checklist
Follow `docs/new-game-prompt-template.md` steps 1–6 verbatim, plus:
- `ai_assessment/app/rules.py`: add
  `{"game_id": "tulong_kaibigan", "name": "Tulong, Kaibigan!"}` to
  `AREA_MODULE_MAP["social"]` and to `AREA_MODULE_MAP["communication"]`.
- Migration `supabase/migrations/<YYYYMMDD>_add_tulong_kaibigan_game.sql`
  following `20260810_add_hintay_game.sql`: `games` row (sort_order 12),
  `game_skill_categories` → `social_interaction` 1.0 and `communication` 0.5,
  `learning_modules` with `module_code = 'tulong_kaibigan'`,
  `title = 'Tulong, Kaibigan!'` (**must match
  `ActiveGamesService._titleToGameId` exactly** — comma and exclamation mark
  included — or the game silently never appears), `target_domain = 'social'`,
  `difficulty_level = 'beginner'`, `active = true`.
  **Write the migration file only — do not apply it.**
- Tests in `packages/game_core/test/tulong_kaibigan_test.dart` following
  `sari_sari_sort_test.dart` and `draggable_item_fingertip_test.dart`: tier 3
  never gives both buddies the same item, a right-item/wrong-buddy drop is
  recorded as `wrongRecipientRate` and not as a plain error, and the fingertip
  drag offset behaves as it does in `sari_sari_sort`.

## Constraints
- No new dependencies without asking.
- Match surrounding comment density and tone — explain the *why*, especially
  for therapeutic/ABA decisions.
- Landscape-only, child-safe: no text-dependent instructions, no failure states,
  no timers visible to the child. Respect `GameMotion.reduced` — the bubble
  cross-fades instead of popping, and on tier 3 it does not auto-fade.
- Prefer lifting shared code out of `sari_sari_sort` over duplicating it, but do
  not refactor `sari_sari_sort`'s behaviour in the process — it ships.
- Run `flutter analyze` for `packages/game_core` and `apps/main_app` when done
  and report the output.
- Report anything you couldn't wire up (missing VO recordings, missing sheets).
````
