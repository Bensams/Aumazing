#!/usr/bin/env python3
"""Add 'Aumazing' voice-over while keeping original audio.

Mixes the new voice-over with any existing audio in the video.
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

def mix_audio_with_video(video_path, new_audio_path, output_path):
    """Mix new audio with existing video audio using ffmpeg."""
    print("Mixing audio tracks with ffmpeg...")

    ffmpeg_exe = imageio_ffmpeg.get_ffmpeg_exe()

    # Use filter_complex to mix original audio with new voice-over
    # [0:a] = original video audio
    # [1:a] = new voice-over
    # Mix them together with amerge + pan
    cmd = [
        ffmpeg_exe,
        "-i", str(video_path),
        "-i", str(new_audio_path),
        "-filter_complex",
        "[0:a][1:a]amix=inputs=2:duration=first:dropout_transition=2,volume=2",
        "-c:v", "copy",
        "-c:a", "aac",
        "-b:a", "192k",
        "-movflags", "+faststart",
        "-y",
        str(output_path)
    ]

    print(f"Running ffmpeg with audio mixing...")
    result = subprocess.run(cmd, capture_output=True, text=True)

    if result.returncode != 0:
        print(f"STDERR: {result.stderr}")
        sys.exit(1)

    size_mb = output_path.stat().st_size / (1024 * 1024)
    print(f"[OK] Video with mixed audio created: {output_path} ({size_mb:.1f} MB)")

async def main():
    if not VIDEO_PATH.exists():
        print(f"ERROR: Backup video not found at {VIDEO_PATH}")
        sys.exit(1)

    print(f"Using backup video: {VIDEO_PATH}")

    # Generate TTS
    await generate_tts("Aumazing", TEMP_AUDIO)

    # Mix audio with video
    mix_audio_with_video(VIDEO_PATH, TEMP_AUDIO, OUTPUT_PATH)

    # Cleanup
    if TEMP_AUDIO.exists():
        TEMP_AUDIO.unlink()
        print("[OK] Cleaned up temporary audio file")

    print(f"\n[OK] Done!")
    print(f"  Output: {OUTPUT_PATH}")
    print(f"\nThe video now has:")
    print(f"  - Original background audio/music")
    print(f"  - 'Aumazing' voice-over mixed on top")

if __name__ == "__main__":
    asyncio.run(main())
