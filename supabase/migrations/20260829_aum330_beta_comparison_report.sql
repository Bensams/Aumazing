-- AUM-330 — Beta visibility of guest children's assessment results.
--
-- Extends the consent-gated admin report RPC with the pre/post comparison
-- rows so the SPED validator portal can show a before/after picture per
-- beta tester without any broad admin SELECT on the underlying tables.
--
-- Why an RPC and not admin-read RLS policies: 20260816_family_data_rls.sql
-- establishes that admin access to user data flows exclusively through
-- SECURITY DEFINER RPCs gated on public.is_admin() and a research consent
-- check ("no broad admin SELECT"). This migration follows that policy —
-- it changes only what get_child_report returns, and keeps every gate
-- verbatim: the VOLATILE body (it must keep writing its own AUM-209 audit
-- record before returning data), the is_admin() check, the FOUND-based
-- consent check, and the PUBLIC/anon revokes plus the
-- authenticated/service_role grants.
--
-- The beta portal already reaches guest-backed data: children created on
-- the offline-guest path are re-keyed to a real anonymous Supabase user by
-- the app (LocalDbService.migrateGuestUserId / backfillGuestData) when the
-- guest is upgraded, so their rows carry a genuine uuid owner by the time
-- they sync. Nothing in this migration changes ownership rules.
--
-- The comparisons payload degrades to '[]' when assessment_comparisons
-- does not exist (older database), so the report never breaks.
--
-- Rollback-safe: CREATE OR REPLACE on one function; no schema changes.
-- NOTE: must be applied to the live database by the team (same flow as the
-- AUM-328 star-shop migration); not applied automatically.

DO $mig$
BEGIN
  IF to_regclass('public.audit_logs') IS NULL
     OR to_regclass('public.research_consents') IS NULL
     OR to_regclass('public.validator_reviews') IS NULL THEN
    RAISE NOTICE 'AUM-330: audit/consent tables missing, skipping RPC update';
    RETURN;
  END IF;

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

    -- Consent gate identical to 20260816_family_data_rls.sql: presence of
    -- a qualifying row is what authorizes, never the value of a column.
    -- The version is read alongside it purely for the audit record, so a
    -- NULL consent_version could never be mistaken for "not consented".
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
      -- AUM-330: the pre/post comparison picture. Degrades to an empty
      -- list on databases that predate the assessment_comparisons table.
      'comparisons', CASE
        WHEN to_regclass('public.assessment_comparisons') IS NULL
          THEN '[]'::jsonb
        ELSE COALESCE((
          SELECT jsonb_agg(jsonb_build_object(
            'id', ac.id,
            'compared_at', ac.compared_at,
            'overall_progress_status', ac.overall_progress_status,
            'comparison_summary_json', ac.comparison_summary_json,
            'baseline', (
              SELECT jsonb_build_object(
                'assessment_date', br.assessment_date,
                'overall_band', br.overall_band,
                'progress_status', br.progress_status,
                'communication_level', br.communication_level,
                'social_level', br.social_level,
                'play_level', br.play_level,
                'attention_level', br.attention_level)
              FROM public.assessment_results br
              WHERE br.id = ac.baseline_assessment_result_id
            ),
            'comparison', (
              SELECT jsonb_build_object(
                'assessment_date', cr.assessment_date,
                'overall_band', cr.overall_band,
                'progress_status', cr.progress_status,
                'communication_level', cr.communication_level,
                'social_level', cr.social_level,
                'play_level', cr.play_level,
                'attention_level', cr.attention_level)
              FROM public.assessment_results cr
              WHERE cr.id = ac.comparison_assessment_result_id
            )
          ) ORDER BY ac.compared_at DESC)
          FROM public.assessment_comparisons ac
          WHERE ac.child_id = p_child_id
        ), '[]'::jsonb)
      END,
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
