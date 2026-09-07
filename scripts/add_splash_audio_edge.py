#!/usr/bin/env python3
"""Add 'Aumazing' voice-over to splash screen video using edge-tts.

Uses Microsoft Edge TTS (already used in the project) and ffmpeg.

Usage:
  pip install edge-tts
  python scripts/add_splash_audio_edge.py

Input:
  packages/assets/videos/Aumazing_Splash_Screen_Generation.webm
Output:
  packages/assets/videos/aumazing_splash_with_audio.webm
"""

import asyncio
import subprocess
import sys
from pathlib import Path

import edge_tts
import imageio_ffmpeg  # Use the project's bundled ffmpeg

# ── Paths ─────────────────────────────────────────────────────────────
SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parent
VIDEO_PATH = PROJECT_ROOT / "packages" / "assets" / "videos" / "Aumazing_Splash_Screen_Generation.webm"
OUTPUT_PATH = PROJECT_ROOT / "packages" / "assets" / "videos" / "aumazing_splash_with_audio.webm"
TEMP_AUDIO = PROJECT_ROOT / "packages" / "assets" / "videos" / "temp_aumazing.mp3"

# Use the same voice as the project's main voice-over system
VOICE = "en-US-AnaNeural"  # Microsoft's child voice - warm, kid-friendly

async def generate_tts(text, output_path):
    """Generate TTS audio using edge-tts."""
    print(f"Generating TTS for: '{text}' using {VOICE}...")

    # Apply emotion profile similar to celebration category
    # Excited, joyful but not overwhelming for kids with ASD
    communicate = edge_tts.Communicate(
        text,
        VOICE,
        rate="+10%",   # Slightly faster, energetic
        pitch="+20Hz"  # Bright, cheerful
    )

    await communicate.save(str(output_path))
    print(f"[OK] TTS audio generated: {output_path}")

def combine_audio_video(video_path, audio_path, output_path):
    """Combine audio and video using ffmpeg."""
    print("Combining audio and video with ffmpeg...")

    # Get ffmpeg executable from imageio-ffmpeg
    ffmpeg_exe = imageio_ffmpeg.get_ffmpeg_exe()

    # Combine video and audio
    # Note: The input video is H264, but WebM requires VP9/VP8
    # We need to re-encode to VP9 for proper WebM output
    cmd = [
        ffmpeg_exe,
        "-i", str(video_path),
        "-i", str(audio_path),
        "-c:v", "libvpx-vp9",  # Encode video to VP9 for WebM
        "-c:a", "libvorbis",   # Encode audio to vorbis for webm
        "-b:v", "2M",          # Video bitrate
        "-shortest",           # Use shortest stream duration
        "-y",                  # Overwrite output
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
        print("Run generate_splash_video.py first")
        sys.exit(1)

    # Step 1: Generate TTS
    await generate_tts("Aumazing", TEMP_AUDIO)

    # Step 2: Combine with video
    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    combine_audio_video(VIDEO_PATH, TEMP_AUDIO, OUTPUT_PATH)

    # Step 3: Cleanup
    if TEMP_AUDIO.exists():
        TEMP_AUDIO.unlink()
        print("[OK] Cleaned up temporary audio file")

    print(f"\n[OK] Splash screen with audio generated successfully!")
    print(f"  Output: {OUTPUT_PATH}")

if __name__ == "__main__":
    asyncio.run(main())
