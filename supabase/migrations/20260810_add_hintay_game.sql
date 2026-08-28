-- Migration: Add "Hintay!" (Wait For It) game rows
-- Description:
--   Registers Hintay!, a go/no-go attention task, in the games catalog with
--   its skill-category mapping and learning_modules row.
--
--   Note on the category: rules.py routes this game from the `attention`
--   skill area, but `skill_categories` has no `attention` row and the Dart
--   SkillCategory enum has no matching value, so the mapping below uses
--   play_skills to stay consistent with GameRegistry. Introducing a real
--   `attention` category is a separate change — it needs a skill_categories
--   insert, the enum value, and a pass over game_skill_categories for the
--   existing games that also load attention (do_what_i_say, match_it).
-- Date: 2026-08-10

-- 1. Game catalog
INSERT INTO public.games (slug, name, description, sort_order) VALUES
  ('hintay', 'Hintay!', 'Wait for the star to wake up, then tap it!', 7)
ON CONFLICT (slug) DO NOTHING;

-- 2. Skill category mapping (mirrors GameRegistry categories).
INSERT INTO public.game_skill_categories (game_id, skill_category_id, weight)
SELECT g.id, sc.id, mappings.weight
FROM (VALUES
  ('hintay', 'play_skills', 1.0::real)
) AS mappings(game_slug, category_slug, weight)
JOIN public.games g ON g.slug = mappings.game_slug
JOIN public.skill_categories sc ON sc.slug = mappings.category_slug
ON CONFLICT (game_id, skill_category_id) DO NOTHING;

-- 3. Learning module. `title` is a hard join key against
--    ActiveGamesService._titleToGameId — 'Hintay!' must match exactly,
--    exclamation mark included, or the game silently never appears.
INSERT INTO public.learning_modules
  (module_code, title, description, target_domain, difficulty_level, active)
VALUES
  ('hintay', 'Hintay!', 'Wait for the sleeping star to wake up before tapping it! Builds impulse control and sustained attention.', 'attention', 'beginner', true)
ON CONFLICT (module_code) DO NOTHING;
