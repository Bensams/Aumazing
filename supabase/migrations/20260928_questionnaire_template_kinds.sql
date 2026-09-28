-- AUM-352: practitioners author all three question sets from the portal.
--
-- questionnaire_templates held only the home questionnaire (AUM-344). The
-- observed assessment (AUM-351) added two more sets asked of the watching
-- adult: "Before your child starts" (intake) and "What did you see?"
-- (observation). `kind` says which set a template is, and one template per
-- kind and assessment type may be active at a time.
--
-- Existing rows are home questionnaires.
--
-- Applied to the live project on 2026-09-28.

ALTER TABLE public.questionnaire_templates
  ADD COLUMN IF NOT EXISTS kind text NOT NULL DEFAULT 'home';

ALTER TABLE public.questionnaire_templates
  DROP CONSTRAINT IF EXISTS questionnaire_templates_kind_check;
ALTER TABLE public.questionnaire_templates
  ADD CONSTRAINT questionnaire_templates_kind_check
  CHECK (kind IN ('home', 'intake', 'observation'));

DROP INDEX IF EXISTS public.questionnaire_templates_one_active;
CREATE UNIQUE INDEX questionnaire_templates_one_active
  ON public.questionnaire_templates (kind, questionnaire_type)
  WHERE is_active;

-- A practitioner changing what a template is for — its kind or its
-- assessment type — takes it out of use, like rewording it does.
CREATE OR REPLACE FUNCTION public.questionnaire_templates_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  NEW.updated_at := now();
  IF public.is_admin() THEN
    IF NEW.is_active AND (TG_OP = 'INSERT' OR NOT OLD.is_active) THEN
      NEW.activated_by := auth.uid();
      NEW.activated_at := now();
    END IF;
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' THEN
    NEW.is_active := false;
    NEW.status := 'draft';
    NEW.activated_by := NULL;
    NEW.activated_at := NULL;
  ELSE
    IF NEW.status IS DISTINCT FROM OLD.status
       OR NEW.activated_by IS DISTINCT FROM OLD.activated_by
       OR NEW.activated_at IS DISTINCT FROM OLD.activated_at
       OR (NEW.is_active AND NOT OLD.is_active) THEN
      RAISE EXCEPTION 'only an admin can activate or validate a template';
    END IF;
    -- Content edits deactivate and un-validate: parents must never see
    -- unreviewed text, and reworded text is not the text that was validated.
    IF NEW.items IS DISTINCT FROM OLD.items
       OR NEW.title IS DISTINCT FROM OLD.title
       OR NEW.intro IS DISTINCT FROM OLD.intro
       OR NEW.kind IS DISTINCT FROM OLD.kind
       OR NEW.questionnaire_type IS DISTINCT FROM OLD.questionnaire_type THEN
      NEW.is_active := false;
      NEW.status := 'draft';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.questionnaire_templates_guard() FROM PUBLIC, anon, authenticated;
