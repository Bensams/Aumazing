# Aumazing — rules for agents

Read this before touching the repo or the Jira board. These are not style
preferences; each one is here because breaking it has already cost real work.

## Jira: the backlog is STATIC

Site `ecnovators.atlassian.net`, cloudId `94a4be68-fedd-4628-846a-7543000866a5`,
project `AUM` ("Aumazing Kanban").

```
BACKLOG  (static — nothing here ever moves or changes)
   │
   └── duplicate ──> To Do ──> DOING ──> TESTING ──> DONE
```

**Never transition an item that lives in BACKLOG. Never edit one. Never mark a
backlog sub-task complete.** The backlog is a reference list, not a work queue.

To work on something, **duplicate it**. The copy is a **Task** titled
`[AUM-xxx] <topic>`, renamed to `[AUM-xxx] <topic> — ready for testing` when it
lands. Its description opens with:

> Working copy of AUM-xxx. The original is left untouched in the backlog so the
> backlog stays static.

and carries implementation status, automated verification numbers, and human
testing steps. **Only the copy moves through the columns.**

### The trap

**New issues are created into `BACKLOG` by default.** A working copy that is not
transitioned immediately after creation silently pollutes the static backlog.
Create, then transition — to `To Do` if queued, or straight to `TESTING` if the
work is already done.

### Ids

| Column | Status id | Transition id |
|---|---|---|
| BACKLOG | 10034 | 1 |
| To Do | 10033 | **6** |
| DOING | 10035 | 2 |
| TESTING | 10036 | 4 |
| DONE | 10037 | 3 |

Sub-tasks use a separate workflow with only `complete` (transition 1, status
10039) and `incomplete` (transition 3, status 10038).

Finished work goes to **TESTING**, not DONE. One working copy per backlog item —
duplicate status cards are a known past mistake (AUM-243 duplicated AUM-154's).

## Git

- Branch `claude/aum-xxx-<slug>`. **PR against `dev`, never `main`.**
- `main` is stale and predates the monorepo refactor — files there may already
  be deleted on `dev`. New worktrees must be created from `origin/dev`, or you
  will be editing a layout that no longer exists.
- Commit generated assets rather than leaving them untracked. A `git clean -fd`
  has already destroyed a day of untracked generated art and an untracked
  `CLAUDE.md`.

## Generated assets

- All asset generation goes through **kie.ai**. `KIE_API_KEY` lives in
  `tools/voice_gen/.env` and nothing auto-loads it — source it explicitly, and
  never write it into a tracked file.
- **Caches belong outside the working tree.** `SPRITE_CACHE_DIR` and
  `COSTUME_CACHE_DIR` default to `~/.cache/aumazing/…` because an in-repo cache
  was deleted by `git clean -fd` along with the finished art, turning a free
  rebuild into a paid regeneration.
- `packages/assets/` has **no pubspec and does not ship**. It is source art for
  the generator scripts. Anything the app renders at runtime must live under a
  real package's declared assets — for shared art that is
  `packages/shared_ui/assets/`.
- Read `scripts/SPRITES.md` before touching anything that generates sprites.

## Supabase

The repo is not a reliable picture of the live schema — `initial_schema` is not
checked in and some checked-in migrations were never applied. Verify against the
live database before writing a migration.
