-- Migration: Add "Kumusta!" (Greet Back) game rows
-- Description:
--   Registers Kumusta!, a greeting-exchange game, in the games catalog with
--   its skill-category mappings and learning_modules row.
--
--   Mapped to BOTH social_interaction and communication: answering another
--   person's greeting is the social act the game is named for, and the
--   returned gesture is a non-verbal conversational turn.
-- Date: 2026-08-12

-- 1. Game catalog
INSERT INTO public.games (slug, name, description, sort_order) VALUES
  ('kumusta', 'Kumusta!', 'Your buddy says hello — greet them back!', 10)
ON CONFLICT (slug) DO NOTHING;

-- 2. Skill category mappings (mirrors GameRegistry categories).
INSERT INTO public.game_skill_categories (game_id, skill_category_id, weight)
SELECT g.id, sc.id, mappings.weight
FROM (VALUES
  ('kumusta', 'social_interaction', 1.0::real),
  ('kumusta', 'communication', 1.0::real)
) AS mappings(game_slug, category_slug, weight)
JOIN public.games g ON g.slug = mappings.game_slug
JOIN public.skill_categories sc ON sc.slug = mappings.category_slug
ON CONFLICT (game_id, skill_category_id) DO NOTHING;

-- 3. Learning module. `title` is a hard join key against
--    ActiveGamesService._titleToGameId — "Kumusta!" must match exactly,
--    exclamation mark included, or the game silently never appears in the
--    lobby.
INSERT INTO public.learning_modules
  (module_code, title, description, target_domain, difficulty_level, active)
VALUES
  ('kumusta', 'Kumusta!', 'Greet your buddy back! Builds social responding, joint attention, and turn-taking.', 'social_interaction', 'beginner', true)
ON CONFLICT (module_code) DO NOTHING;
