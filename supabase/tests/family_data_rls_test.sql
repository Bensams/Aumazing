-- AUM-209 — executable policy tests for family-scoped database access.
--
-- These tests PROVE behaviour: every case performs a real SELECT / INSERT /
-- UPDATE / DELETE as a specific role and asserts on the result, rather than
-- inspecting policy text.
--
-- Everything runs inside one transaction and ends in ROLLBACK, and every
-- identifier is a synthetic constant. No real user ids, emails or payloads.
--
-- Run with:
--   supabase/tests/run_rls_tests.sh
-- or, against any Postgres 15+ superuser connection:
--   psql -v ON_ERROR_STOP=1 -f supabase/tests/fixtures/00_bootstrap.sql
--   psql -v ON_ERROR_STOP=1 -f supabase/migrations/20260816_family_data_rls.sql
--   psql -v ON_ERROR_STOP=1 -f supabase/tests/family_data_rls_test.sql

\set ON_ERROR_STOP on

BEGIN;

-- ── Test helpers ───────────────────────────────────────────────────────
CREATE SCHEMA tests;

CREATE FUNCTION tests.assert(p_ok boolean, p_label text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF p_ok IS NOT TRUE THEN
    RAISE EXCEPTION 'FAIL: %', p_label;
  END IF;
  RAISE NOTICE 'ok   %', p_label;
END;
$$;

-- Runs p_sql and asserts it is rejected (RLS violation, FK violation, or
-- any other error). Used for writes that must be refused outright.
CREATE FUNCTION tests.assert_rejected(p_sql text, p_label text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    EXECUTE p_sql;
  EXCEPTION WHEN others THEN
    RAISE NOTICE 'ok   % (rejected: %)', p_label, SQLSTATE;
    RETURN;
  END;
  RAISE EXCEPTION 'FAIL: % — statement was accepted but should not be', p_label;
END;
$$;

-- Runs a write that RLS filters silently (UPDATE/DELETE blocked by USING)
-- and asserts that it touched zero rows.
CREATE FUNCTION tests.assert_no_rows_affected(p_sql text, p_label text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE
  v_count integer;
BEGIN
  EXECUTE p_sql;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'FAIL: % — % row(s) affected, expected 0', p_label, v_count;
  END IF;
  RAISE NOTICE 'ok   % (0 rows affected)', p_label;
END;
$$;

GRANT USAGE ON SCHEMA tests TO anon, authenticated;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA tests TO anon, authenticated;

-- ── Fixture data (created as the owner, RLS bypassed) ──────────────────
-- Parent A, Parent B, an administrator, and a guest who signed in
-- anonymously (is_anonymous = true — a real authenticated uid).
INSERT INTO auth.users (id, email, is_anonymous) VALUES
  ('11111111-1111-1111-1111-111111111111', 'parent-a@example.test', false),
  ('22222222-2222-2222-2222-222222222222', 'parent-b@example.test', false),
  ('33333333-3333-3333-3333-333333333333', 'admin@example.test',    false),
  ('44444444-4444-4444-4444-444444444444', NULL,                    true);

INSERT INTO public.admin_users (user_id, note)
VALUES ('33333333-3333-3333-3333-333333333333', 'test admin');

-- Family A
INSERT INTO public.children (id, parent_user_id, display_name, birth_date)
VALUES ('0a000001-0000-0000-0000-000000000001',
        '11111111-1111-1111-1111-111111111111', 'Child A', '2021-01-01');
INSERT INTO public.assessment_runs (id, child_id)
VALUES ('0a000002-0000-0000-0000-000000000001',
        '0a000001-0000-0000-0000-000000000001');
INSERT INTO public.game_sessions (id, child_id, assessment_run_id, context)
VALUES ('0a000003-0000-0000-0000-000000000001',
        '0a000001-0000-0000-0000-000000000001',
        '0a000002-0000-0000-0000-000000000001', 'pre_assessment');
INSERT INTO public.game_rounds (id, session_id, round_no)
VALUES ('0a000004-0000-0000-0000-000000000001',
        '0a000003-0000-0000-0000-000000000001', 1);
INSERT INTO public.assessment_results (id, assessment_run_id, child_id)
VALUES ('0a000005-0000-0000-0000-000000000001',
        '0a000002-0000-0000-0000-000000000001',
        '0a000001-0000-0000-0000-000000000001');

-- Family B
INSERT INTO public.children (id, parent_user_id, display_name, birth_date)
VALUES ('0b000001-0000-0000-0000-000000000001',
        '22222222-2222-2222-2222-222222222222', 'Child B', '2020-06-01');
INSERT INTO public.assessment_runs (id, child_id)
VALUES ('0b000002-0000-0000-0000-000000000001',
        '0b000001-0000-0000-0000-000000000001');
INSERT INTO public.game_sessions (id, child_id, assessment_run_id)
VALUES ('0b000003-0000-0000-0000-000000000001',
        '0b000001-0000-0000-0000-000000000001',
        '0b000002-0000-0000-0000-000000000001');
INSERT INTO public.game_rounds (id, session_id, round_no)
VALUES ('0b000004-0000-0000-0000-000000000001',
        '0b000003-0000-0000-0000-000000000001', 1);
INSERT INTO public.assessment_results (id, assessment_run_id, child_id)
VALUES ('0b000005-0000-0000-0000-000000000001',
        '0b000002-0000-0000-0000-000000000001',
        '0b000001-0000-0000-0000-000000000001');

-- Catalog row, for the "ordinary catalog reads still work" case.
INSERT INTO public.learning_modules (title, active) VALUES ('Turn Taking', true);
INSERT INTO public.learning_modules (title, active) VALUES ('Retired', false);

-- ══ 1. Parent A can CRUD Child A and its descendants ═══════════════════
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims =
  '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

DO $$
DECLARE v_n integer;
BEGIN
  SELECT count(*) INTO v_n FROM public.children;
  PERFORM tests.assert(v_n = 1, '1.1 Parent A sees exactly their own child');

  SELECT count(*) INTO v_n FROM public.assessment_runs;
  PERFORM tests.assert(v_n = 1, '1.2 Parent A sees only their own runs');

  SELECT count(*) INTO v_n FROM public.game_sessions;
  PERFORM tests.assert(v_n = 1, '1.3 Parent A sees only their own sessions');

  SELECT count(*) INTO v_n FROM public.game_rounds;
  PERFORM tests.assert(v_n = 1, '1.4 Parent A sees only their own rounds');

  SELECT count(*) INTO v_n FROM public.assessment_results;
  PERFORM tests.assert(v_n = 1, '1.5 Parent A sees only their own results');

  -- Writes down the whole ownership chain.
  INSERT INTO public.game_sessions (id, child_id)
  VALUES ('0a000013-0000-0000-0000-000000000001',
          '0a000001-0000-0000-0000-000000000001');
  PERFORM tests.assert(true, '1.6 Parent A can insert a session for Child A');

  INSERT INTO public.game_rounds (session_id, round_no)
  VALUES ('0a000013-0000-0000-0000-000000000001', 1);
  PERFORM tests.assert(true, '1.7 Parent A can insert a round in own session');

  INSERT INTO public.session_events (session_id, round_id, event_type)
  VALUES ('0a000003-0000-0000-0000-000000000001',
          '0a000004-0000-0000-0000-000000000001', 'tap');
  PERFORM tests.assert(true, '1.8 Parent A can insert an event on own round');

  UPDATE public.children SET display_name = 'Child A renamed'
  WHERE id = '0a000001-0000-0000-0000-000000000001';
  GET DIAGNOSTICS v_n = ROW_COUNT;
  PERFORM tests.assert(v_n = 1, '1.9 Parent A can update own child');

  DELETE FROM public.game_rounds
  WHERE session_id = '0a000013-0000-0000-0000-000000000001';
  GET DIAGNOSTICS v_n = ROW_COUNT;
  PERFORM tests.assert(v_n = 1, '1.10 Parent A can delete own round');
END $$;

-- ══ 2. Parent A cannot reach Parent B's records ════════════════════════
DO $$
DECLARE v_n integer;
BEGIN
  SELECT count(*) INTO v_n FROM public.children
  WHERE id = '0b000001-0000-0000-0000-000000000001';
  PERFORM tests.assert(v_n = 0, '2.1 Parent A cannot SELECT Child B');

  SELECT count(*) INTO v_n FROM public.assessment_runs
  WHERE id = '0b000002-0000-0000-0000-000000000001';
  PERFORM tests.assert(v_n = 0, '2.2 Parent A cannot SELECT Family B runs');

  SELECT count(*) INTO v_n FROM public.assessment_results
  WHERE id = '0b000005-0000-0000-0000-000000000001';
  PERFORM tests.assert(v_n = 0, '2.3 Parent A cannot SELECT Family B results');

  PERFORM tests.assert_no_rows_affected(
    $q$UPDATE public.children SET display_name = 'hijacked'
       WHERE id = '0b000001-0000-0000-0000-000000000001'$q$,
    '2.4 Parent A cannot UPDATE Child B');

  PERFORM tests.assert_no_rows_affected(
    $q$DELETE FROM public.children
       WHERE id = '0b000001-0000-0000-0000-000000000001'$q$,
    '2.5 Parent A cannot DELETE Child B');

  PERFORM tests.assert_no_rows_affected(
    $q$UPDATE public.game_sessions SET completed = true
       WHERE id = '0b000003-0000-0000-0000-000000000001'$q$,
    '2.6 Parent A cannot UPDATE Family B session');

  PERFORM tests.assert_rejected(
    $q$INSERT INTO public.children
         (parent_user_id, display_name, birth_date)
       VALUES ('22222222-2222-2222-2222-222222222222', 'Planted', '2021-01-01')$q$,
    '2.7 Parent A cannot INSERT a child owned by Parent B');

  -- Re-parenting own child to Parent B must fail the WITH CHECK.
  PERFORM tests.assert_rejected(
    $q$UPDATE public.children
       SET parent_user_id = '22222222-2222-2222-2222-222222222222'
       WHERE id = '0a000001-0000-0000-0000-000000000001'$q$,
    '2.8 Parent A cannot re-parent own child to Parent B');
END $$;

-- ══ 3. Parent B has symmetric isolation ════════════════════════════════
SET LOCAL request.jwt.claims =
  '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}';

DO $$
DECLARE v_n integer;
BEGIN
  SELECT count(*) INTO v_n FROM public.children;
  PERFORM tests.assert(v_n = 1, '3.1 Parent B sees exactly one child');

  SELECT count(*) INTO v_n FROM public.children
  WHERE id = '0a000001-0000-0000-0000-000000000001';
  PERFORM tests.assert(v_n = 0, '3.2 Parent B cannot SELECT Child A');

  SELECT count(*) INTO v_n FROM public.game_rounds
  WHERE id = '0a000004-0000-0000-0000-000000000001';
  PERFORM tests.assert(v_n = 0, '3.3 Parent B cannot SELECT Family A rounds');

  PERFORM tests.assert_no_rows_affected(
    $q$DELETE FROM public.game_sessions
       WHERE id = '0a000003-0000-0000-0000-000000000001'$q$,
    '3.4 Parent B cannot DELETE Family A session');
END $$;

-- ══ 4. Unauthenticated access is denied ════════════════════════════════
RESET ROLE;
SET LOCAL ROLE anon;
SET LOCAL request.jwt.claims = '{"role":"anon"}';

DO $$
DECLARE v_n integer;
BEGIN
  SELECT count(*) INTO v_n FROM public.children;
  PERFORM tests.assert(v_n = 0, '4.1 anon reads no children');

  SELECT count(*) INTO v_n FROM public.game_sessions;
  PERFORM tests.assert(v_n = 0, '4.2 anon reads no sessions');

  SELECT count(*) INTO v_n FROM public.game_rounds;
  PERFORM tests.assert(v_n = 0, '4.3 anon reads no rounds');

  SELECT count(*) INTO v_n FROM public.assessment_results;
  PERFORM tests.assert(v_n = 0, '4.4 anon reads no assessment results');

  SELECT count(*) INTO v_n FROM public.sensory_profiles;
  PERFORM tests.assert(v_n = 0, '4.5 anon reads no sensory profiles');

  PERFORM tests.assert_rejected(
    $q$INSERT INTO public.children
         (parent_user_id, display_name, birth_date)
       VALUES ('11111111-1111-1111-1111-111111111111', 'anon', '2021-01-01')$q$,
    '4.6 anon cannot INSERT a child');

  PERFORM tests.assert_no_rows_affected(
    $q$UPDATE public.children SET display_name = 'anon'$q$,
    '4.7 anon cannot UPDATE any child');
END $$;

-- ══ 5. Cross-family foreign keys rejected on INSERT and UPDATE ═════════
RESET ROLE;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims =
  '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

DO $$
BEGIN
  -- Own child, but another family's assessment run.
  PERFORM tests.assert_rejected(
    $q$INSERT INTO public.game_sessions (child_id, assessment_run_id)
       VALUES ('0a000001-0000-0000-0000-000000000001',
               '0b000002-0000-0000-0000-000000000001')$q$,
    '5.1 session cannot borrow Family B assessment_run_id');

  PERFORM tests.assert_rejected(
    $q$UPDATE public.game_sessions
       SET assessment_run_id = '0b000002-0000-0000-0000-000000000001'
       WHERE id = '0a000003-0000-0000-0000-000000000001'$q$,
    '5.2 session cannot be updated onto Family B assessment_run_id');

  -- Own child, another family's run, on assessment_results.
  PERFORM tests.assert_rejected(
    $q$INSERT INTO public.assessment_results (assessment_run_id, child_id)
       VALUES ('0b000002-0000-0000-0000-000000000001',
               '0a000001-0000-0000-0000-000000000001')$q$,
    '5.3 result cannot borrow Family B assessment_run_id');

  -- Own child, another family's baseline result.
  PERFORM tests.assert_rejected(
    $q$UPDATE public.assessment_results
       SET baseline_result_id = '0b000005-0000-0000-0000-000000000001'
       WHERE id = '0a000005-0000-0000-0000-000000000001'$q$,
    '5.4 result cannot reference Family B baseline result');

  -- Own child, another family's source assessment.
  PERFORM tests.assert_rejected(
    $q$INSERT INTO public.module_recommendations
         (child_id, source_assessment_id)
       VALUES ('0a000001-0000-0000-0000-000000000001',
               '0b000005-0000-0000-0000-000000000001')$q$,
    '5.5 recommendation cannot borrow Family B source assessment');

  -- Own child, another family's questionnaire run.
  PERFORM tests.assert_rejected(
    $q$INSERT INTO public.caregiver_questionnaires
         (child_id, assessment_run_id)
       VALUES ('0a000001-0000-0000-0000-000000000001',
               '0b000002-0000-0000-0000-000000000001')$q$,
    '5.6 questionnaire cannot borrow Family B assessment_run_id');

  -- Own child, another family's compared results.
  PERFORM tests.assert_rejected(
    $q$INSERT INTO public.assessment_comparisons
         (child_id, baseline_assessment_result_id,
          comparison_assessment_result_id)
       VALUES ('0a000001-0000-0000-0000-000000000001',
               '0b000005-0000-0000-0000-000000000001',
               '0a000005-0000-0000-0000-000000000001')$q$,
    '5.7 comparison cannot borrow Family B result');

  -- Own child, another family's run, on sensory_profiles.
  PERFORM tests.assert_rejected(
    $q$INSERT INTO public.sensory_profiles (child_id, assessment_run_id)
       VALUES ('0a000001-0000-0000-0000-000000000001',
               '0b000002-0000-0000-0000-000000000001')$q$,
    '5.8 sensory profile cannot borrow Family B assessment_run_id');

  -- Consent must name the caller's own child.
  PERFORM tests.assert_rejected(
    $q$INSERT INTO public.research_consents
         (user_id, child_id, consent_version, research_participation)
       VALUES ('11111111-1111-1111-1111-111111111111',
               '0b000001-0000-0000-0000-000000000001', 'v1', true)$q$,
    '5.9 consent cannot be filed against Family B child');
END $$;

-- ══ 6. Transitive tables unreachable through another family's ids ══════
DO $$
BEGIN
  PERFORM tests.assert_rejected(
    $q$INSERT INTO public.game_rounds (session_id, round_no)
       VALUES ('0b000003-0000-0000-0000-000000000001', 99)$q$,
    '6.1 round cannot be inserted into Family B session');

  PERFORM tests.assert_rejected(
    $q$INSERT INTO public.session_events (session_id, event_type)
       VALUES ('0b000003-0000-0000-0000-000000000001', 'tap')$q$,
    '6.2 event cannot be inserted into Family B session');

  -- Own session, but a round id belonging to Family B.
  PERFORM tests.assert_rejected(
    $q$INSERT INTO public.session_events (session_id, round_id, event_type)
       VALUES ('0a000003-0000-0000-0000-000000000001',
               '0b000004-0000-0000-0000-000000000001', 'tap')$q$,
    '6.3 event cannot point at a round outside its own session');

  PERFORM tests.assert_no_rows_affected(
    $q$UPDATE public.game_rounds SET correct = true
       WHERE id = '0b000004-0000-0000-0000-000000000001'$q$,
    '6.4 Family B round is invisible to UPDATE');

  PERFORM tests.assert_no_rows_affected(
    $q$DELETE FROM public.game_rounds
       WHERE session_id = '0b000003-0000-0000-0000-000000000001'$q$,
    '6.5 Family B rounds cannot be deleted through their session id');
END $$;

-- ══ 7. Guest / anonymous behaviour ═════════════════════════════════════
-- A guest who has signed in anonymously holds a normal authenticated uid,
-- so the same policies apply: they own what they create and see nothing
-- else. Local `guest_*` identifiers stay on device — they are not UUIDs and
-- no policy asks for them.
RESET ROLE;
INSERT INTO public.children (id, parent_user_id, display_name, birth_date)
VALUES ('0c000001-0000-0000-0000-000000000001',
        '44444444-4444-4444-4444-444444444444', 'Guest Child', '2022-03-03');

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims =
  '{"sub":"44444444-4444-4444-4444-444444444444","role":"authenticated"}';

DO $$
DECLARE v_n integer;
BEGIN
  SELECT count(*) INTO v_n FROM public.children;
  PERFORM tests.assert(v_n = 1, '7.1 anonymous user sees only their own child');

  SELECT count(*) INTO v_n FROM public.children
  WHERE id = '0a000001-0000-0000-0000-000000000001';
  PERFORM tests.assert(v_n = 0, '7.2 anonymous user cannot see Family A');

  INSERT INTO public.game_sessions (child_id)
  VALUES ('0c000001-0000-0000-0000-000000000001');
  PERFORM tests.assert(true, '7.3 anonymous user can write for own child');

  PERFORM tests.assert_rejected(
    $q$INSERT INTO public.game_sessions (child_id)
       VALUES ('0a000001-0000-0000-0000-000000000001')$q$,
    '7.4 anonymous user cannot write for another family''s child');

  -- A local guest identifier is not a UUID; nothing in the policy set asks
  -- the client to upload one, and the column type rejects it outright.
  PERFORM tests.assert_rejected(
    $q$INSERT INTO public.children (id, parent_user_id, display_name, birth_date)
       VALUES ('guest_abc', '44444444-4444-4444-4444-444444444444',
               'Local', '2022-01-01')$q$,
    '7.5 local guest_* identifiers are not uploadable as UUIDs');
END $$;

-- Binding a guest to a permanent account keeps the same auth uid, so the
-- rows stay owned by the same user and no unrelated row becomes reachable.
RESET ROLE;
UPDATE auth.users
SET is_anonymous = false, email = 'bound@example.test'
WHERE id = '44444444-4444-4444-4444-444444444444';

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims =
  '{"sub":"44444444-4444-4444-4444-444444444444","role":"authenticated"}';

DO $$
DECLARE v_n integer;
BEGIN
  SELECT count(*) INTO v_n FROM public.children;
  PERFORM tests.assert(v_n = 1, '7.6 after binding, same single child is owned');

  SELECT count(*) INTO v_n FROM public.game_sessions;
  PERFORM tests.assert(v_n = 1, '7.7 after binding, no extra rows became visible');
END $$;

-- ══ 8/9/10. Administrator authorization and audit ══════════════════════
RESET ROLE;
INSERT INTO public.research_consents
  (user_id, child_id, consent_version, research_participation)
VALUES ('11111111-1111-1111-1111-111111111111',
        '0a000001-0000-0000-0000-000000000001', 'v1', true);

-- 9. A non-admin cannot invoke the restricted operation.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims =
  '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

DO $$
DECLARE v_n integer;
BEGIN
  PERFORM tests.assert(public.is_admin() = false,
    '9.1 is_admin() is false for a parent');

  PERFORM tests.assert_rejected(
    $q$SELECT public.get_child_report(
         '0a000001-0000-0000-0000-000000000001'::uuid)$q$,
    '9.2 non-admin cannot call get_child_report');

  SELECT count(*) INTO v_n FROM public.audit_logs;
  PERFORM tests.assert(v_n = 0, '9.3 parent cannot read audit_logs');

  -- A parent must not be able to grant themselves admin.
  PERFORM tests.assert_rejected(
    $q$INSERT INTO public.admin_users (user_id)
       VALUES ('11111111-1111-1111-1111-111111111111')$q$,
    '9.4 parent cannot insert themselves into admin_users');
END $$;

-- 8/10. A real admin succeeds, and the access is audited.
SET LOCAL request.jwt.claims =
  '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated"}';

DO $$
DECLARE
  v_n integer;
  v_report jsonb;
  v_audit public.audit_logs%ROWTYPE;
BEGIN
  PERFORM tests.assert(public.is_admin() = true,
    '8.1 is_admin() is true for a real admin');

  v_report := public.get_child_report('0a000001-0000-0000-0000-000000000001');
  PERFORM tests.assert(v_report ? 'child',
    '8.2 admin can call get_child_report for a consented child');

  -- Admins still get no blanket RLS access to family tables.
  SELECT count(*) INTO v_n FROM public.children;
  PERFORM tests.assert(v_n = 0,
    '8.3 admin has no direct SELECT on children (RPC path only)');

  PERFORM tests.assert_rejected(
    $q$SELECT public.get_child_report(
         '0b000001-0000-0000-0000-000000000001'::uuid)$q$,
    '8.4 admin cannot report on a child without research consent');

  SELECT count(*) INTO v_n FROM public.audit_logs
  WHERE action = 'ADMIN_CHILD_REPORT_READ';
  PERFORM tests.assert(v_n = 1, '10.1 exactly one audit row was written');

  SELECT * INTO v_audit FROM public.audit_logs
  WHERE action = 'ADMIN_CHILD_REPORT_READ';

  PERFORM tests.assert(
    v_audit.actor_id = '33333333-3333-3333-3333-333333333333',
    '10.2 audit row records the acting admin');
  PERFORM tests.assert(
    v_audit.record_id = '0a000001-0000-0000-0000-000000000001',
    '10.3 audit row records the child accessed');
  PERFORM tests.assert(
    v_audit.new_data = jsonb_build_object('consent_version', 'v1'),
    '10.4 audit row stores consent metadata only, not the report payload');
  PERFORM tests.assert(
    v_audit.old_data IS NULL,
    '10.5 audit row stores no prior-state payload');
END $$;

-- ══ 11. Ordinary catalog reads and parent sync still work ══════════════
SET LOCAL request.jwt.claims =
  '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

DO $$
DECLARE v_n integer;
BEGIN
  SELECT count(*) INTO v_n FROM public.learning_modules;
  PERFORM tests.assert(v_n = 1,
    '11.1 parent reads active catalog rows (and only active ones)');

  -- A full hydration join across the whole ownership chain still resolves.
  SELECT count(*) INTO v_n
  FROM public.children c
  JOIN public.assessment_runs r ON r.child_id = c.id
  JOIN public.game_sessions gs ON gs.child_id = c.id
  JOIN public.game_rounds gr ON gr.session_id = gs.id
  WHERE c.parent_user_id = '11111111-1111-1111-1111-111111111111';
  PERFORM tests.assert(v_n >= 1, '11.2 parent hydration join returns own rows');

  SELECT count(*) INTO v_n FROM public.research_consents;
  PERFORM tests.assert(v_n = 1, '11.3 parent reads own research consent');
END $$;

-- ══ 13. Re-parenting via UPDATE, and other WITH CHECK paths ════════════
-- Added during independent review: sections 2/5/6 prove INSERT-side
-- rejection, but an UPDATE that moves an already-owned row onto another
-- family's parent exercises a different policy clause (USING passes, only
-- WITH CHECK can stop it). Each case below is that second clause.
RESET ROLE;

-- Extra Family A fixtures needed by the UPDATE cases.
INSERT INTO public.assessment_runs (id, child_id)
VALUES ('0a000006-0000-0000-0000-000000000001',
        '0a000001-0000-0000-0000-000000000001');
INSERT INTO public.assessment_results (id, assessment_run_id, child_id)
VALUES ('0a000007-0000-0000-0000-000000000001',
        '0a000006-0000-0000-0000-000000000001',
        '0a000001-0000-0000-0000-000000000001');
INSERT INTO public.assessment_comparisons
  (id, child_id, baseline_assessment_result_id, comparison_assessment_result_id)
VALUES ('0a000008-0000-0000-0000-000000000001',
        '0a000001-0000-0000-0000-000000000001',
        '0a000005-0000-0000-0000-000000000001',
        '0a000007-0000-0000-0000-000000000001');
INSERT INTO public.module_recommendations (id, child_id, source_assessment_id)
VALUES ('0a000009-0000-0000-0000-000000000001',
        '0a000001-0000-0000-0000-000000000001',
        '0a000005-0000-0000-0000-000000000001');
INSERT INTO public.sensory_profiles (id, child_id, assessment_run_id)
VALUES ('0a00000a-0000-0000-0000-000000000001',
        '0a000001-0000-0000-0000-000000000001',
        '0a000002-0000-0000-0000-000000000001');
-- A second session of Parent A's own, to prove events cannot cross even
-- between two sessions the SAME parent owns.
INSERT INTO public.game_sessions (id, child_id)
VALUES ('0a00000b-0000-0000-0000-000000000001',
        '0a000001-0000-0000-0000-000000000001');
INSERT INTO public.game_rounds (id, session_id, round_no)
VALUES ('0a00000c-0000-0000-0000-000000000001',
        '0a00000b-0000-0000-0000-000000000001', 1);
INSERT INTO public.session_events (id, session_id, event_type)
VALUES ('0a00000d-0000-0000-0000-000000000001',
        '0a000003-0000-0000-0000-000000000001', 'tap');

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims =
  '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

DO $$
BEGIN
  PERFORM tests.assert_rejected(
    $q$UPDATE public.game_sessions
       SET child_id = '0b000001-0000-0000-0000-000000000001'
       WHERE id = '0a000003-0000-0000-0000-000000000001'$q$,
    '13.1 own session cannot be moved onto Family B child');

  PERFORM tests.assert_rejected(
    $q$UPDATE public.game_rounds
       SET session_id = '0b000003-0000-0000-0000-000000000001'
       WHERE id = '0a000004-0000-0000-0000-000000000001'$q$,
    '13.2 own round cannot be moved into Family B session');

  PERFORM tests.assert_rejected(
    $q$UPDATE public.assessment_runs
       SET child_id = '0b000001-0000-0000-0000-000000000001'
       WHERE id = '0a000002-0000-0000-0000-000000000001'$q$,
    '13.3 own run cannot be moved onto Family B child');

  -- Same owner on both sides, but the round belongs to a different session.
  PERFORM tests.assert_rejected(
    $q$UPDATE public.session_events
       SET round_id = '0a00000c-0000-0000-0000-000000000001'
       WHERE id = '0a00000d-0000-0000-0000-000000000001'$q$,
    '13.4 event cannot be repointed at a round of an unrelated own session');

  PERFORM tests.assert_rejected(
    $q$INSERT INTO public.caregiver_questionnaires
         (child_id, assessment_run_id, completed_by_user_id)
       VALUES ('0a000001-0000-0000-0000-000000000001',
               '0a000002-0000-0000-0000-000000000001',
               '22222222-2222-2222-2222-222222222222')$q$,
    '13.5 questionnaire cannot be attributed to another user');

  PERFORM tests.assert_rejected(
    $q$UPDATE public.assessment_comparisons
       SET comparison_assessment_result_id =
           '0b000005-0000-0000-0000-000000000001'
       WHERE id = '0a000008-0000-0000-0000-000000000001'$q$,
    '13.6 own comparison cannot be repointed at Family B result');

  PERFORM tests.assert_rejected(
    $q$UPDATE public.module_recommendations
       SET source_assessment_id = '0b000005-0000-0000-0000-000000000001'
       WHERE id = '0a000009-0000-0000-0000-000000000001'$q$,
    '13.7 own recommendation cannot be repointed at Family B assessment');

  PERFORM tests.assert_rejected(
    $q$UPDATE public.sensory_profiles
       SET assessment_run_id = '0b000002-0000-0000-0000-000000000001'
       WHERE id = '0a00000a-0000-0000-0000-000000000001'$q$,
    '13.8 own sensory profile cannot be repointed at Family B run');

  PERFORM tests.assert_rejected(
    $q$UPDATE public.research_consents
       SET child_id = '0b000001-0000-0000-0000-000000000001'
       WHERE child_id = '0a000001-0000-0000-0000-000000000001'$q$,
    '13.9 own consent cannot be repointed at Family B child');
END $$;

-- Parent B: sensory profiles and the rest of Family A stay invisible.
SET LOCAL request.jwt.claims =
  '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}';

DO $$
DECLARE v_n integer;
BEGIN
  SELECT count(*) INTO v_n FROM public.sensory_profiles;
  PERFORM tests.assert(v_n = 0,
    '13.10 Parent B cannot SELECT Family A sensory profiles');

  SELECT count(*) INTO v_n FROM public.assessment_comparisons;
  PERFORM tests.assert(v_n = 0,
    '13.11 Parent B cannot SELECT Family A comparisons');

  SELECT count(*) INTO v_n FROM public.module_recommendations;
  PERFORM tests.assert(v_n = 0,
    '13.12 Parent B cannot SELECT Family A recommendations');

  SELECT count(*) INTO v_n FROM public.caregiver_questionnaires;
  PERFORM tests.assert(v_n = 0,
    '13.13 Parent B cannot SELECT Family A questionnaires');
END $$;

-- anon: DELETE as well as UPDATE.
RESET ROLE;
SET LOCAL ROLE anon;
SET LOCAL request.jwt.claims = '{"role":"anon"}';

DO $$
BEGIN
  PERFORM tests.assert_no_rows_affected(
    $q$DELETE FROM public.children$q$,
    '13.14 anon cannot DELETE any child');
  PERFORM tests.assert_no_rows_affected(
    $q$DELETE FROM public.game_rounds$q$,
    '13.15 anon cannot DELETE any round');
  PERFORM tests.assert_no_rows_affected(
    $q$UPDATE public.sensory_profiles SET notes = 'x'$q$,
    '13.16 anon cannot UPDATE sensory profiles');
END $$;

-- Administrator: the RPC is the only door. No direct writes either.
RESET ROLE;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims =
  '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated"}';

DO $$
DECLARE v_n integer;
BEGIN
  PERFORM tests.assert_no_rows_affected(
    $q$UPDATE public.children SET display_name = 'admin edit'$q$,
    '13.17 admin cannot UPDATE family rows directly');

  PERFORM tests.assert_no_rows_affected(
    $q$DELETE FROM public.game_sessions$q$,
    '13.18 admin cannot DELETE family rows directly');

  SELECT count(*) INTO v_n FROM public.assessment_results;
  PERFORM tests.assert(v_n = 0,
    '13.19 admin has no direct SELECT on assessment_results');

  SELECT count(*) INTO v_n FROM public.game_rounds;
  PERFORM tests.assert(v_n = 0,
    '13.20 admin has no direct SELECT on game_rounds');
END $$;

RESET ROLE;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims =
  '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

-- ══ 12. Deletion behaviour ═════════════════════════════════════════════
-- The remote schema has no soft-delete column; `sync_status` and the other
-- soft-delete markers live only in the device's SQLite mirror. Server side,
-- a parent deleting a child cascades the whole family subtree, and account
-- deletion cascades from auth.users.
DO $$
DECLARE v_n integer;
BEGIN
  DELETE FROM public.children
  WHERE id = '0a000001-0000-0000-0000-000000000001';
  GET DIAGNOSTICS v_n = ROW_COUNT;
  PERFORM tests.assert(v_n = 1, '12.1 parent can delete own child');

  SELECT count(*) INTO v_n FROM public.game_sessions
  WHERE child_id = '0a000001-0000-0000-0000-000000000001';
  PERFORM tests.assert(v_n = 0, '12.2 child delete cascades its sessions');
END $$;

RESET ROLE;

DO $$
DECLARE v_n integer;
BEGIN
  -- Regression guard: before this migration, sensory_profiles' foreign keys
  -- had no ON DELETE CASCADE, so 12.1 above would have failed outright with
  -- a foreign key violation and account deletion could not complete.
  SELECT count(*) INTO v_n FROM public.sensory_profiles
  WHERE child_id = '0a000001-0000-0000-0000-000000000001';
  PERFORM tests.assert(v_n = 0,
    '12.2b child delete cascades its sensory profiles');
END $$;

-- Give Family B a sensory profile too, so account deletion has to cascade
-- through the constraint this migration repaired.
INSERT INTO public.sensory_profiles (child_id, assessment_run_id)
VALUES ('0b000001-0000-0000-0000-000000000001',
        '0b000002-0000-0000-0000-000000000001');

DO $$
DECLARE v_n integer;
BEGIN
  DELETE FROM auth.users WHERE id = '22222222-2222-2222-2222-222222222222';

  SELECT count(*) INTO v_n FROM public.children
  WHERE parent_user_id = '22222222-2222-2222-2222-222222222222';
  PERFORM tests.assert(v_n = 0, '12.3 account deletion cascades children');

  SELECT count(*) INTO v_n FROM public.game_rounds
  WHERE id = '0b000004-0000-0000-0000-000000000001';
  PERFORM tests.assert(v_n = 0,
    '12.4 account deletion cascades the whole descendant chain');

  SELECT count(*) INTO v_n FROM public.sensory_profiles;
  PERFORM tests.assert(v_n = 0,
    '12.5 account deletion cascades sensory profiles (no FK block)');
END $$;

DO $$ BEGIN RAISE NOTICE 'AUM-209 policy tests: all assertions passed'; END $$;

ROLLBACK;
