-- ============================================================
-- Migration: AI Assessment Support
-- Date: 2026-04-24
-- Description: Extends assessment_results and module_recommendations
--              tables to store XGBoost AI prediction outputs.
--              Seeds learning_modules with the 4 game modules.
--              Adds 'attention' skill category.
-- ============================================================

-- 1. Extend assessment_results with AI prediction columns
ALTER TABLE assessment_results ADD COLUMN IF NOT EXISTS predicted_profile TEXT;
ALTER TABLE assessment_results ADD COLUMN IF NOT EXISTS confidence REAL;
ALTER TABLE assessment_results ADD COLUMN IF NOT EXISTS support_level TEXT;
ALTER TABLE assessment_results ADD COLUMN IF NOT EXISTS type TEXT DEFAULT 'pre';
ALTER TABLE assessment_results ADD COLUMN IF NOT EXISTS game_id TEXT;
ALTER TABLE assessment_results ADD COLUMN IF NOT EXISTS score INTEGER;
ALTER TABLE assessment_results ADD COLUMN IF NOT EXISTS total_items INTEGER;
ALTER TABLE assessment_results ADD COLUMN IF NOT EXISTS error_count INTEGER;
ALTER TABLE assessment_results ADD COLUMN IF NOT EXISTS avg_response_time_ms INTEGER;
ALTER TABLE assessment_results ADD COLUMN IF NOT EXISTS raw_metrics JSONB;

-- Add check constraint for predicted_profile values
ALTER TABLE assessment_results ADD CONSTRAINT IF NOT EXISTS chk_predicted_profile
  CHECK (predicted_profile IS NULL OR predicted_profile IN (
    'communication_support', 'social_support', 'play_support',
    'attention_support', 'balanced_profile'
  ));

-- Add check constraint for support_level values
ALTER TABLE assessment_results ADD CONSTRAINT IF NOT EXISTS chk_support_level
  CHECK (support_level IS NULL OR support_level IN ('high', 'moderate', 'low'));

-- Add check constraint for type values
ALTER TABLE assessment_results ADD CONSTRAINT IF NOT EXISTS chk_assessment_type
  CHECK (type IS NULL OR type IN ('pre', 'post', 'progress'));

-- 2. Extend module_recommendations with AI output columns
ALTER TABLE module_recommendations ADD COLUMN IF NOT EXISTS assessment_run_id UUID;
ALTER TABLE module_recommendations ADD COLUMN IF NOT EXISTS module_id UUID;
ALTER TABLE module_recommendations ADD COLUMN IF NOT EXISTS module_name TEXT;
ALTER TABLE module_recommendations ADD COLUMN IF NOT EXISTS game_id TEXT;
ALTER TABLE module_recommendations ADD COLUMN IF NOT EXISTS starting_level INTEGER DEFAULT 1;
ALTER TABLE module_recommendations ADD COLUMN IF NOT EXISTS confidence REAL;
ALTER TABLE module_recommendations ADD COLUMN IF NOT EXISTS predicted_profile TEXT;
ALTER TABLE module_recommendations ADD COLUMN IF NOT EXISTS rationale TEXT;
ALTER TABLE module_recommendations ADD COLUMN IF NOT EXISTS skill_areas TEXT[];
ALTER TABLE module_recommendations ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT NOW();

-- 3. Seed learning_modules with the 4 game modules + mixed starter
INSERT INTO learning_modules (title, description, active, difficulty_level)
VALUES
  ('Copy Me', 'Watch the sequence of shapes, then copy it! Builds imitation and communication skills.', true, 1),
  ('Do What I Say', 'Follow the verbal instructions to tap the right shape! Develops listening and communication.', true, 1),
  ('My Turn, Your Turn', 'Take turns placing shapes with your buddy! Encourages social interaction and turn-taking.', true, 1),
  ('Match It', 'Tap shapes that look the same to make a match! Develops visual matching and play skills.', true, 1),
  ('Mixed Starter Module', 'A balanced mix of all activities for children with well-rounded skills.', true, 1)
ON CONFLICT DO NOTHING;

-- 4. Add 'attention' skill category (communication, social_interaction, play_skills already exist)
INSERT INTO skill_categories (slug, name, description, sort_order)
VALUES ('attention', 'Attention & Focus', 'Skills related to sustained attention, focus, and self-regulation', 4)
ON CONFLICT (slug) DO NOTHING;

-- 5. Create index for faster AI assessment queries
CREATE INDEX IF NOT EXISTS idx_assessment_results_predicted_profile
  ON assessment_results (predicted_profile) WHERE predicted_profile IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_assessment_results_child_type
  ON assessment_results (child_id, type);

CREATE INDEX IF NOT EXISTS idx_module_recommendations_child
  ON module_recommendations (child_id, created_at DESC);
