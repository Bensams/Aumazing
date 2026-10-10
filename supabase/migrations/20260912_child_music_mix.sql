-- Parent-selected custom mix of 3–5 bundled background tracks.
alter table public.children
  add column if not exists music_tracks jsonb;
