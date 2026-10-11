-- AUM-364: the home questionnaire's "before" is asked once, right after the
-- child's profile is set up, before any assessment exists. The app stores
-- that report as a `pre` questionnaire with no assessment run, so
-- assessment_run_id has to accept null or the report can never sync.
-- Post-assessment reports and the observer records keep their run.
--
-- Relaxing only: no existing row changes. The foreign key to assessment_runs
-- still checks every run that is given. The live access policies check only
-- that the caller owns the child, so they accept a report with no run as
-- they are. (The unapplied 20260816_family_data_rls.sql policies also require
-- owns_assessment_run(assessment_run_id); if they are ever applied, they need
-- `assessment_run_id is null or ...` for setup reports to sync.)
--
-- Applied to the live project on 2026-10-12.

alter table public.caregiver_questionnaires
  alter column assessment_run_id drop not null;
