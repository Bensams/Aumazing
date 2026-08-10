-- Migration: Add "Ano'ng Susunod?" (What's Next?) game rows
-- Description:
--   Registers Ano'ng Susunod?, a routine-sequencing game, in the games
--   catalog with its skill-category mappings and learning_modules row.
--
--   The game is the app's most direct TEACCH implementation: a visual
--   schedule turned into an assessable task. It is mapped to BOTH
--   play_skills and communication because ordering a picture sequence is a
--   receptive-language act as much as a play one — the child reads a series
--   of pictures and acts on what they mean.
-- Date: 2026-08-10

-- 1. Game catalog
INSERT INTO public.games (slug, name, description, sort_order) VALUES
  ('anong_susunod', 'Ano''ng Susunod?', 'Put the steps of the routine in the right order!', 8)
ON CONFLICT (slug) DO NOTHING;

-- 2. Skill category mappings (mirrors GameRegistry categories).
INSERT INTO public.game_skill_categories (game_id, skill_category_id, weight)
SELECT g.id, sc.id, mappings.weight
FROM (VALUES
  ('anong_susunod', 'play_skills', 1.0::real),
  ('anong_susunod', 'communication', 1.0::real)
) AS mappings(game_slug, category_slug, weight)
JOIN public.games g ON g.slug = mappings.game_slug
JOIN public.skill_categories sc ON sc.slug = mappings.category_slug
ON CONFLICT (game_id, skill_category_id) DO NOTHING;

-- 3. Learning module. `title` is a hard join key against
--    ActiveGamesService._titleToGameId — "Ano'ng Susunod?" must match
--    exactly, apostrophe and question mark included, or the game silently
--    never appears in the lobby.
INSERT INTO public.learning_modules
  (module_code, title, description, target_domain, difficulty_level, active)
VALUES
  ('anong_susunod', 'Ano''ng Susunod?', 'Put the steps of an everyday routine in order! Builds sequencing, receptive language, and daily-living skills.', 'play_skills', 'beginner', true)
ON CONFLICT (module_code) DO NOTHING;
