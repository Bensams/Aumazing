-- AUM-349: keep Premium's 30-day period when the webhook moves to
-- apply_payment_outcome.
--
-- The webhook deployed until now (pre-AUM-168) gave each Premium payment 30
-- days: it set entitlements.expires_at, extending a period that was still
-- running, and ended the period on a refund. 20260821_apply_payment_outcome
-- deliberately left expires_at alone, so deploying the AUM-168 webhook as it
-- was would have made a new purchase last forever and left a returning
-- parent's expired period expired even after paying (has_active_premium
-- reads expires_at). This keeps the live behaviour inside the same locked
-- transaction:
--
--   grant   expires_at = max(now, running period end) + 30 days
--   revoke  expires_at = now
--
-- Profile-slot effects (20260928_profile_slot_payments) are unchanged and
-- never touch the Premium period.

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
  v_period constant interval := interval '30 days';
BEGIN
  -- Defence in depth: service_role only (see the grants below).
  v_request_role := NULLIF(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role';
  IF v_request_role IS NOT NULL AND v_request_role <> 'service_role' THEN
    RAISE EXCEPTION 'apply_payment_outcome is service_role only';
  END IF;

  IF p_payment_id IS NULL OR p_user_id IS NULL THEN
    RETURN jsonb_build_object(
      'applied', false, 'reason', 'invalid_arguments',
      'payment_status', NULL, 'entitlement_effect', 'none');
  END IF;

  IF p_effect IS NULL OR p_effect NOT IN
     ('none', 'grant', 'revoke', 'grant_slot', 'revoke_slot') THEN
    RAISE EXCEPTION 'unknown entitlement effect: %', p_effect;
  END IF;

  IF p_new_status IS NOT NULL AND p_new_status NOT IN
     ('pending', 'paid', 'failed', 'cancelled', 'expired', 'refunded') THEN
    RAISE EXCEPTION 'unknown payment status: %', p_new_status;
  END IF;

  -- The serialisation point: a second delivery for the same purchase waits
  -- here and then reads the status the first one wrote.
  SELECT * INTO v_payment
  FROM public.payment_records
  WHERE id = p_payment_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'applied', false, 'reason', 'payment_not_found',
      'payment_status', NULL, 'entitlement_effect', 'none');
  END IF;

  IF v_payment.user_id <> p_user_id THEN
    RETURN jsonb_build_object(
      'applied', false, 'reason', 'owner_mismatch',
      'payment_status', v_payment.status, 'entitlement_effect', 'none');
  END IF;

  -- The effect must be one this payment's product can have.
  IF (p_effect IN ('grant', 'revoke') AND v_payment.product <> 'premium')
     OR (p_effect IN ('grant_slot', 'revoke_slot')
         AND v_payment.product <> 'profile_slot') THEN
    RETURN jsonb_build_object(
      'applied', false, 'reason', 'effect_product_mismatch',
      'payment_status', v_payment.status, 'entitlement_effect', 'none');
  END IF;

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

  -- Same transaction as the status write above.
  IF p_effect = 'grant' THEN
    -- Paying while a period is still running extends it; paying after it
    -- ended starts a fresh 30 days from now.
    INSERT INTO public.entitlements
      (user_id, is_premium, source, activated_at, expires_at, updated_at)
    VALUES (p_user_id, true, p_source, v_at, v_at + v_period, v_at)
    ON CONFLICT (user_id) DO UPDATE
    SET is_premium = true,
        source = EXCLUDED.source,
        activated_at = EXCLUDED.activated_at,
        expires_at = GREATEST(
          v_at,
          CASE
            WHEN public.entitlements.is_premium
                 AND public.entitlements.expires_at IS NOT NULL
            THEN public.entitlements.expires_at
            ELSE v_at
          END
        ) + v_period,
        updated_at = EXCLUDED.updated_at;
  ELSIF p_effect = 'revoke' THEN
    INSERT INTO public.entitlements
      (user_id, is_premium, source, expires_at, updated_at)
    VALUES (p_user_id, false, p_source, v_at, v_at)
    ON CONFLICT (user_id) DO UPDATE
    SET is_premium = false,
        source = EXCLUDED.source,
        expires_at = EXCLUDED.expires_at,
        updated_at = EXCLUDED.updated_at;
  ELSIF p_effect = 'grant_slot' THEN
    -- Leaves Premium and its period alone: a slot is not a Premium grant.
    INSERT INTO public.entitlements
      (user_id, is_premium, source, extra_profile_slots, updated_at)
    VALUES (p_user_id, false, p_source, 1, v_at)
    ON CONFLICT (user_id) DO UPDATE
    SET extra_profile_slots = public.entitlements.extra_profile_slots + 1,
        updated_at = EXCLUDED.updated_at;
  ELSIF p_effect = 'revoke_slot' THEN
    -- Children already on the account stay (AUM-343 grandfathering).
    UPDATE public.entitlements
    SET extra_profile_slots = GREATEST(extra_profile_slots - 1, 0),
        updated_at = v_at
    WHERE user_id = p_user_id;
  END IF;

  RETURN jsonb_build_object(
    'applied', true, 'reason', 'applied',
    'payment_status', v_status, 'entitlement_effect', p_effect);
END;
$$;

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
  'AUM-168/AUM-349: applies a payment_records transition and its effect '
  'atomically under a row lock — Premium grant (30 days, extending a running '
  'period) or revoke, or one extra child-profile slot. Returns {applied, '
  'reason, payment_status, entitlement_effect}; applied=false means a '
  'concurrent, stale or mismatched decision was correctly refused. '
  'service_role only.';
