#!/usr/bin/env python3
"""Add 'Aumazing' voice-over to the existing splash screen video.

Uses Microsoft Edge TTS and ffmpeg to add audio to the existing video.

Usage:
  pip install edge-tts
  python scripts/add_voice_to_existing_splash.py

Input:
  packages/assets/videos/Aumazing_Splash_Screen.mp4
Output:
  packages/assets/videos/Aumazing_Splash_Screen.mp4 (overwritten)
"""

import asyncio
import subprocess
import sys
from pathlib import Path
import shutil

import edge_tts
import imageio_ffmpeg

# ── Paths ─────────────────────────────────────────────────────────────
SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parent
VIDEO_PATH = PROJECT_ROOT / "packages" / "assets" / "videos" / "Aumazing_Splash_Screen.mp4"
BACKUP_PATH = PROJECT_ROOT / "packages" / "assets" / "videos" / "Aumazing_Splash_Screen_backup.mp4"
TEMP_AUDIO = PROJECT_ROOT / "packages" / "assets" / "videos" / "temp_aumazing_voice.mp3"
TEMP_OUTPUT = PROJECT_ROOT / "packages" / "assets" / "videos" / "temp_output.mp4"

# Use the same voice as the project's main voice-over system
VOICE = "en-US-AnaNeural"  # Microsoft's child voice - warm, kid-friendly

async def generate_tts(text, output_path):
    """Generate TTS audio using edge-tts."""
    print(f"Generating TTS for: '{text}' using {VOICE}...")

    # Apply emotion profile - cheerful and welcoming for splash screen
    communicate = edge_tts.Communicate(
        text,
        VOICE,
        rate="+8%",   # Slightly energetic
        pitch="+18Hz"  # Warm, friendly
    )

    await communicate.save(str(output_path))
    print(f"[OK] TTS audio generated: {output_path}")

def combine_audio_video(video_path, audio_path, output_path):
    """Combine audio and video using ffmpeg."""
    print("Combining audio and video with ffmpeg...")

    # Get ffmpeg executable from imageio-ffmpeg
    ffmpeg_exe = imageio_ffmpeg.get_ffmpeg_exe()

    # Combine video and audio
    # Keep the original video codec, add audio track
    cmd = [
        ffmpeg_exe,
        "-i", str(video_path),
        "-i", str(audio_path),
        "-c:v", "copy",  # Copy video stream as-is (keep original quality)
        "-c:a", "aac",   # Encode audio to AAC for MP4
        "-b:a", "128k",  # Audio bitrate
        "-shortest",     # Use shortest stream duration
        "-y",            # Overwrite output
        str(output_path)
    ]

    result = subprocess.run(cmd, capture_output=True, text=True)

    if result.returncode != 0:
        print(f"ffmpeg error: {result.stderr}")
        sys.exit(1)

    size_mb = output_path.stat().st_size / (1024 * 1024)
    print(f"[OK] Combined video created: {output_path} ({size_mb:.1f} MB)")

async def main():
    if not VIDEO_PATH.exists():
        print(f"ERROR: Video not found at {VIDEO_PATH}")
        sys.exit(1)

    # Step 1: Create backup of original video
    print(f"Creating backup: {BACKUP_PATH.name}")
    shutil.copy2(VIDEO_PATH, BACKUP_PATH)
    print("[OK] Backup created")

    # Step 2: Generate TTS
    await generate_tts("Aumazing", TEMP_AUDIO)

    # Step 3: Combine with video
    combine_audio_video(VIDEO_PATH, TEMP_AUDIO, TEMP_OUTPUT)

    # Step 4: Replace original with new version
    print("Replacing original video...")
    shutil.move(TEMP_OUTPUT, VIDEO_PATH)
    print(f"[OK] Original video updated: {VIDEO_PATH}")

    # Step 5: Cleanup
    if TEMP_AUDIO.exists():
        TEMP_AUDIO.unlink()
        print("[OK] Cleaned up temporary audio file")

    print(f"\n[OK] Voice-over added successfully!")
    print(f"  Updated: {VIDEO_PATH}")
    print(f"  Backup saved: {BACKUP_PATH}")
    print(f"\nTo restore original: copy {BACKUP_PATH.name} back to {VIDEO_PATH.name}")

if __name__ == "__main__":
    asyncio.run(main())
