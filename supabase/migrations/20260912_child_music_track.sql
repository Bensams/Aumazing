-- Allow a parent to persist one exact bundled background-music track.
-- NULL preserves the existing category-shuffle behaviour for legacy profiles.

alter table public.children
  add column if not exists music_track text;
