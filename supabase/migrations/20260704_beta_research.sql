-- Migration: Beta research — parental consent + SPED validator review
-- Description: Ethical foundation for the beta test (RA 10173-aligned):
--   1) research_consents — parent-recorded, versioned consent per child,
--      with a separate AI-training opt-in. Written by the parent's app;
--      readable by admins.
--   2) validator_reviews — SPED validator agree/disagree sign-off per
--      developmental area, recorded from the admin portal.
--   3) get_beta_children / get_child_report RPCs — admin access to child
--      results is possible ONLY for research-consented children (data
--      minimization: report exposes gameplay indicators, rubric levels,
--      and recommendations; not the parent's email).
-- Date: 2026-07-04

-- ── 1. Parental research consent ────────────────────────────────────────
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

ALTER TABLE public.research_consents ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Parents manage their own research consents"
  ON public.research_consents FOR ALL TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "Admins can read research consents"
  ON public.research_consents FOR SELECT TO authenticated
  USING (public.is_admin());

-- ── 2. SPED validator reviews ───────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.validator_reviews (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  child_id uuid NOT NULL REFERENCES public.children(id) ON DELETE CASCADE,
  assessment_run_id uuid,
  area text NOT NULL,          -- communication|social|play|attention|recommendation
  agrees boolean NOT NULL,
  comment text,
  reviewer_id uuid,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE public.validator_reviews ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admins can insert validator reviews"
  ON public.validator_reviews FOR INSERT TO authenticated
  WITH CHECK (public.is_admin());

CREATE POLICY "Admins can read validator reviews"
  ON public.validator_reviews FOR SELECT TO authenticated
  USING (public.is_admin());

-- ── 3. Beta report RPCs (consented children only) ───────────────────────

CREATE OR REPLACE FUNCTION public.get_beta_children()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER STABLE
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'not authorized';
  END IF;
  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'child_id', c.id,
      'display_name', c.display_name,
      'birth_date', c.birth_date,
      'ai_training_opt_in', rc.ai_training_opt_in,
      'consent_version', rc.consent_version,
      'consented_at', rc.created_at,
      'session_count',
        (SELECT count(*) FROM public.game_sessions gs
         WHERE gs.child_id = c.id
           AND gs.context IN ('pre_assessment','post_assessment')),
      'result_count',
        (SELECT count(*) FROM public.assessment_results ar
         WHERE ar.child_id = c.id),
      'review_count',
        (SELECT count(*) FROM public.validator_reviews vr
         WHERE vr.child_id = c.id)
    ) ORDER BY rc.created_at DESC)
    FROM public.research_consents rc
    JOIN public.children c ON c.id = rc.child_id
    WHERE rc.research_participation = true
      AND rc.withdrawn_at IS NULL
  ), '[]'::jsonb);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_beta_children() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_beta_children() FROM anon;

CREATE OR REPLACE FUNCTION public.get_child_report(p_child_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER STABLE
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'not authorized';
  END IF;
  -- Hard gate: no consent (or withdrawn) means no report, full stop.
  IF NOT EXISTS (
    SELECT 1 FROM public.research_consents
    WHERE child_id = p_child_id
      AND research_participation = true
      AND withdrawn_at IS NULL
  ) THEN
    RAISE EXCEPTION 'child is not research-consented';
  END IF;

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
$$;

REVOKE EXECUTE ON FUNCTION public.get_child_report(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_child_report(uuid) FROM anon;
