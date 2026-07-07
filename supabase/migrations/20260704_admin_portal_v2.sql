-- Migration: Admin portal v2 — account management, rubric thresholds,
--            date-range analytics
-- Description: Implements the remaining Section B admin FRs:
--   1) Parent account management: search/filter listing and
--      suspend/reactivate via security-definer RPCs with audit logging.
--   2) Editable rubric scoring thresholds (singleton config row) that the
--      mobile app reads at startup, replacing hardcoded cutoffs.
--   3) get_admin_stats() gains an optional date range: period-scoped
--      activity counts alongside current-state totals.
-- Date: 2026-07-04

-- ── 1. Rubric thresholds (admin-editable scoring config) ────────────────
-- Defaults mirror the constants previously hardcoded in the app's
-- RubricScoringService so behaviour is unchanged until an admin edits.
CREATE TABLE IF NOT EXISTS public.rubric_thresholds (
  id integer PRIMARY KEY DEFAULT 1 CHECK (id = 1),  -- singleton row
  strength_accuracy real NOT NULL DEFAULT 0.80,
  emerging_accuracy real NOT NULL DEFAULT 0.50,
  strength_completion real NOT NULL DEFAULT 0.80,
  emerging_completion real NOT NULL DEFAULT 0.50,
  strength_max_prompt_dependency real NOT NULL DEFAULT 0.20,
  strength_turn_taking real NOT NULL DEFAULT 0.80,
  emerging_turn_taking real NOT NULL DEFAULT 0.50,
  sustained_max_idle_seconds real NOT NULL DEFAULT 5.0,
  variable_max_idle_seconds real NOT NULL DEFAULT 15.0,
  updated_at timestamptz DEFAULT now(),
  -- Strength cutoffs must sit above their Emerging counterparts.
  CHECK (strength_accuracy > emerging_accuracy),
  CHECK (strength_completion > emerging_completion),
  CHECK (strength_turn_taking > emerging_turn_taking),
  CHECK (variable_max_idle_seconds > sustained_max_idle_seconds)
);

INSERT INTO public.rubric_thresholds (id) VALUES (1)
ON CONFLICT (id) DO NOTHING;

ALTER TABLE public.rubric_thresholds ENABLE ROW LEVEL SECURITY;

-- The mobile app scores with these, so every signed-in user may read.
CREATE POLICY "Authenticated users can read rubric thresholds"
  ON public.rubric_thresholds FOR SELECT TO authenticated
  USING (true);

CREATE POLICY "Admins can update rubric thresholds"
  ON public.rubric_thresholds FOR UPDATE TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());

DROP TRIGGER IF EXISTS audit_rubric_thresholds ON public.rubric_thresholds;
CREATE TRIGGER audit_rubric_thresholds
  AFTER UPDATE ON public.rubric_thresholds
  FOR EACH ROW EXECUTE FUNCTION public.log_admin_change();

-- ── 2. Parent account management ────────────────────────────────────────

-- Search/filter listing of parent accounts (admin-only). Reads auth.users
-- via SECURITY DEFINER; returns the newest 200 matches.
CREATE OR REPLACE FUNCTION public.get_admin_users(
  p_search text DEFAULT NULL,
  p_filter text DEFAULT 'all'   -- all | active | suspended | guests
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER STABLE
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'not authorized';
  END IF;

  RETURN COALESCE((
    SELECT jsonb_agg(row ORDER BY (row->>'created_at') DESC)
    FROM (
      SELECT jsonb_build_object(
        'id', u.id,
        'email', u.email,
        'is_anonymous', u.is_anonymous,
        'created_at', u.created_at,
        'last_sign_in_at', u.last_sign_in_at,
        'suspended', (u.banned_until IS NOT NULL AND u.banned_until > now()),
        'is_admin', EXISTS (
          SELECT 1 FROM public.admin_users a WHERE a.user_id = u.id),
        'is_premium', COALESCE(
          (SELECT e.is_premium FROM public.entitlements e
           WHERE e.user_id = u.id), false),
        'children_count',
          (SELECT count(*) FROM public.children c
           WHERE c.parent_user_id = u.id)
      ) AS row
      FROM auth.users u
      WHERE (p_search IS NULL OR p_search = ''
             OR u.email ILIKE '%' || p_search || '%')
        AND (
          p_filter = 'all'
          OR (p_filter = 'suspended'
              AND u.banned_until IS NOT NULL AND u.banned_until > now())
          OR (p_filter = 'active'
              AND (u.banned_until IS NULL OR u.banned_until <= now()))
          OR (p_filter = 'guests' AND u.is_anonymous)
        )
      ORDER BY u.created_at DESC
      LIMIT 200
    ) sub
  ), '[]'::jsonb);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_admin_users(text, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_admin_users(text, text) FROM anon;

-- Suspend (ban) or reactivate a parent account. Banned users cannot sign
-- in or refresh tokens (an existing access token lapses within the hour).
-- Admin accounts cannot be suspended. Every action is audit-logged.
CREATE OR REPLACE FUNCTION public.set_user_suspension(
  p_user_id uuid,
  p_suspend boolean
)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'not authorized';
  END IF;
  IF EXISTS (SELECT 1 FROM public.admin_users WHERE user_id = p_user_id) THEN
    RAISE EXCEPTION 'cannot suspend an administrator account';
  END IF;

  UPDATE auth.users
  SET banned_until = CASE WHEN p_suspend THEN 'infinity'::timestamptz END
  WHERE id = p_user_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'user not found';
  END IF;

  INSERT INTO public.audit_logs
    (actor_id, action, table_name, record_id, new_data)
  VALUES (
    auth.uid(),
    CASE WHEN p_suspend THEN 'SUSPEND' ELSE 'REACTIVATE' END,
    'auth.users',
    p_user_id::text,
    jsonb_build_object('suspended', p_suspend)
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.set_user_suspension(uuid, boolean)
  FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.set_user_suspension(uuid, boolean)
  FROM anon;

-- ── 3. Date-range analytics ──────────────────────────────────────────────
-- Replace the zero-arg version (defaults would make the overloads
-- ambiguous for PostgREST).
DROP FUNCTION IF EXISTS public.get_admin_stats();

CREATE OR REPLACE FUNCTION public.get_admin_stats(
  p_from timestamptz DEFAULT NULL,
  p_to timestamptz DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER STABLE
SET search_path = public
AS $$
DECLARE
  v_from timestamptz := COALESCE(p_from, '-infinity'::timestamptz);
  v_to timestamptz := COALESCE(p_to, 'infinity'::timestamptz);
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'not authorized';
  END IF;
  RETURN jsonb_build_object(
    -- Activity within the selected period
    'new_users',
      (SELECT count(*) FROM auth.users
       WHERE created_at BETWEEN v_from AND v_to),
    'new_children',
      (SELECT count(*) FROM public.children
       WHERE created_at BETWEEN v_from AND v_to),
    'assessment_results',
      (SELECT count(*) FROM public.assessment_results
       WHERE created_at BETWEEN v_from AND v_to),
    'game_sessions',
      (SELECT count(*) FROM public.game_sessions
       WHERE created_at BETWEEN v_from AND v_to),
    -- Current state (not date-scoped)
    'users', (SELECT count(*) FROM auth.users),
    'children', (SELECT count(*) FROM public.children),
    'therapy_centers',
      (SELECT count(*) FROM public.therapy_centers WHERE active = true),
    'active_modules',
      (SELECT count(*) FROM public.learning_modules WHERE active = true),
    'premium_users',
      (SELECT count(*) FROM public.entitlements WHERE is_premium = true)
  );
END;
$$;
