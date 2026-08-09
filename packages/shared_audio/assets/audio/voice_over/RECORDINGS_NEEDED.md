# Voice-over recordings still needed

> **Reconstructed 2026-07-26.** The original file was lost (zero-filled) in the
> drive-copy data loss and was not in git. Everything below was re-derived by
> comparing the `en/`, `tl/` and `ceb/` asset folders — treat the framing as
> provisional and correct it where it misses your intent.

## Coverage today

| language | files | status |
|---|---|---|
| `en` | 105 | complete — the reference set |
| `ceb` | 105 | complete |
| `tl` | 100 | **5 missing** |

## Missing in `tl`

These five exist in `en` and `ceb` but not in `tl`:

- `colors/Gold.wav`
- `colors/Magenta.wav`
- `colors/Pink.wav`
- `colors/Teal.wav`
- `shapes/Heart.wav`

They are the same five the voice-cloning tool uses as its placeholder batch
(see `tools/voice_gen/README.md`), so they were most likely added to `en` and
`ceb` in one pass and `tl` was not backfilled.

## Known constraint: Cebuano and Tagalog cannot be generated

`tools/voice_gen` clones a voice; it does not translate. Pointing it at
Tagalog or Cebuano text produces English words in the cloned voice. The
`tl/` and `ceb/` folders need a human speaker of those languages, or a
translation step before synthesis.

## Format contract

All clips: **24 kHz, mono, 16-bit PCM WAV**, ~30 ms lead and ~80 ms tail
padding. New recordings must match, or they will sit unevenly against the
existing library.
