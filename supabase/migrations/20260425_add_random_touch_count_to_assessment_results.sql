-- Add random_touch_count column to assessment_results
-- Tracks off-target/random touches (taps on non-interactive areas) per assessment.
ALTER TABLE assessment_results
  ADD COLUMN IF NOT EXISTS random_touch_count INTEGER NOT NULL DEFAULT 0;

-- Comment for documentation
COMMENT ON COLUMN assessment_results.random_touch_count IS 'Number of random/off-target touches (taps on non-interactive areas)';
