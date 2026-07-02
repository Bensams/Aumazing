-- The app's sync payload sends `context` ('pre_assessment' | 'post_assessment'
-- | 'practice') but not `session_type`, which is NOT NULL with a CHECK using
-- an older vocabulary. Expand the vocabulary (superset — old data stays
-- valid) and default session_type from context on write.
-- Applied to production 2026-07-02 as default_session_type_from_context.

alter table public.game_sessions drop constraint game_sessions_session_type_check;
alter table public.game_sessions add constraint game_sessions_session_type_check
  check (session_type = any (array[
    'pre_assessment'::text, 'post_assessment'::text, 'practice'::text,
    'training'::text, 'recommended_module'::text, 'free_play'::text
  ]));

create or replace function public.game_sessions_default_session_type()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.session_type := coalesce(new.session_type, new.context, 'practice');
  return new;
end;
$$;

drop trigger if exists trg_game_sessions_default_session_type on public.game_sessions;
create trigger trg_game_sessions_default_session_type
before insert or update on public.game_sessions
for each row execute function public.game_sessions_default_session_type();
