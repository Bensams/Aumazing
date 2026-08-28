-- Migration: Add "Trace It" + backfill "Sari-Sari Store Sorting" game rows
-- Description:
--   1) Registers Trace It (finger-tracing of letters, numbers, and
--      pre-writing strokes) and the previously-missing Sari-Sari Store
--      Sorting in the games catalog, with skill-category mappings.
--   2) Re-seeds learning_modules with the correct schema. The seed in
--      20260424_ai_assessment_columns.sql assumed columns
--      (title, description, active, difficulty_level int) but the live
--      table requires module_code and target_domain and a text
--      difficulty_level, so that insert failed and the table stayed empty.
-- Date: 2026-07-02

-- 1. Game catalog
INSERT INTO public.games (slug, name, description, sort_order) VALUES
  ('sari_sari_sort', 'Sari-Sari Store Sorting', 'Drag each item into the right basket at the store!', 5),
  ('trace_it', 'Trace It', 'Trace the letter or number with your finger!', 6)
ON CONFLICT (slug) DO NOTHING;

-- 2. Skill category mappings (mirrors GameRegistry categories).
--    Trace It is primarily Play Skills (solitary, goal-directed tool use);
--    its fine-motor load is captured in gameplay analytics, not as a
--    separate category.
INSERT INTO public.game_skill_categories (game_id, skill_category_id, weight)
SELECT g.id, sc.id, mappings.weight
FROM (VALUES
  ('sari_sari_sort', 'play_skills', 1.0::real),
  ('sari_sari_sort', 'communication', 1.0::real),
  ('trace_it', 'play_skills', 1.0::real)
) AS mappings(game_slug, category_slug, weight)
JOIN public.games g ON g.slug = mappings.game_slug
JOIN public.skill_categories sc ON sc.slug = mappings.category_slug
ON CONFLICT (game_id, skill_category_id) DO NOTHING;

-- 3. Learning modules (admin on/off toggles; titles must match
--    ActiveGamesService._titleToGameId in the app). Seeds every game, since
--    the 20260424 seed never landed.
INSERT INTO public.learning_modules
  (module_code, title, description, target_domain, difficulty_level, active)
VALUES
  ('copy_me', 'Copy Me', 'Watch the sequence of shapes, then copy it! Builds imitation and communication skills.', 'communication', 'beginner', true),
  ('do_what_i_say', 'Do What I Say', 'Follow the verbal instructions to tap the right shape! Develops listening and communication.', 'communication', 'beginner', true),
  ('my_turn_your_turn', 'My Turn, Your Turn', 'Take turns placing shapes with your buddy! Encourages social interaction and turn-taking.', 'social_interaction', 'beginner', true),
  ('match_it', 'Match It', 'Tap shapes that look the same to make a match! Develops visual matching and play skills.', 'play_skills', 'beginner', true),
  ('sari_sari_sort', 'Sari-Sari Store Sorting', 'Drag each item into the right basket at the store! Builds sorting and play skills.', 'play_skills', 'beginner', true),
  ('trace_it', 'Trace It', 'Trace letters, numbers, and pre-writing strokes with your finger! Builds visual-motor and play skills.', 'play_skills', 'beginner', true),
  ('mixed_starter', 'Mixed Starter Module', 'A balanced mix of all activities for children with well-rounded skills.', 'mixed', 'beginner', true)
ON CONFLICT (module_code) DO NOTHING;
