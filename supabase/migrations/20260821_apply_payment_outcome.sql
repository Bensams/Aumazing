-- Migration: atomic payment outcome application (AUM-168)
-- Description: `apply_payment_outcome` commits a payment_records status
--              transition and its entitlement effect inside ONE
--              transaction, under a row lock on the payment.
-- Date: 2026-08-21
--
-- Why this exists
-- ───────────────
-- The webhook previously did two independent statements:
--
--     UPDATE payment_records SET status='paid' WHERE id=? AND status=?
--     UPSERT entitlements ...
--
-- which is wrong in two ways that both cost a parent real money:
--
--   1. Not concurrency-safe. PostgREST does not report the affected-row
--      count unless it is asked to return rows, so two deliveries for the
--      same purchase (PayMongo emits `checkout_session.payment.paid` AND
--      `payment.paid`, with different event ids, so event-id dedupe does
--      not catch it) could both "succeed": the loser updated zero rows,
--      saw no error, and applied the entitlement anyway.
--   2. Not atomic. If the status write committed and the entitlement
--      write then failed, the retry saw `paid` and decided no-op — so a
--      real payment could permanently fail to grant Premium.
--
-- Both are fixed by moving the pair into the database as one statement.
-- `SELECT ... FOR UPDATE` serialises concurrent callers on the payment
-- row; the expected-status re-check inside the lock means the loser
-- observes the winner's committed status and returns `applied = false`
-- instead of writing. Because the two writes share a transaction, there
-- is no interleaving in which the payment settles without its effect.
--
-- Scope note: subscription lifecycle is outside this function. It deliberately
-- does not read or write `entitlements.expires_at`.

-- ── Guard: fail loudly rather than silently mis-target ─────────────────
DO $$
BEGIN
  IF to_regclass('public.payment_records') IS NULL
     OR to_regclass('public.entitlements') IS NULL THEN
    RAISE EXCEPTION
      'apply_payment_outcome requires public.payment_records and '
      'public.entitlements (see 20260703_paymongo_entitlements.sql)';
  END IF;
END $$;

-- Concurrent deliveries for one purchase queue on this lookup, so the
-- session→row resolution the webhook does before calling is cheap.
CREATE INDEX IF NOT EXISTS payment_records_checkout_session_id_idx
  ON public.payment_records (checkout_session_id);

-- ── The function ───────────────────────────────────────────────────────
--
-- Arguments mirror the decision the edge function reached:
--
--   p_payment_id      the payment_records row the decision was about
--   p_user_id         the owner that decision was reasoned about, re-checked
--                     against the locked row so a raced lookup cannot land
--   p_expected_status the status observed when deciding; the transition is
--                     refused if the row has since moved
--   p_new_status      the status to write, or NULL to leave it (used when
--                     only the entitlement half is missing)
--   p_effect          'none' | 'grant' | 'revoke'
--   p_source          entitlement provenance ('paymongo' / 'paymongo_test')
--   p_at              the decision timestamp
--
-- Returns jsonb: { applied, reason, payment_status, entitlement_effect }.
-- `applied = false` is a normal, expected outcome (a concurrent winner or
-- a stale decision) — never an error, and never something the caller may
-- report as a successful grant.
CREATE OR REPLACE FUNCTION public.apply_payment_outcome(
  p_payment_id uuid,
  p_user_id uuid,
  p_expected_status text,
  p_new_status text,
  p_effect text,
  p_source text,
  p_at timestamptz DEFAULT now()
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_payment public.payment_records%ROWTYPE;
  v_at timestamptz := COALESCE(p_at, now());
  v_status text;
  v_request_role text;
BEGIN
  -- Defence in depth. EXECUTE is granted only to service_role below, but
  -- if a PostgREST request ever reaches here under another JWT role,
  -- refuse rather than run as the definer. A direct database connection
  -- (migrations, tests) sets no claims and is allowed through.
  v_request_role := NULLIF(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role';
  IF v_request_role IS NOT NULL AND v_request_role <> 'service_role' THEN
    RAISE EXCEPTION 'apply_payment_outcome is service_role only';
  END IF;

  IF p_payment_id IS NULL OR p_user_id IS NULL THEN
    RETURN jsonb_build_object(
      'applied', false, 'reason', 'invalid_arguments',
      'payment_status', NULL, 'entitlement_effect', 'none');
  END IF;

  IF p_effect IS NULL OR p_effect NOT IN ('none', 'grant', 'revoke') THEN
    RAISE EXCEPTION 'unknown entitlement effect: %', p_effect;
  END IF;

  IF p_new_status IS NOT NULL AND p_new_status NOT IN
     ('pending', 'paid', 'failed', 'cancelled', 'expired', 'refunded') THEN
    RAISE EXCEPTION 'unknown payment status: %', p_new_status;
  END IF;

  -- The serialisation point. A second delivery for the same purchase
  -- blocks here until the first commits, and therefore reads the status
  -- the first one wrote.
  SELECT * INTO v_payment
  FROM public.payment_records
  WHERE id = p_payment_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'applied', false, 'reason', 'payment_not_found',
      'payment_status', NULL, 'entitlement_effect', 'none');
  END IF;

  -- Ownership is re-established against the locked row, not trusted from
  -- the caller: the grant follows the stored binding create-checkout
  -- wrote, never anything an event claimed.
  IF v_payment.user_id <> p_user_id THEN
    RETURN jsonb_build_object(
      'applied', false, 'reason', 'owner_mismatch',
      'payment_status', v_payment.status, 'entitlement_effect', 'none');
  END IF;

  -- The idempotency key: the decision was reasoned about this status, so
  -- it may only be applied to this status. Anything else means another
  -- delivery already settled the purchase.
  IF p_expected_status IS NOT NULL AND v_payment.status IS DISTINCT FROM p_expected_status THEN
    RETURN jsonb_build_object(
      'applied', false, 'reason', 'status_changed',
      'payment_status', v_payment.status, 'entitlement_effect', 'none');
  END IF;

  v_status := v_payment.status;

  IF p_new_status IS NOT NULL AND p_new_status IS DISTINCT FROM v_payment.status THEN
    UPDATE public.payment_records
    SET status = p_new_status, updated_at = v_at
    WHERE id = p_payment_id;
    v_status := p_new_status;
  END IF;

  -- Same transaction as the status write above: either both land or
  -- neither does, so a payment can never read `paid` without its effect.
  IF p_effect = 'grant' THEN
    INSERT INTO public.entitlements
      (user_id, is_premium, source, activated_at, updated_at)
    VALUES (p_user_id, true, p_source, v_at, v_at)
    ON CONFLICT (user_id) DO UPDATE
    SET is_premium = true,
        source = EXCLUDED.source,
        activated_at = EXCLUDED.activated_at,
        updated_at = EXCLUDED.updated_at;
  ELSIF p_effect = 'revoke' THEN
    INSERT INTO public.entitlements
      (user_id, is_premium, source, updated_at)
    VALUES (p_user_id, false, p_source, v_at)
    ON CONFLICT (user_id) DO UPDATE
    SET is_premium = false,
        source = EXCLUDED.source,
        updated_at = EXCLUDED.updated_at;
  END IF;

  RETURN jsonb_build_object(
    'applied', true, 'reason', 'applied',
    'payment_status', v_status, 'entitlement_effect', p_effect);
END;
$$;

-- ── Execution is service_role only ─────────────────────────────────────
-- Anything else could mint Premium: the function is SECURITY DEFINER and
-- writes entitlements, so it must never be reachable from an app JWT.
REVOKE ALL ON FUNCTION public.apply_payment_outcome(
  uuid, uuid, text, text, text, text, timestamptz) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.apply_payment_outcome(
  uuid, uuid, text, text, text, text, timestamptz) FROM anon;
REVOKE ALL ON FUNCTION public.apply_payment_outcome(
  uuid, uuid, text, text, text, text, timestamptz) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.apply_payment_outcome(
  uuid, uuid, text, text, text, text, timestamptz) TO service_role;

COMMENT ON FUNCTION public.apply_payment_outcome(
  uuid, uuid, text, text, text, text, timestamptz) IS
  'AUM-168: applies a payment_records transition and its entitlement '
  'effect atomically under a row lock. Returns {applied, reason, '
  'payment_status, entitlement_effect}; applied=false means a concurrent '
  'or stale decision was correctly refused. service_role only.';
