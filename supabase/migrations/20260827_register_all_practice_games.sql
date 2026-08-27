-- AUM-307 — register every Practice game in the recommendation catalog.
--
-- A partial seed existed (6 games, 3 categories, 7 modules incl.
-- mixed_starter). This migration adds the missing 6 practice games, the
-- attention category, the missing game→category mappings, and the missing
-- practice modules. Registration is idempotent: every INSERT is guarded by
-- ON CONFLICT ... DO NOTHING, so already-seeded rows are left untouched.
--
-- game.title is a hard join key against ActiveGamesService.titleToGameId:
-- keep the comma, space, and apostrophes exactly as written or the game
-- silently disappears from the lobby.
--
-- mixed_starter is intentionally NOT seeded here: it is a legacy aggregate
-- profile, not a practice game. It is documented in
-- docs/games/recommendation-coverage.md.

-- 1. Skill categories (adds the missing `attention` row; mirrors the enum in
--    the app minus the `attention` category mapping, which is deferred).
INSERT INTO public.skill_categories (slug, name, description, sort_order) VALUES
  ('communication', 'Communication', 'Skills related to expressing needs, following instructions, and understanding language', 1),
  ('social_interaction', 'Social Interaction', 'Skills related to joining, greeting, turn-taking, and reading others', 2),
  ('play_skills', 'Play Skills', 'Skills related to play: matching, sorting, tracing, and creative play', 3),
  ('attention', 'Attention & Focus', 'Skills related to sustained attention, focus, and self-regulation', 4)
ON CONFLICT (slug) DO NOTHING;

-- 2. Games catalog. `name` MUST equal GameRegistry display names exactly.
INSERT INTO public.games (slug, name, description, sort_order) VALUES
  ('match_it', 'Match It', 'Tap shapes that look the same to make a match.', 1),
  ('copy_me', 'Copy Me', 'Watch the sequence, then copy it!', 2),
  ('do_what_i_say', 'Do What I Say', 'Follow the instructions to tap the right shape!', 3),
  ('my_turn_your_turn', 'My Turn, Your Turn', 'Take turns placing shapes with your buddy!', 4),
  ('sari_sari_sort', 'Sari-Sari Store Sorting', 'Move each picture to the right basket — toys, food, or things!', 5),
  ('trace_it', 'Trace It', 'Trace the letter or number with your finger!', 6),
  ('tulong_kaibigan', 'Tulong, Kaibigan!', 'Share the matching item with a friend who asks for it!', 7),
  ('hintay', 'Hintay!', 'Wait for the signal, then act on it!', 8),
  ('anong_susunod', 'Ano''ng Susunod?', 'Say what comes next in the sequence!', 9),
  ('sabay_tayo', 'Sabay Tayo!', 'Do the action together with your buddy!', 10),
  ('kumusta', 'Kumusta!', 'Greet the friend and get a smile back!', 11),
  ('anong_nararamdaman', 'Ano''ng Nararamdaman?', 'Match feelings to the faces you see!', 12)
ON CONFLICT (slug) DO NOTHING;

-- 3. Game -> skill-category mappings, mirrored from GameRegistry.categories.
INSERT INTO public.game_skill_categories (game_id, skill_category_id, weight)
SELECT g.id, sc.id, mappings.weight
FROM (VALUES
  ('match_it', 'play_skills', 1.0::real),
  ('copy_me', 'communication', 1.0::real),
  ('copy_me', 'play_skills', 1.0::real),
  ('do_what_i_say', 'communication', 1.0::real),
  ('my_turn_your_turn', 'social_interaction', 1.0::real),
  ('sari_sari_sort', 'play_skills', 1.0::real),
  ('sari_sari_sort', 'communication', 1.0::real),
  ('trace_it', 'play_skills', 1.0::real),
  ('tulong_kaibigan', 'social_interaction', 1.0::real),
  ('tulong_kaibigan', 'communication', 1.0::real),
  ('hintay', 'play_skills', 1.0::real),
  ('anong_susunod', 'play_skills', 1.0::real),
  ('anong_susunod', 'communication', 1.0::real),
  ('sabay_tayo', 'social_interaction', 1.0::real),
  ('sabay_tayo', 'play_skills', 1.0::real),
  ('kumusta', 'social_interaction', 1.0::real),
  ('kumusta', 'communication', 1.0::real),
  ('anong_nararamdaman', 'social_interaction', 1.0::real),
  ('anong_nararamdaman', 'communication', 1.0::real)
) AS mappings(game_slug, category_slug, weight)
JOIN public.games g ON g.slug = mappings.game_slug
JOIN public.skill_categories sc ON sc.slug = mappings.category_slug
ON CONFLICT (game_id, skill_category_id) DO NOTHING;

-- 4. Learning modules. `title` equals games.name exactly (hard join key);
--    target_domain is the game's FIRST registry category slug.
INSERT INTO public.learning_modules
  (module_code, title, description, target_domain, difficulty_level, active)
VALUES
  ('match_it', 'Match It', 'Tap shapes that look the same to make a match.', 'play_skills', 'beginner', true),
  ('copy_me', 'Copy Me', 'Watch the sequence, then copy it!', 'communication', 'beginner', true),
  ('do_what_i_say', 'Do What I Say', 'Follow the instructions to tap the right shape!', 'communication', 'beginner', true),
  ('my_turn_your_turn', 'My Turn, Your Turn', 'Take turns placing shapes with your buddy!', 'social_interaction', 'beginner', true),
  ('sari_sari_sort', 'Sari-Sari Store Sorting', 'Move each picture to the right basket — toys, food, or things!', 'play_skills', 'beginner', true),
  ('trace_it', 'Trace It', 'Trace the letter or number with your finger!', 'play_skills', 'beginner', true),
  ('tulong_kaibigan', 'Tulong, Kaibigan!', 'Share the matching item with a friend who asks for it!', 'social_interaction', 'beginner', true),
  ('hintay', 'Hintay!', 'Wait for the signal, then act on it!', 'play_skills', 'beginner', true),
  ('anong_susunod', 'Ano''ng Susunod?', 'Say what comes next in the sequence!', 'play_skills', 'beginner', true),
  ('sabay_tayo', 'Sabay Tayo!', 'Do the action together with your buddy!', 'social_interaction', 'beginner', true),
  ('kumusta', 'Kumusta!', 'Greet the friend and get a smile back!', 'social_interaction', 'beginner', true),
  ('anong_nararamdaman', 'Ano''ng Nararamdaman?', 'Match feelings to the faces you see!', 'social_interaction', 'beginner', true)
ON CONFLICT (module_code) DO NOTHING;
