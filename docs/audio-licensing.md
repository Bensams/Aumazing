# Audio licensing and voice provenance

Every sound Aumazing ships — voice-over, SFX, music — and where it came from,
what licence it is believed to carry, and what still has to be confirmed before
release.

**Status legend**

| | meaning |
|---|---|
| ✅ | verified from files in this repository |
| ⚠️ | believed true, **not** confirmed against the provider's live terms |
| ❌ | provenance unknown — must be resolved before shipping |

> The ⚠️ rows below could not be checked against the live terms of service from
> this machine. They record what to check and where, not a legal opinion. None
> of this is legal advice; a lawyer should sign off before a paid release.

---

## 1. The structural question

Everything synthetic in the voice library is generated through **kie.ai**, which
is a reseller: it fronts Google's and ElevenLabs' models on its own API key and
its own billing. That matters more than any individual provider's policy.

Google's and ElevenLabs' own terms describe the rights *their* direct customers
get. Aumazing is not their customer — KIE is. So the licence that actually binds
this project is **KIE's**, and the single question to answer is:

> Does kie.ai grant its customers ownership of, or a commercial redistribution
> licence to, the audio its API returns — specifically the right to embed that
> audio in a distributed application?

Get that in writing (support ticket or the ToS clause, screenshotted and dated,
filed next to this document). If the answer is no, or unclear, the fallback is
already built and costs nothing: the **local Chatterbox path** (§4) is MIT and
generates from a reference recording you own outright.

---

## 2. Voice model IDs — for reproducing or extending the library

All of this is verified from `tools/voice_gen/voices.py`.

### 2.1 Model slugs ✅

Four slugs exist on KIE; every other spelling returns 422:

```
google/gemini-3-1-flash-tts                 <- dashes, not "3.1"  (default)
elevenlabs/text-to-speech-multilingual-v2
elevenlabs/text-to-speech-turbo-2-5
elevenlabs/text-to-dialogue-v3
```

The shipped generated packs were made with **`google/gemini-3-1-flash-tts`**.
Every ElevenLabs model on KIE was failing with `failCode 500` as of 2026-07-31.

### 2.2 Gemini — the actual "voice ID" is three fields, not one ✅

Gemini has no speaker embedding. A voice is reproducible only as the
combination of `voice_name` + `audio_profile` + `style`, and even then the model
re-rolls per call (see §5). To regenerate a pack that matches what shipped, all
three must match `voices.py` exactly:

| pack | `voice_name` | `style` | `audio_profile` (abbreviated) |
|---|---|---|---|
| `*_adult_woman` | Sulafat | per-emotion | warm, patient adult woman in her thirties |
| `*_adult_man` | Charon | **pinned** Empathetic | very deep, low, resonant male chest voice |
| `*_young_girl` | Autonoe | per-emotion | friendly teenage girl about fifteen |
| `*_young_boy` | Alnilam | **pinned** Empathetic | teenage boy ~fifteen, voice already broken |
| `*_child_girl` | Leda | per-emotion | cheerful young girl, about seven |
| `*_child_boy` | Alnilam | **pinned** Empathetic | cheerful boy about ten, noticeably lower |

The male pins are load-bearing: `style` moves pitch more than `voice_name` does
(Vocal Smile 150 Hz vs Empathetic 100 Hz on the same voice), and without the pin
every male slot lands inside the female range. Changing a `style` mapping
silently re-genders a pack.

Language is inferred from the text — there is no `language_code` field. The
`scene` string in `_gemini_input` is what stops one-word Cebuano prompts from
drifting into English.

### 2.3 ElevenLabs voice IDs ✅ (unused in shipped packs)

Kept for reproducibility if the ElevenLabs backend is ever revived. Full roster
with IDs is in `voices.py` → `ELEVEN_VOICES`. Examples: Bella
`hpp4J3VqNfWAUOO0d1Us`, Benjamin `LruHrtVF6PSyGItzMNHS`, Emma
`pPdl9cQBQq4p6mRkZy2Z`. The `child` tier there is **not** a real child voice —
it is the brightest adult presets with a +2-semitone local shift, and the tier
assignments were curated from KIE's written descriptions, not by listening.

---

## 3. What ships today, per language

| pack family | languages | source | licence status |
|---|---|---|---|
| `ceb_lexianne` | ceb | human voice actor ("Lexianne") | ❌ no release on file |
| `*_adult_*`, `*_young_*`, `*_child_*` (18 packs) | en / tl / ceb | KIE → `google/gemini-3-1-flash-tts` | ⚠️ see §1 |

**Added 2026-08-11:** `items/Bola`, `items/Manika`, `items/Kotse`, `items/Teddy`
— 4 cues × 18 packs = 72 clips, for the Sari-Sari Sort `toys` category. Same
model and voice configuration as the rest of §2.2, so §1 applies to them
unchanged. Reproduce with:

```
python generate_kie.py --lang all --only "items/Bola,items/Manika,items/Kotse,items/Teddy" --yes
python to_mp3.py --src out/kie/gemini --dst out/mp3
python install_packs.py
```

The `en` / `tl` / `ceb` default packs were **removed** on 2026-08-07. They were
mixed-provenance — original cues of unrecorded origin, plus `letters/`,
`numbers/` and `items/` borrowed from generated packs by `fill_default_packs.py`
— and audibly mixed-speaker, which is why they were dropped. Each language now
defaults to its `*_adult_woman` pack, so everything the app ships except
`ceb_lexianne` is KIE-generated and covered by §1.

Two things need closing:

1. **`ceb_lexianne`.** A human recording needs a signed performer release
   covering commercial use, distribution, and (if the recording is of a minor)
   written parental consent. The repo has the audio and no paperwork.
2. **Cebuano coverage generally.** Cebuano is not in ElevenLabs Multilingual
   v2's language set at all; only Eleven v3 and Gemini speak it. That constrains
   any future re-generation to those two.

---

## 4. Local cloning path — the clean-licence fallback ✅

`tools/voice_gen/generate.py` uses
[Chatterbox](https://github.com/resemble-ai/chatterbox), **MIT licensed**, run
locally from a reference recording. No third-party service sees the audio and no
reseller sits in the licence chain — which is exactly why it is the fallback if
§1 resolves badly.

Two caveats, both already documented in `tools/voice_gen/README.md`:

- Chatterbox embeds a **Perth neural watermark** in every output by design.
  Inaudible, and the licence permits commercial use, but it is present.
- It does **not translate** — it speaks the English text in the cloned voice. It
  cannot produce the Tagalog or Cebuano packs.

A child voice must be cloned from an actual child recording, with written
parental consent. Cloning an adult and pitching up does not work and is not the
same permission.

---

## 5. Voice consistency within a pack ✅

The requirement that a pack sound like one person is handled, and the mechanism
is worth understanding because it is imperfect by nature.

Gemini's `voice_name` is a **prior, not a locked speaker**. Every API call
re-rolls the voice inside that description, so a pack generated clip-by-clip
drifts — the first run produced one nominal "voice" spanning 157–389 Hz.
Temperature does not control it (0.2 measured *worse* than 1.0), and KIE renders
only the first entry of `dialogue_turns`, so batching a whole pack into one call
is not available either.

`tools/voice_gen/repair_consistency.py` closes the gap by rejection sampling:
build a voice centre from the pack's clips (median F0 + median MFCC), score
every clip against it, and regenerate outliers beyond 3 median-absolute-
deviations, keeping a new take only when it scores better than the old one.

```bash
python repair_consistency.py --root out/kie/gemini --report-only
python repair_consistency.py --root out/kie/gemini --attempts 3
```

**This narrows the spread; it does not eliminate it.** Any newly generated cues
must be run through it, or the new clips will be the audible outliers in an
otherwise settled pack — the naming cues added for immediate feedback are heard
on *every* correct answer, so drift there is more noticeable than anywhere else
in the library.

`tools/voice_gen/check_library.py` gates the other half: it verifies the three
manifests, the cue enum, the category map, the asset-path map, and every pack's
files all agree. Run it before every commit that touches the library. On the
Dart side, `voice_asset_bundle_test.dart` covers the failure `check_library.py`
cannot see — a cue that exists on disk but was never declared in
`pubspec.yaml`, which fails only on-device, as silence.

Measured on the 2026-08-06 naming-cue run, the repair pass was not optional:
those clips came out of the API at **40.3%** outliers, fell to 18.3% after one
pass and 10.1% after a second — against 11.8% for the settled rest of the
library. Single letters drifted worst, having the least context to anchor the
voice. Budget two passes for any future single-word family.

---

## 6. Sound effects and music

| asset | apparent source | licence status |
|---|---|---|
| `soundshelfstudio-ui-click-retro-514601.wav`, `soundshelfstudio-ui-tap-soft-short-514599.wav` | Pixabay (contributor + Pixabay asset ID in filename) | ⚠️ Pixabay Content License — commercial use, no attribution required, no redistribution as a standalone audio product. Confirm and archive the download pages. |
| `floraphonic-casual-click-pop-ui-*-2621xx.wav` (9 files) | Pixabay (same pattern) | ⚠️ as above |
| `Gentle_Learning_Breeze_Lyria_3_Pro_97971.ogg` | Google Lyria 3 Pro (AI-generated music) | ⚠️ terms depend on how it was accessed; Lyria output carries SynthID watermarking |
| `BG_Music/<category>/*.ogg` (60 files, added 2026-08-07) | KIE → Suno `V5_5` | ⚠️ **§1 applies in full** — see [asd-friendly-bgm.md](asd-friendly-bgm.md) |
| `sfx/rewards/*.ogg` (balloon, bubble, candy, firework) | added in `4eff06d`, no source recorded | ❌ |
| `sfx/*.wav` (correct, wrong, drag, drop, shimmer, game/level complete) | no source recorded | ❌ |
| **`sfx/cheer_clap.wav`** (children cheering, end-of-game) | copied from `packages/assets/audio/SFX/kids_appraising.wav`, added in `4eff06d`, no source recorded | ❌ **highest priority** |

The 60-track background-music library added on 2026-08-07 raises the stakes on
§1 rather than introducing a new question. It is the same reseller and the same
unanswered clause, but music is a more conspicuous category of copyrighted work
than a spoken cue, and Suno specifically has been the subject of infringement
litigation over its training data — which is a risk that sits upstream of
whatever KIE's own terms say. Treat the library as unreleasable until §1 is
answered, and note that the clean-licence fallback available for voices (§4)
has **no equivalent here**: there is no local, permissively-licensed music
generator already wired into this repo. If §1 resolves badly, the fallback is
commissioned or properly-licensed stock music, which costs money and time.

`cheer_clap.wav` is called out because this change puts it at the end of every
single game session — it goes from an unused file in a scratch folder to one of
the most-heard sounds in the product. It is also a recording of real children's
voices, which raises a consent question on top of the licence question. If its
origin cannot be established, replace it before release; a royalty-free applause
bed is easy to source and the code needs no change beyond swapping the file.

---

## 7. Open actions

1. ✅ ~~Establish the origin of the `en` / `tl` / `ceb` default voice packs.~~
   Moot — the packs were removed on 2026-08-07.
2. ❌ Obtain a signed performer release for `ceb_lexianne`.
3. ❌ Establish the origin of `cheer_clap.wav` / `kids_appraising.wav`, or
   replace it.
4. ❌ Establish the origin of the reward and game SFX added in `4eff06d`.
5. ⚠️ Get KIE's position on commercial redistribution in writing (§1). Now
   covers 60 music tracks as well as the voice library.
6. ⚠️ Archive the Pixabay download pages for the UI click/tap SFX.
7. ⚠️ Confirm the terms under which the Lyria background track was obtained.

File the evidence for each next to this document as it arrives, and move the
row's status marker. An asset with no paper trail is the same risk whether or
not anyone has noticed it yet.
