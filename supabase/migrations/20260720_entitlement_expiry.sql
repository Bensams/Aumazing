-- Migration: Entitlement expiry — Premium is a time-boxed period, not a
--              lifetime flag. Each payment buys one period; the webhook
--              stamps `expires_at`, clients treat an expired row as Free,
--              and admin metrics only count active periods.
-- Date: 2026-07-20

ALTER TABLE public.entitlements
  ADD COLUMN IF NOT EXISTS expires_at timestamptz;

-- Backfill: pre-expiry grants were open-ended. Give each one a full month
-- from activation so nobody who already paid is cut off retroactively.
UPDATE public.entitlements
SET expires_at = COALESCE(activated_at, updated_at, now()) + interval '1 month'
WHERE is_premium = true AND expires_at IS NULL;

-- Single definition of "active Premium" for server-side consumers.
-- A NULL expires_at on a premium row counts as active (legacy grant not
-- yet backfilled); the app applies the same rule locally.
CREATE OR REPLACE FUNCTION public.has_active_premium(p_user_id uuid)
RETURNS boolean
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = public
AS $$
  SELECT COALESCE((
    SELECT e.is_premium AND (e.expires_at IS NULL OR e.expires_at > now())
    FROM public.entitlements e
    WHERE e.user_id = p_user_id
  ), false);
$$;

REVOKE EXECUTE ON FUNCTION public.has_active_premium(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.has_active_premium(uuid) FROM anon;

-- Admin listing: is_premium now reflects the ACTIVE state, not the raw flag.
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
        'is_premium', public.has_active_premium(u.id),
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

-- Conversion metric: only currently-active subscriptions count.
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
      (SELECT count(*) FROM public.entitlements
       WHERE is_premium = true
         AND (expires_at IS NULL OR expires_at > now()))
  );
END;
$$;
