#!/usr/bin/env python3
"""Add 'Aumazing' voice-over to splash screen video.

Uses kie.ai Gemini TTS to generate audio, then combines with video using ffmpeg.

Usage:
  set KIE_API_KEY=...
  python scripts/add_splash_audio.py

Input:
  packages/assets/videos/Aumazing_Splash_Screen_Generation.webm
Output:
  packages/assets/videos/aumazing_splash_with_audio.webm
"""

import json
import os
import subprocess
import sys
import time
from pathlib import Path

import requests

# ── Paths ─────────────────────────────────────────────────────────────
SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parent
VIDEO_PATH = PROJECT_ROOT / "packages" / "assets" / "videos" / "Aumazing_Splash_Screen_Generation.webm"
OUTPUT_PATH = PROJECT_ROOT / "packages" / "assets" / "videos" / "aumazing_splash_with_audio.webm"
TEMP_AUDIO = PROJECT_ROOT / "packages" / "assets" / "videos" / "temp_aumazing.wav"

JOBS_API = "https://api.kie.ai"

def load_api_key():
    """Load KIE_API_KEY from environment or .env file."""
    key = os.environ.get("KIE_API_KEY")
    if key:
        return key

    env_file = PROJECT_ROOT / "tools" / "voice_gen" / ".env"
    if env_file.exists():
        with open(env_file) as f:
            for line in f:
                if line.startswith("KIE_API_KEY="):
                    return line.split("=", 1)[1].strip()

    print("ERROR: KIE_API_KEY not found in environment or tools/voice_gen/.env")
    sys.exit(1)

def generate_tts(api_key, text):
    """Generate TTS audio using kie.ai Gemini TTS."""
    print(f"Generating TTS for: '{text}'...")

    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
        "User-Agent": "Mozilla/5.0"
    }

    # Use Gemini TTS with dialogue format
    payload = {
        "model": "google/gemini-3-1-flash-tts",
        "input": {
            "speakers": [{
                "speaker_id": "Speaker 1",
                "voice": "Puck",  # Friendly, energetic child voice
                "gender": "female"
            }],
            "dialogue_turns": [{
                "speaker_id": "Speaker 1",
                "text": text
            }]
        }
    }

    resp = requests.post(
        f"{JOBS_API}/api/v1/jobs/createTask",
        headers=headers,
        json=payload,
        timeout=60
    )
    resp.raise_for_status()
    data = resp.json()

    if data.get("code") != 200:
        print(f"TTS task creation failed: {data}")
        sys.exit(1)

    task_id = data["data"]["taskId"]
    print(f"[OK] TTS task created: {task_id}")

    # Poll for completion
    print("Waiting for TTS generation...")
    for i in range(60):
        time.sleep(5)
        resp = requests.get(
            f"{JOBS_API}/api/v1/jobs/recordInfo",
            params={"taskId": task_id},
            headers=headers,
            timeout=60
        )
        resp.raise_for_status()
        data = resp.json()

        if not data.get("data"):
            print(f"Poll failed: {data}")
            sys.exit(1)

        record = data["data"]
        status = record.get("state")

        if status == "success":
            result_json = json.loads(record["resultJson"])
            audio_url = result_json["resultUrls"][0]
            print(f"[OK] TTS ready: {audio_url}")
            return audio_url
        elif status == "fail":
            print(f"TTS generation failed: {record.get('failMsg')}")
            sys.exit(1)

    print("Timeout waiting for TTS")
    sys.exit(1)

def download_audio(url, output_path):
    """Download audio from URL."""
    print(f"Downloading audio to {output_path}...")

    headers = {"User-Agent": "Mozilla/5.0"}
    resp = requests.get(url, headers=headers, stream=True, timeout=60)
    resp.raise_for_status()

    with open(output_path, "wb") as f:
        for chunk in resp.iter_content(chunk_size=8192):
            f.write(chunk)

    print(f"[OK] Audio downloaded: {output_path.stat().st_size / 1024:.1f} KB")

def combine_audio_video(video_path, audio_path, output_path):
    """Combine audio and video using ffmpeg."""
    print("Combining audio and video...")

    # Use ffmpeg to merge audio and video
    # -shortest ensures video duration is used (audio may be longer)
    cmd = [
        "ffmpeg",
        "-i", str(video_path),
        "-i", str(audio_path),
        "-c:v", "copy",  # Copy video stream as-is
        "-c:a", "libvorbis",  # Encode audio to vorbis for webm
        "-shortest",  # Use shortest stream duration
        "-y",  # Overwrite output
        str(output_path)
    ]

    result = subprocess.run(cmd, capture_output=True, text=True)

    if result.returncode != 0:
        print(f"ffmpeg failed: {result.stderr}")
        sys.exit(1)

    print(f"[OK] Combined video created: {output_path}")

def main():
    if not VIDEO_PATH.exists():
        print(f"ERROR: Video not found at {VIDEO_PATH}")
        print("Run generate_splash_video.py first")
        sys.exit(1)

    api_key = load_api_key()

    # Step 1: Generate TTS
    audio_url = generate_tts(api_key, "Aumazing")

    # Step 2: Download audio
    download_audio(audio_url, TEMP_AUDIO)

    # Step 3: Combine with video
    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    combine_audio_video(VIDEO_PATH, TEMP_AUDIO, OUTPUT_PATH)

    # Step 4: Cleanup
    if TEMP_AUDIO.exists():
        TEMP_AUDIO.unlink()
        print("[OK] Cleaned up temporary audio file")

    print(f"\n[OK] Splash screen with audio generated successfully!")
    print(f"  Output: {OUTPUT_PATH}")
    print(f"  Size: {OUTPUT_PATH.stat().st_size / (1024 * 1024):.1f} MB")

if __name__ == "__main__":
    main()
