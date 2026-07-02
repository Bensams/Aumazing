-- Columns the app's sync payload sends but the remote schema lacked
-- (PGRST204 failures during game session/round sync).
-- Applied to production 2026-07-02 as add_missing_sync_columns_to_game_tables.

alter table public.game_sessions
  add column if not exists context text,
  add column if not exists score integer,
  add column if not exists total_items integer,
  add column if not exists error_count integer,
  add column if not exists total_response_time_ms integer,
  add column if not exists bg_music_enabled boolean default true,
  add column if not exists haptic_feedback_enabled boolean default true,
  add column if not exists turn_taking_success_rate double precision,
  add column if not exists interruption_count integer,
  add column if not exists waiting_tolerance_seconds double precision,
  add column if not exists sensory_condition text,
  add column if not exists settings_snapshot text;

alter table public.game_rounds
  add column if not exists music_enabled boolean default true,
  add column if not exists haptic_enabled boolean default true;
