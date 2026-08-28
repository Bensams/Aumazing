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
python scripts/generate_sprites.py bps --only look_up,look_down_left    # gaze grid
python scripts/generate_sprites.py reiz --compose-only   # free: rebuild from cache
python scripts/check_gaze.py bps reiz lexianne        # REQUIRED after any look_* run
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
| `spread` | talk | Even sampling across the whole clip. The clip is in motion end to end, so `gesture` would just return all of it; and a talk sheet is never lip-synced — nothing cues it to phonemes — so what it needs is six *distinct* mouth openings to shuffle through, which an even spread over a continuous cycle gives. |
| `still` | encourage, listen, sleepy, think, `look_left`, `look_right` | One frame, 60% in — settled, before drift grows. |
| `blink` | idle | Finds the eyes by **temporal variance** (only eyelids move, so the highest-variance pixels *are* the eyes), then takes rest / half / closed / half / open from a tight window around the second blink. |

Velocity, not difference-from-frame-0: proportions drift over a clip, so the
final rest pose no longer matches the first and a difference metric reads the
static tail as motion.

### Gaze: nine held poses, not a sweep

The mascot follows a child's finger while they drag (`Mascot.gaze`). The art
side is eight `still` sheets — `look_left/right/up/down` and the four corners —
which with the idle rest frame form a **3x3 grid** the app indexes by where the
finger is (`CharacterSprites.gazeFrameFor`).

**Seven takes went into arriving at stills rather than an animation.** The
short version, so nobody pays for this ground twice:

| take | asked for | got |
|---|---|---|
| 1 | head turn, long motion prompt | faced forward the entire clip |
| 2 | head turn, short prompt shaped like `nod` | same; Reiz moved 1.8% of body width |
| 3 | head turn, "THREE-QUARTER VIEW" | whole **body** swung to profile; one frame showed the back of its head |
| 4 | small turn, "both eyes visible, shoulders square" | body square, turn barely there, frame 1 mid-blink |
| 5 | eyes only, polite phrasing | clean and stable, but pupils moved 0.9% of body width — **one pixel** at mascot size |
| 6 | eyes only, "EXTREME SIDE-EYE" | drew a superb extreme side-eye and then **held it** for all 97 frames |
| 7 | that same pose as `still` actions | ✅ shipped |

Three things worth keeping:

* **This model will not rotate a flat front-facing 2D chibi in depth.** Asked as
  motion it does nothing; asked with drawing vocabulary it overshoots to full
  profile. There is no reliable middle setting.
* **It will happily change one facial feature and leave everything else alone.**
  That is what `idle` (eyelids) and `talk` (mouth) already are, and a sideways
  glance is the same class of edit. This is the direction that works.
* **It holds poses far better than it sweeps between them.** Take 6 was the
  pipeline saying so out loud — an excellent pose, refusing to animate.

#### Directions are image-relative, and corners need both axes named

Two prompt lessons, each paid for in clips:

* `point` and `present` say "its own left" and land correctly mirrored on frame
  right, so the gaze prompts did the same. The model did not honour it — BPS
  came back with **both** poses inverted, Reiz looking left for **both**, twice.
  Naming the side of the **image** ("the right as the viewer sees it") fixed it
  outright: there is nothing left to mirror.
* Asked only for "the top-left corner" it delivers one axis and forgets the
  other. `_BOTH` now spells the diagonal out as two equally strong movements.

#### The eyes must stay CUTE — this is a safety property, not polish

The first `look_down` for both characters came back with the irises shrunk to
**tiny black dots adrift in huge white eyes, with dark shadows underneath**. It
is a genuinely unsettling face. This app is for autistic children and the
mascot's whole job is to be calm company, so a pose that reads as creepy or
vacant is worse than having no gaze sheet at all — and nothing else in this
pipeline would ever have caught it. `SheetTooTight` and `check_gaze.py` both
passed it happily.

The cause was the prompt asking for the glance in terms of *extremity* —
"jammed hard into the corner", "a WIDE expanse of empty eye-white". Straight
down is the one direction where the lower lid crops the iris, so pushing hard
leaves a sliver of pupil and a face full of white.

`_GAZE` now carries a CRITICAL clause that pins the **iris size** ("exactly the
same large size as in the reference image… never shrunk into small dots"), keeps
the catchlight highlights, and forbids under-eye shadows. Stating it as size
rather than as mood is what makes it work — "look cute" is not actionable, "do
not shrink the iris" is.

**Always look at a regenerated pose before shipping it.** The measurement tools
answer "which way is it looking", never "is this a face you would put in front
of a child".

#### Reiz's vertical gaze is subtle, and that is the correct trade-off

Reiz's irises fill almost the entire eye opening, leaving very little white to
shift. A pure `look_down` is therefore only ever slightly legible — the only way
to make it obvious is to shrink the iris, which is exactly the failure above.
Its diagonals read better (they borrow the horizontal axis), and `Mascot._lean`
carries the rest. Do not "fix" this by pushing harder.

#### Lexianne's vertical gaze does not pass, and that is the same trade-off

She has the same large-iris geometry, and `check_gaze.py lexianne` **exits
non-zero** on `look_up < look_down`. Read the magnitudes before spending a clip
on it:

| | look_up y | look_down y | gap |
|---|---|---|---|
| Reiz (shipped, passes) | −6.39 | −5.88 | **+0.51** |
| Lexianne | −9.39 | −10.26 | **−0.87** |

`MIN_TRAVEL` is 2.5 — the point at which a shift is visible at mascot size.
Both characters are an order of magnitude under it, so neither has a vertical
gaze that a child could perceive; Reiz merely landed on the lucky side of a ±1
noise band. Her *horizontal* axis is the strongest of the three (+15.9 against
BPS's +2.6), and her diagonals pass, so eight of the nine grid cells are doing
real work.

One re-roll of `look_down` was attempted and came back **cropped** — rejected by
`SheetTooTight`, 164 credits for nothing. Do not spend more here: the only lever
that would move the number is shrinking the iris, which is the creepy-face
failure above.

#### Verify every run — `scripts/check_gaze.py`

A wrong-way pose passes every other check here: perfectly scaled, perfectly
centred, perfectly clean. It must be measured.

```bash
python scripts/check_gaze.py bps reiz     # exits non-zero on a wrong-way pose
```

It finds each eye by its **white**, then compares each pose against its
**opposite** on the axis they disagree about.

Four traps it exists around, all of which produced confidently wrong numbers
during this work:

* **Don't locate the eyes by diffing two poses.** They come from separate clips
  whose hair and outlines differ everywhere, so the difference image lights up
  the whole head. BPS measured 0.4px of travel that way.
* **Don't measure irises in absolute pixels.** Eyebrows are dark, static and far
  larger than a pupil; any metric including them reports noise.
* **Don't reference the rest frame.** BPS's idle measures well left of its own
  `look_left` and marked four good poses as failures. Opposing pairs have no
  such anchor problem.
* **Don't trust the iris alone.** The upper lid *clips* it on any upward glance,
  which reported BPS's top corners as pointing the wrong way round when they
  plainly do not. The reading is the iris and the (never-clipped) eye-white
  averaged together.

The tool asserts **direction** and only advises on **magnitude**, for the same
reason: the sign is robust, the size is not once a lid is involved. A `weak`
line means look at the sheet, not that it is broken.

**Isolating which pose is at fault:** a failing pair names two sheets, and it is
easy to regenerate the innocent one — that happened twice here. Print the raw
values for the whole row or column before spending a clip:

```python
from check_gaze import gaze, cell
for n in ['look_up_left', 'look_up', 'look_up_right']:
    print(n, gaze(cell('bps', n)))
```

The outlier against its neighbours is the one to redo.

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
python scripts/check_gaze.py bps reiz          # direction of the gaze poses
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

### The app depends on `point` reaching frame RIGHT — check it, per character

`BuddyCharacter.pointAt` mirrors the whole character when the target is on the
left, and says why in a comment: *"the sheet points to the viewer's right, so a
target on the left mirrors the character."* A sheet that points the other way
therefore makes the buddy point **away** from every target — a functional bug
that `SheetTooTight` and `check_gaze.py` both pass happily.

Lexianne's `point` came back on frame LEFT on **two separate takes**, while her
`present` came back correctly on frame right — so the pair also disagreed with
each other. Two takes landing the same way is systematic for a character, not
the random flip a re-roll fixes, so re-rolling a third time is throwing credits
at it.

The fix is the `MIRROR` set in `generate_sprites.py`, which flips a clip's
frames before `metrics()` measures them. It is applied per (character, action)
and deliberately kept tiny:

* Mirroring is **not** available for BPS (it reverses the lettering on his
  book) or Reiz (it swaps his lapel and necklace).
* It is safe for Lexianne because she holds nothing and her outfit is
  symmetric — centred pendant, plain dress, plain sandals. Only her hair part
  changes, and the app already mirrors her wholesale at runtime.

Check any new character's `point` against `bps_point` before shipping it.

## Known pending work

- **Costume sheets** (AUM-275 / STAR-F3) are not started, and are explicitly
  flagged DECIDE FIRST. At 21 actions it is 27 × 21 = **567 sheets ≈ 93,000
  credits**; the ticket's own figure of 243 predates the gaze poses. The
  accessory-overlay alternative (STAR-F2) is ~9 PNGs.

  **The costume source art exists but is not checked out.** All 27 images
  (9 costumes × 3 characters), `scripts/generate_costumes.py` and
  `.planning/phases/02.0-star-rewards/BACKLOG.md` live in a git **stash** —
  `stash@{0}^3`, commit `524f05e5`, "untracked files on
  claude/voice-over-replay-callback". `.costume_cache/` is gitignored and the
  art was swept up by a `git stash -u`, so a plain `ls` or a `git log` over the
  working tree finds nothing and it looks like the art was never made. It was:

  ```bash
  git checkout 524f05e5 -- packages/assets/images/Character/Character_Costume scripts/generate_costumes.py
  ```

  Restore it before costing STAR-F3 — it means the costumed REST POSES already
  exist, which is the expensive input to the overlay approach.

## Eyeballing an `oops` take

`SheetTooTight` catches a cropped clip; nothing catches a mascot that looks
*upset*. Before shipping one, open the sheet and check the last frame has
recovered to a soft smile and that no frame shows tears, a harsh frown, or a
covered face. BPS and Reiz both passed on the first take; Reiz's middle frames
sit closer to "serious" than "sad", which is acceptable but is the direction to
watch if the prompt is ever re-run.
