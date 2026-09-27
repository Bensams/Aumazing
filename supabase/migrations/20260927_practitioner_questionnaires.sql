-- AUM-344: approved practitioners author the parent questionnaire
-- (pre-final defense note: "roles and functionality for approved
-- practitioner/therapist to add pre and post survey or questionnaire").
--
-- Phase 1:
--   * A practitioner registers (status 'pending'); an admin approves them.
--   * Approved practitioners create and edit questionnaire templates.
--   * Only an admin can make a template active. The app reads the active
--     template for pre / post and falls back to its bundled draft.
--
-- Relies on public.is_admin() (present in the live project).
--
-- NOT YET APPLIED to the live project — review, then apply.

-- ── Practitioners ────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.practitioners (
  user_id        uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name      text NOT NULL,
  profession     text NOT NULL,           -- e.g. 'SPED teacher', 'OT', 'SLP'
  license_number text,                    -- e.g. PRC licence, verified by admin
  status         text NOT NULL DEFAULT 'pending'
                   CHECK (status IN ('pending', 'approved', 'revoked')),
  approved_by    uuid REFERENCES auth.users(id),
  approved_at    timestamptz,
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.practitioners ENABLE ROW LEVEL SECURITY;

-- Whether the caller is an approved practitioner. SECURITY DEFINER so it can
-- be used inside other tables' policies without exposing this table.
CREATE OR REPLACE FUNCTION public.is_approved_practitioner()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.practitioners
    WHERE user_id = auth.uid() AND status = 'approved'
  );
$$;

DROP POLICY IF EXISTS practitioners_select_own_or_admin ON public.practitioners;
CREATE POLICY practitioners_select_own_or_admin
  ON public.practitioners FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_admin());

-- Anyone signed in may apply — but only as themselves, and only as pending.
DROP POLICY IF EXISTS practitioners_insert_self_pending ON public.practitioners;
CREATE POLICY practitioners_insert_self_pending
  ON public.practitioners FOR INSERT TO authenticated
  WITH CHECK (
    user_id = auth.uid()
    AND status = 'pending'
    AND approved_by IS NULL
    AND approved_at IS NULL
  );

-- Approval, revocation and corrections are admin-only.
DROP POLICY IF EXISTS practitioners_update_admin ON public.practitioners;
CREATE POLICY practitioners_update_admin
  ON public.practitioners FOR UPDATE TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

-- ── Questionnaire templates ─────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.questionnaire_templates (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  template_key       text NOT NULL,
  version            integer NOT NULL DEFAULT 1 CHECK (version > 0),
  -- Which assessment the template serves; 'both' for the usual case where
  -- the identical questions are asked before and after.
  questionnaire_type text NOT NULL DEFAULT 'both'
                       CHECK (questionnaire_type IN ('pre', 'post', 'both')),
  title              text NOT NULL,
  intro              text NOT NULL DEFAULT '',
  -- [{"id": "...", "domain": "communication|play|social|attention",
  --   "text": "..."}]
  items              jsonb NOT NULL CHECK (jsonb_typeof(items) = 'array'),
  status             text NOT NULL DEFAULT 'draft'
                       CHECK (status IN ('draft', 'validated')),
  is_active          boolean NOT NULL DEFAULT false,
  authored_by        uuid NOT NULL REFERENCES auth.users(id),
  activated_by       uuid REFERENCES auth.users(id),
  activated_at       timestamptz,
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now(),
  UNIQUE (template_key, version)
);

-- At most one active template per assessment type.
CREATE UNIQUE INDEX IF NOT EXISTS questionnaire_templates_one_active
  ON public.questionnaire_templates (questionnaire_type)
  WHERE is_active;

ALTER TABLE public.questionnaire_templates ENABLE ROW LEVEL SECURITY;

-- Parents (and guests, who are signed in anonymously) read the active
-- template; practitioners also read their own drafts; admins read all.
DROP POLICY IF EXISTS questionnaire_templates_select ON public.questionnaire_templates;
CREATE POLICY questionnaire_templates_select
  ON public.questionnaire_templates FOR SELECT TO authenticated
  USING (
    is_active
    OR authored_by = auth.uid()
    OR public.is_admin()
  );

DROP POLICY IF EXISTS questionnaire_templates_insert ON public.questionnaire_templates;
CREATE POLICY questionnaire_templates_insert
  ON public.questionnaire_templates FOR INSERT TO authenticated
  WITH CHECK (
    -- An admin may enter a template on a practitioner's behalf.
    public.is_admin()
    OR (public.is_approved_practitioner() AND authored_by = auth.uid())
  );

DROP POLICY IF EXISTS questionnaire_templates_update ON public.questionnaire_templates;
CREATE POLICY questionnaire_templates_update
  ON public.questionnaire_templates FOR UPDATE TO authenticated
  USING (
    public.is_admin()
    OR (public.is_approved_practitioner() AND authored_by = auth.uid())
  )
  WITH CHECK (
    public.is_admin()
    OR (public.is_approved_practitioner() AND authored_by = auth.uid())
  );

-- Only an admin may activate a template or mark it validated; a
-- practitioner's edit to an active template takes it back out of use until
-- an admin re-approves it.
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
    -- Content edits deactivate: parents must never see unreviewed text.
    IF NEW.items IS DISTINCT FROM OLD.items
       OR NEW.title IS DISTINCT FROM OLD.title
       OR NEW.intro IS DISTINCT FROM OLD.intro THEN
      NEW.is_active := false;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS questionnaire_templates_guard ON public.questionnaire_templates;
CREATE TRIGGER questionnaire_templates_guard
  BEFORE INSERT OR UPDATE ON public.questionnaire_templates
  FOR EACH ROW EXECUTE FUNCTION public.questionnaire_templates_guard();
