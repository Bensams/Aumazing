-- Migration: Create game categorization tables
-- Description: Creates games, skill_categories, and game_skill_categories tables
--              for mapping games to developmental skill areas (many-to-many).
-- Date: 2026-04-23

-- ============================================================================
-- 1. CREATE TABLES
-- ============================================================================

-- Games table - Game catalog
CREATE TABLE IF NOT EXISTS public.games (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug text UNIQUE NOT NULL,        -- e.g. 'copy_me', 'match_it'
  name text NOT NULL,                -- e.g. 'Copy Me', 'Match It'
  description text,
  icon text,                         -- icon identifier
  sort_order integer DEFAULT 0,
  created_at timestamptz DEFAULT now()
);

COMMENT ON TABLE public.games IS 'Game catalog containing all available games';
COMMENT ON COLUMN public.games.slug IS 'URL-friendly unique identifier for the game';
COMMENT ON COLUMN public.games.icon IS 'Icon identifier used in the Flutter app';
COMMENT ON COLUMN public.games.sort_order IS 'Display order in game lists';

-- Skill Categories table - Developmental skill areas
CREATE TABLE IF NOT EXISTS public.skill_categories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug text UNIQUE NOT NULL,        -- e.g. 'communication', 'social_interaction', 'play_skills'
  name text NOT NULL,                -- e.g. 'Communication', 'Social Interaction', 'Play Skills'
  description text,
  sort_order integer DEFAULT 0,
  created_at timestamptz DEFAULT now()
);

COMMENT ON TABLE public.skill_categories IS 'Developmental skill areas that games target';
COMMENT ON COLUMN public.skill_categories.slug IS 'URL-friendly unique identifier for the category';

-- Game-Skill Categories junction table - Many-to-many mapping
CREATE TABLE IF NOT EXISTS public.game_skill_categories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  game_id uuid NOT NULL REFERENCES public.games(id) ON DELETE CASCADE,
  skill_category_id uuid NOT NULL REFERENCES public.skill_categories(id) ON DELETE CASCADE,
  weight real DEFAULT 1.0,           -- contribution weight (0.0-1.0)
  created_at timestamptz DEFAULT now(),
  UNIQUE(game_id, skill_category_id)
);

COMMENT ON TABLE public.game_skill_categories IS 'Junction table mapping games to skill categories (many-to-many)';
COMMENT ON COLUMN public.game_skill_categories.weight IS 'Contribution weight of this game to the skill category (0.0-1.0)';

-- Create indexes for better query performance
CREATE INDEX IF NOT EXISTS idx_game_skill_categories_game_id
  ON public.game_skill_categories(game_id);

CREATE INDEX IF NOT EXISTS idx_game_skill_categories_skill_category_id
  ON public.game_skill_categories(skill_category_id);

-- ============================================================================
-- 2. ENABLE ROW LEVEL SECURITY
-- ============================================================================

ALTER TABLE public.games ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.skill_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.game_skill_categories ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- 3. RLS POLICIES
-- ============================================================================

-- Games: Authenticated users can read
CREATE POLICY "Authenticated users can read games"
  ON public.games
  FOR SELECT
  TO authenticated
  USING (true);

-- Games: Only service_role can insert
CREATE POLICY "Service role can insert games"
  ON public.games
  FOR INSERT
  TO service_role
  WITH CHECK (true);

-- Games: Only service_role can update
CREATE POLICY "Service role can update games"
  ON public.games
  FOR UPDATE
  TO service_role
  USING (true)
  WITH CHECK (true);

-- Games: Only service_role can delete
CREATE POLICY "Service role can delete games"
  ON public.games
  FOR DELETE
  TO service_role
  USING (true);

-- Skill Categories: Authenticated users can read
CREATE POLICY "Authenticated users can read skill_categories"
  ON public.skill_categories
  FOR SELECT
  TO authenticated
  USING (true);

-- Skill Categories: Only service_role can insert
CREATE POLICY "Service role can insert skill_categories"
  ON public.skill_categories
  FOR INSERT
  TO service_role
  WITH CHECK (true);

-- Skill Categories: Only service_role can update
CREATE POLICY "Service role can update skill_categories"
  ON public.skill_categories
  FOR UPDATE
  TO service_role
  USING (true)
  WITH CHECK (true);

-- Skill Categories: Only service_role can delete
CREATE POLICY "Service role can delete skill_categories"
  ON public.skill_categories
  FOR DELETE
  TO service_role
  USING (true);

-- Game Skill Categories: Authenticated users can read
CREATE POLICY "Authenticated users can read game_skill_categories"
  ON public.game_skill_categories
  FOR SELECT
  TO authenticated
  USING (true);

-- Game Skill Categories: Only service_role can insert
CREATE POLICY "Service role can insert game_skill_categories"
  ON public.game_skill_categories
  FOR INSERT
  TO service_role
  WITH CHECK (true);

-- Game Skill Categories: Only service_role can update
CREATE POLICY "Service role can update game_skill_categories"
  ON public.game_skill_categories
  FOR UPDATE
  TO service_role
  USING (true)
  WITH CHECK (true);

-- Game Skill Categories: Only service_role can delete
CREATE POLICY "Service role can delete game_skill_categories"
  ON public.game_skill_categories
  FOR DELETE
  TO service_role
  USING (true);

-- ============================================================================
-- 4. SEED DATA
-- ============================================================================

-- Insert games
INSERT INTO public.games (slug, name, description, sort_order) VALUES
  ('copy_me', 'Copy Me', 'Watch the sequence, then copy it!', 1),
  ('do_what_i_say', 'Do What I Say', 'Follow the instructions to tap the right shape!', 2),
  ('my_turn_your_turn', 'My Turn, Your Turn', 'Take turns placing shapes with your buddy!', 3),
  ('match_it', 'Match It', 'Tap shapes that look the same to make a match', 4)
ON CONFLICT (slug) DO NOTHING;

-- Insert skill categories
INSERT INTO public.skill_categories (slug, name, sort_order) VALUES
  ('communication', 'Communication', 1),
  ('social_interaction', 'Social Interaction', 2),
  ('play_skills', 'Play Skills', 3)
ON CONFLICT (slug) DO NOTHING;

-- Insert game-to-category mappings
INSERT INTO public.game_skill_categories (game_id, skill_category_id, weight)
SELECT g.id, sc.id, mappings.weight
FROM (VALUES
  ('copy_me', 'communication', 1.0::real),
  ('copy_me', 'play_skills', 1.0::real),
  ('do_what_i_say', 'communication', 1.0::real),
  ('my_turn_your_turn', 'social_interaction', 1.0::real),
  ('match_it', 'play_skills', 1.0::real)
) AS mappings(game_slug, category_slug, weight)
JOIN public.games g ON g.slug = mappings.game_slug
JOIN public.skill_categories sc ON sc.slug = mappings.category_slug
ON CONFLICT (game_id, skill_category_id) DO NOTHING;
