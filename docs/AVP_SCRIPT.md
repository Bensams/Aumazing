# Activity 8 — Capstone AVP script & shot list

Target runtime **4:20** (brief allows 3:00–5:00). Narration below is timed at a
calm ~135 wpm; read it slower than feels natural, the pauses are where the
screen recording breathes.

Covers all five required sections in order: **1** intro, **2** problem &
solution, **3** feature walkthrough, **4** resources & responsible use,
**5** closing / call to action.

Assets referenced as `cutouts/<tag>.mov` come from
`python scripts/generate_avp.py cutouts` — alpha-channel clips of BPS and Reiz,
already generated, no credits. `shots/<name>.mp4` are the optional 16:9 hero
scenes from `generate_avp.py shots` — those cost credits. Run
`python scripts/generate_avp.py --help` for both; the API quirks are documented
in `scripts/SPRITES.md`.

> **Fill in before recording:** proponent names and who did what (the brief
> wants this in the YouTube caption), and confirm the AI-disclosure list in
> §4 matches what you actually used. Everything else below is drawn from the
> manuscript.

> **The narration below is the long form.** `BLOCKS` in
> `scripts/generate_avp_voice.py` holds the **trimmed** version that was
> actually recorded — measured TTS pace is ~119 wpm, and the full text above
> ran 5:26 of speech, past the hard 5:00 limit. The trim is ~20% shorter and
> lands the finished cut at 4:06. Treat `BLOCKS` as authoritative for timing;
> read this file for the fuller phrasing if you are re-recording in your own
> voice and want more room.

---

## 1 — Introduction (0:00 – 0:35)

| | |
|---|---|
| Visual | Title card on the app's calm background. `cutouts/bps_wave.mov` bottom-left, `cutouts/reiz_wave.mov` bottom-right, both waving. Title "Aumazing" fades up between them. Optionally `shots/title.mp4` instead. |
| Audio | Soft, low-tempo bed. Keep it quiet — the app is built for low sensory load and the video should match. |

> "Hi po! We're **[names]**, BSIT students from Assumption College of Davao.
> This is **Aumazing** — a gamified learning app for children with Autism
> Spectrum Disorder, built around each child's own skill level rather than
> their age.
>
> These two are **BPS** and **Reiz**. They're the characters who guide the
> child through every activity in the app, and they'll walk you through this
> presentation too."

*Beat. Let the wave finish before cutting.*

---

## 2 — The problem & the solution (0:35 – 1:40)

### The problem (0:35 – 1:10)

| | |
|---|---|
| Visual | `cutouts/bps_think.mov` or `shots/problem.mp4` at frame-left. Frame-right: simple text cards, one figure at a time. No stock photos of real children. |
| Cards | `₱700–800` per therapy session · `3 hours a day` · `₱42,000–48,000 a month` · `DCSNICC: ~1,160 clients, citywide` |

> "In Davao City, one occupational therapy session costs around seven to eight
> hundred pesos. A child who needs three hours a day can cost a family more
> than forty thousand pesos a month.
>
> The Davao City Special Needs Intervention Center for Children offers therapy
> for free — but it serves around 1,160 clients for the whole city, so many
> families end up waiting.
>
> And here's the part that's easy to miss: early intervention only works with
> **daily repetition**. Between clinic visits, that falls on the parents —
> usually the mother. Without proper tools, she's guessing which activity to
> do today, and spending hours preparing it."

### The solution (1:10 – 1:40)

| | |
|---|---|
| Visual | Animated flow, one node at a time: **Pre-assessment → AI recommends modules → Post-assessment**. `cutouts/reiz_point.mov` pointing at the flow as each node appears. |

> "Aumazing replaces that guesswork. The child plays a short **gamified
> pre-assessment**. The app watches how they play — accuracy, response time,
> how many retries — and an AI model turns that into a skill level for
> communication, social, and play.
>
> From that, it **recommends which learning modules to do next**. The child
> plays them, then takes a post-assessment so the parent can see what actually
> changed.
>
> No worksheets to prepare. No guessing. Just: open the app, play what it
> says."

---

## 3 — Key features walkthrough (1:40 – 3:20)

**This is the section that must be real screen recording**, not slides.
Record on a physical Android device or emulator at 1080p. Keep BPS or Reiz as
a small corner overlay (`cutouts/*_idle.mov`, ~15% height, bottom-right) so the
characters stay present without covering the UI.

Suggested capture order — roughly 15 seconds each:

| # | Screen | What to show | Say |
|---|---|---|---|
| 1 | Child profile + sensory preferences | Creating a child, setting comfort options | "First, the parent sets up the child's profile and their sensory preferences — reduced motion, quieter sound. The app adapts to the child, not the other way around." |
| 2 | A mini-game (**Do What I Say** or **Match It**) | One full round: prompt → child taps → immediate feedback | "Every game is one clear instruction, one response, immediate feedback. That structure comes from ABA's Discrete Trial Training — and it's also how the app collects its data." |
| 3 | A second game (**Copy Me** / **My Turn, Your Turn**) | Show BPS or Reiz reacting in-game | "Notice BPS reacting. When the child gets it wrong, he never looks upset — just gently encouraging, then they try again." |
| 4 | Result / reward screen | Skill bands, then the recommended modules | "After the cycle, here's the recommendation — and it's explained in plain language, not scores the parent has to decode." |
| 5 | Parent dashboard | Basic dashboard, then Advanced (premium) trend lines | "Parents get a dashboard showing progress per domain, plus screen-time limits they control." |
| 6 | Therapy locator | Free view (name + city) → Premium map, nearest-first, then the hand-off to Google Maps | "And the therapy directory. Free users see the centers. Premium ranks them by actual distance and hands you off to your maps app for directions." |
| 7 | **Airplane mode** | Toggle it on, keep playing, show the pending/sync banner | "One more thing, and it matters here: turn the internet off — and the games keep working. Everything saves locally and syncs when you're back online." |

> The offline demo is the strongest 10 seconds in the video. Don't cut it for
> time; cut a game instead.

---

## 4 — Resources & responsible use (3:20 – 3:55)

| | |
|---|---|
| Visual | `cutouts/reiz_encourage.mov` or `shots/credits.mp4` at frame-left; a clean list building line by line at frame-right. |

> "We want to be honest about what we built and what we used.
>
> Aumazing is built with **Flutter and the Flame engine**, with **Supabase**
> for the cloud database and **SQLite** on the device for offline storage. The
> assessment model is **XGBoost**, and payments go through **PayMongo**. The
> therapy locator uses the **Google Maps SDK** with the Haversine formula for
> distance. All of these are used under their published licenses — the
> open-source components under permissive licenses, and the paid services
> under their standard developer terms.
>
> We also used **AI assistance**. Our characters BPS and Reiz were drawn as
> original artwork for this project, and their animations were generated from
> that artwork using an image-to-video model through the **kie.ai** API. We
> used **AI coding assistants** during development. Every AI-generated asset
> and every suggested change was reviewed by us before it went into the
> project, and the design decisions, the research, and the manuscript are our
> own.
>
> No real child's data appears anywhere in this video."

**Verify each line before recording.** Cut anything you didn't actually use;
add anything missing. An honest short list beats an impressive wrong one, and
this section is explicitly graded on honesty.

---

## 5 — Closing / call to action (3:55 – 4:20)

| | |
|---|---|
| Visual | `cutouts/bps_celebrate.mov` + `cutouts/reiz_celebrate.mov`, or `shots/closing.mp4`. End card holds on the last frame: app name, proponents, contact. |

> "Aumazing is working today — the games, the assessment, the dashboard, and
> the offline mode all run on a real device.
>
> Next, we're moving into **testing with parents and children here in Davao**,
> and we'd like to coordinate with therapy centers so the directory reflects
> what's actually available in the city.
>
> If you're a parent, a therapist, or a center — we'd genuinely like your
> feedback. Ang goal namin is simple: that a parent at home, on any ordinary
> Tuesday, knows exactly what to do next with their child.
>
> Thank you po for watching."

*Hold the end card 3 seconds past the last word.*

---

## Production notes

**Record narration separately** from the screen capture, then lay picture under
it. Trying to narrate live while demoing is what pushes these videos past five
minutes.

**Lip sync is automatic and re-runs against any voice.** `scripts/lipsync.py`
measures the narration's loudness per video frame and picks the matching mouth
from the `talk` sheet's six openings. It is amplitude-driven, not phoneme-
driven — the same thing hand-drawn animation has always done for dialogue, and
at mascot size it is indistinguishable from true visemes. **When you replace
the scratch narration with your own recording, just re-run `build_avp.py`; the
mouths re-sync to your voice for free.**

Shots opt in via `"lip:<name>"` in `SHOTS`. Narrator "a" is BPS and narrator
"b" is Reiz, so the character whose mouth moves is the one being heard — swap
that mapping and it reads as the wrong character speaking, which is worse than
no lip sync. Gesture shots (`wave`, `oops`, `point`, `celebrate`) deliberately
keep their own clip: the gesture is the point of those, and the head moves
through them, so a substituted mouth would not track the face.

The AI lip-sync models on kie.ai (InfiniteTalk, OmniHuman) were not used. Both
target photorealistic human faces; a chibi face with huge eyes and a mouth a
few dozen pixels wide is the case that makes them redraw the face realistically
or miss the mouth entirely. The sprite approach cannot break the art style
because it only ever shows cells that were already drawn.

**Character clips are 4 seconds at 24fps.** For a longer hold, reverse-loop
(ping-pong) the clip — every action starts and ends on the same rest pose, so
it loops seamlessly. `*_idle.mov` and the single-pose clips (`encourage`,
`listen`, `think`, `sleepy`) are the ones to use for long holds; save
`wave`, `celebrate`, `nod`, `point` for punctuation.

**Available cutouts:** `idle`, `talk`, `wave`, `walk`, `celebrate`, `nod`,
`point`, `present`, `oops`, `encourage`, `listen`, `sleepy`, `think` — for both
`bps` and `reiz`.

**`talk` is the one to use whenever a character is on screen at full size while
you narrate** — a static mouth under four minutes of voice-over is what makes a
character read as a still image. Cycle it for the length of the line and cut
back to `idle` on the pause. At the ~15% corner size used during the demo it
doesn't matter, so don't bother there.

**`present` and `point` both gesture to frame-RIGHT**, so put your screen
capture on the right of the composition. `present` is the open palm — use it to
hand off to the demo; `point` is the index finger — use it to call out one
specific thing. Do not mirror either clip to gesture leftward: it reverses the
lettering on BPS's book and swaps Reiz's lapel and necklace.

**Export** 1920×1080, 24 or 30fps, H.264, then upload to YouTube as *Unlisted*
with link sharing on. Put the group member names and contributions in the
video description, and paste the link in Classroom.

## Scope: the AVP is ahead of the manuscript

This video says Aumazing serves **children with ASD generally, matched by skill
level rather than age**. The manuscript does not say that yet. Chapter 1's
delimitation still reads:

> "The system targets children aged **two to six** with early-stage ASD; older
> children, severe profiles, and adult ASD are out of scope."
> — `docs/Manuscript_Revision2_Chapter1.md:171`

The phrase "children aged two to six with early-stage ASD" also appears in the
general objective and in the scope section, and the title on the PDF cover page
is *"...for Children with Early Childhood Autism Spectrum Disorder."*

**Fix the manuscript before submitting both together**, or a panelist reading
the document while watching the video will land on the contradiction
immediately. Broadening scope also has knock-on effects worth thinking through
once: the ML model was trained and the games were designed against the narrower
population, so widening the claim widens what you have to defend.

## One inconsistency to be aware of

The manuscript describes the AI service two different ways: Chapter 1 (scope)
says the XGBoost model is **served on-device via ONNX Runtime Mobile**, while
Chapter 3.3.1 says it is **hosted in the cloud via FastAPI**. The repo has
`ai_assessment/training/export_onnx.py`, which points to the on-device route.
Say whichever is actually true in the demo, and fix the manuscript before
final defense — a panelist who reads both will ask.
