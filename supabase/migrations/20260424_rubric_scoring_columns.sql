-- Add rubric scoring columns to assessment_results
ALTER TABLE assessment_results
  ADD COLUMN IF NOT EXISTS play_skills_label TEXT,
  ADD COLUMN IF NOT EXISTS communication_label TEXT,
  ADD COLUMN IF NOT EXISTS social_interaction_label TEXT,
  ADD COLUMN IF NOT EXISTS behavior_attention_label TEXT,
  ADD COLUMN IF NOT EXISTS sensory_preference_label TEXT,
  ADD COLUMN IF NOT EXISTS recommended_module TEXT,
  ADD COLUMN IF NOT EXISTS overall_summary TEXT,
  ADD COLUMN IF NOT EXISTS model_source TEXT DEFAULT 'rubric_based',
  ADD COLUMN IF NOT EXISTS xgboost_ready BOOLEAN DEFAULT true;

-- Add missing telemetry columns to game_sessions
ALTER TABLE game_sessions
  ADD COLUMN IF NOT EXISTS task_completion_rate REAL,
  ADD COLUMN IF NOT EXISTS prompt_dependency_score REAL,
  ADD COLUMN IF NOT EXISTS turn_taking_success_rate REAL,
  ADD COLUMN IF NOT EXISTS interruption_count INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS waiting_tolerance_seconds REAL,
  ADD COLUMN IF NOT EXISTS time_to_first_touch REAL,
  ADD COLUMN IF NOT EXISTS time_to_first_valid_action REAL,
  ADD COLUMN IF NOT EXISTS time_to_completion REAL,
  ADD COLUMN IF NOT EXISTS sensory_condition TEXT;

-- Add index for XGBoost-ready queries
CREATE INDEX IF NOT EXISTS idx_assessment_results_xgboost
  ON assessment_results (xgboost_ready, model_source)
  WHERE xgboost_ready = true;

-- Comment for documentation
COMMENT ON COLUMN assessment_results.model_source IS 'Source of labels: rubric_based or xgboost';
COMMENT ON COLUMN assessment_results.xgboost_ready IS 'Whether this row can be used for XGBoost training';
COMMENT ON COLUMN assessment_results.play_skills_label IS 'Rubric label: Strength, Emerging, or Needs Support';
COMMENT ON COLUMN assessment_results.sensory_preference_label IS 'Sensory label: Music Helps, Haptic Helps, etc.';
