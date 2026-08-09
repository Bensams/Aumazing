# Voice-over generation

Two independent paths produce the voice-over library. Both write **24 kHz,
mono, 16-bit PCM WAV** with ~20 ms lead and ~40 ms tail padding, and both write
to `out/` — the live asset folder is never touched. That padding is deliberately
tight: cues are played back to back inside composed phrases, where a generous
tail plus the next clip's lead becomes a pause mid-phrase.

| path | script | languages | voice source |
|---|---|---|---|
| **KIE** | `generate_kie.py` | en, tl, ceb | 16 voices in 3 age tiers, 2 backends |
| **Local clone** | `generate.py` | en only | your own reference recording |

Use the KIE path for the shipped library and for anything Filipino or Cebuano.
Use the local path when you specifically want *your* voice cloned and are
willing to stay in English.

---

# 1. KIE path

Renders every line in all three languages, in three age tiers, so the app can
offer the user a choice of narrator.

## Backends

```bash
--backend gemini      # default: google/gemini-3-1-flash-tts
--backend elevenlabs  # elevenlabs/text-to-speech-*
```

**Gemini is the default and the one that currently works.** As of 2026-07-31
every ElevenLabs model on KIE fails generation with `failCode 500 — internal
error`, while other providers on the same key succeed. See Troubleshooting.

Gemini is also the better fit on the merits: it takes a free-text
`audio_profile` per speaker, so the age tier is *stated* rather than guessed
from a preset's marketing copy, and it returns 24 kHz WAV natively — already
the library's target rate, so no resampling.

| | gemini | elevenlabs |
|---|---|---|
| model | one, all languages | v2 for en/tl, **v3 for ceb** (v2 lacks Cebuano) |
| age control | `audio_profile` free text | preset choice + local pitch shift |
| child tier | genuine | approximated |
| short lines | `scene` pins the line | `previous_text`/`next_text` |
| emotion | `style` field | v3 audio tags only |
| status | **working** | failing upstream |

## Setup

```bash
./.venv/Scripts/python.exe -m pip install requests soundfile soxr librosa numpy
export KIE_API_KEY=...   # PowerShell: $env:KIE_API_KEY = "..."
```

Get a key at <https://kie.ai/api-key>. It is a paid API — **never commit it**,
and note that `out/`, `.env` and `.venv/` are gitignored here for that reason.

## Languages

| lang | manifest | notes |
|---|---|---|
| `en` | `lines.csv` | — |
| `tl` | `tagalog_lines.csv` | Filipino / Tagalog |
| `ceb` | `cebuano_lines.csv` | Bisaya / Cebuano |

This is the constraint `RECORDINGS_NEEDED.md` recorded as unsolvable — the
local cloning path could not translate. It is solved here: the manifests
already carry translated text, and both backends speak it natively.

Gemini has **no `language_code` field** — it infers the language from the text.
The `scene` string therefore names the target language explicitly and tells the
model to speak only the given line. That is what keeps one-word prompts like
`Asul.` from drifting into English. If you see the wrong language, that string
in `voices.py:_gemini_input` is the knob.

## Voice tiers

```bash
./.venv/Scripts/python.exe generate_kie.py --list-voices
./.venv/Scripts/python.exe generate_kie.py --backend elevenlabs --list-voices
```

- **adult** — 6 voices, grown-up narrator
- **young** — 6 voices, teen / young-adult energy
- **child** — 4 voices, young-child character

On **gemini**, age comes from the per-tier `audio_profile` (e.g. *"A cheerful
young child, about seven years old"*), and `voice_name` only picks the timbre.
Edit `GEMINI_TIER_PROFILE` in `voices.py` to change how old anyone sounds.

On **elevenlabs**, the tiers are weaker: the preset roster has no verified child
voices, so `child` is the brightest presets plus an optional **+2 semitone**
local shift, and every tier assignment was curated from KIE's written
descriptions — **not by listening**. `--no-pitch` hears it unshifted; the shift
has no formant correction and can read as thin.

Either backend: audition before adopting. Nobody has listened to these yet.

## Generate

Always audition first — this generates a few representative lines per voice:

```bash
./.venv/Scripts/python.exe generate_kie.py --lang en --preview
```

Then narrow to what you want:

```bash
# one language, one tier
./.venv/Scripts/python.exe generate_kie.py --lang ceb --tier child

# specific voices across all three languages
./.venv/Scripts/python.exe generate_kie.py --lang all --voices bella,finn,emma --yes

# everything: 3 langs x 16 voices x 105 lines = 5040 clips
./.venv/Scripts/python.exe generate_kie.py --lang all --yes
```

Output lands at `out/kie/<backend>/<lang>/<tier>_<voice>/<path>.wav`.

`--dry-run` prints the plan and costs nothing — no key needed. Runs over 200
clips refuse to start without `--yes`, because every clip is a paid call.

## The naming-feedback cues

A correct answer no longer earns praise in the moment — it earns the *name* of
what the child got right ("red circle", "Gatas", "A"). That added three cue
families, **generated and installed** on 2026-08-06:

| family | count | where it is heard |
|---|---|---|
| `letters/` | 8 (A C E H L T U V) | Trace It |
| `numbers/` | 6 (One Two Three Four Five Seven) | Trace It |
| `items/` | 14 (Tinapay … Syampu) | Sari-Sari Sort |

504 clips: 28 lines x 3 languages x 6 voices, on
`google/gemini-3-1-flash-tts`. Every pack now reports 133/133 in
`check_library.py`. This is the sequence that produced them, and the one to
repeat for any future cue family:

```bash
./.venv/Scripts/python.exe generate_kie.py --lang all --only letters/,numbers/,items/ --workers 8 --yes
# two passes -- see "Budget the repair pass" below; one is not enough
./.venv/Scripts/python.exe repair_consistency.py --root out/kie/gemini --only letters/,numbers/,items/ --attempts 3
./.venv/Scripts/python.exe repair_consistency.py --root out/kie/gemini --only letters/,numbers/,items/ --attempts 4
./.venv/Scripts/python.exe to_mp3.py --src out/kie/gemini --dst out/mp3
./.venv/Scripts/python.exe install_packs.py
python check_library.py
```

`install_packs.py` copies the 18 generated packs and rewrites their
`voice_pack.dart` and `pubspec.yaml` blocks. `ceb_lexianne` is human-recorded,
has none of these cues, and needs nothing — it is not a default, so it falls
back to its language's default pack.

> The old hand-made `en` / `tl` / `ceb` packs, and `fill_default_packs.py` which
> patched their gaps, are gone. Each was stitched from more than one speaker, so
> the voice could change mid-session. Every language now defaults to its
> `*_adult_woman` pack, which is one speaker throughout.

### Dead air is the thing that makes composed phrases drag

A composed phrase — "Tap the" + "Yellow" + "Star", or the naming feedback
"Yellow" + "Star" — plays as separate clips back to back, so silence baked into
the *end* of one clip and the *start* of the next lands in the middle of the
phrase. A child hears a long unexplained pause between two words that belong
together. Reported from the field as roughly three seconds between words.

Two faults produced it, and both are fixed:

**1. The trim threshold never fired.** `voice_lib.THRESH_DB` was `-60 dB` — 0.1%
of peak — chosen so quiet word onsets were never clipped. It was so permissive
that the model's own noise floor read as speech: `speech_bounds` reported a clip
starting at 0.03 s when the first *audible* sound was at 0.33 s, so
`pad_and_fade` thought the clip was already tight and left ~0.3 s of dead air at
each end. It also measured per sample, where one stray sample is enough to
defeat it. It is now **-45 dB over a 10 ms RMS window**, measured: the detected
span is stable from -45 to -40 dB and only starts eating speech at -35 dB, where
"Great job!" loses 120 ms off its tail. `tl` was worse still — never conformed at
all, ~1.0 s of trailing silence per clip.

Silence per word boundary, before and after:

| pack | before | after |
|---|---|---|
| `tl` default | ~1.15 s | ~0.17 s |
| generated packs | ~0.73 s | ~0.17 s |

`conform_library.py` repairs clips produced before the threshold was corrected.
Run it on the **WAV masters first**, then re-derive the MP3s, so generated packs
never take a second lossy encode:

```bash
./.venv/Scripts/python.exe conform_library.py --root out/kie/gemini
./.venv/Scripts/python.exe to_mp3.py --src out/kie/gemini --dst out/mp3 --force
./.venv/Scripts/python.exe install_packs.py
./.venv/Scripts/python.exe conform_library.py --assets   # en / tl / ceb in place
```

`--assets` keeps a `.bak` beside every file it edits (the default packs are the
only copy that exists); `--restore` undoes it. `--check` exits non-zero if
anything is out of contract — use it to gate a commit:

```bash
./.venv/Scripts/python.exe conform_library.py --assets --check
```

It only ever *removes* silence. A clip trimmed tighter than the contract — the
human-recorded ones sit at ~20 ms — is left exactly as found.

**2. Each word was loaded only when its turn came.** `playSequence` called
`play()` per cue, so every word paid a fresh platform round trip (asset
extraction plus an Android MediaPlayer prepare) *between* words. It now loads
every clip in the phrase onto its own pool player before the first word starts,
so that cost is paid once, up front, where it reads as onset latency instead of
a stutter mid-phrase. The deliberate inter-word `gap` also dropped from 80 ms to
40 ms, since the clips no longer bring their own.

### Colour+shape is one phrase, not two words

The naming feedback used to play "Purple" then "Circle" as two clips, and it
never sounded like one phrase however tight the join. Punctuation is why: the
manifest writes every colour as `"Purple."`, so the model delivers a complete
sentence. Measured on en_adult_woman, `colors/Purple` falls **63%** across its
length (445 -> 165 Hz). Two of those butted together are a list, not a phrase.

Three cheaper fixes were tried and measured, and all three failed:

| attempt | result |
|---|---|
| trailing comma, `"Purple,"` | still falling: -53%, -38%, -54%, -59% |
| scene prompt: "keep the pitch lifted, unfinished" | still falling: -61%, -53%, -31%, -55% |
| slice the word out of a carrier phrase | usable 2 times in 6; several slices came out *longer* |

A lone word has no following context, so the model renders it sentence-final no
matter how it is asked. Only a phrase recorded whole has the contour: measured,
the colour rises into the shape (+344%) and only the shape falls (-36%).

So the 30 colour+shape pairs the games actually show are recorded as single
utterances under `phrases/`. The pair list is **read out of
`match_it_game.dart` and `do_what_i_say_game.dart`**, not hand-maintained, so it
cannot drift from what a child sees. `answerLabelCues` returns the phrase when
one exists and falls back to two separate words when it does not, so an
unrecorded pair degrades instead of going silent.

Tagalog and Cebuano gained real grammar in the process. Two concatenated words
were "Lila" + "Bilog"; a recorded phrase has to be said properly, so it is now
`Lilang bilog` (Tagalog links with `-ng` after a vowel, `na` after a consonant)
and `Lila nga lingin` (Cebuano uses `nga`). **Worth a native-speaker ear.**

The cost is combinatorial: adding one colour to a game's palette is 18 new clips
(3 languages x 6 voices). `check_library.py` flags a missing pair rather than
letting it fail silently.

### The debounce was eating the end-of-game praise

Worth knowing about because it is invisible: `VoiceOverService.play` drops any
cue that arrives within 300 ms of the previous one, to stop a child's rapid
tapping stacking up speech. Every game fires the celebration line in the *same
synchronous block* as the final answer's naming cue — in `match_it_game.dart`
they are 26 lines apart with nothing awaited between them — so the celebration
landed inside that window and was discarded. No error, no crash, just no praise
at the end of the game. The round-transition line ("Next one!") was going the
same way.

Both now go through `_playRandomAfterCurrent`, which waits for whatever is
speaking to finish and then plays exempt from the debounce. Skipping the
debounce alone would have swallowed the label instead, cutting it off mid-word.

Note that recording colour+shape as one phrase made this *worse* before it was
found: two-cue labels went through `playSequence`, which never stamped the
debounce clock, so colour+shape answers were the one path that accidentally
worked. A single phrase cue goes through `play`, which does stamp it.

`celebration_not_dropped_test.dart` pins both halves — that an ordinary cue in
that position really is dropped, and that these two are not.

### There is one narrator, and it needs arbitrating

Reported as two voices talking over each other when opening a game. Two causes,
both structural rather than anything to do with the audio:

**Each screen builds its own `VoiceOverService`, and screens outlive each
other.** The child-mode lobby is still mounted underneath an open game, so its
service is still alive and still owns three audio players. Tapping a game card
makes the lobby speak a confirmation, then the game screen's own service speaks
the instruction. Neither can see the other, so nothing stops either. Stopping
players inside one instance cannot fix this by construction.

`VoiceOverService` now keeps a static registry of live instances, and any
service about to speak silences the rest first (`_takeFloor`). A disposed
service leaves the registry, so it is never touched afterwards.

**Silencing by scanning for playing players is not enough**, and the first
attempt at this fix failed for that reason. Starting a cue is asynchronous — the
asset is loaded and the platform player prepared, 100–400 ms on Android — and
during that window the player is not yet `playing`, so a service looking for
something to stop finds nothing, and the pending cue surfaces afterwards anyway.
That is the game-launch case exactly: `_launch` in the lobby fires "Let's go"
and pushes the game route in the same breath, so the game's "Match it" claims
the floor while "Let's go" is still preparing, sees an idle pool, and both
speak.

So the floor is a **ticket**, not a scan: every claim takes the next number, and
a call that no longer holds the current one abandons itself at its next await
instead of reaching the speaker. Last claim wins regardless of what order the
platform gets around to things. Players are also stopped unconditionally rather
than only when observed `playing`.

One consequence worth knowing: the lobby's "Let's go" is now *dropped* rather
than overlapped, because the game's instruction claims the floor after it. The
instruction is the line that matters, so that is the right winner — but if the
tap acknowledgement is wanted, it has to be sequenced deliberately, not left to
a race.

**`playSequence` had stopped yielding.** Its rewrite for phrase playback stopped
routing through `play()`, which is what used to stop other players — so a
concurrent cue overlapped the sequence instead of replacing it. It takes the
floor explicitly now, and a cancelled sequence stops rather than continuing to
produce words underneath whatever started.

Separately, **Do What I Say spoke twice on load**: `onLoad` played a generic
instruction and `_setupRound` immediately played the composite one ("Tap the
purple circle"). The composite *is* the instruction, so the generic one now
plays only when there is no composite — the same rule `_setupRound` already
applied to `onPlayListenVo`. The other five games were checked; only Copy Me
speaks twice on load and it already waits 2000 ms between, deliberately.

`single_narrator_test.dart` pins the floor contract.

### Two repair passes, and the order matters

`repair_consistency.py` polices *who* is speaking; `repair_delivery.py` polices
*how*. Each regenerates clips to improve its own metric, so **each can spoil the
other's** -- running consistency after delivery put 12 phrases back over the
pause tolerance. Run delivery **last**, then re-check consistency; they
converged after one round trip (delivery 0 over tolerance, consistency 4 of 540).

Phrase delivery over the run:

| | first generation | after two delivery passes |
|---|---|---|
| inner gap, median | 0.10 s | **0.07 s** |
| inner gap, p90 | 0.27 s | **0.15 s** |
| inner gap, worst | 0.87 s | **0.18 s** |
| clips with an audible pause | 123 / 540 | **0** |

"Inner gap" is the longest *contiguous* near-silence inside the speech. Summing
every quiet frame instead counts stop consonants and makes a fluent phrase look
broken.

### Budget the repair pass, don't skip it

Single-word cues drift far worse than the rest of the library, and these are
heard after *every* correct answer, so the drift is the most audible in the app.
Measured on this run:

| | outlier rate |
|---|---|
| new cues, straight from the API | **40.3%** |
| after one repair pass (3 attempts) | 18.3% |
| after a second pass (4 attempts) | **10.1%** |
| the settled rest of the library, for comparison | 11.8% |

Two passes brought the new cues level with the existing library. One pass was
not enough. Single letters were the worst offenders by a wide margin — `H`, `A`
and `C` topped the outlier list in nearly every pack — because a one-character
prompt gives the model almost nothing to anchor the voice to.

`--only letters/,numbers/,items/` is what makes a second pass affordable: the
pack centre is still computed from all 133 clips, but calls are spent only on
the new ones instead of re-rolling clips that already settled.

Letter and numeral names were not auditioned per language and should be, before
adoption: Filipino and Cebuano use English-style letter names, so the manifests
carry the bare letter and rely on the `scene` prompt to keep the delivery in the
right language. Numerals are written as native words (`Tatlo` / `Tulo`), and the
sari-sari item names are identical across all three manifests on purpose — they
have to match the Filipino word printed on the item the child is looking at.

## Reruns are cheap

Existing files are skipped, so **re-running the same command retries only what
failed**. Failures are collected in `out/kie/failures.json` rather than
aborting the batch. Use `--force` to deliberately regenerate.

## Troubleshooting

**`internal error, please try again later` (failCode 500).** The task was
accepted, then failed inside KIE's provider integration. Nothing in this repo
can fix it — this is exactly what every ElevenLabs model does as of
2026-07-31, which is why `--backend gemini` is the default. Confirm it is
upstream and not your account:

```bash
# credits present?
curl -H "Authorization: Bearer $KIE_API_KEY" https://api.kie.ai/api/v1/chat/credit

# does any other provider work?
python -c "from kie_client import KieClient; c=KieClient(); \
  print(c.synthesize('google/nano-banana', {'prompt':'a red circle'})[1])"
```

If credits are healthy and another model succeeds, that provider is down —
switch backends, or wait and re-run. Existing files are skipped, so re-running
picks up exactly where it stopped. `--task-retries` (default 2) already retries
transient upstream failures per clip.

**`The model name you specified is not supported` (422).** These four slugs
exist; every other plausible spelling 422s (verified against the live API):

```
google/gemini-3-1-flash-tts                 <- note the dashes, not "3.1"
elevenlabs/text-to-speech-multilingual-v2
elevenlabs/text-to-speech-turbo-2-5
elevenlabs/text-to-dialogue-v3
```

## Useful flags

| flag | effect |
|---|---|
| `--only colors/,shapes/Heart` | path-prefix filter |
| `--limit 5` | first N manifest lines |
| `--workers 8` | parallelism (the client caps itself at KIE's 18 tasks / 10 s) |
| `--timeout 300` | per-clip seconds before a task is abandoned |
| `--task-retries 2` | retries when a task is accepted but fails upstream |
| `--out DIR` | output root, default `out/kie` |

## Short lines

Most of this library is one to three words, which zero-shot TTS delivers badly:
clipped onsets and falling intonation. Neither backend needs the carrier-phrase
audio surgery the local path uses — both get prosodic context natively, and
**only the target text is rendered**:

- gemini — `scene` frames the line and pins the turn to it.
- elevenlabs v2 — `previous_text` / `next_text` place the line between "Okay."
  and "Ready.", localised per language.

## Files

- `kie_client.py` — KIE API client. All KIE jobs are async: `createTask`
  returns a taskId, `recordInfo` is polled until it settles. Handles backoff on
  429/5xx, task-level retries, rate limiting, and downloads results immediately
  (result URLs expire in ~24 h).
- `voices.py` — both voice rosters, tier profiles, and backend routing. This is
  the file to edit when re-curating.
- `generate_kie.py` — CLI driver.
- `voice_lib.py` — shared audio conforming, used by both paths.

---

# 2. Local cloning path (Chatterbox)

Clones a voice from a short reference recording using
[Chatterbox](https://github.com/resemble-ai/chatterbox) (MIT).

## Setup

```bash
python -m venv .venv
./.venv/Scripts/python.exe -m pip install chatterbox-tts
```

CPU-only works. Expect roughly 20–60 s per clip without a GPU — slow, but the
whole library is ~105 short lines, so it is a one-time batch.

## 1. Record a reference

10–20 seconds of clean speech in the voice you want cloned. Quiet room,
consistent mic distance, no background music. Any format soundfile reads.

Record a **separate** reference per character (child / man / woman). Cloning an
adult voice into a child voice does not work — record an actual child, with
written parental consent.

## 2. Build and review the manifest

```bash
python build_manifest.py ../../packages/shared_audio/assets/audio/voice_over/en -o lines.csv
```

This derives spoken text from the asset filenames. **Read `lines.csv` before
generating.** Punctuation drives delivery, so it is worth getting right.

| column | meaning |
|---|---|
| `path` | output file, mirrors the asset tree |
| `text` | what gets spoken |
| `carrier` | `yes` wraps short words in a carrier phrase (see below) |
| `exaggeration` | emotional intensity, 0–1. Lower = calmer |
| `cfg_weight` | adherence to the reference voice |

## 3. Generate

Start with the five placeholder words, not the whole library:

```bash
./.venv/Scripts/python.exe generate.py \
  --ref my_voice.wav --manifest lines.csv --out out/en \
  --only colors/Gold,colors/Pink,colors/Magenta,colors/Teal,shapes/Heart
```

Then the full set:

```bash
./.venv/Scripts/python.exe generate.py --ref my_voice.wav --manifest lines.csv --out out/en
```

## The carrier phrase

Zero-shot TTS handles bare one-word prompts badly. So short lines are generated
inside a carrier — `"Okay. Yellow. Ready."` — and the middle segment is
extracted by silence detection.

The extraction is **verified**: if the audio does not split into exactly three
voiced segments, the line is reported as flagged rather than silently mis-cut.
For flagged lines, retry with `--no-carrier` or reword that line in the
manifest and regenerate just that path with `--only`.

## Known gaps (local path only)

- **Cebuano and Tagalog are not solved by this path.** Chatterbox speaks the
  English text in your cloned voice; it does not translate. Use `generate_kie.py`
  for those languages.
- **`Aumazing` and `Ausome`** are invented brand words. TTS will mispronounce
  them. Spell them phonetically in the manifest (e.g. `Aw-mazing`) and iterate.
  This applies to the KIE path too.
- Chatterbox embeds a **Perth neural watermark** in its output by design. It is
  inaudible and the licence permits commercial use, but be aware it is there.
