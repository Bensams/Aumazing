#!/usr/bin/env python3
"""Add 'Aumazing' voice-over at 7 seconds into the video.

Delays the voice-over to start at 7 seconds while keeping original audio.
"""

import asyncio
import subprocess
import sys
from pathlib import Path

import edge_tts
import imageio_ffmpeg

SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parent
VIDEO_PATH = PROJECT_ROOT / "packages" / "assets" / "videos" / "Aumazing_Splash_Screen_backup.mp4"
OUTPUT_PATH = PROJECT_ROOT / "packages" / "assets" / "videos" / "Aumazing_Splash_Screen.mp4"
TEMP_AUDIO = PROJECT_ROOT / "packages" / "assets" / "videos" / "temp_aumazing_voice.mp3"

VOICE = "en-US-AnaNeural"
DELAY_SECONDS = 7.0

async def generate_tts(text, output_path):
    """Generate TTS audio using edge-tts."""
    print(f"Generating TTS for: '{text}' using {VOICE}...")

    communicate = edge_tts.Communicate(
        text,
        VOICE,
        rate="+8%",
        pitch="+18Hz"
    )

    await communicate.save(str(output_path))
    size_kb = output_path.stat().st_size / 1024
    print(f"[OK] TTS audio generated: {output_path} ({size_kb:.1f} KB)")

def mix_audio_with_delay(video_path, new_audio_path, output_path, delay_sec):
    """Mix new audio with existing video audio, delayed by specified seconds."""
    print(f"Mixing audio tracks with {delay_sec}s delay...")

    ffmpeg_exe = imageio_ffmpeg.get_ffmpeg_exe()

    # Use filter_complex to:
    # 1. Delay the new voice-over by delay_sec seconds
    # 2. Mix it with the original audio
    # adelay expects milliseconds
    delay_ms = int(delay_sec * 1000)

    cmd = [
        ffmpeg_exe,
        "-i", str(video_path),
        "-i", str(new_audio_path),
        "-filter_complex",
        f"[1:a]adelay={delay_ms}|{delay_ms}[delayed];[0:a][delayed]amix=inputs=2:duration=first:dropout_transition=2,volume=2",
        "-c:v", "copy",
        "-c:a", "aac",
        "-b:a", "192k",
        "-movflags", "+faststart",
        "-y",
        str(output_path)
    ]

    print(f"Running ffmpeg with delayed audio mixing...")
    result = subprocess.run(cmd, capture_output=True, text=True)

    if result.returncode != 0:
        print(f"STDERR: {result.stderr}")
        sys.exit(1)

    size_mb = output_path.stat().st_size / (1024 * 1024)
    print(f"[OK] Video with delayed audio created: {output_path} ({size_mb:.1f} MB)")

async def main():
    if not VIDEO_PATH.exists():
        print(f"ERROR: Backup video not found at {VIDEO_PATH}")
        sys.exit(1)

    print(f"Using backup video: {VIDEO_PATH}")

    # Generate TTS
    await generate_tts("Aumazing", TEMP_AUDIO)

    # Mix audio with delay
    mix_audio_with_delay(VIDEO_PATH, TEMP_AUDIO, OUTPUT_PATH, DELAY_SECONDS)

    # Cleanup
    if TEMP_AUDIO.exists():
        TEMP_AUDIO.unlink()
        print("[OK] Cleaned up temporary audio file")

    print(f"\n[OK] Done!")
    print(f"  Output: {OUTPUT_PATH}")
    print(f"\nThe 'Aumazing' voice-over will play at {DELAY_SECONDS} seconds into the video.")

if __name__ == "__main__":
    asyncio.run(main())
