-- Migration: PayMongo freemium entitlements (sandbox)
-- Description: Entitlements (Premium access), payment records, and webhook
--              event log for the PayMongo integration (manuscript Use Cases
--              12 & 13, ERD tables Entitlements / Payment_intents /
--              webhook_events). Writes happen only in Edge Functions using
--              the service role; clients can read their own rows.
-- Date: 2026-07-03

CREATE TABLE IF NOT EXISTS public.entitlements (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  is_premium boolean NOT NULL DEFAULT false,
  source text,                       -- e.g. 'paymongo_test'
  activated_at timestamptz,
  updated_at timestamptz DEFAULT now()
);

ALTER TABLE public.entitlements ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read their own entitlement"
  ON public.entitlements FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_admin());

CREATE TABLE IF NOT EXISTS public.payment_records (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  checkout_session_id text UNIQUE,
  amount integer,                    -- centavos
  currency text DEFAULT 'PHP',
  status text NOT NULL DEFAULT 'pending',  -- pending / paid / failed
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

ALTER TABLE public.payment_records ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read their own payments"
  ON public.payment_records FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_admin());

CREATE TABLE IF NOT EXISTS public.webhook_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id text UNIQUE,              -- PayMongo event id (dedupe/replay)
  event_type text,
  signature_valid boolean NOT NULL DEFAULT false,
  payload jsonb,
  processed boolean NOT NULL DEFAULT false,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE public.webhook_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admins can read webhook events"
  ON public.webhook_events FOR SELECT TO authenticated
  USING (public.is_admin());

-- Premium conversion metric for the admin dashboard.
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
      (SELECT count(*) FROM public.learning_modules WHERE active = true),
    'premium_users',
      (SELECT count(*) FROM public.entitlements WHERE is_premium = true)
  );
END;
$$;
