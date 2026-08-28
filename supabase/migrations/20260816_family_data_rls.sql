-- Migration: Family-scoped database access (AUM-209)
-- Description: Checks in — and hardens — the row level security policy set
--   for the core family-data tables used by offline-first sync.
--
--   Ownership is always derived server side from auth.uid() and the
--   authoritative child/family relationship. A client-supplied child_id,
--   assessment_run_id, session_id or result_id is never trusted: every
--   foreign key that can re-parent a row is verified through an
--   ownership helper in both USING and WITH CHECK.
--
--   Guest model: local `guest_*` identifiers never leave the device, so no
--   policy here requires them to be uploadable as UUIDs. Once a guest signs
--   in anonymously, Supabase issues a real `authenticated` session whose
--   auth.uid() owns the rows it creates — the same policies then apply
--   unchanged, and binding to a permanent account keeps the same uid.
--
--   Admin access to family data stays on the audited SECURITY DEFINER RPC
--   path (public.is_admin() + public.audit_logs); no broad admin SELECT
--   policy is granted on family tables.
--
-- Idempotent: safe to re-run, and safe on an already-populated database.
-- Every block is guarded with to_regclass so the migration also applies to
-- environments where a table has not been created yet.
-- Date: 2026-08-16

-- ══ 1. Ownership helper functions ══════════════════════════════════════
--
-- SECURITY DEFINER so a policy can resolve the child/session/run chain
-- without recursively re-evaluating RLS on the referenced table. Each
-- helper filters on auth.uid() itself, so it can only ever confirm
-- ownership for the calling user. STABLE, fixed search_path, no dynamic
-- SQL, no caller-controlled identifiers.
--
-- All helpers return false (never null) when auth.uid() is null, which is
-- what denies every unauthenticated read and write.

CREATE OR REPLACE FUNCTION public.owns_child(p_child_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.children c
    WHERE c.id = p_child_id
      AND c.parent_user_id = auth.uid()
  );
$$;

CREATE OR REPLACE FUNCTION public.owns_assessment_run(p_run_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.assessment_runs r
    JOIN public.children c ON c.id = r.child_id
    WHERE r.id = p_run_id
      AND c.parent_user_id = auth.uid()
  );
$$;

CREATE OR REPLACE FUNCTION public.owns_game_session(p_session_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.game_sessions gs
    JOIN public.children c ON c.id = gs.child_id
    WHERE gs.id = p_session_id
      AND c.parent_user_id = auth.uid()
  );
$$;

CREATE OR REPLACE FUNCTION public.owns_assessment_result(p_result_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.assessment_results ar
    JOIN public.children c ON c.id = ar.child_id
    WHERE ar.id = p_result_id
      AND c.parent_user_id = auth.uid()
  );
$$;

CREATE OR REPLACE FUNCTION public.owns_module_recommendation(p_recommendation_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.module_recommendations mr
    JOIN public.children c ON c.id = mr.child_id
    WHERE mr.id = p_recommendation_id
      AND c.parent_user_id = auth.uid()
  );
$$;

-- A session_event may point at a round, but only at a round of its own
-- session. This closes the "borrow another family's round id" path without
-- a second ownership lookup.
CREATE OR REPLACE FUNCTION public.round_belongs_to_session(
  p_round_id uuid,
  p_session_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.game_rounds gr
    WHERE gr.id = p_round_id
      AND gr.session_id = p_session_id
  );
$$;

REVOKE EXECUTE ON FUNCTION public.owns_child(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.owns_assessment_run(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.owns_game_session(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.owns_assessment_result(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.owns_module_recommendation(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.round_belongs_to_session(uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.owns_child(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.owns_assessment_run(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.owns_game_session(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.owns_assessment_result(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.owns_module_recommendation(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.round_belongs_to_session(uuid, uuid) TO authenticated, service_role;

-- is_admin() is the single server-side admin gate. Re-assert its hardened
-- shape (fixed search_path, SECURITY DEFINER over admin_users) so this
-- migration is self-contained rather than depending on migration order.
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

REVOKE EXECUTE ON FUNCTION public.is_admin() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_admin() TO authenticated, service_role;

-- ══ 2. children — the root of every ownership path ═════════════════════

DO $$
BEGIN
  IF to_regclass('public.children') IS NULL THEN
    RAISE NOTICE 'AUM-209: public.children missing, skipping';
    RETURN;
  END IF;

  ALTER TABLE public.children ENABLE ROW LEVEL SECURITY;

  DROP POLICY IF EXISTS children_select_own ON public.children;
  DROP POLICY IF EXISTS children_insert_own ON public.children;
  DROP POLICY IF EXISTS children_update_own ON public.children;
  DROP POLICY IF EXISTS children_delete_own ON public.children;

  CREATE POLICY children_select_own ON public.children
    FOR SELECT TO authenticated
    USING (parent_user_id = auth.uid());

  CREATE POLICY children_insert_own ON public.children
    FOR INSERT TO authenticated
    WITH CHECK (parent_user_id = auth.uid());

  CREATE POLICY children_update_own ON public.children
    FOR UPDATE TO authenticated
    USING (parent_user_id = auth.uid())
    WITH CHECK (parent_user_id = auth.uid());

  CREATE POLICY children_delete_own ON public.children
    FOR DELETE TO authenticated
    USING (parent_user_id = auth.uid());
END $$;

-- ══ 3. assessment_runs — direct child ownership ════════════════════════
-- baseline_assessment_run_id and related_recommendation_id are nullable
-- back-references; when set they must also resolve to the caller's family.

DO $$
BEGIN
  IF to_regclass('public.assessment_runs') IS NULL THEN
    RAISE NOTICE 'AUM-209: public.assessment_runs missing, skipping';
    RETURN;
  END IF;

  ALTER TABLE public.assessment_runs ENABLE ROW LEVEL SECURITY;

  DROP POLICY IF EXISTS assessment_runs_select_own ON public.assessment_runs;
  DROP POLICY IF EXISTS assessment_runs_insert_own ON public.assessment_runs;
  DROP POLICY IF EXISTS assessment_runs_update_own ON public.assessment_runs;
  DROP POLICY IF EXISTS assessment_runs_delete_own ON public.assessment_runs;

  CREATE POLICY assessment_runs_select_own ON public.assessment_runs
    FOR SELECT TO authenticated
    USING (public.owns_child(child_id));

  CREATE POLICY assessment_runs_insert_own ON public.assessment_runs
    FOR INSERT TO authenticated
    WITH CHECK (
      public.owns_child(child_id)
      AND (baseline_assessment_run_id IS NULL
           OR public.owns_assessment_run(baseline_assessment_run_id))
      AND (related_recommendation_id IS NULL
           OR public.owns_module_recommendation(related_recommendation_id))
    );

  CREATE POLICY assessment_runs_update_own ON public.assessment_runs
    FOR UPDATE TO authenticated
    USING (public.owns_child(child_id))
    WITH CHECK (
      public.owns_child(child_id)
      AND (baseline_assessment_run_id IS NULL
           OR public.owns_assessment_run(baseline_assessment_run_id))
      AND (related_recommendation_id IS NULL
           OR public.owns_module_recommendation(related_recommendation_id))
    );

  CREATE POLICY assessment_runs_delete_own ON public.assessment_runs
    FOR DELETE TO authenticated
    USING (public.owns_child(child_id));
END $$;

-- ══ 4. game_sessions — direct child ownership + optional run ═══════════

DO $$
BEGIN
  IF to_regclass('public.game_sessions') IS NULL THEN
    RAISE NOTICE 'AUM-209: public.game_sessions missing, skipping';
    RETURN;
  END IF;

  ALTER TABLE public.game_sessions ENABLE ROW LEVEL SECURITY;

  DROP POLICY IF EXISTS game_sessions_select_own ON public.game_sessions;
  DROP POLICY IF EXISTS game_sessions_insert_own ON public.game_sessions;
  DROP POLICY IF EXISTS game_sessions_update_own ON public.game_sessions;
  DROP POLICY IF EXISTS game_sessions_delete_own ON public.game_sessions;

  CREATE POLICY game_sessions_select_own ON public.game_sessions
    FOR SELECT TO authenticated
    USING (public.owns_child(child_id));

  CREATE POLICY game_sessions_insert_own ON public.game_sessions
    FOR INSERT TO authenticated
    WITH CHECK (
      public.owns_child(child_id)
      AND (assessment_run_id IS NULL
           OR public.owns_assessment_run(assessment_run_id))
    );

  CREATE POLICY game_sessions_update_own ON public.game_sessions
    FOR UPDATE TO authenticated
    USING (public.owns_child(child_id))
    WITH CHECK (
      public.owns_child(child_id)
      AND (assessment_run_id IS NULL
           OR public.owns_assessment_run(assessment_run_id))
    );

  CREATE POLICY game_sessions_delete_own ON public.game_sessions
    FOR DELETE TO authenticated
    USING (public.owns_child(child_id));
END $$;

-- ══ 5. game_rounds — transitive through the session ════════════════════

DO $$
BEGIN
  IF to_regclass('public.game_rounds') IS NULL THEN
    RAISE NOTICE 'AUM-209: public.game_rounds missing, skipping';
    RETURN;
  END IF;

  ALTER TABLE public.game_rounds ENABLE ROW LEVEL SECURITY;

  DROP POLICY IF EXISTS game_rounds_select_own ON public.game_rounds;
  DROP POLICY IF EXISTS game_rounds_insert_own ON public.game_rounds;
  DROP POLICY IF EXISTS game_rounds_update_own ON public.game_rounds;
  DROP POLICY IF EXISTS game_rounds_delete_own ON public.game_rounds;

  CREATE POLICY game_rounds_select_own ON public.game_rounds
    FOR SELECT TO authenticated
    USING (public.owns_game_session(session_id));

  CREATE POLICY game_rounds_insert_own ON public.game_rounds
    FOR INSERT TO authenticated
    WITH CHECK (public.owns_game_session(session_id));

  CREATE POLICY game_rounds_update_own ON public.game_rounds
    FOR UPDATE TO authenticated
    USING (public.owns_game_session(session_id))
    WITH CHECK (public.owns_game_session(session_id));

  CREATE POLICY game_rounds_delete_own ON public.game_rounds
    FOR DELETE TO authenticated
    USING (public.owns_game_session(session_id));
END $$;

-- ══ 6. session_events — transitive through session, round must match ═══

DO $$
BEGIN
  IF to_regclass('public.session_events') IS NULL THEN
    RAISE NOTICE 'AUM-209: public.session_events missing, skipping';
    RETURN;
  END IF;

  ALTER TABLE public.session_events ENABLE ROW LEVEL SECURITY;

  DROP POLICY IF EXISTS session_events_select_own ON public.session_events;
  DROP POLICY IF EXISTS session_events_insert_own ON public.session_events;
  DROP POLICY IF EXISTS session_events_update_own ON public.session_events;
  DROP POLICY IF EXISTS session_events_delete_own ON public.session_events;

  CREATE POLICY session_events_select_own ON public.session_events
    FOR SELECT TO authenticated
    USING (public.owns_game_session(session_id));

  CREATE POLICY session_events_insert_own ON public.session_events
    FOR INSERT TO authenticated
    WITH CHECK (
      public.owns_game_session(session_id)
      AND (round_id IS NULL
           OR public.round_belongs_to_session(round_id, session_id))
    );

  CREATE POLICY session_events_update_own ON public.session_events
    FOR UPDATE TO authenticated
    USING (public.owns_game_session(session_id))
    WITH CHECK (
      public.owns_game_session(session_id)
      AND (round_id IS NULL
           OR public.round_belongs_to_session(round_id, session_id))
    );

  CREATE POLICY session_events_delete_own ON public.session_events
    FOR DELETE TO authenticated
    USING (public.owns_game_session(session_id));
END $$;

-- ══ 7. caregiver_questionnaires — child + run must both be the caller's ═

DO $$
BEGIN
  IF to_regclass('public.caregiver_questionnaires') IS NULL THEN
    RAISE NOTICE 'AUM-209: public.caregiver_questionnaires missing, skipping';
    RETURN;
  END IF;

  ALTER TABLE public.caregiver_questionnaires ENABLE ROW LEVEL SECURITY;

  DROP POLICY IF EXISTS caregiver_questionnaires_select_own
    ON public.caregiver_questionnaires;
  DROP POLICY IF EXISTS caregiver_questionnaires_insert_own
    ON public.caregiver_questionnaires;
  DROP POLICY IF EXISTS caregiver_questionnaires_update_own
    ON public.caregiver_questionnaires;
  DROP POLICY IF EXISTS caregiver_questionnaires_delete_own
    ON public.caregiver_questionnaires;

  CREATE POLICY caregiver_questionnaires_select_own
    ON public.caregiver_questionnaires
    FOR SELECT TO authenticated
    USING (public.owns_child(child_id));

  CREATE POLICY caregiver_questionnaires_insert_own
    ON public.caregiver_questionnaires
    FOR INSERT TO authenticated
    WITH CHECK (
      public.owns_child(child_id)
      AND public.owns_assessment_run(assessment_run_id)
      AND (completed_by_user_id IS NULL
           OR completed_by_user_id = auth.uid())
    );

  CREATE POLICY caregiver_questionnaires_update_own
    ON public.caregiver_questionnaires
    FOR UPDATE TO authenticated
    USING (public.owns_child(child_id))
    WITH CHECK (
      public.owns_child(child_id)
      AND public.owns_assessment_run(assessment_run_id)
      AND (completed_by_user_id IS NULL
           OR completed_by_user_id = auth.uid())
    );

  CREATE POLICY caregiver_questionnaires_delete_own
    ON public.caregiver_questionnaires
    FOR DELETE TO authenticated
    USING (public.owns_child(child_id));
END $$;

-- ══ 8. assessment_results — child + run + optional baseline result ═════

DO $$
BEGIN
  IF to_regclass('public.assessment_results') IS NULL THEN
    RAISE NOTICE 'AUM-209: public.assessment_results missing, skipping';
    RETURN;
  END IF;

  ALTER TABLE public.assessment_results ENABLE ROW LEVEL SECURITY;

  DROP POLICY IF EXISTS assessment_results_select_own ON public.assessment_results;
  DROP POLICY IF EXISTS assessment_results_insert_own ON public.assessment_results;
  DROP POLICY IF EXISTS assessment_results_update_own ON public.assessment_results;
  DROP POLICY IF EXISTS assessment_results_delete_own ON public.assessment_results;

  CREATE POLICY assessment_results_select_own ON public.assessment_results
    FOR SELECT TO authenticated
    USING (public.owns_child(child_id));

  CREATE POLICY assessment_results_insert_own ON public.assessment_results
    FOR INSERT TO authenticated
    WITH CHECK (
      public.owns_child(child_id)
      AND public.owns_assessment_run(assessment_run_id)
      AND (baseline_result_id IS NULL
           OR public.owns_assessment_result(baseline_result_id))
    );

  CREATE POLICY assessment_results_update_own ON public.assessment_results
    FOR UPDATE TO authenticated
    USING (public.owns_child(child_id))
    WITH CHECK (
      public.owns_child(child_id)
      AND public.owns_assessment_run(assessment_run_id)
      AND (baseline_result_id IS NULL
           OR public.owns_assessment_result(baseline_result_id))
    );

  CREATE POLICY assessment_results_delete_own ON public.assessment_results
    FOR DELETE TO authenticated
    USING (public.owns_child(child_id));
END $$;

-- ══ 9. module_recommendations — child + optional source result ═════════

DO $$
BEGIN
  IF to_regclass('public.module_recommendations') IS NULL THEN
    RAISE NOTICE 'AUM-209: public.module_recommendations missing, skipping';
    RETURN;
  END IF;

  ALTER TABLE public.module_recommendations ENABLE ROW LEVEL SECURITY;

  DROP POLICY IF EXISTS module_recommendations_select_own
    ON public.module_recommendations;
  DROP POLICY IF EXISTS module_recommendations_insert_own
    ON public.module_recommendations;
  DROP POLICY IF EXISTS module_recommendations_update_own
    ON public.module_recommendations;
  DROP POLICY IF EXISTS module_recommendations_delete_own
    ON public.module_recommendations;

  CREATE POLICY module_recommendations_select_own
    ON public.module_recommendations
    FOR SELECT TO authenticated
    USING (public.owns_child(child_id));

  CREATE POLICY module_recommendations_insert_own
    ON public.module_recommendations
    FOR INSERT TO authenticated
    WITH CHECK (
      public.owns_child(child_id)
      AND (source_assessment_id IS NULL
           OR public.owns_assessment_result(source_assessment_id))
    );

  CREATE POLICY module_recommendations_update_own
    ON public.module_recommendations
    FOR UPDATE TO authenticated
    USING (public.owns_child(child_id))
    WITH CHECK (
      public.owns_child(child_id)
      AND (source_assessment_id IS NULL
           OR public.owns_assessment_result(source_assessment_id))
    );

  CREATE POLICY module_recommendations_delete_own
    ON public.module_recommendations
    FOR DELETE TO authenticated
    USING (public.owns_child(child_id));
END $$;

-- ══ 10. assessment_comparisons — child + both compared results ═════════

DO $$
BEGIN
  IF to_regclass('public.assessment_comparisons') IS NULL THEN
    RAISE NOTICE 'AUM-209: public.assessment_comparisons missing, skipping';
    RETURN;
  END IF;

  ALTER TABLE public.assessment_comparisons ENABLE ROW LEVEL SECURITY;

  DROP POLICY IF EXISTS assessment_comparisons_select_own
    ON public.assessment_comparisons;
  DROP POLICY IF EXISTS assessment_comparisons_insert_own
    ON public.assessment_comparisons;
  DROP POLICY IF EXISTS assessment_comparisons_update_own
    ON public.assessment_comparisons;
  DROP POLICY IF EXISTS assessment_comparisons_delete_own
    ON public.assessment_comparisons;

  CREATE POLICY assessment_comparisons_select_own
    ON public.assessment_comparisons
    FOR SELECT TO authenticated
    USING (public.owns_child(child_id));

  CREATE POLICY assessment_comparisons_insert_own
    ON public.assessment_comparisons
    FOR INSERT TO authenticated
    WITH CHECK (
      public.owns_child(child_id)
      AND public.owns_assessment_result(baseline_assessment_result_id)
      AND public.owns_assessment_result(comparison_assessment_result_id)
    );

  CREATE POLICY assessment_comparisons_update_own
    ON public.assessment_comparisons
    FOR UPDATE TO authenticated
    USING (public.owns_child(child_id))
    WITH CHECK (
      public.owns_child(child_id)
      AND public.owns_assessment_result(baseline_assessment_result_id)
      AND public.owns_assessment_result(comparison_assessment_result_id)
    );

  CREATE POLICY assessment_comparisons_delete_own
    ON public.assessment_comparisons
    FOR DELETE TO authenticated
    USING (public.owns_child(child_id));
END $$;

-- ══ 11. sensory_profiles — narrow the legacy catch-all policy ══════════
--
-- The shipped policy was FOR ALL TO public (which includes the anon role)
-- with no WITH CHECK of its own and no verification of assessment_run_id.
-- Replace it with the same per-command, authenticated-only shape as the
-- rest of the family tables.

DO $$
BEGIN
  IF to_regclass('public.sensory_profiles') IS NULL THEN
    RAISE NOTICE 'AUM-209: public.sensory_profiles missing, skipping';
    RETURN;
  END IF;

  ALTER TABLE public.sensory_profiles ENABLE ROW LEVEL SECURITY;

  DROP POLICY IF EXISTS "Parents can only access their own children's sensory profiles"
    ON public.sensory_profiles;
  DROP POLICY IF EXISTS sensory_profiles_select_own ON public.sensory_profiles;
  DROP POLICY IF EXISTS sensory_profiles_insert_own ON public.sensory_profiles;
  DROP POLICY IF EXISTS sensory_profiles_update_own ON public.sensory_profiles;
  DROP POLICY IF EXISTS sensory_profiles_delete_own ON public.sensory_profiles;

  CREATE POLICY sensory_profiles_select_own ON public.sensory_profiles
    FOR SELECT TO authenticated
    USING (public.owns_child(child_id));

  CREATE POLICY sensory_profiles_insert_own ON public.sensory_profiles
    FOR INSERT TO authenticated
    WITH CHECK (
      public.owns_child(child_id)
      AND public.owns_assessment_run(assessment_run_id)
    );

  CREATE POLICY sensory_profiles_update_own ON public.sensory_profiles
    FOR UPDATE TO authenticated
    USING (public.owns_child(child_id))
    WITH CHECK (
      public.owns_child(child_id)
      AND public.owns_assessment_run(assessment_run_id)
    );

  CREATE POLICY sensory_profiles_delete_own ON public.sensory_profiles
    FOR DELETE TO authenticated
    USING (public.owns_child(child_id));

  CREATE INDEX IF NOT EXISTS idx_sensory_profiles_child_id
    ON public.sensory_profiles (child_id);
  CREATE INDEX IF NOT EXISTS idx_sensory_profiles_assessment_run_id
    ON public.sensory_profiles (assessment_run_id);

  -- sensory_profiles is the only family table whose foreign keys were
  -- created without ON DELETE CASCADE. Every sibling table cascades from
  -- children (and children cascades from auth.users), so a single
  -- sensory_profiles row is enough to make a parent's own "delete this
  -- child" fail, and to abort the auth.users cascade that account deletion
  -- depends on. Align both keys with the rest of the family tree.
  --
  -- This deletes no data: it only changes what happens to a dependent row
  -- when its parent child/run is deleted, which today is "refuse".
  ALTER TABLE public.sensory_profiles
    DROP CONSTRAINT IF EXISTS sensory_profiles_child_id_fkey;
  ALTER TABLE public.sensory_profiles
    ADD CONSTRAINT sensory_profiles_child_id_fkey
    FOREIGN KEY (child_id) REFERENCES public.children(id) ON DELETE CASCADE;

  ALTER TABLE public.sensory_profiles
    DROP CONSTRAINT IF EXISTS sensory_profiles_assessment_run_id_fkey;
  ALTER TABLE public.sensory_profiles
    ADD CONSTRAINT sensory_profiles_assessment_run_id_fkey
    FOREIGN KEY (assessment_run_id) REFERENCES public.assessment_runs(id)
    ON DELETE CASCADE;
END $$;

-- ══ 12. research_consents — consent must name the caller's own child ═══
--
-- The shipped policy checked only user_id, so a parent could file a consent
-- row against another family's child_id. Keep the same policy name and the
-- same admin read path; add the child ownership check.

DO $$
BEGIN
  IF to_regclass('public.research_consents') IS NULL THEN
    RAISE NOTICE 'AUM-209: public.research_consents missing, skipping';
    RETURN;
  END IF;

  ALTER TABLE public.research_consents ENABLE ROW LEVEL SECURITY;

  DROP POLICY IF EXISTS "Parents manage their own research consents"
    ON public.research_consents;

  CREATE POLICY "Parents manage their own research consents"
    ON public.research_consents FOR ALL TO authenticated
    USING (user_id = auth.uid() AND public.owns_child(child_id))
    WITH CHECK (user_id = auth.uid() AND public.owns_child(child_id));

  CREATE INDEX IF NOT EXISTS idx_research_consents_user_id
    ON public.research_consents (user_id);
END $$;

-- ══ 13. admin_users — remove the self-referencing policy ═══════════════
--
-- The shipped policy sub-selected admin_users from inside admin_users' own
-- policy. public.is_admin() is SECURITY DEFINER and does the same check
-- without re-entering RLS.

DO $$
BEGIN
  IF to_regclass('public.admin_users') IS NULL THEN
    RAISE NOTICE 'AUM-209: public.admin_users missing, skipping';
    RETURN;
  END IF;

  ALTER TABLE public.admin_users ENABLE ROW LEVEL SECURITY;

  DROP POLICY IF EXISTS "Admins can read admin_users" ON public.admin_users;

  CREATE POLICY "Admins can read admin_users"
    ON public.admin_users FOR SELECT TO authenticated
    USING (user_id = auth.uid() OR public.is_admin());
END $$;

-- ══ 14. Audited admin access to a child's family data ══════════════════
--
-- get_child_report is the only path by which an administrator reads another
-- family's records. It stays a SECURITY DEFINER RPC gated on is_admin() and
-- on research consent; this migration adds the audit record required by
-- AUM-209. The audit row stores the action, the child id and the consent
-- version only — never the report payload.

DO $mig$
BEGIN
  IF to_regclass('public.audit_logs') IS NULL
     OR to_regclass('public.research_consents') IS NULL
     OR to_regclass('public.validator_reviews') IS NULL THEN
    RAISE NOTICE 'AUM-209: audit/consent tables missing, skipping RPC audit';
    RETURN;
  END IF;

  -- Same authorization gate, same consent gate, same payload as
  -- 20260704_beta_research.sql; now VOLATILE so it can write its own
  -- audit trail, and it records the access before returning any data.
  CREATE OR REPLACE FUNCTION public.get_child_report(p_child_id uuid)
  RETURNS jsonb
  LANGUAGE plpgsql
  VOLATILE
  SECURITY DEFINER
  SET search_path TO 'public'
  AS $fn$
  DECLARE
    v_consent_version text;
  BEGIN
    IF NOT public.is_admin() THEN
      RAISE EXCEPTION 'not authorized';
    END IF;

    -- Consent gate identical to 20260704_beta_research.sql: presence of a
    -- qualifying row is what authorizes, never the value of a column. The
    -- version is read alongside it purely for the audit record, so a NULL
    -- consent_version could never be mistaken for "not consented".
    SELECT rc.consent_version INTO v_consent_version
    FROM public.research_consents rc
    WHERE rc.child_id = p_child_id
      AND rc.research_participation = true
      AND rc.withdrawn_at IS NULL
    LIMIT 1;

    -- FOUND, not the column value: authorization depends on the existence
    -- of a qualifying consent row, so a NULL consent_version can never be
    -- mistaken for "not consented" (nor a missing row for "consented").
    IF NOT FOUND THEN
      RAISE EXCEPTION 'child is not research-consented';
    END IF;

    -- Audit the access itself. Metadata only: who, what, which child and
    -- under which consent version. The report payload is never stored.
    INSERT INTO public.audit_logs
      (actor_id, action, table_name, record_id, new_data)
    VALUES (
      auth.uid(),
      'ADMIN_CHILD_REPORT_READ',
      'children',
      p_child_id::text,
      jsonb_build_object('consent_version', v_consent_version)
    );

    RETURN jsonb_build_object(
      'child', (
        SELECT jsonb_build_object(
          'id', c.id, 'display_name', c.display_name,
          'birth_date', c.birth_date, 'sex', c.sex)
        FROM public.children c WHERE c.id = p_child_id
      ),
      'sessions', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'game_id', gs.game_id,
          'context', gs.context,
          'started_at', gs.started_at,
          'score', gs.score,
          'total_items', gs.total_items,
          'accuracy', gs.accuracy,
          'task_completion_rate', gs.task_completion_rate,
          'error_count', gs.error_count,
          'avg_response_time', gs.avg_response_time,
          'hint_count', gs.hint_count,
          'prompt_count', gs.prompt_count,
          'prompt_dependency_score', gs.prompt_dependency_score,
          'idle_time_seconds', gs.idle_time_seconds,
          'random_touch_count', gs.random_touch_count,
          'retry_count', gs.retry_count,
          'turn_taking_success_rate', gs.turn_taking_success_rate,
          'interruption_count', gs.interruption_count
        ) ORDER BY gs.started_at)
        FROM public.game_sessions gs
        WHERE gs.child_id = p_child_id
          AND gs.context IN ('pre_assessment','post_assessment')
      ), '[]'::jsonb),
      'results', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'assessment_date', ar.assessment_date,
          'created_at', ar.created_at,
          'communication_level', ar.communication_level,
          'communication_confidence', ar.communication_confidence,
          'social_level', ar.social_level,
          'social_confidence', ar.social_confidence,
          'play_level', ar.play_level,
          'play_confidence', ar.play_confidence,
          'attention_level', ar.attention_level,
          'attention_confidence', ar.attention_confidence,
          'overall_band', ar.overall_band,
          'progress_status', ar.progress_status
        ) ORDER BY ar.created_at DESC)
        FROM public.assessment_results ar
        WHERE ar.child_id = p_child_id
      ), '[]'::jsonb),
      'recommendations', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'top_module', mr.top_module,
          'recommended_path_json', mr.recommended_path_json,
          'confidence', mr.confidence,
          'created_at', mr.created_at
        ) ORDER BY mr.created_at DESC)
        FROM public.module_recommendations mr
        WHERE mr.child_id = p_child_id
      ), '[]'::jsonb),
      'reviews', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'area', vr.area,
          'agrees', vr.agrees,
          'comment', vr.comment,
          'created_at', vr.created_at
        ) ORDER BY vr.created_at DESC)
        FROM public.validator_reviews vr
        WHERE vr.child_id = p_child_id
      ), '[]'::jsonb)
    );
  END;
  $fn$;

  REVOKE EXECUTE ON FUNCTION public.get_child_report(uuid) FROM PUBLIC, anon;
  GRANT EXECUTE ON FUNCTION public.get_child_report(uuid)
    TO authenticated, service_role;
END $mig$;
