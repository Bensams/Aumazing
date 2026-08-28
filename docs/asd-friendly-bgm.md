# ASD-friendly background music library

60 instrumental background tracks across 6 parent-selectable categories, generated for Aumazing via the kie.ai Suno `V5_5` API. Every track is designed as a *bed* — something a child can have running for twenty minutes without it ever demanding attention or producing a startle.

> **Licence status: unresolved.** These files are KIE-generated and fall under exactly the same open question as the voice library — see [audio-licensing.md](audio-licensing.md) §1. Do not ship them commercially until KIE's position on redistribution is in writing.

## Why these constraints

Autistic children show elevated rates of auditory hypersensitivity and of distress at unpredictable sound. The design rules below follow from that: the risk in a children's game is not that the music is boring, it is that the music *startles*, masks the voice-over, or adds sensory load on top of the task the child is trying to do.

| Rule | Why |
|---|---|
| **Instrumental only, no vocals** | Lyrics compete with the app's spoken prompts for the same language-processing channel, and the voice-over is the part that carries the instruction. |
| **56–80 BPM, never changing** | Sits at or below resting heart rate. A constant tempo means the child's prediction of what comes next is never violated. |
| **Narrow loudness range (target ≤7 LU)** | No crescendos, no swells, no sudden accents — the single most common startle source in game music. Measured per track below. |
| **No percussion or transients** | Drum hits, cymbals and stabs are sharp onsets. Soft, rounded attacks (felt piano, mallets, pads) are not. |
| **Treble shelved −4 dB above 6 kHz, low-passed at 13 kHz** | Auditory hypersensitivity is most often reported in the upper frequencies. |
| **Normalised to −20 LUFS** | Deliberately quiet, so music never competes with speech. The voice-over stays clearly on top at any music volume. |
| **Seamless loop, no fade to silence** | The tail is crossfaded into the head, so a 20-minute session has no repeating dip to silence to notice. |
| **Consonant, simple, repeating** | Predictability is the point. No key changes, no dissonance, no development. |

Two of these are enforced mechanically rather than by prompting: loudness and the loop join are done in post with ffmpeg, because a generative model cannot be trusted to hit them reliably.

## Categories

Categories differ by *arousal level and timbre*, not by how strictly the rules apply — the rules above hold for all of them. This is what the parent picker should expose, ideally with the guidance text as a subtitle.

### Soft & Relaxing  (`soft_relaxing`)

Lowest-arousal category. Sustained, slow, almost motionless. For children who are easily over-stimulated, or for winding down after a session.

| # | Track | Length | Loudness | Range |
|---|---|---|---|---|
| 1 | Felt Piano Rest 1 ⚠️ | 100s | -20.0 LUFS | 7.1 LU |
| 2 | Felt Piano Rest 2 ⚠️ | 86s | -20.0 LUFS | 7.7 LU |
| 3 | Warm Strings Haze 1 | 98s | -20.0 LUFS | 6.0 LU |
| 4 | Warm Strings Haze 2 | 101s | -20.0 LUFS | 6.2 LU |
| 5 | Soft Harp Drift 1 ⚠️ | 78s | -20.0 LUFS | 7.7 LU |
| 6 | Soft Harp Drift 2 | 77s | -20.0 LUFS | 5.8 LU |
| 7 | Quiet Guitar Room 1 | 77s | -20.0 LUFS | 4.2 LU |
| 8 | Quiet Guitar Room 2 | 93s | -20.0 LUFS | 4.2 LU |
| 9 | Breathing Pad 1 | 75s | -20.0 LUFS | 4.5 LU |
| 10 | Breathing Pad 2 | 82s | -20.0 LUFS | 5.2 LU |

### Nature & Ambient  (`nature_ambient`)

Soft tonal music layered with steady natural texture. The constant broadband texture masks unpredictable household noise, which many sound-sensitive children find easier than silence.

| # | Track | Length | Loudness | Range |
|---|---|---|---|---|
| 1 | Gentle Rainfall 1 | 80s | -20.0 LUFS | 3.6 LU |
| 2 | Gentle Rainfall 2 ⚠️ | 84s | -20.0 LUFS | 8.0 LU |
| 3 | Morning Garden 1 | 102s | -20.0 LUFS | 6.0 LU |
| 4 | Morning Garden 2 | 107s | -20.0 LUFS | 4.8 LU |
| 5 | Slow Ocean 1 | 95s | -20.0 LUFS | 4.7 LU |
| 6 | Slow Ocean 2 | 77s | -20.0 LUFS | 4.1 LU |
| 7 | Forest Light 1 | 101s | -20.0 LUFS | 3.3 LU |
| 8 | Forest Light 2 | 97s | -20.0 LUFS | 3.1 LU |
| 9 | Small Stream 1 | 90s | -20.0 LUFS | 5.6 LU |
| 10 | Small Stream 2 | 76s | -20.0 LUFS | 3.7 LU |

### Gentle Playful  (`gentle_playful`)

Mildly energising without becoming stimulating. Slightly brighter and more rhythmic, for children who disengage when music is too still. Still no percussive transients.

| # | Track | Length | Loudness | Range |
|---|---|---|---|---|
| 1 | Happy Marimba 1 | 85s | -20.0 LUFS | 3.2 LU |
| 2 | Happy Marimba 2 | 75s | -20.0 LUFS | 2.6 LU |
| 3 | Bouncy Pizzicato 1 ⚠️ | 99s | -20.0 LUFS | 4.8 LU |
| 4 | Bouncy Pizzicato 2 | 84s | -20.0 LUFS | 3.2 LU |
| 5 | Sunny Ukulele 1 | 56s | -20.0 LUFS | 3.3 LU |
| 6 | Sunny Ukulele 2 ⚠️ | 99s | -20.0 LUFS | 5.0 LU |
| 7 | Toy Xylophone Walk 1 | 75s | -20.0 LUFS | 3.6 LU |
| 8 | Toy Xylophone Walk 2 | 96s | -20.0 LUFS | 4.9 LU |
| 9 | Little Whistle Tune 1 | 110s | -20.0 LUFS | 2.2 LU |
| 10 | Little Whistle Tune 2 | 95s | -20.0 LUFS | 4.0 LU |

### Lullaby & Music Box  (`lullaby_music_box`)

Familiar, highly predictable nursery timbres. Strongest cue for 'settle down' — useful for transitions, calm corners and the end of a play session.

| # | Track | Length | Loudness | Range |
|---|---|---|---|---|
| 1 | Music Box Circle 1 | 81s | -20.0 LUFS | 3.6 LU |
| 2 | Music Box Circle 2 | 89s | -20.0 LUFS | 3.5 LU |
| 3 | Celesta Cradle 1 | 81s | -20.0 LUFS | 3.5 LU |
| 4 | Celesta Cradle 2 | 80s | -20.0 LUFS | 3.4 LU |
| 5 | Kalimba Sleep 1 | 79s | -20.0 LUFS | 2.5 LU |
| 6 | Kalimba Sleep 2 | 113s | -20.0 LUFS | 4.5 LU |
| 7 | Humming Bells 1 | 81s | -20.0 LUFS | 2.9 LU |
| 8 | Humming Bells 2 | 85s | -20.0 LUFS | 3.0 LU |
| 9 | Cradle Piano 1 ⚠️ | 79s | -20.0 LUFS | 7.1 LU |
| 10 | Cradle Piano 2 ⚠️ | 114s | -20.0 LUFS | 4.2 LU |

### Focus & Minimal  (`focus_minimal`)

Deliberately uneventful. A steady, near-static bed with almost no melodic 'events' to capture attention, so it supports on-task attention during matching, tracing and sorting activities.

| # | Track | Length | Loudness | Range |
|---|---|---|---|---|
| 1 | Steady Loop One 1 | 81s | -20.0 LUFS | 5.4 LU |
| 2 | Steady Loop One 2 | 108s | -20.0 LUFS | 4.9 LU |
| 3 | Soft Pulse 1 | 86s | -20.0 LUFS | 3.2 LU |
| 4 | Soft Pulse 2 | 83s | -20.0 LUFS | 3.2 LU |
| 5 | Quiet Ostinato 1 | 86s | -20.0 LUFS | 5.6 LU |
| 6 | Quiet Ostinato 2 ⚠️ | 105s | -20.0 LUFS | 7.1 LU |
| 7 | Even Ground 1 | 85s | -20.0 LUFS | 5.6 LU |
| 8 | Even Ground 2 | 76s | -20.0 LUFS | 2.9 LU |
| 9 | Patient Keys 1 | 103s | -20.0 LUFS | 3.8 LU |
| 10 | Patient Keys 2 | 92s | -20.0 LUFS | 3.0 LU |

### Filipino Calm  (`filipino_calm`)

Culturally familiar tone colours for Filipino families, kept within the same calm envelope as the other categories. Pairs with the app's Tagalog and Cebuano voice-overs.

| # | Track | Length | Loudness | Range |
|---|---|---|---|---|
| 1 | Kundiman Hush 1 ⚠️ | 110s | -20.0 LUFS | 4.9 LU |
| 2 | Kundiman Hush 2 | 97s | -20.0 LUFS | 4.3 LU |
| 3 | Soft Rondalla 1 | 114s | -20.0 LUFS | 6.2 LU |
| 4 | Soft Rondalla 2 | 77s | -20.0 LUFS | 2.6 LU |
| 5 | Bamboo Breeze 1 | 91s | -20.0 LUFS | 4.5 LU |
| 6 | Bamboo Breeze 2 | 91s | -20.0 LUFS | 5.2 LU |
| 7 | Kulintang Calm 1 | 85s | -20.0 LUFS | 3.1 LU |
| 8 | Kulintang Calm 2 | 96s | -20.0 LUFS | 3.7 LU |
| 9 | Harana Evening 1 | 79s | -20.0 LUFS | 4.1 LU |
| 10 | Harana Evening 2 | 75s | -20.0 LUFS | 3.0 LU |

## Verification

Every file was measured after conversion. 50 of 60 passed both checks: loudness range at or under 7 LU, and no near-silent dropout longer than half a second.

These did not, and should be auditioned before use:

- `filipino_calm_01_v1` — 2.5s of near-silence (dropout)
- `focus_minimal_03_v2` — 9.8s of near-silence (dropout)
- `gentle_playful_02_v1` — 4.8s of near-silence (dropout)
- `gentle_playful_03_v2` — 1.8s of near-silence (dropout)
- `lullaby_music_box_05_v1` — loudness range 7.1 LU exceeds 7.0 LU
- `lullaby_music_box_05_v2` — 3.5s of near-silence (dropout)
- `nature_ambient_01_v2` — loudness range 8.0 LU exceeds 7.0 LU
- `soft_relaxing_01_v1` — loudness range 7.1 LU exceeds 7.0 LU
- `soft_relaxing_01_v2` — loudness range 7.7 LU exceeds 7.0 LU
- `soft_relaxing_03_v1` — loudness range 7.7 LU exceeds 7.0 LU

**Loop joins.** All 60 files were checked for the wrap being seamless, by comparing the step from the last sample back to the first against a normal sample-to-sample step inside the same file. Median ratio 0.279, worst 1.636 — i.e. the join is typically a *smaller* jump than the audio's own movement, so it is inaudible. 0 files exceeded the 3.0x threshold.

This check earns its place: the first render passed every loudness metric while half the files had an audible click at the wrap, because the tone-shaping IIR filters ran *after* the join and left a startup transient on the first ~20 ms. Loudness measurement cannot see that. Re-run `check_loops.py` after any change to the filter chain.

**Take the loudness flags seriously.** It is tempting to dismiss a wide range on sparse material as the measurement counting the gaps between phrases rather than a real crescendo. That reasoning was applied to the worst-scoring track in the first build, and it was wrong: a listener immediately described it as eerie coming in and going out. The flag was a true positive. Audition flagged tracks; do not argue them away.

**The dropout check exists because loudness range actively hides them.** Silence lowers a track's measured range, so ranking on LRA alone *prefers* a take with a hole in it — two replacement candidates scored best in their batch while containing seven seconds of digital silence. A dropout mid-bed is a startle in its own right, so it now outranks every other criterion when choosing which take ships.

What the measurements do **not** cover: whether a track is musically pleasant, whether it suits the game it plays under, whether the nature textures read as 'rain' rather than 'hiss', and whether a loop that is seamless at the sample level is still *musically* satisfying to hear repeat every two minutes. Those need a listen, ideally with a child.

## Reproducing / extending

Scripts are in `tools/bgm_gen/`. The generation contract:

```
model            V5_5   (only V5_5 honours `duration`)
instrumental     true
duration         120 s
styleWeight      0.8    hold the requested style hard
weirdnessConstraint 0.1   allow almost no creative deviation
```

Three behaviours are not in kie.ai's documentation, and the first two will fail a whole batch:

- `negativeTags` is capped at **200 characters** (422 above that).
- `/api/v1/generate` rate-limits hard on concurrent submits — submit serially with a delay, then poll in parallel.
- `duration` is a *request*, not a guarantee. Asking for 120 s returned anything from 56 s to 114 s after trimming. Since these loop, short tracks are usable — but do not assume a fixed length.

**Where the loop starts is the subtlest part of this pipeline.** Both ends of a finished file are cut from the same point, so whatever sits there is heard twice per lap. Suno almost always opens from silence with a swell — on the track this was first noticed on, -88 dB to -9.5 dB in 4.5 seconds — and starting at zero puts that swell on the intro *and* the outro. It reads as eerie, and no loudness metric catches it.

Naively skipping the intro is not enough: on a track that swells all the way through, the next point is just as uneven, and skipping far enough in buys flatness by leaving a short, repetitive loop. The converter searches for the steadiest window instead, scoring across both the tail region and the opening, and refuses points that would cut the loop below 75.0s. Measured over the worst offenders plus controls, that took the mean dip at the loop boundary from -11.8 dB to -7.3 dB with no track regressing.

One ffmpeg trap is worth recording too: `acrossfade` yields **zero frames** when both its inputs are `asplit` branches of the same source, and ffmpeg still exits 0. The conversion cuts head and body to real files first, and asserts a minimum output size, because a silent success here otherwise looks identical to a real one.

Shared negative prompt (at the 200-char limit):

```
vocals, lyrics, drums, percussion, cymbals, brass, distortion, crescendo, riser, drop, sudden dynamics, key change, tempo change, dissonance, sound effects, loud, aggressive, dramatic
```

Shared style suffix appended to every category prompt:

```
instrumental only, no vocals, steady unchanging tempo, very narrow dynamic range, no crescendo, no sudden accents, no startling transients, soft rounded attack, warm low-mid tone with rolled-off harsh treble, simple repeating motif, consonant harmony, gentle seamless loop, mixed quiet as background bed under speech
```

## How it is wired into the app

Implemented. The parent picks a **category**; the app picks one track from it per session and loops that track. Music never changes underneath a child mid-session — variety comes from the next session's pick.

| Piece | Where |
|---|---|
| Track list (generated) | `packages/shared_audio/lib/src/bgm_library.dart` |
| Playback | `AudioService.playCategoryMusic()` |
| Stored choice | `ChildProfile.musicCategory`, children table v16 |
| Picker UI | Settings → Audio → Music Style |
| Session pick | `GameFlowScreen.initState` (`restart: true`) |
| Bundle guard | `packages/shared_audio/test/bgm_asset_bundle_test.dart` |

Only a subset of the library ships, to keep the bundle down — 30 tracks (17.9 MB) out of 60. The rest stay here as masters; `tools/bgm_gen/install_bgm.py` chooses which ship and regenerates `bgm_library.dart`.

Three behaviours are deliberate and easy to undo by accident:

- **`playCategoryMusic` no-ops when the same category is already playing**, so rebuilds and lifecycle callbacks cannot restart the track mid-session. Only `restart: true` forces a new pick.
- **Loading and login play the default category**, because no profile is loaded yet; `HomeScreen` switches to the child's own category once it is. That is the one mid-run change, and it lands before any game.
- **The picker previews immediately** (`restart: true`). That is the exception to the rule above, and it is intentional: the parent is listening on purpose and needs to hear what they picked.

An unknown category key — a profile written by a build that shipped a category this build does not have — falls back to the default rather than leaving the child in silence.
