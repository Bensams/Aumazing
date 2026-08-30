-- Child-row settings that the app has always written but the cloud could not
-- hold (AUM-328).
--
-- `ChildProfile.toSupabase()` has sent character, costume and the comfort
-- settings for some time, but `public.children` has none of those columns, so
-- every launch hydrated them back as schema defaults and a parent's choice of
-- character died on the next open. These columns are the cloud half of that
-- fix; the sync layer's `_mapChildToSupabase` is the app half.
--
-- The character/costume pair is also declared in 20260818_star_shop.sql, which
-- was never applied. That file still holds the star ledger and unlock tables,
-- which remain unapplied and are NOT created here — stars are still local-only
-- and need their own ticket. `add column if not exists` keeps both files safe
-- to run in either order.

alter table public.children
  -- Existing children keep BPS, the character the app has always shown them.
  -- A migration silently reassigning a familiar companion is exactly the
  -- surprise this feature exists to avoid; the parent re-picks deliberately.
  add column if not exists character_id text not null default 'bps',
  add column if not exists equipped_costume text not null default 'none',
  add column if not exists music_volume real not null default 0.5,
  add column if not exists music_category text not null default 'soft_relaxing',
  add column if not exists sfx_volume real not null default 0.7,
  add column if not exists animation_intensity real not null default 1.0,
  add column if not exists prompt_speed real not null default 1.0,
  add column if not exists sensory_preferences_set boolean not null default false;

-- Deliberately NOT constrained to a fixed list of character ids, and not a
-- foreign key either. A client that knows a character the server does not must
-- still be able to sync — a CHECK here would turn "this build has a new
-- character" into "this family's profile silently stops syncing". The app
-- falls back to BPS on read (ChildCharacter.fromId), which is the right place
-- for that decision because only the app knows what art it actually ships.
alter table public.children
  drop constraint if exists children_character_id_check;
