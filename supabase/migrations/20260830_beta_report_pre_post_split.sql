-- Beta report: tell pre from post, and free practice from path practice.
--
-- Three gaps the SPED validator portal hit once assessments finally started
-- reaching the cloud (AUM-330 fixed the upload; this fixes what the report
-- can say about it):
--
--   * `recommendations` carried no way to tell which assessment produced
--     them, so a child with both a pre and a post recommendation showed one
--     undifferentiated list and the portal could only render the newest.
--   * `results` had the same problem -- "Rubric Outcome (latest assessment)"
--     could not say WHICH assessment it was the outcome of.
--   * `sessions` was filtered to pre/post only, so the gameplay the child
--     did on their recommended module path, and in free practice, was
--     invisible. The rubric is scored from assessment play, but a validator
--     judging whether the recommendation suited the child needs to see what
--     the child actually did with it afterwards.
--
-- `module_recommendations` has no assessment-type column of its own. It does
-- not need one: `source_assessment_id` points at the `assessment_results`
-- row, which is keyed on its run, and the run knows its type. The join is
-- authoritative and costs no schema change.
--
-- Practice volume is capped at the most recent 200 non-assessment sessions
-- per child. Assessment sessions are never capped -- there are at most a
-- handful per run and every one of them feeds the rubric.
--
-- Every access gate from 20260829_aum330_beta_comparison_report.sql is kept
-- verbatim: VOLATILE body (it writes its own AUM-209 audit record before
-- returning), is_admin(), the FOUND-based consent check, and the
-- PUBLIC/anon revokes plus authenticated/service_role grants.
--
-- Rollback-safe: CREATE OR REPLACE on one function; no schema changes.
-- NOTE: must be applied to the live database by the team; not automatic.

DO $mig$
BEGIN
  IF to_regclass('public.audit_logs') IS NULL
     OR to_regclass('public.research_consents') IS NULL
     OR to_regclass('public.validator_reviews') IS NULL THEN
    RAISE NOTICE 'beta report: audit/consent tables missing, skipping';
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
      -- Every context now, not just pre/post. `bucket` is what the portal
      -- groups the gameplay table by; it is derived from the session's own
      -- context rather than guessed at from the game or the date.
      'sessions', COALESCE((
        SELECT jsonb_agg(grouped.s ORDER BY grouped.s->>'started_at')
        FROM (
          SELECT jsonb_build_object(
            'game_id', gs.game_id,
            'context', gs.context,
            'bucket', COALESCE(gs.context, gs.session_type, 'practice'),
            'assessment_run_id', gs.assessment_run_id,
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
          ) AS s
          FROM public.game_sessions gs
          WHERE gs.child_id = p_child_id
            AND gs.context IN ('pre_assessment','post_assessment')

          UNION ALL

          -- Non-assessment play, newest 200. A child with months of daily
          -- practice would otherwise return a payload the portal cannot
          -- usefully render, and the recent play is the informative part.
          SELECT recent.s FROM (
            SELECT jsonb_build_object(
              'game_id', gs.game_id,
              'context', gs.context,
              'bucket', COALESCE(gs.context, gs.session_type, 'practice'),
              'assessment_run_id', gs.assessment_run_id,
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
            ) AS s
            FROM public.game_sessions gs
            WHERE gs.child_id = p_child_id
              AND (gs.context IS NULL
                   OR gs.context NOT IN ('pre_assessment','post_assessment'))
            ORDER BY gs.started_at DESC
            LIMIT 200
          ) recent
        ) grouped
      ), '[]'::jsonb),
      -- `assessment_type` comes from the run, so the portal can label the
      -- rubric outcome by which assessment it belongs to instead of "latest".
      'results', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'assessment_run_id', ar.assessment_run_id,
          'assessment_type', run.assessment_type,
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
          'progress_status', ar.progress_status,
          'notes', ar.notes,
          'summary_json', ar.summary_json
        ) ORDER BY ar.created_at DESC)
        FROM public.assessment_results ar
        LEFT JOIN public.assessment_runs run
          ON run.id = ar.assessment_run_id
        WHERE ar.child_id = p_child_id
      ), '[]'::jsonb),
      -- Same join, one table further out: source_assessment_id is the
      -- assessment_results row, which is keyed on its run.
      'recommendations', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'top_module', mr.top_module,
          'recommended_path_json', mr.recommended_path_json,
          'explanation_json', mr.explanation_json,
          'recommended_by', mr.recommended_by,
          'confidence', mr.confidence,
          'source_assessment_id', mr.source_assessment_id,
          'assessment_type', run.assessment_type,
          'assessment_date', src.assessment_date,
          'created_at', mr.created_at
        ) ORDER BY mr.created_at DESC)
        FROM public.module_recommendations mr
        LEFT JOIN public.assessment_results src
          ON src.id = mr.source_assessment_id
        LEFT JOIN public.assessment_runs run
          ON run.id = src.assessment_run_id
        WHERE mr.child_id = p_child_id
      ), '[]'::jsonb),
      -- The pre/post comparison picture. Degrades to an empty list on
      -- databases that predate the assessment_comparisons table.
      'comparisons', CASE
        WHEN to_regclass('public.assessment_comparisons') IS NULL
          THEN '[]'::jsonb
        ELSE COALESCE((
          SELECT jsonb_agg(jsonb_build_object(
            'id', ac.id,
            'compared_at', ac.compared_at,
            'overall_progress_status', ac.overall_progress_status,
            'accuracy_change', ac.accuracy_change,
            'response_time_change', ac.response_time_change,
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
