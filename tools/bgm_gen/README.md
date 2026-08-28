# bgm_gen — ASD-friendly background music

Generates the background-music library in
`packages/assets/audio/BG_Music/`. See
[`docs/asd-friendly-bgm.md`](../../docs/asd-friendly-bgm.md) for the design
rules, the category list and the measured results, and
[`docs/audio-licensing.md`](../../docs/audio-licensing.md) §1 for the
unresolved licence question that applies to everything this tool produces.

## Requirements

```bash
pip install requests numpy imageio-ffmpeg
```

`imageio-ffmpeg` ships the ffmpeg binary, so no system install is needed.

## Running

```bash
export KIE_API_KEY=...   # from https://kie.ai/api-key
python generate_bgm.py   # ~30 min: submits 30 requests, downloads 60 MP3s
python convert_bgm.py    # MP3 -> loop-ready, level-matched OGG
python check_loops.py    # verifies every file wraps without a click
python install_bgm.py    # picks the shipping subset -> shared_audio + Dart list
python make_catalogue.py # writes bgm_manifest.json + docs/asd-friendly-bgm.md
```

Run them in that order; each reads the previous step's manifest.

After `install_bgm.py`, run the bundle guard — it is the only thing that
catches a category folder missing from `pubspec.yaml`, which otherwise fails
on-device as silence:

```bash
cd packages/shared_audio && flutter test test/bgm_asset_bundle_test.dart
```

## Files

| file | role |
|---|---|
| `bgm_catalog.py` | the category and prompt definitions, plus the global style/negative prompts that make a track ASD-appropriate |
| `generate_bgm.py` | submits to the kie.ai Suno API and downloads results |
| `convert_bgm.py` | trims, loops, tone-shapes and level-matches into OGG |
| `check_loops.py` | verifies loop seams; exits non-zero if any file would click |
| `install_bgm.py` | picks which tracks ship, re-encodes them into `shared_audio`, and generates `bgm_library.dart` |
| `make_catalogue.py` | emits the shipping manifest and the docs page |

`install_bgm.py` ships one variant per prompt: the two variants of a prompt are
the same musical idea, so shipping both would spend bundle size on
near-duplicates. `PER_CATEGORY` and `QUALITY` at the top of that file control
how many tracks ship and at what bitrate.

It also **deletes** any `.ogg` already in a destination category folder before
writing, so tracks dropped from the selection do not linger in the bundle. If
you hand-add a file there, the next run removes it — change the script instead.

## Things that will bite you

These are all load-bearing and none are obvious from the API docs or from
listening casually.

- **`negativeTags` is capped at 200 characters.** Over that, every request in
  the batch fails with a 422.
- **`/api/v1/generate` rate-limits concurrent submits.** Submit serially with a
  delay, then poll in parallel. `generate_bgm.py` already does this; do not
  "optimise" it back into a thread pool.
- **`duration` is a request, not a guarantee.** Asking for 120 s returns
  anywhere from ~55 s to ~145 s.
- **`acrossfade` returns zero frames when both inputs are `asplit` branches of
  the same source**, and ffmpeg still exits 0. Cut head and body to real files
  first. `convert_bgm.py` asserts a minimum output size because a silent
  failure here is indistinguishable from success.
- **Tone-shaping must happen before the loop join, not after.** `highshelf` and
  `lowpass` are IIR filters; applied after the join they leave a startup
  transient on the first ~20 ms, so the file no longer wraps onto itself. Every
  loudness metric still looks perfect. This is exactly what `check_loops.py`
  exists to catch — run it after any filter-chain change.
- **Normalise with a measured static gain, not one-pass `loudnorm`.**
  `loudnorm` rides the gain over time, which compresses the narrow dynamics the
  prompts deliberately produce and disturbs the loop join.

## Adding a category

Add an entry to `CATEGORIES` in `bgm_catalog.py` with five prompts (each
request returns two variants, so five gives ten tracks), then re-run the
pipeline. Keep the prompts inside the same envelope as the existing ones —
tempo in the 56–80 BPM range, soft-attack instruments, no percussion — because
`GLOBAL_STYLE_SUFFIX` and `NEGATIVE_TAGS` steer but do not enforce.
