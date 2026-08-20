#!/usr/bin/env python3
"""Generate the naming voice-over lines for the seed object bank (en/tl/ceb).

One short spoken word per seed — "Dog" / "Aso" / "Iro" — so a game can say the
object's name when it appears, or pair it with the existing dynamic fragments
("Tap the …", "Drag the …") from generate_voice_lines.py.

Engine: Microsoft Edge neural TTS (edge-tts), the same pipeline and voices as
`generate_voice_lines.py` — read that file's header for the voice choices and
the Cebuano limitation. Naming a single object is word-teaching, so every line
uses the slow, clear `colors`/`shapes` prosody profile: a child is meant to hear
and learn the word, not be rushed past it.

The seed list is imported from `generate_seed_cards.py` so the slugs and the
en/tl/ceb names are defined in exactly one place; adding a seed there gives it a
card AND a line with no second edit here.

Usage:
  pip install edge-tts imageio-ffmpeg
  python scripts/generate_seed_lines.py              # all languages
  python scripts/generate_seed_lines.py tl ceb       # subset

The naming WAVs are co-located with the picture cards under the self-contained
`seed_cards/` bank rather than in shared_audio's voice-pack system: this is a
standalone asset bank with its own manifest, and folding it into the packs
(install_packs.py / the kie.ai TTS pipeline) is a wiring decision for later.

Output:
  packages/shared_ui/assets/seed_cards/audio/{lang}/{Slug}.wav
  (24 kHz mono WAV — the format VoiceOverService expects.)
"""

import asyncio
import subprocess
import sys
import time
from pathlib import Path

from generate_seed_cards import SEEDS  # single source of truth for slugs+names

SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parent
OUTPUT_ROOT = (PROJECT_ROOT / "packages" / "shared_ui" / "assets" / "seed_cards"
               / "audio")

LANGUAGE_MODELS = {
    "en":  "en-US-AnaNeural",
    "tl":  "fil-PH-BlessicaNeural",
    "ceb": "fil-PH-BlessicaNeural",
}

# Slow and clear — a single word the child is meant to learn, matching the
# `colors`/`shapes` profile in generate_voice_lines.py.
PROFILE = {"rate": "-15%", "pitch": "+10Hz"}


def _ffmpeg_exe() -> str:
    import imageio_ffmpeg
    return imageio_ffmpeg.get_ffmpeg_exe()


async def _synthesize_one(semaphore, ffmpeg, lang, slug) -> tuple:
    """Generate one naming WAV. Returns (lang, slug, error-or-None)."""
    import edge_tts

    text = SEEDS[slug].get(lang) or SEEDS[slug]["en"]
    voice = LANGUAGE_MODELS[lang]
    out_dir = OUTPUT_ROOT / lang
    out_dir.mkdir(parents=True, exist_ok=True)
    fname = slug.capitalize()
    wav_path = out_dir / f"{fname}.wav"
    mp3_path = out_dir / f"{fname}.tmp.mp3"

    async with semaphore:
        last_error = None
        for attempt in range(3):  # the free Edge endpoint can rate-limit
            try:
                communicate = edge_tts.Communicate(
                    text, voice, rate=PROFILE["rate"], pitch=PROFILE["pitch"])
                await communicate.save(str(mp3_path))
                result = subprocess.run(
                    [ffmpeg, "-y", "-i", str(mp3_path),
                     "-ar", "24000", "-ac", "1", str(wav_path)],
                    capture_output=True)
                if result.returncode != 0:
                    raise RuntimeError(
                        f"ffmpeg: {result.stderr.decode(errors='ignore')[-200:]}")
                print(f"  [OK] [{lang}] audio/{lang}/{fname}.wav  \"{text}\"")
                return (lang, slug, None)
            except Exception as e:  # noqa: BLE001 — retried, then reported
                last_error = str(e)
                await asyncio.sleep(1.5 * (attempt + 1))
            finally:
                mp3_path.unlink(missing_ok=True)

        print(f"  [ERR] [{lang}] audio/{lang}/{fname}.wav — {last_error}")
        return (lang, slug, last_error)


async def generate_all_async(languages):
    ffmpeg = _ffmpeg_exe()
    semaphore = asyncio.Semaphore(4)
    tasks = [
        _synthesize_one(semaphore, ffmpeg, lang, slug)
        for lang in languages
        for slug in SEEDS
    ]
    results = await asyncio.gather(*tasks)
    errors = [(l, s, e) for (l, s, e) in results if e is not None]
    print(f"\n{'='*60}")
    print("[DONE] Seed naming voice-over generation complete!")
    print(f"   Generated: {len(results) - len(errors)}/{len(results)} files")
    print(f"   Output:    {OUTPUT_ROOT}")
    if errors:
        print(f"   Errors:    {len(errors)}")
        for lang, slug, err in errors:
            print(f"     - [{lang}] {slug}: {err}")
    print(f"{'='*60}")
    return len(errors)


def main():
    languages = sys.argv[1:] if len(sys.argv) > 1 else None
    if languages:
        invalid = [l for l in languages if l not in LANGUAGE_MODELS]
        if invalid:
            print(f"[WARN] Unknown language codes: {invalid}")
            print(f"  Available: {list(LANGUAGE_MODELS.keys())}")
            sys.exit(1)
    else:
        languages = list(LANGUAGE_MODELS.keys())
    print(f"Generating seed names for: {languages}")

    start = time.time()
    error_count = asyncio.run(generate_all_async(languages))
    print(f"\nTotal time: {time.time() - start:.1f}s")
    sys.exit(1 if error_count else 0)


if __name__ == "__main__":
    main()
