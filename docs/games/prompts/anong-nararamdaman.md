# Prompt — Ano'ng Nararamdaman? (emotion recognition)

Paste everything inside the fence into a fresh Claude Code session in its own
worktree. Nothing needs filling in.

This is the only one of the four that needs a genuinely new generated art set,
so the asset section below is the part to read carefully.

````markdown
# New Aumazing mini-game: Ano'ng Nararamdaman?

Add a new child mini-game to the Aumazing monorepo, following the exact
conventions of the existing games (read `anong_susunod` and `match_it`
end-to-end first — game logic in `packages/game_core`, screen wrapper in
`main_app`, and `docs/new-game-prompt-template.md` for the full checklist).

## Game spec
- **id**: `anong_nararamdaman`
- **Display name**: `Ano'ng Nararamdaman?`
- **One-line description**: `How is your friend feeling? Find the face that matches!`
- **Skill categories**: `socialInteraction`, `communication`
- **Sort order** (DB): `11`
- **Core mechanic**: A short picture scene shows a child character in a
  situation (their ice cream fell, a friend gave them a gift, a dog barked at
  them, they finished a drawing). The buddy's face shows the resulting emotion.
  The child taps the matching emotion face from a row of large face cards.
  On tier 3 a second step follows: *what would you do?* — the child picks a
  caring response card (offer a hug, share a toy, say sorry, clap).
  The emotion set is deliberately small and unambiguous: **happy, sad, scared,
  surprised, angry**. Do not add subtle states (proud, embarrassed, confused);
  they are a later target and they make the distractor set unfair.
- **Round structure**: 3 rounds (standard), `config.itemsPerRound`
  scenes per round.
- **Difficulty tiers 1–3**:
  - tier 1: 2 face cards, and the two emotions are maximally distinct
    (happy vs sad). Scene + face both shown.
  - tier 2: 3–4 cards including one *near-miss pair* (sad vs scared,
    surprised vs scared) — the confusions that matter clinically.
  - tier 3: 4 cards, plus the second "what would you do?" response step. The
    scene card is hidden during the response step so the child answers from the
    emotion, not the picture.
- **Correctness rule**: the tapped face must match the scene's emotion.
  Generous hit targets (inflate visual bounds ~20%, as `sari_sari_sort` does).
  No timers visible to the child, no fail state — a wrong tap dims and settles
  back, the buddy's face re-animates into the emotion, and the trial continues.
  **Never label a wrong answer as a wrong feeling.** The gently-retry VO must
  read as "look again", never as a correction about emotion.
- **Hint policy**: ABA prompt hierarchy via `DifficultyProfile`, escalating per
  wrong tap — (1) the buddy's face re-animates from neutral into the emotion
  (the transition is more legible than the held pose), (2) incorrect cards fade
  back to leave two, (3) the correct card pulses, (4) `shared/ghost_hand.dart`
  taps it. Easy: unlimited + guided demo. Medium: budget of 2, then ghost hand.
  Hard: none. `DifficultyProfile.assessment` suppresses all of it.
- **Extra metrics for analytics**: `confusionPairs` (which emotion was chosen
  for which target — the actual clinical output of this game; a child who reads
  scared as sad is a different profile from one guessing at random),
  `nearMissRate` (tier 2 errors that landed on the paired emotion vs elsewhere),
  `responseStepAccuracy` (tier 3's second step, scored separately from
  recognition — knowing the feeling and knowing what to do are different
  skills), `promptLevelUsed` (0 = independent).

## Assets — IMPORTANT
- **Every generated asset goes through kie.ai.** No other provider.
- **New art needed: the emotion face cards and the scene cards.** Generate them
  with a new script modelled *closely* on `scripts/generate_routine_cards.py`
  (kie.ai `google/nano-banana-edit`) — read that file's header comment in full
  before writing anything. Its two hard-won rules both apply here:
  1. **Two reference images per call**, not one: the character's chibi artwork
     carries identity, and a strip of three shipped `routine_cards` carries the
     drawing style. One reference alone gives you either the wrong art style or
     a generic child.
  2. **One character across the entire set.** The routine cards were recast to a
     single character for exactly the reason that bites hardest here: a child
     asked "how does he feel?" should not first have to work out whether the
     new face is a new person. Use BPS, matching the routine cards.
  Output to `packages/shared_ui/assets/routine_cards/`'s sibling,
  `packages/shared_ui/assets/emotion_cards/`, 512px RGBA palettised, and cache
  raw generations in a gitignored `.card_cache/` as that script does.
  `export KIE_API_KEY=…` (from <https://kie.ai/api-key>) — **never commit it**.
- **Loading the cards into Flame**: copy
  `packages/game_core/lib/src/games/anong_susunod/routine_art_cache.dart`
  exactly — `Images(prefix: '')` with full package paths, best-effort loading,
  and a painted fallback (`RoutineArtPainter`'s equivalent) so a missing card
  never ends a child's session. **A painted fallback is mandatory here**, not
  optional: this game is unplayable without a legible face, so the fallback must
  draw a real schematic expression (mouth curve + eyebrow angle per emotion),
  not a placeholder box.
- **Voice-over**: reuse Core Praise and Gently Retry cues. Emotion names and the
  instruction will need new cues — propose `howIsHeFeeling`, `emotionHappy`,
  `emotionSad`, `emotionScared`, `emotionSurprised`, `emotionAngry`, following
  the naming pattern of the existing `colorRed`/`colorBlue` dynamic cue block in
  `packages/shared_audio/lib/src/voice_over_service.dart`. Generate with
  `tools/voice_gen/generate_kie.py --backend gemini` (default; ElevenLabs on kie
  has failed with `failCode 500` since 2026-07-31) — it renders en / tl / ceb
  across three age tiers. Read `tools/voice_gen/README.md`; output goes to
  `out/`, installed via the existing scripts, never copied by hand.
  Note the `style` field on the gemini backend: an emotion label should be read
  warmly and neutrally, **not** acted out in that emotion — a sad-sounding "sad"
  teaches tone, not recognition, and undercuts what the card is testing.
- **Logo**: hand-author
  `packages/shared_ui/assets/game_logos/anong_nararamdaman.svg` to match the
  existing eight tiles.

## Implementation checklist
Follow `docs/new-game-prompt-template.md` steps 1–6 verbatim, plus:
- `ai_assessment/app/rules.py`: add
  `{"game_id": "anong_nararamdaman", "name": "Ano'ng Nararamdaman?"}` to
  `AREA_MODULE_MAP["social"]` and to `AREA_MODULE_MAP["communication"]`.
- Migration `supabase/migrations/<YYYYMMDD>_add_anong_nararamdaman_game.sql`
  following `20260810_add_anong_susunod_game.sql` (note its SQL-escaped
  apostrophe: `'Ano''ng Susunod?'` — you need the same for `Ano''ng
  Nararamdaman?`). `games` row (sort_order 11); `game_skill_categories` →
  `social_interaction` 1.0 and `communication` 1.0; `learning_modules` with
  `module_code = 'anong_nararamdaman'`, `title = 'Ano''ng Nararamdaman?'`
  (**must match `ActiveGamesService._titleToGameId` exactly** — apostrophe and
  question mark included — or the game silently never appears),
  `target_domain = 'social'`, `difficulty_level = 'beginner'`, `active = true`.
  **Write the migration file only — do not apply it.**
- Tests in `packages/game_core/test/anong_nararamdaman_test.dart` following
  `sari_sari_sort_test.dart`: tier 1 never pairs two near-miss emotions, tier 2
  always includes exactly one near-miss, and the confusion-pair metric records
  the chosen emotion rather than just a boolean.

## Constraints
- No new dependencies without asking.
- Match surrounding comment density and tone — explain the *why*, especially
  for therapeutic/ABA decisions.
- Landscape-only, child-safe: no text-dependent instructions, no failure states,
  no timers visible to the child. Respect `GameMotion.reduced` — under reduced
  motion the face transitions cross-fade instead of animating.
- Scene content must stay mild. "Ice cream fell" is the ceiling for negative
  emotion; nothing frightening, nothing that depicts a child being hurt or
  excluded.
- Run `flutter analyze` for `packages/game_core` and `apps/main_app` when done
  and report the output.
- Report anything you couldn't wire up (missing VO recordings, missing cards).
````
