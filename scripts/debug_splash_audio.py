#!/usr/bin/env python3
"""Debug and fix audio in splash screen.

Checks if audio exists and re-adds it properly.
"""

import asyncio
import subprocess
import sys
from pathlib import Path
import shutil

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

def add_audio_to_video(video_path, audio_path, output_path):
    """Add audio track to video using ffmpeg."""
    print("Adding audio to video with ffmpeg...")

    ffmpeg_exe = imageio_ffmpeg.get_ffmpeg_exe()

    # Use filter_complex to mix audio properly and ensure it plays
    cmd = [
        ffmpeg_exe,
        "-i", str(video_path),
        "-i", str(audio_path),
        "-c:v", "copy",           # Copy video as-is
        "-c:a", "aac",            # Encode audio to AAC
        "-b:a", "192k",           # Higher bitrate for clarity
        "-map", "0:v:0",          # Map video from first input
        "-map", "1:a:0",          # Map audio from second input
        "-shortest",              # Match shortest stream
        "-movflags", "+faststart", # Optimize for streaming
        "-y",
        str(output_path)
    ]

    print(f"Running: {' '.join(str(x) for x in cmd)}")
    result = subprocess.run(cmd, capture_output=True, text=True)

    if result.returncode != 0:
        print(f"STDERR: {result.stderr}")
        sys.exit(1)

    size_mb = output_path.stat().st_size / (1024 * 1024)
    print(f"[OK] Video with audio created: {output_path} ({size_mb:.1f} MB)")

    # Show some of the ffmpeg output for verification
    if "audio" in result.stderr.lower():
        print("\nFFmpeg output (audio-related):")
        for line in result.stderr.split('\n'):
            if 'audio' in line.lower() or 'Stream' in line:
                print(f"  {line}")

async def main():
    if not VIDEO_PATH.exists():
        print(f"ERROR: Backup video not found at {VIDEO_PATH}")
        sys.exit(1)

    print(f"Using backup video: {VIDEO_PATH}")

    # Generate TTS
    await generate_tts("Aumazing", TEMP_AUDIO)

    # Add audio to video
    add_audio_to_video(VIDEO_PATH, TEMP_AUDIO, OUTPUT_PATH)

    # Cleanup
    if TEMP_AUDIO.exists():
        TEMP_AUDIO.unlink()
        print("[OK] Cleaned up temporary audio file")

    print(f"\n[OK] Done!")
    print(f"  Output: {OUTPUT_PATH}")
    print(f"\nPlease test the video to verify audio is audible.")

if __name__ == "__main__":
    asyncio.run(main())
