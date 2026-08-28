-- AUM-209 policy-test bootstrap
--
-- The repository does not check in the `initial_schema` migration that
-- created the core family tables (it exists only in the remote project's
-- migration history). To make the RLS policies executably testable without
-- a Supabase CLI stack, this fixture recreates the pieces the policies
-- depend on:
--
--   * the anon / authenticated / service_role roles,
--   * an `auth` schema shim (auth.users + auth.uid()) that reads the same
--     `request.jwt.claims` setting PostgREST sets in production,
--   * the family tables, with the same column names, nullability and
--     foreign keys as the live project (verified against the live schema).
--
-- It is a TEST FIXTURE ONLY. It is never applied to a real database and it
-- deliberately mirrors, rather than replaces, the production schema. Column
-- sets are trimmed to what the policies and tests exercise; every column a
-- policy references is present with its production nullability.

-- ── Roles ──────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    CREATE ROLE anon NOLOGIN NOINHERIT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    CREATE ROLE authenticated NOLOGIN NOINHERIT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
    CREATE ROLE service_role NOLOGIN NOINHERIT BYPASSRLS;
  END IF;
END $$;

-- ── auth schema shim ───────────────────────────────────────────────────
CREATE SCHEMA IF NOT EXISTS auth;

CREATE TABLE IF NOT EXISTS auth.users (
  id uuid PRIMARY KEY,
  email text,
  is_anonymous boolean NOT NULL DEFAULT false,
  banned_until timestamptz,
  last_sign_in_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Identical body to the production auth.uid().
CREATE OR REPLACE FUNCTION auth.uid()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE(
    NULLIF(current_setting('request.jwt.claim.sub', true), ''),
    (NULLIF(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  )::uuid;
$$;

GRANT USAGE ON SCHEMA auth TO anon, authenticated, service_role;
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;

-- ── Family tables ──────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.children (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  parent_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name text NOT NULL,
  birth_date date NOT NULL,
  sex text,
  diagnosis_status text NOT NULL DEFAULT 'unknown',
  notes text,
  avatar text NOT NULL DEFAULT 'bear',
  music_enabled boolean NOT NULL DEFAULT true,
  vibration_enabled boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.module_recommendations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  child_id uuid NOT NULL REFERENCES public.children(id) ON DELETE CASCADE,
  source_assessment_id uuid,
  recommended_by text NOT NULL DEFAULT 'rubric',
  recommended_path_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  top_module text,
  confidence double precision,
  explanation_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  input_snapshot_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  accepted_by_parent boolean,
  status text NOT NULL DEFAULT 'pending',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.assessment_runs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  child_id uuid NOT NULL REFERENCES public.children(id) ON DELETE CASCADE,
  assessment_type text NOT NULL DEFAULT 'pre',
  baseline_assessment_run_id uuid REFERENCES public.assessment_runs(id)
    ON DELETE SET NULL,
  related_recommendation_id uuid REFERENCES public.module_recommendations(id)
    ON DELETE SET NULL,
  assessor_type text NOT NULL DEFAULT 'parent',
  started_at timestamptz NOT NULL DEFAULT now(),
  ended_at timestamptz,
  completed boolean NOT NULL DEFAULT false,
  version text NOT NULL DEFAULT 'v1',
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.game_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  child_id uuid NOT NULL REFERENCES public.children(id) ON DELETE CASCADE,
  assessment_run_id uuid REFERENCES public.assessment_runs(id)
    ON DELETE SET NULL,
  game_id text NOT NULL DEFAULT 'test_game',
  session_type text NOT NULL DEFAULT 'practice',
  context text,
  started_at timestamptz NOT NULL DEFAULT now(),
  ended_at timestamptz,
  completed boolean NOT NULL DEFAULT false,
  retry_count integer NOT NULL DEFAULT 0,
  hint_count integer NOT NULL DEFAULT 0,
  prompt_count integer NOT NULL DEFAULT 0,
  random_touch_count integer NOT NULL DEFAULT 0,
  off_task_action_count integer NOT NULL DEFAULT 0,
  early_exit boolean NOT NULL DEFAULT false,
  score integer,
  total_items integer,
  accuracy double precision,
  task_completion_rate double precision,
  error_count integer,
  avg_response_time double precision,
  prompt_dependency_score double precision,
  idle_time_seconds double precision,
  turn_taking_success_rate double precision,
  interruption_count integer,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.game_rounds (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id uuid NOT NULL REFERENCES public.game_sessions(id)
    ON DELETE CASCADE,
  round_no integer NOT NULL,
  correct boolean,
  retry_count integer NOT NULL DEFAULT 0,
  hint_count integer NOT NULL DEFAULT 0,
  prompt_count integer NOT NULL DEFAULT 0,
  random_touch_count integer NOT NULL DEFAULT 0,
  strong_prompt_triggered boolean NOT NULL DEFAULT false,
  guided_assist_triggered boolean NOT NULL DEFAULT false,
  completed boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (session_id, round_no)
);

CREATE TABLE IF NOT EXISTS public.session_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id uuid NOT NULL REFERENCES public.game_sessions(id)
    ON DELETE CASCADE,
  round_id uuid REFERENCES public.game_rounds(id) ON DELETE SET NULL,
  event_type text NOT NULL DEFAULT 'tap',
  event_time timestamptz NOT NULL DEFAULT now(),
  event_value_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.assessment_results (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  assessment_run_id uuid NOT NULL REFERENCES public.assessment_runs(id)
    ON DELETE CASCADE,
  child_id uuid NOT NULL REFERENCES public.children(id) ON DELETE CASCADE,
  assessment_date date NOT NULL DEFAULT current_date,
  baseline_result_id uuid REFERENCES public.assessment_results(id)
    ON DELETE SET NULL,
  overall_band text,
  progress_status text,
  communication_level smallint,
  social_level smallint,
  play_level smallint,
  attention_level smallint,
  communication_confidence real,
  social_confidence real,
  play_confidence real,
  attention_confidence real,
  screening_flag boolean NOT NULL DEFAULT false,
  requires_followup boolean NOT NULL DEFAULT false,
  summary_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  change_summary_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (assessment_run_id)
);

ALTER TABLE public.module_recommendations
  DROP CONSTRAINT IF EXISTS module_recommendations_source_assessment_id_fkey;
ALTER TABLE public.module_recommendations
  ADD CONSTRAINT module_recommendations_source_assessment_id_fkey
  FOREIGN KEY (source_assessment_id)
  REFERENCES public.assessment_results(id) ON DELETE SET NULL;

CREATE TABLE IF NOT EXISTS public.caregiver_questionnaires (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  child_id uuid NOT NULL REFERENCES public.children(id) ON DELETE CASCADE,
  assessment_run_id uuid NOT NULL REFERENCES public.assessment_runs(id)
    ON DELETE CASCADE,
  completed_by_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  completed_by_role text NOT NULL DEFAULT 'parent',
  questionnaire_type text NOT NULL DEFAULT 'baseline',
  responses_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.assessment_comparisons (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  child_id uuid NOT NULL REFERENCES public.children(id) ON DELETE CASCADE,
  baseline_assessment_result_id uuid NOT NULL
    REFERENCES public.assessment_results(id) ON DELETE CASCADE,
  comparison_assessment_result_id uuid NOT NULL
    REFERENCES public.assessment_results(id) ON DELETE CASCADE,
  compared_at timestamptz NOT NULL DEFAULT now(),
  overall_progress_status text,
  comparison_summary_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (baseline_assessment_result_id, comparison_assessment_result_id)
);

CREATE TABLE IF NOT EXISTS public.sensory_profiles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  child_id uuid NOT NULL REFERENCES public.children(id),
  assessment_run_id uuid NOT NULL REFERENCES public.assessment_runs(id),
  preferred_music boolean,
  preferred_haptic boolean,
  optimal_combo text,
  notes text,
  created_at timestamptz DEFAULT now()
);

-- ── Admin / audit / consent ────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.admin_users (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  note text,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.audit_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_id uuid,
  action text NOT NULL,
  table_name text NOT NULL,
  record_id text,
  old_data jsonb,
  new_data jsonb,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.research_consents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  child_id uuid NOT NULL UNIQUE REFERENCES public.children(id)
    ON DELETE CASCADE,
  consent_version text NOT NULL,
  research_participation boolean NOT NULL DEFAULT false,
  ai_training_opt_in boolean NOT NULL DEFAULT false,
  withdrawn_at timestamptz,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.validator_reviews (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  child_id uuid NOT NULL REFERENCES public.children(id) ON DELETE CASCADE,
  assessment_run_id uuid,
  area text NOT NULL,
  agrees boolean NOT NULL,
  comment text,
  reviewer_id uuid,
  created_at timestamptz DEFAULT now()
);

-- Catalog table, used to prove ordinary catalog reads still work.
CREATE TABLE IF NOT EXISTS public.learning_modules (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title text NOT NULL,
  active boolean NOT NULL DEFAULT true
);

ALTER TABLE public.learning_modules ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS learning_modules_select_authenticated
  ON public.learning_modules;
CREATE POLICY learning_modules_select_authenticated
  ON public.learning_modules FOR SELECT TO authenticated
  USING (active = true);

-- ── Baseline privileges (PostgREST grants these; RLS then filters) ─────
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public
  TO anon, authenticated;

-- is_admin() is asserted by the migration under test, but the beta_research
-- policies that reference it are created here, so define it first.
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.admin_users WHERE user_id = auth.uid()
  );
$$;

-- Pre-AUM-209 policies, reproduced so the migration's DROP/CREATE pattern
-- is exercised against the state it will actually meet in production.
ALTER TABLE public.research_consents ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Parents manage their own research consents"
  ON public.research_consents;
CREATE POLICY "Parents manage their own research consents"
  ON public.research_consents FOR ALL TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "Admins can read research consents"
  ON public.research_consents;
CREATE POLICY "Admins can read research consents"
  ON public.research_consents FOR SELECT TO authenticated
  USING (public.is_admin());

ALTER TABLE public.validator_reviews ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Admins can read validator reviews"
  ON public.validator_reviews;
CREATE POLICY "Admins can read validator reviews"
  ON public.validator_reviews FOR SELECT TO authenticated
  USING (public.is_admin());

ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Admins can read audit_logs" ON public.audit_logs;
CREATE POLICY "Admins can read audit_logs"
  ON public.audit_logs FOR SELECT TO authenticated
  USING (public.is_admin());

ALTER TABLE public.admin_users ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Admins can read admin_users" ON public.admin_users;
CREATE POLICY "Admins can read admin_users"
  ON public.admin_users FOR SELECT TO authenticated
  USING ((user_id = auth.uid()) OR (EXISTS (
    SELECT 1 FROM public.admin_users a WHERE a.user_id = auth.uid()
  )));

-- The pre-AUM-209 sensory_profiles policy: FOR ALL, role public, no
-- WITH CHECK, no assessment-run verification. The migration replaces it.
ALTER TABLE public.sensory_profiles ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Parents can only access their own children's sensory profiles"
  ON public.sensory_profiles;
CREATE POLICY "Parents can only access their own children's sensory profiles"
  ON public.sensory_profiles FOR ALL
  USING (child_id IN (
    SELECT children.id FROM public.children
    WHERE children.parent_user_id = auth.uid()
  ));

-- get_child_report as shipped by 20260704_beta_research.sql (STABLE, no
-- audit record). The migration under test replaces it.
CREATE OR REPLACE FUNCTION public.get_child_report(p_child_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'not authorized';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.research_consents
    WHERE child_id = p_child_id
      AND research_participation = true
      AND withdrawn_at IS NULL
  ) THEN
    RAISE EXCEPTION 'child is not research-consented';
  END IF;
  RETURN jsonb_build_object('child', (
    SELECT jsonb_build_object('id', c.id, 'display_name', c.display_name)
    FROM public.children c WHERE c.id = p_child_id));
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_child_report(uuid) TO authenticated;
