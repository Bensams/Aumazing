-- Migration: Admin portal foundation
-- Description: Admin allowlist + role check, admin RLS policies for content
--              management (learning_modules, therapy_centers), an audit log
--              populated by triggers (accountability FR), and a stats RPC
--              for the admin dashboard.
-- Date: 2026-07-03

-- 1. Admin allowlist ------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.admin_users (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  note text,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE public.admin_users ENABLE ROW LEVEL SECURITY;

-- Admins can see who the admins are; nobody else can read the table.
CREATE POLICY "Admins can read admin_users"
  ON public.admin_users FOR SELECT TO authenticated
  USING (user_id = auth.uid()
         OR EXISTS (SELECT 1 FROM public.admin_users a
                    WHERE a.user_id = auth.uid()));

-- Role check used by policies and the RPC.
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = public
AS $$
  SELECT EXISTS (SELECT 1 FROM public.admin_users WHERE user_id = auth.uid());
$$;

-- 2. Admin content-management policies -----------------------------------
CREATE POLICY "Admins can read all learning_modules"
  ON public.learning_modules FOR SELECT TO authenticated
  USING (public.is_admin() OR active = true);

CREATE POLICY "Admins can update learning_modules"
  ON public.learning_modules FOR UPDATE TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());

CREATE POLICY "Admins can insert therapy_centers"
  ON public.therapy_centers FOR INSERT TO authenticated
  WITH CHECK (public.is_admin());

CREATE POLICY "Admins can update therapy_centers"
  ON public.therapy_centers FOR UPDATE TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());

CREATE POLICY "Admins can read all therapy_centers"
  ON public.therapy_centers FOR SELECT TO authenticated
  USING (public.is_admin() OR active = true);

-- 3. Audit log (trigger-populated — tamper-resistant by construction) ----
CREATE TABLE IF NOT EXISTS public.audit_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_id uuid,
  action text NOT NULL,            -- INSERT / UPDATE / DELETE
  table_name text NOT NULL,
  record_id text,
  old_data jsonb,
  new_data jsonb,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admins can read audit_logs"
  ON public.audit_logs FOR SELECT TO authenticated
  USING (public.is_admin());

CREATE OR REPLACE FUNCTION public.log_admin_change()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.audit_logs
    (actor_id, action, table_name, record_id, old_data, new_data)
  VALUES (
    auth.uid(),
    TG_OP,
    TG_TABLE_NAME,
    COALESCE((to_jsonb(NEW) ->> 'id'), (to_jsonb(OLD) ->> 'id')),
    CASE WHEN TG_OP IN ('UPDATE','DELETE') THEN to_jsonb(OLD) END,
    CASE WHEN TG_OP IN ('INSERT','UPDATE') THEN to_jsonb(NEW) END
  );
  RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS audit_learning_modules ON public.learning_modules;
CREATE TRIGGER audit_learning_modules
  AFTER INSERT OR UPDATE OR DELETE ON public.learning_modules
  FOR EACH ROW EXECUTE FUNCTION public.log_admin_change();

DROP TRIGGER IF EXISTS audit_therapy_centers ON public.therapy_centers;
CREATE TRIGGER audit_therapy_centers
  AFTER INSERT OR UPDATE OR DELETE ON public.therapy_centers
  FOR EACH ROW EXECUTE FUNCTION public.log_admin_change();

-- 4. Dashboard stats RPC (admin-only, security definer so it can count
--    across RLS-protected tables) -----------------------------------------
CREATE OR REPLACE FUNCTION public.get_admin_stats()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER STABLE
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'not authorized';
  END IF;
  RETURN jsonb_build_object(
    'users', (SELECT count(*) FROM auth.users),
    'children', (SELECT count(*) FROM public.children),
    'assessment_results', (SELECT count(*) FROM public.assessment_results),
    'game_sessions', (SELECT count(*) FROM public.game_sessions),
    'therapy_centers',
      (SELECT count(*) FROM public.therapy_centers WHERE active = true),
    'active_modules',
      (SELECT count(*) FROM public.learning_modules WHERE active = true)
  );
END;
$$;

-- 5. Seed the first administrator (best effort — the account must exist)
INSERT INTO public.admin_users (user_id, note)
SELECT id, 'seeded: project owner'
FROM auth.users
WHERE email = 'benedictdigitoid@gmail.com'
ON CONFLICT (user_id) DO NOTHING;
