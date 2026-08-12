# Prompt — Kumusta! (greetings)

Paste everything inside the fence into a fresh Claude Code session in its own
worktree. Nothing needs filling in.

````markdown
# New Aumazing mini-game: Kumusta!

Add a new child mini-game to the Aumazing monorepo, following the exact
conventions of the existing games (read `sari_sari_sort` and `hintay`
end-to-end first — game logic in `packages/game_core`, screen wrapper in
`main_app`, and `docs/new-game-prompt-template.md` for the full checklist).

## Game spec
- **id**: `kumusta`
- **Display name**: `Kumusta!`
- **One-line description**: `Say hello back to your friend!`
- **Skill categories**: `socialInteraction`
- **Sort order** (DB): `10`
- **Core mechanic**: A buddy character (BPS or Reiz — one character for the
  whole session, never both) walks in, faces the child and offers a greeting
  gesture: a wave, a high-five, a fist-bump, or a thumbs-up. The child taps the
  matching greeting icon from a row of large icon buttons to greet back. The
  buddy reacts to a correct greeting by completing it — the high-five connects,
  the wave is returned — which is the reinforcement, not the score.
  The skill is *responding to a social bid*, so the buddy always initiates and
  always waits: there is no time pressure and the buddy never gives up.
- **Round structure**: 4 rounds (fixed — keep it), `config.itemsPerRound`
  greetings per round.
- **Difficulty tiers 1–3**:
  - tier 1: one greeting, 2 icon choices, buddy holds the gesture indefinitely.
  - tier 2: 3 icon choices; buddy holds the gesture then relaxes to rest,
    so the child must recall it rather than match what is currently on screen.
  - tier 3: 4 choices, and a *return greeting* — the buddy greets, the child
    responds, then the buddy immediately offers a second, different greeting in
    the same trial. Two-turn exchanges are the actual social target; a single
    response is only half of a greeting.
- **Correctness rule**: the tapped icon must match the gesture the buddy last
  offered. Generous hit targets (inflate visual bounds ~20%, as `sari_sari_sort`
  does). No timers visible to the child, no fail state — a wrong tap gently
  bounces back, the buddy re-offers the gesture, and the trial continues until
  the child gets it.
- **Hint policy**: ABA prompt hierarchy via `DifficultyProfile`, escalating per
  wrong tap — (1) buddy repeats the gesture larger and slower, (2) the correct
  icon pulses, (3) `shared/ghost_hand.dart` travels to the icon and taps it.
  Easy: unlimited + a guided demo before the first trial. Medium: budget of 2,
  then the ghost hand. Hard: none. `DifficultyProfile.assessment` suppresses all.
- **Extra metrics for analytics**: `greetingLatencyMs` (buddy's gesture settles
  → first tap — the social-responsiveness measure, distinct from response time),
  `promptLevelUsed` (0 = independent; the number a therapist reads),
  `returnGreetingAccuracy` (tier 3 only — accuracy on the *second* turn of the
  exchange, which is where children who mimic rather than converse drop off).

## Assets — IMPORTANT
- **Every generated asset goes through kie.ai.** No other provider.
- **Character art: none needed.** The gestures already ship as sprite sheets in
  `packages/shared_ui/assets/characters/`: `{bps,reiz}_wave.png` (4×3, 12
  frames), `_present.png`, `_nod.png`, `_celebrate.png`, `_idle.png`,
  `_oops.png`, `_encourage.png` — see `CharacterSprites.layout` for every
  sheet's grid. Only high-five and fist-bump have no sheet; **first try
  composing them from `_present` + `_celebrate`**, and only if that genuinely
  cannot read as a high-five, generate new actions with
  `python scripts/generate_sprites.py bps --only high_five,fist_bump`
  (kie.ai `bytedance/seedance-2`) — read `scripts/SPRITES.md` first, especially
  `REST_FILL = 0.66`, which is the invariant that cost ~2,100 credits to learn.
  Run `python scripts/quantize_sprites.py --apply` after any sprite run.
- **Loading sprites into Flame**: `CharacterSprites` is Flutter-side
  (`ImageProvider`) and unusable from a Flame component. Copy the pattern in
  `packages/game_core/lib/src/games/anong_susunod/routine_art_cache.dart` —
  `Images(prefix: '')`, full package paths, best-effort load with a painted
  fallback so a missing asset never ends a child's session.
- **Greeting icons**: draw them as painted vector glyphs in the game (a hand,
  an open palm, a fist, a thumb), in the style of
  `sari_sari_sort/components/draggable_item.dart`'s cards. Do not generate art
  for these.
- **Voice-over**: reuse existing `VoiceOverCue`s where they fit (`hereWeGo`,
  `yourTurn`, `nowYouTry`, Core Praise, Gently Retry). A greeting line almost
  certainly needs a new cue — propose `sayHelloBack` and follow the
  `waitForTheStar` precedent in `packages/shared_audio/lib/src/voice_over_service.dart`
  (Hintay! added a dedicated line rather than reusing a near-miss cue; document
  the same reasoning). Generate recordings with
  `tools/voice_gen/generate_kie.py --backend gemini` (default; ElevenLabs on kie
  has failed with `failCode 500` since 2026-07-31). Read
  `tools/voice_gen/README.md`; `export KIE_API_KEY=…` and never commit it.
  Output goes to `out/` — install it with the existing scripts, not by hand.
- **Logo**: hand-author `packages/shared_ui/assets/game_logos/kumusta.svg` to
  match the existing eight tiles.

## Implementation checklist
Follow `docs/new-game-prompt-template.md` steps 1–6 verbatim, plus:
- `ai_assessment/app/rules.py`: add `{"game_id": "kumusta", "name": "Kumusta!"}`
  to `AREA_MODULE_MAP["social"]` (which currently holds one game).
- Migration `supabase/migrations/<YYYYMMDD>_add_kumusta_game.sql` following
  `20260810_add_hintay_game.sql`: `games` row (sort_order 10),
  `game_skill_categories` → `social_interaction` weight 1.0, and a
  `learning_modules` row with `module_code = 'kumusta'`,
  `title = 'Kumusta!'` (**must match `ActiveGamesService._titleToGameId`
  exactly**, exclamation mark included, or the game silently never appears),
  `target_domain = 'social'`, `difficulty_level = 'beginner'`, `active = true`.
  **Write the migration file only — do not apply it.**
- Tests in `packages/game_core/test/kumusta_test.dart` following
  `sari_sari_sort_test.dart`.

## Constraints
- No new dependencies without asking.
- Match surrounding comment density and tone — explain the *why*, especially
  for therapeutic/ABA decisions.
- Landscape-only, child-safe: no text-dependent instructions, no failure states,
  no timers visible to the child. Respect `GameMotion.reduced` (gestures play at
  reduced amplitude; no walk-in entrance).
- Run `flutter analyze` for `packages/game_core` and `apps/main_app` when done
  and report the output.
- Report anything you couldn't wire up (missing VO recordings, missing sheets).
````
