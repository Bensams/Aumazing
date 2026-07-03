-- Migration: Therapy Center Directory
-- Description: Creates the therapy_centers table backing the Freemium
--              Therapy Directory / Interactive Locator (manuscript Use
--              Cases 11, 15, 16). Coordinates enable client-side Haversine
--              proximity ranking; the parent's GPS position is processed
--              in app memory only and never stored (privacy FR).
-- Date: 2026-07-03

CREATE TABLE IF NOT EXISTS public.therapy_centers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  description text,
  address text NOT NULL,
  city text NOT NULL DEFAULT 'Davao City',
  latitude double precision NOT NULL,
  longitude double precision NOT NULL,
  phone text,
  services text[] DEFAULT '{}',
  active boolean NOT NULL DEFAULT true,
  sort_order integer DEFAULT 0,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

COMMENT ON TABLE public.therapy_centers IS
  'Therapy/SPED center listings for the parent-facing directory & locator';

ALTER TABLE public.therapy_centers ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users can read active therapy centers"
  ON public.therapy_centers
  FOR SELECT
  TO authenticated
  USING (active = true);

CREATE POLICY "Service role manages therapy centers"
  ON public.therapy_centers
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- ── Seed: Davao City SPED / therapy providers ───────────────────────────
-- NOTE: seed data for the capstone build. Coordinates are approximate
-- (city-block level); the administrator should verify each pin before
-- production per the admin FR ("input precise latitude and longitude").
INSERT INTO public.therapy_centers
  (name, description, address, latitude, longitude, services, sort_order)
VALUES
  ('Daniel M. Perez Central Elem. School SPED Center',
   'Public elementary SPED center serving learners with special needs.',
   'Bunawan District, Davao City', 7.2278, 125.6483,
   ARRAY['SPED classes','Early intervention'], 1),
  ('Rizal Elementary School SPED Center',
   'Long-running public SPED center in the city center.',
   'C. Bangoy St., Poblacion District, Davao City', 7.0736, 125.6110,
   ARRAY['SPED classes','Assessment support'], 2),
  ('Lamb of God SPED Academy',
   'Private SPED school for children with developmental needs.',
   'Buhangin District, Davao City', 7.1064, 125.6215,
   ARRAY['SPED classes','One-on-one intervention'], 3),
  ('House of Hope Foundation - Davao',
   'Non-profit supporting children with special health and developmental needs.',
   'Davao Medical School Foundation area, Bajada, Davao City', 7.0894, 125.6133,
   ARRAY['Family support','Referrals'], 4),
  ('Philippine Mental Health Association - Davao Chapter',
   'Mental health services including child developmental consultations.',
   'McArthur Highway, Matina, Davao City', 7.0517, 125.5941,
   ARRAY['Consultation','Counseling'], 5),
  ('Davao Doctors Hospital - Developmental Pediatrics',
   'Hospital-based developmental pediatrics and therapy referrals.',
   'E. Quirino Ave., Davao City', 7.0644, 125.6027,
   ARRAY['Developmental pediatrics','Occupational therapy','Speech therapy'], 6)
ON CONFLICT DO NOTHING;
