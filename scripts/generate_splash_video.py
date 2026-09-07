#!/usr/bin/env python3
"""Generate Aumazing splash screen video using kie.ai API.

Creates an engaging, ASD-friendly animated splash screen featuring:
- The new Aumazing logo
- A friendly character animation
- Voice-over saying "Aumazing"
- Calm, non-overstimulating visuals

Usage:
  set KIE_API_KEY=...
  python scripts/generate_splash_video.py

Output:
  packages/assets/videos/Aumazing_Splash_Screen_Generation.webm
"""

import argparse
import base64
import json
import os
import sys
import time
from pathlib import Path

import requests

# ── Paths ─────────────────────────────────────────────────────────────
SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parent
LOGO_PATH = PROJECT_ROOT / "tools" / "logo_gen" / "aumazing_logo_unified.png"
OUTPUT_PATH = PROJECT_ROOT / "packages" / "assets" / "videos" / "Aumazing_Splash_Screen_Generation.webm"

JOBS_API = "https://api.kie.ai"
UPLOAD_API = "https://kieai.redpandaai.co"

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

def upload_image(api_key, image_path):
    """Upload image to kie.ai and return the URL."""
    print(f"Uploading {image_path.name}...")

    with open(image_path, "rb") as f:
        img_b64 = base64.b64encode(f.read()).decode()

    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
        "User-Agent": "Mozilla/5.0"
    }

    payload = {
        "base64Data": f"data:image/png;base64,{img_b64}",
        "uploadPath": "images/aumazing",
        "fileName": image_path.name
    }

    resp = requests.post(
        f"{UPLOAD_API}/api/file-base64-upload",
        headers=headers,
        json=payload,
        timeout=300
    )
    resp.raise_for_status()
    data = resp.json()

    if not data.get("success"):
        print(f"Upload failed: {data}")
        sys.exit(1)

    url = data["data"]["downloadUrl"]
    print(f"[OK] Uploaded: {url}")
    return url

def generate_voice(api_key, text):
    """Generate voice-over using kie.ai Gemini TTS."""
    print(f"Generating voice for: '{text}'...")

    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
        "User-Agent": "Mozilla/5.0"
    }

    payload = {
        "model": "gemini-tts",
        "text": text,
        "voice": "en-US-Neural2-F",  # Friendly female voice
        "speed": 1.0
    }

    resp = requests.post(
        f"{JOBS_API}/api/v1/tts/generate",
        headers=headers,
        json=payload,
        timeout=30
    )
    resp.raise_for_status()
    data = resp.json()

    if "audio_url" in data:
        print(f"[OK] Voice generated: {data['audio_url']}")
        return data["audio_url"]

    print(f"Voice generation failed: {data}")
    sys.exit(1)

def create_video_task(api_key, logo_url):
    """Create video generation task with kie.ai."""
    print("Creating splash screen video task...")

    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
        "User-Agent": "Mozilla/5.0"
    }

    # ASD-friendly prompt: calm, predictable, engaging but not overwhelming
    prompt = (
        "A gentle, friendly animated splash screen for a children's learning app. "
        "The Aumazing logo with three cute chibi characters appears with a soft, smooth entrance. "
        "A cute cartoon mascot character waves hello in a calm, welcoming way. "
        "Soft pastel colors, gentle movements, no sudden changes, no flashing, "
        "no rapid motion, no overwhelming effects. "
        "The character has a warm smile and kind eyes. "
        "Simple, clear, predictable animation that feels safe and inviting. "
        "Smooth transitions, consistent gentle pace throughout. "
        "The whole scene is cheerful but calm, designed to be comfortable "
        "for children with sensory sensitivities. "
        "The character gives a friendly wave and stays centered in frame. "
        "Style: flat 2D cartoon, soft rounded shapes, high contrast but not harsh, "
        "clean simple design matching the logo's friendly aesthetic."
    )

    payload = {
        "model": "bytedance/seedance-2",
        "input": {
            "prompt": prompt,
            "first_frame_url": logo_url,
            "generate_audio": False,
            "resolution": "720p",
            "aspect_ratio": "3:4",
            "duration": 4
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
        print(f"Task creation failed: {data}")
        sys.exit(1)

    task_id = data["data"]["taskId"]
    print(f"[OK] Task created: {task_id}")
    return task_id

    resp = requests.post(
        f"{JOBS_API}/api/v1/jobs/createTask",
        headers=headers,
        json=payload,
        timeout=30
    )
    resp.raise_for_status()
    data = resp.json()

    if data.get("code") != 0:
        print(f"Task creation failed: {data}")
        sys.exit(1)

    task_id = data["data"]["taskId"]
    print(f"[OK] Task created: {task_id}")
    return task_id

def poll_task(api_key, task_id):
    """Poll task until complete and return video URL."""
    print(f"Waiting for video generation (taskId: {task_id})...")

    headers = {
        "Authorization": f"Bearer {api_key}",
        "User-Agent": "Mozilla/5.0"
    }

    max_wait = 600  # 10 minutes max
    start = time.time()

    while time.time() - start < max_wait:
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
        print(f"  Status: {status}")

        if status == "success":
            result_json = json.loads(record["resultJson"])
            video_url = result_json["resultUrls"][0]
            credits = record.get("creditsConsumed", "unknown")
            print(f"[OK] Video ready: {video_url}")
            print(f"  Credits used: {credits}")
            return video_url
        elif status == "fail":
            print(f"Video generation failed: {record.get('failMsg')}")
            sys.exit(1)

        time.sleep(10)

    print("Timeout waiting for video generation")
    sys.exit(1)

def download_video(url, output_path):
    """Download video from URL."""
    print(f"Downloading video to {output_path}...")

    headers = {"User-Agent": "Mozilla/5.0"}
    resp = requests.get(url, headers=headers, stream=True, timeout=60)
    resp.raise_for_status()

    output_path.parent.mkdir(parents=True, exist_ok=True)

    with open(output_path, "wb") as f:
        for chunk in resp.iter_content(chunk_size=8192):
            f.write(chunk)

    size_mb = output_path.stat().st_size / (1024 * 1024)
    print(f"[OK] Downloaded: {size_mb:.1f} MB")

def main():
    parser = argparse.ArgumentParser(description="Generate Aumazing splash screen video")
    parser.add_argument("--logo", type=Path, default=LOGO_PATH,
                       help="Path to logo image")
    parser.add_argument("--output", type=Path, default=OUTPUT_PATH,
                       help="Output video path")
    args = parser.parse_args()

    if not args.logo.exists():
        print(f"ERROR: Logo not found at {args.logo}")
        print("Please provide the path to the Aumazing logo PNG")
        sys.exit(1)

    api_key = load_api_key()

    # Step 1: Upload logo
    logo_url = upload_image(api_key, args.logo)

    # Step 2: Create video generation task
    # Note: Voice-over "Aumazing" should be added separately after generation
    # The video will be generated with gentle animation suitable for kids with ASD
    task_id = create_video_task(api_key, logo_url)

    # Step 3: Poll until complete
    video_url = poll_task(api_key, task_id)

    # Step 4: Download result
    download_video(video_url, args.output)

    print(f"\n[OK] Splash screen generated successfully!")
    print(f"  Output: {args.output}")
    print(f"\nNote: To add voice-over 'Aumazing', you'll need to:")
    print(f"  1. Generate TTS audio separately")
    print(f"  2. Combine audio and video using ffmpeg")

if __name__ == "__main__":
    main()
