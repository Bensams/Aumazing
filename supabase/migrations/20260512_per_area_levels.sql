-- ============================================================
-- Migration: Per-Area Ordinal Levels (Path B)
-- Date: 2026-05-12
-- Description: Extends assessment_results with per-area ordinal level
--              predictions for the four developmental skill areas
--              (communication, social, play, attention).
--
--              Backwards compatible: legacy `predicted_profile` and
--              `confidence` columns are NOT dropped. The API writes
--              both representations (dual-response strategy).
-- ============================================================

-- 1. Add four ordinal level columns. Stored as smallint (0/1/2):
--    0 = Needs Support, 1 = Emerging, 2 = Strength.
ALTER TABLE assessment_results ADD COLUMN IF NOT EXISTS communication_level SMALLINT;
ALTER TABLE assessment_results ADD COLUMN IF NOT EXISTS social_level        SMALLINT;
ALTER TABLE assessment_results ADD COLUMN IF NOT EXISTS play_level          SMALLINT;
ALTER TABLE assessment_results ADD COLUMN IF NOT EXISTS attention_level     SMALLINT;

-- 2. Add four per-area confidence columns.
ALTER TABLE assessment_results ADD COLUMN IF NOT EXISTS communication_confidence REAL;
ALTER TABLE assessment_results ADD COLUMN IF NOT EXISTS social_confidence        REAL;
ALTER TABLE assessment_results ADD COLUMN IF NOT EXISTS play_confidence          REAL;
ALTER TABLE assessment_results ADD COLUMN IF NOT EXISTS attention_confidence     REAL;

-- 3. CHECK constraints — added idempotently. Postgres does not support
--    "ADD CONSTRAINT IF NOT EXISTS", so we guard with a pg_constraint lookup.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_communication_level') THEN
    ALTER TABLE assessment_results ADD CONSTRAINT chk_communication_level
      CHECK (communication_level IS NULL OR communication_level BETWEEN 0 AND 2);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_social_level') THEN
    ALTER TABLE assessment_results ADD CONSTRAINT chk_social_level
      CHECK (social_level IS NULL OR social_level BETWEEN 0 AND 2);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_play_level') THEN
    ALTER TABLE assessment_results ADD CONSTRAINT chk_play_level
      CHECK (play_level IS NULL OR play_level BETWEEN 0 AND 2);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_attention_level') THEN
    ALTER TABLE assessment_results ADD CONSTRAINT chk_attention_level
      CHECK (attention_level IS NULL OR attention_level BETWEEN 0 AND 2);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_communication_confidence') THEN
    ALTER TABLE assessment_results ADD CONSTRAINT chk_communication_confidence
      CHECK (communication_confidence IS NULL OR (communication_confidence >= 0 AND communication_confidence <= 1));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_social_confidence') THEN
    ALTER TABLE assessment_results ADD CONSTRAINT chk_social_confidence
      CHECK (social_confidence IS NULL OR (social_confidence >= 0 AND social_confidence <= 1));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_play_confidence') THEN
    ALTER TABLE assessment_results ADD CONSTRAINT chk_play_confidence
      CHECK (play_confidence IS NULL OR (play_confidence >= 0 AND play_confidence <= 1));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_attention_confidence') THEN
    ALTER TABLE assessment_results ADD CONSTRAINT chk_attention_confidence
      CHECK (attention_confidence IS NULL OR (attention_confidence >= 0 AND attention_confidence <= 1));
  END IF;
END $$;

-- 5. Documentation: column comments mapping ordinal values to labels.
COMMENT ON COLUMN assessment_results.communication_level IS
  'Per-area ordinal label for the Communication skill area. 0=Needs Support, 1=Emerging, 2=Strength. Path B per-area ordinal design (May 2026).';
COMMENT ON COLUMN assessment_results.social_level IS
  'Per-area ordinal label for the Social Interaction skill area. 0=Needs Support, 1=Emerging, 2=Strength.';
COMMENT ON COLUMN assessment_results.play_level IS
  'Per-area ordinal label for the Play Skills area. 0=Needs Support, 1=Emerging, 2=Strength.';
COMMENT ON COLUMN assessment_results.attention_level IS
  'Per-area ordinal label for the Attention & Focus area. 0=Needs Support, 1=Emerging, 2=Strength.';

COMMENT ON COLUMN assessment_results.communication_confidence IS
  'Model confidence for the communication_level prediction (0.0-1.0).';
COMMENT ON COLUMN assessment_results.social_confidence IS
  'Model confidence for the social_level prediction (0.0-1.0).';
COMMENT ON COLUMN assessment_results.play_confidence IS
  'Model confidence for the play_level prediction (0.0-1.0).';
COMMENT ON COLUMN assessment_results.attention_confidence IS
  'Model confidence for the attention_level prediction (0.0-1.0).';

-- 6. Indexes to support analytical queries that filter by per-area levels.
CREATE INDEX IF NOT EXISTS idx_assessment_results_communication_level
  ON assessment_results (communication_level)
  WHERE communication_level IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_assessment_results_social_level
  ON assessment_results (social_level)
  WHERE social_level IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_assessment_results_play_level
  ON assessment_results (play_level)
  WHERE play_level IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_assessment_results_attention_level
  ON assessment_results (attention_level)
  WHERE attention_level IS NOT NULL;

-- 7. Composite index for "find all children with co-occurring weaknesses"
--    queries (any two or more areas at Needs Support).
CREATE INDEX IF NOT EXISTS idx_assessment_results_per_area_levels
  ON assessment_results (communication_level, social_level, play_level, attention_level)
  WHERE communication_level IS NOT NULL;
