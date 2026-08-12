-- Migration: Add "Sabay Tayo!" (Let's Look Together) game rows
-- Description:
--   Registers Sabay Tayo!, a joint-attention task, in the games catalog with
--   its skill-category mapping and learning_modules row.
--
--   This is the first module in the catalog that trains joint attention —
--   following another person's gaze to a shared referent — which is the
--   earliest social-interaction skill on the developmental ladder and the one
--   every other social game already assumes. Before this, `social` in
--   ai_assessment/app/rules.py routed to exactly one game (my_turn_your_turn),
--   so a child whose social area came back needing support had a single
--   turn-taking module offered to them regardless of whether they could share
--   attention with a partner at all.
-- Date: 2026-08-12

-- 1. Game catalog
INSERT INTO public.games (slug, name, description, sort_order) VALUES
  ('sabay_tayo', 'Sabay Tayo!', 'Look where your buddy is looking, then tap what they see!', 9)
ON CONFLICT (slug) DO NOTHING;

-- 2. Skill category mapping (mirrors GameRegistry categories).
--
--    Social Interaction carries the full weight; Play Skills is secondary at
--    0.5 because the tap-the-object layer is a play task wrapped around the
--    social one, and weighting it equally would let this game inflate a play
--    score it only incidentally exercises.
INSERT INTO public.game_skill_categories (game_id, skill_category_id, weight)
SELECT g.id, sc.id, mappings.weight
FROM (VALUES
  ('sabay_tayo', 'social_interaction', 1.0::real),
  ('sabay_tayo', 'play_skills', 0.5::real)
) AS mappings(game_slug, category_slug, weight)
JOIN public.games g ON g.slug = mappings.game_slug
JOIN public.skill_categories sc ON sc.slug = mappings.category_slug
ON CONFLICT (game_id, skill_category_id) DO NOTHING;

-- 3. Learning module. `title` is a hard join key against
--    ActiveGamesService._titleToGameId — 'Sabay Tayo!' must match exactly,
--    exclamation mark included, or the game silently never appears.
--
--    `target_domain` takes the `skill_categories.slug` form
--    ('social_interaction', not 'social'), matching every seeded row. Nothing
--    reads the column today, so a mismatch would sit in the data unnoticed
--    until something does.
INSERT INTO public.learning_modules
  (module_code, title, description, target_domain, difficulty_level, active)
VALUES
  ('sabay_tayo', 'Sabay Tayo!', 'Follow your buddy''s gaze to the object they are looking at, then tap it. Builds joint attention — the foundation every other social skill is built on.', 'social_interaction', 'beginner', true)
ON CONFLICT (module_code) DO NOTHING;
