# Mascot sprite sheets — generation pipeline

How the BPS / Reiz / Lexianne animation sheets are made, and the rules that
keep them usable. Read this before touching `generate_sprites.py`; most of the
constraints below were learned by burning credits on takes that had to be
thrown away.

---

## TL;DR

```bash
export KIE_API_KEY=...                     # never commit; rotate if leaked
python scripts/generate_sprites.py reiz               # all actions
python scripts/generate_sprites.py bps --only nod,point
python scripts/generate_sprites.py reiz --compose-only   # free: rebuild from cache
python scripts/quantize_sprites.py --apply            # run once at the end
```

Output: `packages/shared_ui/assets/characters/{name}_{action}.png`
Rejected takes: `.../characters/Archive/` (gitignored, not bundled)
Clips + frames cache: `.sprite_cache/` (gitignored)

---

## The service

**kie.ai**, model `bytedance/seedance-2` (image-to-video). We generate a short
locked-camera *clip* per action, then cut frames out of it. Video rather than
one image per frame because identity, lighting and colour stay locked across a
clip — which is exactly the consistency a sprite sheet needs, and what
per-image generation cannot give you.

| | |
|---|---|
| Create | `POST https://api.kie.ai/api/v1/jobs/createTask` |
| Poll | `GET  https://api.kie.ai/api/v1/jobs/recordInfo?taskId=…` |
| Upload | `POST https://kieai.redpandaai.co/api/file-base64-upload` |
| Credits | `GET  https://api.kie.ai/api/v1/chat/credit` |
| Cost | **164 credits** per 4 s @ 720p clip |
| Time | 80–360 s per clip; 4 run concurrently |

### Two documented facts that are wrong

1. **Uploads are NOT on `api.kie.ai`.** The docs say
   `https://api.kie.ai/api/file-base64-upload`; that returns 404 behind a
   misleading `502`. The working host is `kieai.redpandaai.co`. Uploaded files
   expire after ~3 days, which is fine — we re-upload every run.
2. **`first_frame_url` and `reference_image_urls` are mutually exclusive.**
   Sending both is a `422`. We use `first_frame_url`, which pins frame 1 to the
   exact source artwork.

---

## Invariants — do not break these

**Every action starts from the character's canonical rest frame.**
`rest_frame()` builds it from cell 0 of that character's `_idle.png` (or, for a
brand-new character, `from_image` artwork). All sheets therefore begin and end
on the same pose, so `CalmMascot` hands off between them without a pop.

**`REST_FILL = 0.66`.** The rest frame is padded so the character fills only
two-thirds of the height. seedance creeps closer over a clip; without headroom
it crops the feet. This one line is the difference between a usable sheet and a
rejected one — it was the root cause of **13 sheets (~2,100 credits) being
thrown away**. Never feed a tightly-cropped sheet cell straight to the API.

**One transform per clip.** `compose()` computes a single scale and offset from
the *median* of the clip's chosen frames and applies it to all of them. Never
normalise per frame — that adds jitter which is not in the source. This is also
why the walk cycle is prompted as "walks **in place**": a character that
actually approached would change size between frames and break this assumption.

**All of a character's sheets share one cell size.** `CalmMascot` renders at a
fixed height with `BoxFit.contain`, so a sheet with different cell dimensions
makes the mascot jump in size or slide sideways mid-action. `cell_width_for()`
inherits the width the character's idle sheet already set. Guarded by
`packages/shared_ui/test/character_sprites_test.dart`.

**Games lay out below `kTopOverlayBand`** (`game_core/.../shared/game_layout.dart`).
Unrelated to generation, but the same rule of thumb applies: never shrink a
child-facing tap target to make room for chrome.

---

## Frame selection

Sheets have far fewer frames than the 97 in a clip, so *which* frames matter as
much as the clip itself. Set per action in `ACTIONS`:

| strategy | used by | what it does |
|---|---|---|
| `gesture` | wave, walk, celebrate, nod | Measures **frame-to-frame velocity** and samples only the moving span. Without this, several of the twelve frames are identical rest poses and the gesture visibly stutters. |
| `late` | point | Samples the back 55%. The pose is reached late and held; an even spread wastes most frames on the pre-gesture rest. |
| `still` | encourage, listen, sleepy, think | One frame, 60% in — settled, before drift grows. |
| `spread` | talk | Even sampling across the whole clip. The clip is in motion end to end, so `gesture` would just return all of it; and a talk sheet is never lip-synced — nothing cues it to phonemes — so what it needs is six *distinct* mouth openings to shuffle through, which an even spread over a continuous cycle gives. |
| `blink` | idle | Finds the eyes by **temporal variance** (only eyelids move, so the highest-variance pixels *are* the eyes), then takes rest / half / closed / half / open from a tight window around the second blink. |

Velocity, not difference-from-frame-0: proportions drift over a clip, so the
final rest pose no longer matches the first and a difference metric reads the
static tail as motion.

---

## Safety rails

**`SheetTooTight`** — refuses to write any sheet whose subject fills >95% of
frame height or touches the edge. That means the clip zoomed in and cropped the
character; its measured "head-to-feet" height is really head-to-frame-edge, so
the scale normalisation would be silently wrong. Rejected sheets are moved to
`Archive/` with a reason and timestamp rather than overwritten — a bad take is
usually the fastest way to see what the model did wrong, and it cost money.

**`body_mask()`** — keeps only the character's largest connected component.
Video compression leaves isolated specks near frame edges; a raw min/max over
alpha reports the character as spanning the whole frame, which corrupts the
scale and trips the guard.

**Background removal** floods inward from the frame border, so it only removes
background that actually *touches* the edge. This is why white clothing
survives: Reiz's shirt and Lexianne's dress are enclosed by dark outlines and
never reach the border. A naive white key would punch holes through them.

---

## Recipes

### Add a new action

1. Add to `ACTIONS` in `generate_sprites.py`: `(cols, rows, frames, strategy, prompt)`.
   Append `STYLE` implicitly — it is added for you.
2. Add the matching `SheetSpec` to `CharacterSprites.layout`
   (`packages/shared_ui/lib/src/widgets/character_sprites.dart`).
   Mark it `optional: true` until every character's PNG exists, otherwise a
   missing sheet takes the **whole mascot** off screen.
3. Generate, eyeball the result, then `quantize_sprites.py --apply`.

### Add a new character

1. Put clean artwork somewhere under `packages/assets/images/Character/`.
2. Add a `CHARACTERS` entry with `from_image` and a pinned `cell_w`
   (BPS 406, Reiz 327 — widen for broader silhouettes).
3. `python scripts/generate_sprites.py <name>`
4. Register `static Future<CharacterSprites> <name>() => _load('<name>');` and
   add it to the test map so its geometry is enforced.

### Source artwork requirements

Pure white background, no drop shadow or gradient, full body with margin on all
four sides, arms down and hands empty, closed-mouth neutral expression, no
brand marks or logos. Whatever the rest pose is doing, every action inherits.

---

## Verifying a run

```bash
cd packages/shared_ui && flutter test test/character_sprites_test.dart
cd apps/main_app     && flutter test && flutter analyze
```

**New asset files need a full rebuild** — `flutter clean && flutter pub get &&
flutter run`. Hot reload does not regenerate the asset bundle for a path
dependency, and the mascot will simply be absent until you do.

---

## Handedness — check it on any sheet with a one-sided gesture

`SheetTooTight` catches a cropped clip. Nothing catches a **mirrored** one.

The first `bps_present` take came back flipped: the book had moved to the other
hand and the open palm reached the opposite way from `point`, so the two sheets
could not be cut together — the book teleports. It passed every automated
guard, because a mirrored character is perfectly scaled and perfectly centred.

The cause is that an open-palm reach is symmetric enough that naming a side
("its own left") does not pin the handedness; the model can satisfy the prompt
by flipping the whole character instead of moving the arm. A rigid index finger
(`point`) is asymmetric enough that it never did this. The fix is to anchor the
constraint to the **object** rather than the side — *whichever hand holds
something in the reference keeps holding it, same hand, same side, every
frame* — which is now in the `present` prompt and is the phrasing to reuse.

So: for any new one-sided gesture, put its cell next to `idle` cell 0 and check
the held object has not swapped hands before shipping it.

## Known pending work

- **Lexianne** has a `CHARACTERS` entry and pinned `cell_w: 430`, but no sheets
  generated yet (~2,130 credits for all thirteen). Her `oops` comes with the
  rest. She holds nothing, so the handedness note above does not bite for her.

## Eyeballing an `oops` take

`SheetTooTight` catches a cropped clip; nothing catches a mascot that looks
*upset*. Before shipping one, open the sheet and check the last frame has
recovered to a soft smile and that no frame shows tears, a harsh frown, or a
covered face. BPS and Reiz both passed on the first take; Reiz's middle frames
sit closer to "serious" than "sad", which is acceptable but is the direction to
watch if the prompt is ever re-run.
