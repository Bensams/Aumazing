-- AUM-344 follow-up: keep the practitioner helper functions off the public
-- API. The trigger guard only needs to fire as a trigger, and
-- is_approved_practitioner() is only needed by signed-in users' access rules.
--
-- Applied to the live project on 2026-09-28.

REVOKE EXECUTE ON FUNCTION public.questionnaire_templates_guard() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.is_approved_practitioner() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_approved_practitioner() TO authenticated;
