-- AUM-349: sell extra child profiles through PayMongo.
--
-- Builds on 20260821_apply_payment_outcome.sql (AUM-168), which must be
-- applied first. A payment now records WHAT was bought, and
-- apply_payment_outcome applies the matching effect in the same locked
-- transaction as the status change:
--
--   product 'premium'       effects 'grant' / 'revoke'           (unchanged)
--   product 'profile_slot'  effects 'grant_slot' / 'revoke_slot' — add or
--                           remove ONE entitlements.extra_profile_slots
--
-- An effect that does not match the stored product is refused, so a Premium
-- payment can never mint a slot and a slot payment can never mint Premium,
-- whatever the webhook decided. Slots are only ever added on the pending→paid
-- transition (the expected-status check under the row lock), so a redelivered
-- or duplicate event cannot add a second slot.

ALTER TABLE public.payment_records
  ADD COLUMN IF NOT EXISTS product text NOT NULL DEFAULT 'premium'
  CHECK (product IN ('premium', 'profile_slot'));

COMMENT ON COLUMN public.payment_records.product IS
  'What the checkout sold: premium (30 days) or profile_slot (one extra child '
  'profile, AUM-349). Written by create-checkout; read by the webhook.';

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
  ELSIF p_effect = 'grant_slot' THEN
    -- Leaves is_premium and source alone: a slot is not a Premium grant.
    INSERT INTO public.entitlements
      (user_id, is_premium, source, extra_profile_slots, updated_at)
    VALUES (p_user_id, false, p_source, 1, v_at)
    ON CONFLICT (user_id) DO UPDATE
    SET extra_profile_slots = public.entitlements.extra_profile_slots + 1,
        updated_at = EXCLUDED.updated_at;
  ELSIF p_effect = 'revoke_slot' THEN
    -- Children already on the account stay (AUM-343 grandfathering); the
    -- account simply cannot add another until it has a free slot again.
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
  '(Premium grant/revoke, or one extra child-profile slot) atomically under a '
  'row lock. Returns {applied, reason, payment_status, entitlement_effect}; '
  'applied=false means a concurrent, stale or mismatched decision was '
  'correctly refused. service_role only.';
