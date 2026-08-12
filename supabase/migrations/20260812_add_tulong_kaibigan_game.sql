-- Migration: Add "Tulong, Kaibigan!" sharing and requesting game rows.
-- Write-only migration: apply through the normal deployment workflow.

INSERT INTO public.games (slug, name, description, sort_order) VALUES
  ('tulong_kaibigan', 'Tulong, Kaibigan!',
   'Your friend needs something — give it to them!', 12)
ON CONFLICT (slug) DO NOTHING;

INSERT INTO public.game_skill_categories (game_id, skill_category_id, weight)
SELECT g.id, sc.id, mappings.weight
FROM (VALUES
  ('tulong_kaibigan', 'social_interaction', 1.0::real),
  ('tulong_kaibigan', 'communication', 0.5::real)
) AS mappings(game_slug, category_slug, weight)
JOIN public.games g ON g.slug = mappings.game_slug
JOIN public.skill_categories sc ON sc.slug = mappings.category_slug
ON CONFLICT (game_id, skill_category_id) DO NOTHING;

-- `title` is a hard join key against ActiveGamesService. Keep the comma and
-- exclamation mark exactly as written or the game silently disappears.
INSERT INTO public.learning_modules
  (module_code, title, description, target_domain, difficulty_level, active)
VALUES
  ('tulong_kaibigan', 'Tulong, Kaibigan!',
   'Listen to a friend’s request and share the matching item with them.',
   'social_interaction', 'beginner', true)
ON CONFLICT (module_code) DO NOTHING;
