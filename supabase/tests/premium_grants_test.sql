-- AUM-357 free month and administrator Premium grants.
-- Run by supabase/tests/run_premium_grants_tests.sh after the bootstrap
-- fixture, premium_grants_fixture.sql and the migration. Every assertion
-- is rolled back at the end.

BEGIN;

DO $$
DECLARE
  v_admin uuid := gen_random_uuid();
  v_parent uuid := gen_random_uuid();
  v_guest uuid := gen_random_uuid();
  v_paid uuid := gen_random_uuid();
  v_row public.entitlements%ROWTYPE;
  v_result jsonb;
  v_until timestamptz;
  v_failed boolean;
  v_audits int;
BEGIN
  -- Every new account starts with 30 days, guests included.
  INSERT INTO auth.users (id, email) VALUES (v_admin, 'admin@example.test');
  INSERT INTO auth.users (id, email) VALUES (v_parent, 'parent@example.test');
  INSERT INTO auth.users (id, email, is_anonymous) VALUES (v_guest, NULL, true);
  INSERT INTO auth.users (id, email) VALUES (v_paid, 'paid@example.test');
  INSERT INTO public.admin_users (user_id) VALUES (v_admin);

  SELECT * INTO v_row FROM public.entitlements WHERE user_id = v_guest;
  IF NOT v_row.is_premium OR v_row.source <> 'free_month'
     OR v_row.expires_at < now() + interval '29 days 23 hours'
     OR v_row.expires_at > now() + interval '30 days 1 minute' THEN
    RAISE EXCEPTION 'guest did not get a free month: %', row_to_json(v_row);
  END IF;
  IF NOT public.has_active_premium(v_parent) THEN
    RAISE EXCEPTION 'parent did not get a free month';
  END IF;

  -- The trigger function is not callable by app roles.
  IF has_function_privilege('authenticated', 'public.grant_new_account_free_month()', 'EXECUTE')
     OR has_function_privilege('anon', 'public.grant_new_account_free_month()', 'EXECUTE') THEN
    RAISE EXCEPTION 'app roles must not execute the free-month trigger function';
  END IF;
  IF has_function_privilege('anon', 'public.admin_grant_premium(uuid,integer,text)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.admin_revoke_premium(uuid,text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'anon must not execute the grant functions';
  END IF;

  -- A non-admin cannot grant.
  PERFORM set_config('request.jwt.claim.sub', v_parent::text, true);
  v_failed := false;
  BEGIN
    PERFORM public.admin_grant_premium(v_parent, 30, 'self-grant');
  EXCEPTION WHEN OTHERS THEN
    v_failed := SQLERRM = 'not authorized';
  END;
  IF NOT v_failed THEN RAISE EXCEPTION 'non-admin grant was not refused'; END IF;

  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);

  -- Guests are refused.
  v_failed := false;
  BEGIN
    PERFORM public.admin_grant_premium(v_guest, 30, 'study family');
  EXCEPTION WHEN OTHERS THEN
    v_failed := SQLERRM LIKE 'guest accounts must be linked%';
  END;
  IF NOT v_failed THEN RAISE EXCEPTION 'guest grant was not refused'; END IF;

  -- A reason and a sensible number of days are required.
  v_failed := false;
  BEGIN
    PERFORM public.admin_grant_premium(v_parent, 30, '   ');
  EXCEPTION WHEN OTHERS THEN v_failed := true;
  END;
  IF NOT v_failed THEN RAISE EXCEPTION 'blank reason was accepted'; END IF;
  v_failed := false;
  BEGIN
    PERFORM public.admin_grant_premium(v_parent, 0, 'study family');
  EXCEPTION WHEN OTHERS THEN v_failed := true;
  END;
  IF NOT v_failed THEN RAISE EXCEPTION 'zero days was accepted'; END IF;

  -- A grant during the free month adds on top of the days left.
  SELECT expires_at INTO v_until FROM public.entitlements WHERE user_id = v_parent;
  v_result := public.admin_grant_premium(v_parent, 30, 'study family');
  SELECT * INTO v_row FROM public.entitlements WHERE user_id = v_parent;
  IF v_row.source <> 'admin_grant' OR v_row.expires_at <> v_until + interval '30 days'
     OR (v_result->>'expires_at')::timestamptz <> v_row.expires_at THEN
    RAISE EXCEPTION 'grant did not extend the running period: % %', v_result, row_to_json(v_row);
  END IF;
  SELECT count(*) INTO v_audits FROM public.audit_logs
  WHERE action = 'PREMIUM_GRANT' AND record_id = v_parent::text
    AND actor_id = v_admin AND new_data->>'reason' = 'study family';
  IF v_audits <> 1 THEN RAISE EXCEPTION 'grant was not audited'; END IF;

  -- A grant after Premium ended starts fresh from now.
  UPDATE public.entitlements SET expires_at = now() - interval '5 days' WHERE user_id = v_paid;
  PERFORM public.admin_grant_premium(v_paid, 10, 'goodwill');
  SELECT * INTO v_row FROM public.entitlements WHERE user_id = v_paid;
  IF v_row.expires_at < now() + interval '9 days 23 hours'
     OR v_row.expires_at > now() + interval '10 days 1 minute' THEN
    RAISE EXCEPTION 'grant after expiry did not start from now: %', v_row.expires_at;
  END IF;

  -- Given Premium can be ended; paid Premium cannot.
  PERFORM public.admin_revoke_premium(v_parent, 'granted by mistake');
  IF public.has_active_premium(v_parent) THEN
    RAISE EXCEPTION 'revoke did not end Premium';
  END IF;
  SELECT count(*) INTO v_audits FROM public.audit_logs
  WHERE action = 'PREMIUM_REVOKE' AND record_id = v_parent::text;
  IF v_audits <> 1 THEN RAISE EXCEPTION 'revoke was not audited'; END IF;

  UPDATE public.entitlements
  SET source = 'paymongo', expires_at = now() + interval '20 days', is_premium = true
  WHERE user_id = v_paid;
  v_failed := false;
  BEGIN
    PERFORM public.admin_revoke_premium(v_paid, 'should not work');
  EXCEPTION WHEN OTHERS THEN
    v_failed := SQLERRM LIKE 'paid Premium is ended by refunding%';
  END;
  IF NOT v_failed THEN RAISE EXCEPTION 'paid Premium was revoked'; END IF;

  -- The Users page sees the end date and the source.
  v_result := public.get_admin_users(NULL, 'all');
  IF NOT EXISTS (
    SELECT 1 FROM jsonb_array_elements(v_result) u
    WHERE u->>'id' = v_paid::text
      AND u->>'premium_source' = 'paymongo'
      AND (u->>'premium_until') IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'get_admin_users is missing premium_until/premium_source';
  END IF;

  RAISE NOTICE 'premium grant tests passed';
END;
$$;

ROLLBACK;
