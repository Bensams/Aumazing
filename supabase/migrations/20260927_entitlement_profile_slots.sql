-- AUM-343: extra child-profile slots (pre-final defense note).
--
-- One child profile is free; each additional profile is bought separately,
-- and only Premium accounts can buy them. The app reads this count from the
-- parent's own entitlements row (EntitlementService._refreshProfileSlots).
--
-- Like is_premium, this column is written only by the payment webhook after
-- server-side verification — never by the client. The existing RLS on
-- entitlements (select own row; no client writes) already covers it.
--
-- Applied to the live project on 2026-09-28. The payment webhook does not yet
-- increment it on a verified one-time "extra profile" payment, so every
-- account reads 0 purchased slots until that change ships.

ALTER TABLE public.entitlements
  ADD COLUMN IF NOT EXISTS extra_profile_slots integer NOT NULL DEFAULT 0
  CHECK (extra_profile_slots >= 0);

COMMENT ON COLUMN public.entitlements.extra_profile_slots IS
  'Child profiles bought beyond the free one (AUM-343). Webhook-written only.';
