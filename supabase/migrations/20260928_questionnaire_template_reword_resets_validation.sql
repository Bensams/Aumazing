-- AUM-344 follow-up: when a practitioner rewords a template, it goes back to
-- 'draft' as well as being taken out of use. The new wording has not been
-- validated, so it must not keep the 'validated' label an admin gave the old
-- wording. Found while verifying the access rules against the live project.
--
-- Applied to the live project on 2026-09-28.

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
       OR NEW.intro IS DISTINCT FROM OLD.intro THEN
      NEW.is_active := false;
      NEW.status := 'draft';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
