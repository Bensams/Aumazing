-- AUM-168 payment outcome RPC harness.
-- Run after the PayMongo entitlement migration and
-- 20260821_apply_payment_outcome.sql have been applied, inside a disposable
-- PostgreSQL database. Every assertion is rolled back at the end.

BEGIN;

DO $$
DECLARE
  v_user uuid := gen_random_uuid();
  v_payment uuid := gen_random_uuid();
  v_result jsonb;
  v_status text;
  v_premium boolean;
  v_config text[];
BEGIN
  INSERT INTO auth.users (id, email) VALUES (v_user, 'aum168-harness@example.test');
  INSERT INTO public.payment_records
    (id, user_id, checkout_session_id, amount, currency, status)
  VALUES (v_payment, v_user, 'cs_aum168_harness', 14900, 'PHP', 'pending');

  -- The function is locked to the service role and pins its search path.
  SELECT proconfig INTO v_config
  FROM pg_proc
  WHERE oid = 'public.apply_payment_outcome(uuid,uuid,text,text,text,text,timestamptz)'::regprocedure;
  IF NOT ('search_path=public, pg_temp' = ANY(v_config)) THEN
    RAISE EXCEPTION 'search_path is not hardened: %', v_config;
  END IF;
  IF has_function_privilege('authenticated', 'public.apply_payment_outcome(uuid,uuid,text,text,text,text,timestamptz)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.apply_payment_outcome(uuid,uuid,text,text,text,text,timestamptz)', 'EXECUTE') THEN
    RAISE EXCEPTION 'app roles must not execute SECURITY DEFINER RPC';
  END IF;
  IF NOT has_function_privilege('service_role', 'public.apply_payment_outcome(uuid,uuid,text,text,text,text,timestamptz)', 'EXECUTE') THEN
    RAISE EXCEPTION 'service_role must execute SECURITY DEFINER RPC';
  END IF;

  -- service_role may read the two tables the RPC writes so assertions run
  -- as that role. No INSERT/UPDATE/DELETE — fixture rows stay superuser.
  GRANT SELECT ON public.payment_records TO service_role;
  GRANT SELECT ON public.entitlements TO service_role;

  -- Grant is one atomic transition: both rows change together.
  SET LOCAL ROLE service_role;
  v_result := public.apply_payment_outcome(v_payment, v_user, 'pending', 'paid', 'grant', 'paymongo_test', now());
  IF (v_result->>'applied')::boolean IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'grant did not apply: %', v_result;
  END IF;
  SELECT status INTO v_status FROM public.payment_records WHERE id = v_payment;
  SELECT is_premium INTO v_premium FROM public.entitlements WHERE user_id = v_user;
  IF v_status <> 'paid' OR v_premium IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'grant was not atomic: status %, premium %', v_status, v_premium;
  END IF;

  -- A second delivery with the stale expected status is refused, so a
  -- concurrent winner cannot grant or rewrite the entitlement twice.
  v_result := public.apply_payment_outcome(v_payment, v_user, 'pending', 'paid', 'grant', 'paymongo_test', now());
  IF (v_result->>'applied')::boolean IS DISTINCT FROM false
     OR v_result->>'reason' <> 'status_changed' THEN
    RAISE EXCEPTION 'stale delivery was not refused: %', v_result;
  END IF;

  -- Invalid effects raise and roll back their attempted status write.
  BEGIN
    PERFORM public.apply_payment_outcome(v_payment, v_user, 'paid', 'refunded', 'invalid', 'paymongo_test', now());
    RAISE EXCEPTION 'invalid effect unexpectedly succeeded';
  EXCEPTION WHEN raise_exception THEN
    NULL;
  END;
  SELECT status INTO v_status FROM public.payment_records WHERE id = v_payment;
  IF v_status <> 'paid' THEN
    RAISE EXCEPTION 'failed RPC changed payment status: %', v_status;
  END IF;

  -- A retry after the failed attempt can still settle the original pending
  -- payment; rollback did not leave it falsely marked paid.
  RESET ROLE;
  INSERT INTO public.payment_records
    (id, user_id, checkout_session_id, amount, currency, status)
  VALUES (gen_random_uuid(), v_user, 'cs_aum168_retry', 14900, 'PHP', 'pending')
  RETURNING id INTO v_payment;
  SET LOCAL ROLE service_role;
  v_result := public.apply_payment_outcome(v_payment, v_user, 'pending', 'paid', 'grant', 'paymongo_test', now());
  IF (v_result->>'applied')::boolean IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'retry after rollback did not apply: %', v_result;
  END IF;

  -- Revoke is also atomic and only the owner can be targeted.
  v_result := public.apply_payment_outcome(v_payment, v_user, 'paid', 'refunded', 'revoke', 'paymongo_test', now());
  IF (v_result->>'applied')::boolean IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'revoke did not apply: %', v_result;
  END IF;
  SELECT status INTO v_status FROM public.payment_records WHERE id = v_payment;
  SELECT is_premium INTO v_premium FROM public.entitlements WHERE user_id = v_user;
  IF v_status <> 'refunded' OR v_premium IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'revoke was not atomic: status %, premium %', v_status, v_premium;
  END IF;
END $$;

ROLLBACK;
