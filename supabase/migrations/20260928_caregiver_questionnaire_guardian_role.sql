-- AUM-351: observed assessment. The adult who watches the child play says
-- who they are before the games start, and every record they answer carries
-- that role in completed_by_role. The table allowed parent, therapist and
-- teacher; a guardian who is not the parent had no fitting value.
--
-- Applied to the live project on 2026-09-28.

alter table public.caregiver_questionnaires
  drop constraint if exists caregiver_questionnaires_completed_by_role_check;

alter table public.caregiver_questionnaires
  add constraint caregiver_questionnaires_completed_by_role_check
  check (completed_by_role in ('parent', 'guardian', 'teacher', 'therapist'));
