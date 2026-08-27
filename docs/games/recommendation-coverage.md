# Recommendation coverage — Practice games (AUM-307)

## Context

This audit traced every Practice game through the full recommendation pipeline to find why My Path was empty for authenticated parents:

- **Cloud recommender** — `ai_assessment/app/rules.py` `AREA_MODULE_MAP` (the module list per skill area).
- **On-device rules** — `LocalRecommendationRules` (`apps/main_app/lib/services/local_recommendation_rules.dart`), the local port of `rules.py`.
- **Registry** — `GameRegistry.games` (`packages/game_core/lib/src/registry/game_registry.dart`), the canonical id/name/categories catalog.
- **DB catalog tables** — `games`, `skill_categories`, `game_skill_categories`, `learning_modules` (Supabase).
- **Title join keys** — `ActiveGamesService.titleToGameId` and `RecommendationFilter.nameToGameId`, which bridge the human-readable DB titles to snake_case game ids.
- **Launchability** — `GameLauncher.screenFor`, the practice-screen wiring.

**Root cause:** the live catalog tables were in a **partial seed** state — only 6 of the 12 Practice games (`match_it`, `copy_me`, `do_what_i_say`, `my_turn_your_turn`, `sari_sari_sort`, `trace_it`) had rows in `games`/`skill_categories`/`game_skill_categories`/`learning_modules` (plus the legacy `mixed_starter` module). The other 6 Practice games (`tulong_kaibigan`, `hintay`, `anong_susunod`, `sabay_tayo`, `kumusta`, `anong_nararamdaman`) had **no module rows at all**, so `ActiveGamesService` never surfaced them: they silently disappeared from My Path and from every AI-recommended module set. Fixing this ticket seeds the missing rows and hardens the pipeline with the automated coverage check below.

## Practice game coverage

All 12 Practice games are now `Registered — recommended & launchable`. Cloud areas come from `rules.py` `AREA_MODULE_MAP`; on-device areas are the areas through which `LocalRecommendationRules.deriveModuleDetails` reaches the game; `DB module (target_domain)` is the migration-defined `learning_modules.target_domain`.

| Game id | Name | Registry categories | Cloud areas (rules.py) | On-device areas | DB module (target_domain) | Status |
|---|---|---|---|---|---|---|
| `match_it` | Match It | play_skills | play, attention | play, attention | play_skills | Registered — recommended & launchable |
| `copy_me` | Copy Me | communication, play_skills | communication | play, communication | communication | Registered — recommended & launchable |
| `do_what_i_say` | Do What I Say | communication | communication, attention | communication, attention | communication | Registered — recommended & launchable |
| `my_turn_your_turn` | My Turn, Your Turn | social_interaction | social | social | social_interaction | Registered — recommended & launchable |
| `sari_sari_sort` | Sari-Sari Store Sorting | play_skills, communication | communication, play | play, communication | play_skills | Registered — recommended & launchable |
| `trace_it` | Trace It | play_skills | play | play | play_skills | Registered — recommended & launchable |
| `hintay` | Hintay! | play_skills | attention | play, attention | attention | Registered — recommended & launchable *(hintay added to on-device attention on 2026-08-27)* |
| `anong_susunod` | Ano'ng Susunod? | play_skills, communication | communication, play | play, communication | play_skills | Registered — recommended & launchable |
| `sabay_tayo` | Sabay Tayo! | social_interaction, play_skills | social, play | play, social | social_interaction | Registered — recommended & launchable |
| `kumusta` | Kumusta! | social_interaction, communication | communication, social | communication, social | social_interaction | Registered — recommended & launchable |
| `anong_nararamdaman` | Ano'ng Nararamdaman? | social_interaction, communication | communication, social | communication, social | social_interaction | Registered — recommended & launchable |
| `tulong_kaibigan` | Tulong, Kaibigan! | social_interaction, communication | communication, social | communication, social | social_interaction | Registered — recommended & launchable |

### Fixes shipped in this ticket

- **Catalog seed** (`supabase/migrations/20260827_register_all_practice_games.sql`, applied live): adds the 6 missing Practice games + their `learning_modules` rows (titles exactly equal `games.name`, the hard join key), the `attention` skill category, and the missing game→category mappings (registry parity). Idempotent (`ON CONFLICT DO NOTHING`); pre-existing rows untouched; `mixed_starter` untouched.
- `hintay` is now in `LocalRecommendationRules.attentionGameIds` (`['hintay', 'do_what_i_say', 'match_it']`), matching the cloud `attention` area. Previously it was reachable only through the play category, so an attention-only need did not surface it the way the cloud recommender would.
- `ActiveGamesService.titleToGameId` and `RecommendationFilter.nameToGameId` are now public, so the automated coverage check can assert the DB title join contract.

## Intentional exclusions

- **(a) `mixed_starter` ('Mixed Starter Module')** — a legacy aggregate-profile artifact, not a Practice game, with no practice screen, and never emitted by the cloud recommender's `AREA_MODULE_MAP`. It is therefore **not seeded** in `learning_modules`; the balanced-set behavior is produced by the recommender engine at runtime (all-Strength → mixed set at level 3), not by a catalog row.
- **(b) Cloud play map omits `copy_me` and `hintay` by design** — `copy_me` routes through the `communication` area and `hintay` through `attention` (see the `rules.py` comments); each appears in exactly the area it targets, not also in play.
- **(c) A real `attention` skill_categories enum + `game_skill_categories` pass is deferred** (per the 2026-08-10 note): the `attention` row is seeded in `skill_categories`, but the Dart `SkillCategory` enum has no `attention` value, `hintay`'s `learning_modules.target_domain` stays `play_skills` (first registry category, same rule as every other module), and the game-to-category mappings stay `play_skills` for registry parity. Introducing a real `attention` category is a separate change (enum value + a pass over existing games that also load attention, e.g. `do_what_i_say`, `match_it`).

## Known divergences (not changed)

- **On-device play list is registry-derived and is a superset of the cloud play list** — it includes `copy_me` and `hintay` (because both carry `play_skills` in the registry), whereas the cloud play map routes those two through communication/attention only.
- **Per-area module ordering differs** — the on-device engine iterates registry category order; the cloud list is a curated developmental order (e.g. social orders `sabay_tayo` before turn-taking).
- Both divergences are **kept as-is** because changing them changes recommendation behavior (a product gate). They are flagged for product review, not silently altered by this ticket.

## Automated validation

`apps/main_app/test/services/recommendation_coverage_test.dart` is the regression guard. It runs as a pure Dart test (no network, no widgets, no mocks) and asserts six contracts:

1. **Practice catalog is closed** — `GameLauncher.supportedGameIds` and the id set derived from `GameRegistry.games` are identical (no registry game is un-launchable, no practice game is unregistered).
2. **Cloud registration** — parses `ai_assessment/app/rules.py` at runtime and extracts every `"game_id": "..."` into a set; asserts every supported game id is present *and* every cloud id exists in the registry (no phantom ids). The file is read via `File('../../ai_assessment/app/rules.py')`, which resolves from the `flutter test` cwd (the `aumazing` package root, `apps/main_app`) to the repo's `ai_assessment/app/rules.py`.
3. **On-device eligibility** — with all areas at `needs_support` (levelInt 0), `deriveModuleDetails` reaches every supported game; with all areas at strength (levelInt 2) the mixed-starter set also contains every supported game at level 3.
4. **Attention parity** — `LocalRecommendationRules.attentionGameIds == ['hintay', 'do_what_i_say', 'match_it']` (exact order and set).
5. **Display-name join keys** — for every registry game, `ActiveGamesService.titleToGameId[game.name]` and `RecommendationFilter.nameToGameId[game.name]` both map to that game's id (the DB title join contract).
6. **Launchable** — `GameLauncher.screenFor(id, 1)` returns non-null for every supported id.

**Adding a new Practice game now requires**, or the test fails: a `GameRegistry` entry; a `GameLauncher.supportedGameIds` entry **and** a `screenFor` case; an `AREA_MODULE_MAP` entry in `rules.py` (so it is reachable from the cloud); a `LocalRecommendationRules` path (registry category or `attentionGameIds`); an entry in both `titleToGameId`/`nameToGameId`; and a DB seed row. The test fails the moment any one of these is missing.

## Live DB state

Verified 2026-08-27 against the live project (`lzvvjlcfoyczikaszrbp`):

- `games`: **12** (6 pre-existing + 6 added)
- `skill_categories`: **4** (`communication`, `social_interaction`, `play_skills`, `attention`)
- `learning_modules`: **13** (12 Practice modules + pre-existing `mixed_starter`), all `active = true`, titles exactly equal `games.name`
- `game_skill_categories`: **19** (registry parity; per-game counts: match_it 1, copy_me 2, do_what_i_say 1, my_turn_your_turn 1, sari_sari_sort 2, trace_it 1, tulong_kaibigan 2, hintay 1, anong_susunod 2, sabay_tayo 2, kumusta 2, anong_nararamdaman 2)
- Idempotency: re-applying the migration changed no counts.
