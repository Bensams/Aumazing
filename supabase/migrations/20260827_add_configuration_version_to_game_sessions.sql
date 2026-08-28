-- AUM-305: record the game-flow configuration version on every uploaded
-- gameplay session so analytics can separate 3-round ('three-round-v1') runs from
-- 4-round legacy data.
--
-- Additive and non-destructive: existing rows keep NULL, which the app
-- reads as "legacy/unknown configuration".
ALTER TABLE public.game_sessions
  ADD COLUMN IF NOT EXISTS configuration_version text;
