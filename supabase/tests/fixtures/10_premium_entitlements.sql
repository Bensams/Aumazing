-- Live shape of public.entitlements and has_active_premium (checked against
-- the production database on 2026-10-11), for tests that need Premium.

CREATE TABLE IF NOT EXISTS public.entitlements (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  is_premium boolean NOT NULL DEFAULT false,
  source text,
  activated_at timestamptz,
  updated_at timestamptz DEFAULT now(),
  expires_at timestamptz,
  extra_profile_slots integer NOT NULL DEFAULT 0
    CHECK (extra_profile_slots >= 0)
);
ALTER TABLE public.entitlements ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.has_active_premium(p_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT COALESCE((
    SELECT e.is_premium AND (e.expires_at IS NULL OR e.expires_at > now())
    FROM public.entitlements e
    WHERE e.user_id = p_user_id
  ), false);
$$;
