-- AUM-357: a free month of Premium for every new account, and Premium that
-- administrators can grant or end for bound accounts.
--
-- Free month
--   Each account gets 30 days of Premium once, when its auth.users row is
--   created: a guest when the app first reaches the server, a parent who
--   signs up directly when they register. Linking a guest keeps the same
--   user id, so the days left carry over. Paying during the month adds 30
--   days on top (apply_payment_outcome already extends a running period).
--   The grant never blocks sign-up: any failure is logged and skipped.
--
-- Administrator grants
--   admin_grant_premium adds days the same way a payment does and is
--   refused for guest accounts. A guest has no recoverable identity, so
--   Premium given to one is lost with the device; the parent links first.
--   admin_revoke_premium ends Premium that was given, never paid Premium,
--   which is ended by refunding through PayMongo. Both write audit_logs.

-- ── Free month for new accounts ──────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.grant_new_account_free_month()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  BEGIN
    INSERT INTO public.entitlements
      (user_id, is_premium, source, activated_at, expires_at, updated_at)
    VALUES
      (NEW.id, true, 'free_month', now(), now() + interval '30 days', now())
    ON CONFLICT (user_id) DO NOTHING;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'free month not granted to %: %', NEW.id, SQLERRM;
  END;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.grant_new_account_free_month() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS on_auth_user_created_free_month ON auth.users;
CREATE TRIGGER on_auth_user_created_free_month
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.grant_new_account_free_month();

-- ── Administrator grants ─────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.admin_grant_premium(
  p_user_id uuid,
  p_days integer,
  p_reason text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user auth.users%ROWTYPE;
  v_before public.entitlements%ROWTYPE;
  v_reason text := btrim(coalesce(p_reason, ''));
  v_until timestamptz;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'not authorized';
  END IF;
  IF p_days IS NULL OR p_days < 1 OR p_days > 366 THEN
    RAISE EXCEPTION 'days must be between 1 and 366';
  END IF;
  IF v_reason = '' OR length(v_reason) > 500 THEN
    RAISE EXCEPTION 'a reason of up to 500 characters is required';
  END IF;

  SELECT * INTO v_user FROM auth.users WHERE id = p_user_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'user not found';
  END IF;
  IF v_user.is_anonymous OR v_user.email IS NULL THEN
    RAISE EXCEPTION 'guest accounts must be linked before Premium can be granted';
  END IF;

  SELECT * INTO v_before FROM public.entitlements
  WHERE user_id = p_user_id FOR UPDATE;

  INSERT INTO public.entitlements
    (user_id, is_premium, source, activated_at, expires_at, updated_at)
  VALUES
    (p_user_id, true, 'admin_grant', now(),
     now() + make_interval(days => p_days), now())
  ON CONFLICT (user_id) DO UPDATE
  SET is_premium = true,
      source = 'admin_grant',
      activated_at = now(),
      expires_at = GREATEST(
        now(),
        CASE
          WHEN public.entitlements.is_premium
               AND public.entitlements.expires_at IS NOT NULL
          THEN public.entitlements.expires_at
          ELSE now()
        END
      ) + make_interval(days => p_days),
      updated_at = now()
  RETURNING expires_at INTO v_until;

  INSERT INTO public.audit_logs
    (actor_id, action, table_name, record_id, old_data, new_data)
  VALUES (
    auth.uid(), 'PREMIUM_GRANT', 'entitlements', p_user_id::text,
    CASE WHEN v_before.user_id IS NULL THEN NULL ELSE jsonb_build_object(
      'is_premium', v_before.is_premium,
      'source', v_before.source,
      'expires_at', v_before.expires_at) END,
    jsonb_build_object('days', p_days, 'reason', v_reason, 'expires_at', v_until)
  );

  RETURN jsonb_build_object('expires_at', v_until);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_revoke_premium(
  p_user_id uuid,
  p_reason text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_before public.entitlements%ROWTYPE;
  v_reason text := btrim(coalesce(p_reason, ''));
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'not authorized';
  END IF;
  IF v_reason = '' OR length(v_reason) > 500 THEN
    RAISE EXCEPTION 'a reason of up to 500 characters is required';
  END IF;

  SELECT * INTO v_before FROM public.entitlements
  WHERE user_id = p_user_id FOR UPDATE;
  IF NOT FOUND OR NOT public.has_active_premium(p_user_id) THEN
    RAISE EXCEPTION 'this account has no active Premium';
  END IF;
  IF v_before.source IS DISTINCT FROM 'admin_grant'
     AND v_before.source IS DISTINCT FROM 'free_month' THEN
    RAISE EXCEPTION 'paid Premium is ended by refunding it through PayMongo';
  END IF;

  UPDATE public.entitlements
  SET is_premium = false,
      source = 'admin_revoke',
      expires_at = now(),
      updated_at = now()
  WHERE user_id = p_user_id;

  INSERT INTO public.audit_logs
    (actor_id, action, table_name, record_id, old_data, new_data)
  VALUES (
    auth.uid(), 'PREMIUM_REVOKE', 'entitlements', p_user_id::text,
    jsonb_build_object(
      'is_premium', v_before.is_premium,
      'source', v_before.source,
      'expires_at', v_before.expires_at),
    jsonb_build_object('reason', v_reason)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_grant_premium(uuid, integer, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_revoke_premium(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_grant_premium(uuid, integer, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_revoke_premium(uuid, text) TO authenticated;

-- ── The Users page shows when Premium ends and where it came from ────────

CREATE OR REPLACE FUNCTION public.get_admin_users(
  p_search text DEFAULT NULL::text,
  p_filter text DEFAULT 'all'::text
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
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
        'premium_until', (
          SELECT e.expires_at FROM public.entitlements e
          WHERE e.user_id = u.id),
        'premium_source', (
          SELECT e.source FROM public.entitlements e
          WHERE e.user_id = u.id),
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
$function$;
