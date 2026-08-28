-- Star Shop: ledger, unlocks, and the child's chosen character (AUM-246).
--
-- Mirrors LocalDbService v17. The two schemas must stay in step; the sync
-- layer maps column-for-column.
--
-- The central decision, and the one worth not undoing later: there is NO
-- balance column. A balance is SUM(delta) over child_star_ledger. This app is
-- offline-first and a family may use more than one device, so a single mutable
-- balance under last-write-wins sync silently discards whichever device wrote
-- second — which here means a child loses stars they watched themselves earn.
-- Append-only rows from any number of devices merge by addition.

-- ── Character and costume on the child ──────────────────────────────────────
-- Existing children keep BPS, the character the app has always shown them. A
-- migration silently reassigning a familiar companion is exactly the surprise
-- this feature exists to avoid; the parent re-picks deliberately in Settings.
alter table public.children
  add column if not exists character_id text not null default 'bps',
  add column if not exists equipped_costume text not null default 'none';

-- Deliberately NOT a foreign key to a characters table, and deliberately
-- unconstrained beyond this: an older client writing a character a newer
-- server does not know must not fail to sync. The app falls back on read.
alter table public.children
  drop constraint if exists children_character_id_check;
alter table public.children
  add constraint children_character_id_check
  check (character_id in ('bps', 'lexianne', 'reiz'));

-- ── The ledger ──────────────────────────────────────────────────────────────
create table if not exists public.child_star_ledger (
  id uuid primary key,
  child_id uuid not null references public.children(id) on delete cascade,
  delta integer not null,
  reason text not null,
  game_session_id uuid references public.game_sessions(id) on delete set null,
  item_id text,
  created_at timestamptz not null default now()
);

-- Stars are never lost (STAR-B5): only a purchase may remove them. Enforced in
-- the database as well as the client, because the client is not the only thing
-- that can write here.
alter table public.child_star_ledger
  drop constraint if exists child_star_ledger_spend_check;
alter table public.child_star_ledger
  add constraint child_star_ledger_spend_check
  check (delta >= 0 or reason = 'purchase');

-- Idempotency (STAR-E2): one payout per session per reason, so a retried
-- upload — which the sync layer performs after any failure — cannot pay a
-- child twice. Partial, because purchase rows carry no session id and must not
-- collide with one another.
create unique index if not exists child_star_ledger_session_uniq
  on public.child_star_ledger (child_id, game_session_id, reason)
  where game_session_id is not null;

create index if not exists child_star_ledger_child_idx
  on public.child_star_ledger (child_id, created_at desc);

-- ── Unlocks ─────────────────────────────────────────────────────────────────
-- Monotonic by construction: the primary key makes a replayed unlock a no-op,
-- and nothing in the app issues a delete. Once owned, always owned (STAR-C7).
create table if not exists public.child_unlocks (
  child_id uuid not null references public.children(id) on delete cascade,
  item_id text not null,
  unlocked_at timestamptz not null default now(),
  primary key (child_id, item_id)
);

-- ── Row level security ──────────────────────────────────────────────────────
-- Mirrors 20260816_family_data_rls.sql: a row is reachable only through a
-- child the requesting user owns.
alter table public.child_star_ledger enable row level security;
alter table public.child_unlocks enable row level security;

drop policy if exists child_star_ledger_family on public.child_star_ledger;
create policy child_star_ledger_family on public.child_star_ledger
  for all
  using (
    exists (
      select 1 from public.children c
      where c.id = child_star_ledger.child_id
        and c.parent_user_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.children c
      where c.id = child_star_ledger.child_id
        and c.parent_user_id = auth.uid()
    )
  );

drop policy if exists child_unlocks_family on public.child_unlocks;
create policy child_unlocks_family on public.child_unlocks
  for all
  using (
    exists (
      select 1 from public.children c
      where c.id = child_unlocks.child_id
        and c.parent_user_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.children c
      where c.id = child_unlocks.child_id
        and c.parent_user_id = auth.uid()
    )
  );

-- ── Note on STAR-E4 ─────────────────────────────────────────────────────────
-- Stars can never be bought with money. There is deliberately no grant, no
-- function and no entitlement trigger that writes to child_star_ledger. If a
-- future payment feature is tempted to, the answer is no: selling currency to
-- children is an app-store kids-category risk and the easiest thing for a
-- reviewer — or a thesis panel — to object to.
