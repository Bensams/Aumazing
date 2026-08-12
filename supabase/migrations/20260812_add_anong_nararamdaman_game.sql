-- Migration: Add "Ano'ng Nararamdaman?" (How does he feel?) game rows
-- Description:
--   Registers Ano'ng Nararamdaman?, an emotion-recognition game, in the games
--   catalog with its skill-category mappings and learning_modules row.
--
--   Mapped to BOTH social_interaction and communication, and both at full
--   weight. Reading a friend's face is the social half; naming the feeling is
--   the communication half, and the game does the second on every single trial
--   — a correct tap is answered by speaking the emotion word back. Weighting
--   communication lower would under-report a game that is, in practice, an
--   emotion-vocabulary drill wearing a social task's clothes.
-- Date: 2026-08-12

-- 1. Game catalog
INSERT INTO public.games (slug, name, description, sort_order) VALUES
  ('anong_nararamdaman', 'Ano''ng Nararamdaman?', 'How is your friend feeling? Find the face that matches!', 11)
ON CONFLICT (slug) DO NOTHING;

-- 2. Skill category mappings (mirrors GameRegistry categories).
INSERT INTO public.game_skill_categories (game_id, skill_category_id, weight)
SELECT g.id, sc.id, mappings.weight
FROM (VALUES
  ('anong_nararamdaman', 'social_interaction', 1.0::real),
  ('anong_nararamdaman', 'communication', 1.0::real)
) AS mappings(game_slug, category_slug, weight)
JOIN public.games g ON g.slug = mappings.game_slug
JOIN public.skill_categories sc ON sc.slug = mappings.category_slug
ON CONFLICT (game_id, skill_category_id) DO NOTHING;

-- 3. Learning module. `title` is a hard join key against
--    ActiveGamesService._titleToGameId — "Ano'ng Nararamdaman?" must match
--    exactly, apostrophe and question mark included, or the game silently
--    never appears in the lobby.
--
--    `target_domain` is 'social_interaction', not 'social'. Every existing row
--    uses the `skill_categories.slug` spelling — My Turn, Your Turn, the other
--    social game, is 'social_interaction' — and a lone 'social' here would be
--    the only value in the table that matches no category slug. The AI's area
--    keys ('social', 'communication', 'play', 'attention') are a separate
--    namespace and live in rules.py, which this column is not read by.
INSERT INTO public.learning_modules
  (module_code, title, description, target_domain, difficulty_level, active)
VALUES
  ('anong_nararamdaman', 'Ano''ng Nararamdaman?', 'Find the face that matches how your friend feels! Builds emotion recognition, emotion vocabulary, and caring responses.', 'social_interaction', 'beginner', true)
ON CONFLICT (module_code) DO NOTHING;
