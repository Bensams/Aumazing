# Phase 02.0: Stars, Character Choice & Costume Shop — Product Backlog

Mirrors Jira epic **AUM-246** and its 33 sub-tasks (AUM-247 … AUM-279).

## Objective

Let a child earn a predictable currency ("Stars") by playing, and spend it on animal
costumes for a character the parent chose — without importing the compulsion
mechanics that mainstream game economies are built on.

## Naming

`features/rewards/` already means *celebration effect* (balloons / fireworks /
bubbles / candy — see phase 01.0). This phase must not reuse that word. The
currency is **Stars**, the feature is the **Star Shop**, the code lives in
`features/stars/`.

Star SFX (`3_star.ogg`) and "Star" voice-over already exist in en / tl / ceb, so
the currency name costs nothing to localise.

## Framing (read before defending this phase)

This is a **digital token board**, not a game shop. Token economies are a
long-established behavioural practice — physical star charts are standard in ASD
therapy and classrooms. Everything below follows from digitising an accepted
intervention rather than bolting on gamification, and the acceptance criteria are
written to keep it that way. Where a criterion looks unusually strict (fixed
awards, no expiry, nothing greyed out), that strictness *is* the therapeutic
property.

## Board

Statuses match the AUM board's Task workflow: `BACKLOG` → `DOING` → `TESTING` →
`DONE`. Every story below starts in **BACKLOG**.

`AUM` is a simplified business project with only Task (level 0) and Sub-task
(level −1) — there is no Epic issue type. AUM-246 is a Task playing the epic
role; the stories are sub-tasks beneath it.

## Milestones

| Milestone | Contains | Stories | Points |
|---|---|---|---|
| **M1 — Token board** | Epics A, B, E + C1–C5, D1–D2, F1 | 21 | 73 |
| **M2 — Control & polish** | A4, C6–C7, D3–D4, F2, G | 9 | 31 |
| **M3 — Stretch** | F3, F4, H1 | 3 | 31 |

Story points are Fibonacci. 33 stories, 135 points.

---

## Epic A — Character Choice

> Removes the gender bias the adviser flagged. Note the profile model *already*
> stores `male | female | prefer_not_to_say`, so a two-option boy/girl picker
> would be less inclusive than what is already shipped.

### STAR-A1 — Choose the character during setup · 5 pts · M1 · AUM-247

> As a **parent**, I want to choose which character guides my child during profile
> setup, so the character reflects my child rather than a default someone else picked.

- All three shipped characters — BPS, Lexianne, Reiz — with equal visual
  prominence and identical card size.
- **No option is preselected** and none is labelled "recommended".
- Backgrounds behind the three cards are the **same colour**. No pink/blue coding —
  the palette is the actual bias vector, not the character.
- Each character's name is spoken on tap, using the existing voice-over pipeline.
- The step is skippable; skipping assigns a character at random, not a fixed default.
- Selection persists to the child profile as `character_id`.

### STAR-A2 — Change the character later · 2 pts · M1 · AUM-248

> As a **parent**, I want to change my child's character from Settings, so a choice
> made before I knew my child's preference isn't permanent.

- Reachable from parent-mode Settings.
- Stars, unlocks and equipped costume all survive the change.
- Takes effect on next screen build; no restart.

### STAR-A3 — Character never derived from recorded sex · 3 pts · M1 · AUM-249

> As a **parent**, I want my child's recorded sex to stay assessment data only, so
> the app never assumes which character my child wants.

- No code path reads `ChildSex` to select, default, filter or order characters.
- A unit test asserts all three characters are offered for every value of
  `ChildSex`, including `null` and `preferNotToSay`.
- Recorded sex remains available to the assessment/ML layer, unchanged.

### STAR-A4 — Character choice is voiced · 3 pts · M2 · AUM-250

> As a **child**, I want to hear the characters' names, so I can choose without
> reading.

- Name lines generated for en / tl / ceb through the existing `voice_gen` pipeline.
- Falls back to silent-but-usable if a locale's audio is missing.

---

## Epic B — Earning Stars

### STAR-B1 — Fixed stars for finishing a game · 5 pts · M1 · AUM-251

> As a **child**, I want to earn the same stars whenever I finish a game, so playing
> is what earns them and I always know what to expect.

- Completing any game awards **exactly 3 stars**.
- The award does **not** vary with score, accuracy, error count, hints, retries or time.
- A session finished with zero correct answers still awards the full 3 stars.
- No bonus, multiplier, jackpot or variable-ratio award exists anywhere in the code.
- A test enumerates award amounts across a matrix of session outcomes and asserts
  they are all identical.

> **Why effort-contingent, not accuracy-contingent:** accuracy-based points punish
> exactly the children this app exists for, and they corrupt the assessment — a
> child optimising for stars stops responding honestly, which is the signal
> `gameplay_session` is collecting.

### STAR-B2 — A calm star-earned moment · 3 pts · M1 · AUM-252

> As a **child**, I want to see my stars go up after I finish, so the reward is
> connected to what I just did.

- Plays **after** the existing celebration overlay finishes, never on top of it.
- Runs ≤ 2 seconds.
- Honours `animationIntensity` and the platform reduced-motion setting.
- Uses the existing `3_star.ogg`; silent when SFX volume is 0.
- Nothing flashes, strobes or zooms.

### STAR-B3 — Published earn rules · 2 pts · M1 · AUM-253

> As a **parent**, I want to see exactly what earns stars, so I can explain the
> system to my child and keep it predictable.

- A static "How stars work" panel in parent mode lists every earn rule and amount.
- Generated from the same constants the award logic uses, so it cannot drift.

### STAR-B4 — Daily star cap · 3 pts · M1 · AUM-254

> As a **parent**, I want a daily limit on stars, so the shop never becomes a reason
> to keep my child on the tablet longer.

- Configurable daily cap, default 15 (five games).
- At the cap, games remain fully playable and still celebrate normally.
- The message is **"You've got all of today's stars!"** — a completed state, never
  a lockout, a warning, or a greyed screen.
- Coordinates with `screen_time_service` rather than duplicating its state.

### STAR-B5 — Stars are never lost · 2 pts · M1 · AUM-255

> As a **child**, I want to keep every star I earn, so nothing I've done can be
> taken back.

- No expiry job, no decay, no streak that can break, no daily-login requirement.
- The only negative ledger entry the app can write is a purchase.
- A test asserts no code path produces a negative delta with a non-purchase reason.

> Loss aversion in a child prone to dysregulation is a meltdown, not a retention
> mechanic.

### STAR-B6 — Assessments earn stars too · 2 pts · M1 · AUM-256

> As a **child**, I want the assessment activities to earn stars like the games do,
> so the part that feels like a test isn't the part that gives me nothing.

- Pre- and post-assessment runs award the same fixed amount, on completion only.
- Granted after the run is scored, so it cannot influence responses.
- An abandoned run awards nothing but is not penalised.

---

## Epic C — The Star Shop

### STAR-C1 — Browse every costume · 5 pts · M1 · AUM-257

> As a **child**, I want to see all the costumes including the ones I can't have
> yet, so I know what I'm working towards.

- All costumes always visible: Teddy, Panda, Fox, Koala, Frog, Unicorn, Octopus,
  Rabbit, Pig.
- Unaffordable items render in **full colour** with a progress ring.
- **No** padlock icon, **no** greyscale, **no** dimming, **no** sad or disappointed
  mascot reaction. Consistent with the `MascotGesture.oops` rule — the app never
  models distress at a child.
- Owned items are clearly marked as owned.

### STAR-C2 — Progress, not just a number · 3 pts · M1 · AUM-258

> As a **child**, I want to see how close I am to the next costume, so I can tell
> without being able to read numbers.

- Progress toward each item is shown as a filled ring or bar.
- The numeral is secondary, never the only indicator.
- Progress is spoken on tap ("Two more games until Panda").

### STAR-C3 — Preview before buying · 3 pts · M1 · AUM-259

> As a **child**, I want to see the costume on my character before I spend my stars,
> so I don't get a surprise.

- Tapping a costume shows the child's *own* character wearing it, full size.
- Preview works for unaffordable items too.
- Preview is free and repeatable.

### STAR-C4 — Buy a costume · 5 pts · M1 · AUM-260

> As a **child**, I want to buy a costume I can afford and wear it right away, so
> the stars turn into something real.

- One confirm step, phrased as a choice not a warning ("Get Panda?" / "Not yet").
- Purchase is immediate; the costume is equipped on confirm.
- Ledger entry written with reason `purchase` and the item id.
- Idempotent — a double tap cannot buy twice.

### STAR-C5 — Fixed, honest prices · 3 pts · M1 · AUM-261

> As a **parent**, I want prices to be fixed and identical every time, so the shop
> can't manipulate my child.

- Prices come from a static catalogue constant.
- No sales, countdowns, dynamic or personalised pricing, mystery items, or loot
  boxes of any kind.
- A test asserts the catalogue is immutable at runtime.

### STAR-C6 — Parent approval for purchases · 5 pts · M2 · AUM-262

> As a **parent**, I want the option to approve purchases, so my child doesn't spend
> everything on the first costume and regret it.

- Off by default; when on, purchases route through the existing
  parent-verification dialog.
- While awaiting approval the item shows as "asked", not "denied".

### STAR-C7 — Own it forever, on any device · 3 pts · M2 · AUM-263

> As a **parent**, I want costumes we've unlocked to be there on any device we sign
> into, so nothing we earned is tied to one tablet.

- Unlocks are monotonic — once owned, never removed by a sync.
- Signing in on a second device restores every unlock.

---

## Epic D — Wardrobe

### STAR-D1 — Wear and remove costumes · 3 pts · M1 · AUM-264

> As a **child**, I want to put on any costume I own and take it off again, so I can
> change my mind.

- Any owned costume can be equipped; "no costume" (base outfit) is always available.
- Switching is instant and free.

### STAR-D2 — Costume appears everywhere · 5 pts · M1 · AUM-265

> As a **child**, I want my character to wear my costume everywhere in the app, so it
> actually feels like mine.

- Renders in the child-mode lobby, the profile card, and the star shop.
- M1 scope: **static art only** — in-game animated mascot stays in base outfit
  until STAR-F2.
- Missing costume art degrades to the base character rather than an empty frame,
  matching the existing `SheetSpec.optional` philosophy.

### STAR-D3 — Every costume fits every character · 2 pts · M2 · AUM-266

> As a **parent**, I want every costume available to every character, so the app
> never suggests some costumes belong to some children.

- The full 3 × 9 matrix is reachable; art exists for all 27 combinations.
- No costume is filtered by character, by `ChildSex`, or by anything else.
- A test asserts catalogue availability is identical across all three characters.

### STAR-D4 — Costume choice persists · 2 pts · M2 · AUM-267

> As a **child**, I want my costume to still be on next time I open the app.

- Equipped costume stored on the child profile and synced.
- Survives app restart, sign-out/in, and device change.

---

## Epic E — Data & Integrity

### STAR-E1 — Append-only star ledger · 8 pts · M1 · AUM-268 · **START HERE**

> As a **parent**, I want stars earned offline to survive coming back online, so my
> child never loses what they earned on the way home.

- `child_star_ledger (id, child_id, delta, reason, game_session_id, created_at, synced)`.
- Balance is **derived by summing the ledger** — there is no `star_balance` column
  anywhere.
- Two devices earning offline and then syncing produce the sum of both, not the
  later of the two.
- Local SQLite mirrors the schema with the existing `synced` flag pattern.

> A balance column under last-write-wins sync silently deletes stars. In this app
> that is a meltdown and a parent bug report, not a rounding error.

### STAR-E2 — Re-sync never double-awards · 3 pts · M1 · AUM-269

> As a **parent**, I want a retried upload to not inflate my child's stars, so the
> numbers stay honest.

- Unique constraint on `(child_id, game_session_id, reason)` for earn rows.
- Re-uploading an already-synced session is a no-op.

### STAR-E3 — Family-only access · 3 pts · M1 · AUM-270

> As a **parent**, I want only my family to read or change my child's stars.

- RLS policies on `child_star_ledger` and `child_unlocks` mirroring
  `20260816_family_data_rls.sql`.
- Coverage added to `supabase/tests/family_data_rls_test.sql`.
- Verified against the live database before the migration is written — some
  checked-in migrations were never applied.

### STAR-E4 — Stars can never be bought with money · 2 pts · M1 · AUM-271

> As a **parent**, I want to know the app will never sell my child a shortcut.

- No entitlement, subscription or PayMongo path grants stars.
- A test asserts the entitlement layer cannot write to the star ledger.
- Documented in the phase README and the capstone ethics section.

> Selling currency to children is an app-store kids-category risk and the single
> easiest thing for a panellist to attack. Keeping the two systems disjoint is
> cheaper than defending the alternative.

---

## Epic F — Art Pipeline

### STAR-F1 — Costume art in the shop · 3 pts · M1 · AUM-272

> As a **child**, I want to see what each costume looks like before I choose it.

- The 27 generated PNGs wired into `packages/assets` and the shop grid.
- Thumbnails generated at shop size; source art untouched.

**Notes** — art already generated by `scripts/generate_costumes.py`; lives in
`packages/assets/images/Character/Character_Costume/{Animal}/`.

### STAR-F2 — Costume on the mascot's rest pose · 8 pts · M2 · AUM-273

> As a **child**, I want my character to be wearing my costume during games, not
> just in the menus.

- The equipped costume replaces the mascot's rest/idle frame in-game.
- Gestures continue to play from the base sheets (mismatch accepted for M2).
- Falls back to the base character when costume art is missing.

> The cheap 80% of STAR-F3. Ship this and measure whether the full sheets are
> worth it.

### STAR-F3 — Full animated costume sprite sheets · 21 pts · M3 · AUM-275 · **DECIDE FIRST**

> As a **child**, I want my character to move and celebrate in my costume.

- Nine sheets per costume per character through `generate_sprites.py`.

**Read before committing.** The real action set is **21** sheets per character, at
**164 credits per clip** (`scripts/SPRITES.md`). 27 costumes × 21 actions ×
164 ≈ **93,000 credits**. This is the single largest cost in the phase and it is
why F2 exists as the cheap alternative. Cost **accessory overlays** first — one
hood-and-ears PNG per costume composited over the existing sprites works across
every pose and every character for 9 assets instead of 567.

### STAR-F4 — Upscale costume source art · 2 pts · M3 · AUM-274

> As the **team**, we need costume art at base-chibi resolution before cutting
> sprite sheets.

- Costume PNGs are 864 × 1184; base chibis are ~1700 × 2500.
- Upscale pass to match, before any sheet is cut.
- Blocks STAR-F3.

---

## Epic G — Parent Visibility

### STAR-G1 — Star history · 3 pts · M2 · AUM-276

> As a **parent**, I want to see what my child earned and when, so I can talk with
> them about it.

- Parent dashboard lists ledger entries with date, activity and amount.
- Read-only; a parent cannot edit the ledger by hand.

### STAR-G2 — Hide the shop · 3 pts · M2 · AUM-277

> As a **parent**, I want to turn the shop off entirely, so my child can focus on the
> games if the shop becomes a distraction.

- Parent-mode toggle hides the shop entry point completely.
- Stars continue to accrue while hidden, so nothing is lost by turning it off.

### STAR-G3 — Shop is not always open · 2 pts · M2 · AUM-278

> As a **parent**, I want the shop to appear at the end of a session rather than
> mid-play, so my child doesn't fixate on it instead of playing.

- Entry point available from the lobby and the end-of-session screen only.
- Not reachable from inside a game.

---

## Epic H — Evaluation (capstone)

### STAR-H1 — Measure whether the token board works · 8 pts · M3 · AUM-279

> As the **team**, we want to know whether the star system changed behaviour, so the
> capstone has a findings section rather than a feature list.

- Session completion rate and return rate compared before/after, from data
  `gameplay_session` already collects.
- Sample, period and method written down **before** the feature ships, so the
  comparison isn't retrofitted.

---

## Known gap not yet in the backlog

**Lexianne has no sprite sheets.** BPS and Reiz have 21 each in
`packages/shared_ui/assets/characters/`; Lexianne has zero. She is offered as a
character but is static, which blocks STAR-A1's "equal prominence" criterion.

Her sheets cost ~3,444 credits (21 clips × 164) and require a prerequisite: her
current `Lexianne_chibi.png` is an open-mouth smile with arms slightly out, which
makes a poor rest pose that every action inherits. Generate a dedicated
closed-mouth, arms-down rest pose first — the prompt is already written in
`packages/assets/images/Character/Future_Prompt for lexianne.txt`.

File this as a sub-task under AUM-246 before starting STAR-A1.

## Critical path for M1

```
STAR-E1 → STAR-B1 → STAR-C1 → STAR-C4 → STAR-D2
```

Start with the ledger. Every other story writes through it.

## Open decisions

1. **Who spends** — child buys freely (more motivating) vs parent approves (fewer
   regrets). STAR-C6 makes it a toggle; the *default* still needs a decision.
2. **Numerals or progress only** — how much the numeral appears for pre-literate
   children.
3. **F3 vs accessory overlays** — decide before any sprite credits are spent.

## Asset provenance

Costume art: `scripts/generate_costumes.py`, kie.ai `google/nano-banana-edit`,
4 credits per image. Raw generations cache to `~/.cache/aumazing/costumes`
(deliberately outside the repo — an in-repo cache was destroyed by a
`git clean -fd` along with the finished art, turning a free re-install into a
regeneration). Re-installing from cache is free; use `--force` only to re-roll.
