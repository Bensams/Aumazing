# Star Shop follow-ups — session prompt

Tracked as **AUM-281** (BACKLOG). Paste the block below into a fresh session.

---

Finish the remaining work on the Star Shop epic (AUM-246). The feature is
implemented and in TESTING; these are the five items left. Work against `dev` —
`main` is stale and predates the monorepo.

## Where things are

- Branch `claude/star-shop-aum-246` off `dev`, commits `197ffc1` and `cc00048`.
  Worktree at `.claude/worktrees/star-shop-impl`. Nothing is pushed; no PR yet.
- 29 of 33 stories complete. `flutter analyze` clean, 615/615 tests pass.
- Read `.planning/phases/02.0-star-rewards/BACKLOG.md` for the story detail and
  the reasoning behind the design constraints. Read `scripts/SPRITES.md` before
  touching anything that generates sprites.
- `KIE_API_KEY` lives in `tools/voice_gen/.env` and nothing auto-loads it —
  source it. Use the venv at `tools/voice_gen/.venv`. Never write the key into
  a tracked file.

Do these in order. Stop and report after item 1 before spending any credits.

## 1. Verify the feature on a device — FIRST, and nothing else until it passes

Nothing in this epic has ever been run. It is verified only by static analysis
and the test suite. The shop, the character picker and the star-earned overlay
have not been seen rendering.

Assume there are layout and asset bugs the tests cannot see. One layout
assertion — `Expanded` inside a shrink-wrapping scroll view — was already
caught only because a widget test happened to exercise that screen, and the
costume art was pointing at `packages/assets/`, which has no pubspec and does
not ship at all.

Launch the app and walk these, screenshotting each:

1. Create a child profile. The character picker is on step 1, beside name and
   avatar. Confirm nothing is preselected, and all three cards are identical
   apart from the character — same size, same background colour.
2. Play any game to the end. After the celebration overlay finishes, a star
   card should appear for under two seconds, then the usual "what next?"
   choice. It must not stack on top of the celebration.
3. Tap the wardrobe icon in the child lobby. Every costume visible in full
   colour; unaffordable ones show a progress bar, never a padlock or grey.
4. Buy a costume once affordable. It should equip immediately, and the in-game
   mascot should be wearing it — teddy, panda and pig animate; the other six
   fall back to the base character in-game, which is expected.
5. Parent mode → Settings → **Stars & Costumes**: change the character (stars
   and costumes must survive), read "How stars work", toggle the shop off and
   confirm the lobby icon disappears, toggle "Ask me before buying" and confirm
   a purchase asks for parent verification.
6. Play six games in one day. The sixth awards nothing, the shop says "You've
   got all of today's stars!", and games stay fully playable.

Report what broke. Fix it before moving on.

## 2. STAR-A4 (AUM-250) — voiced character names

Asset work only. The `onSpeak` hook already exists on `CharacterPicker` and is
simply not passed a callback.

Generate one line per character — "BPS", "Lexianne", "Reiz" — for en / tl / ceb
through `tools/voice_gen`, then wire an `onSpeak` that plays them on tap. It
must stay silent-but-usable when a locale's audio is missing.

## 3. AUM-280 — Lexianne's 21 default sprite sheets

Blocking. Lexianne is offered in the picker but has no base sheets, so
`CharacterSprites.lexianne()` throws. A fallback in
`MascotCharacter.loadCostumed` currently substitutes BPS, which means a parent
who picks Lexianne gets the wrong character in-game.

Prerequisite first: her current `Lexianne_chibi.png` is an open-mouth smile
with arms slightly out, and `rest_frame()` builds every action's first frame
from it — so all 21 sheets would inherit that pose. Generate a dedicated
closed-mouth, arms-down rest pose using the prompt already written in
`packages/assets/images/Character/Future_Prompt for lexianne.txt`. Pure white
background, no drop shadow, clear margin on all four sides. Show it to me
before generating the sheets.

Then: one action as a smoke test, show me, then the remaining 20 (~3,444
credits). Afterwards `check_gaze.py lexianne` — required, the model has
inverted gaze on both other characters before — and `quantize_sprites.py
--apply`.

When every `MascotCharacter` has a full sheet set, delete the character-level
fallback in `loadCostumed`; it is commented to say so.

## 4. STAR-F3 (AUM-275) — the other six costumes' sprites

Teddy, panda and pig are animated across all three characters (189 sheets,
~31,000 credits). Fox, koala, frog, unicorn, octopus and rabbit are not; they
are bought and worn normally and fall back to the base character in-game.

**Do not start this because the budget allows it.** ~62,000 credits. Watch a
child use the three animated costumes first, and decide whether the animation
is what they actually respond to or whether the still art in the shop and menus
is doing the work. The accessory-overlay alternative — one hood-and-ears PNG
composited over the existing sprites, ~9 assets instead of 378 — is still
uncosted. Cost it before committing.

## 5. STAR-H1 (AUM-279) — the evaluation study

Session completion rate and return rate, before vs after, from data
`gameplay_session` already collects.

Write the sample, period and method down **before** the feature reaches
families. Retrofitted, the comparison is not something the capstone can claim.

## Also worth closing

STAR-F4 (AUM-274) — upscale costume art before cutting sheets. Effectively
moot: the sheets cut cleanly from the 864×1184 art at 406×490 cells, matching
the base characters exactly. Recommend closing as "not needed".

## Ground rules

- The design constraints in this feature are acceptance criteria, not styling.
  Fixed awards, no expiry, nothing greyed out, no purchasable stars. If a
  change would relax one, stop and ask.
- The star balance is `SUM(delta)` over an append-only ledger. Never add a
  balance column.
- Costume art ships through `shared_ui`, not `packages/assets/` — that folder
  has no pubspec. `scripts/bundle_costume_art.py` regenerates the bundled set.
- Sprite caches live outside the repo (`SPRITE_CACHE_DIR`, `~/.cache/aumazing`)
  because an in-repo cache was destroyed by a `git clean -fd` along with a
  day's generated art. Keep them there.
- Update AUM-281 and the relevant sub-tasks as you go.
