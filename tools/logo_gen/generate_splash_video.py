#!/usr/bin/env python3
"""Generate a 5-10 second animated splash screen video using kie.ai.

Usage:
  export KIE_API_KEY=...   # lives in tools/voice_gen/.env — never commit it
  python tools/logo_gen/generate_splash_video.py
"""

import json
import os
import sys
import time
from pathlib import Path

import requests

SCRIPT_DIR = Path(__file__).resolve().parent
OUT = SCRIPT_DIR / "splash_video.mp4"

JOBS_API = "https://api.kie.ai"

PROMPT = (
    "A playful and vibrant animated mobile splash screen. Camera slowly zooms "
    "into a whimsical world. A giant smiling cartoon star with a cheerful face "
    "gently bobs and sparkles in the center. Colorful puzzle pieces (red, blue, "
    "yellow, orange, pink, green) float and drift playfully through the air with "
    "soft smooth motion. A curved rainbow bridge made of interlocking puzzle "
    "pieces glows and shimmers. Soft pastel gradient background of sky blue and "
    "light yellow with dreamy ethereal lighting. Clean vector 2D chibi anime art "
    "style, bright rainbow color palette, flat design aesthetics. Gentle subtle "
    "animation, smooth calm motion, cheerful welcoming atmosphere. Camera slowly "
    "pushes in toward the smiling star. Absolutely no text, no font, no "
    "typography, no watermark, no buttons, no UI elements."
)


def key() -> str:
    k = os.environ.get("KIE_API_KEY")
    if not k:
        sys.exit("KIE_API_KEY is not set (source tools/voice_gen/.env)")
    return k


def headers() -> dict:
    return {"Authorization": f"Bearer {key()}", "Content-Type": "application/json"}


def generate() -> str:
    body = {
        "model": "google/nano-banana-video",
        "input": {
            "prompt": PROMPT,
            "duration": 10,
            "aspect_ratio": "9:16",
        },
    }

    print("Creating video generation task...")
    print(f"  Model: nano-banana-video")
    print(f"  Duration: 10 seconds")
    print(f"  Aspect ratio: 9:16")

    r = requests.post(f"{JOBS_API}/api/v1/jobs/createTask",
                      headers=headers(), json=body, timeout=60)
    r.raise_for_status()
    d = r.json()
    if d.get("code") != 200:
        sys.exit(f"createTask failed: {d}")

    task_id = d["data"]["taskId"]
    print(f"Task created: {task_id}")
    print("Waiting for video generation (this can take several minutes)...")

    data = {}
    for i in range(180):  # up to 15 minutes
        time.sleep(5)
        data = (requests.get(f"{JOBS_API}/api/v1/jobs/recordInfo",
                             headers=headers(), params={"taskId": task_id},
                             timeout=60).json().get("data") or {})
        state = data.get("state")
        if state == "success":
            print(f"Generation complete ({data.get('costTime')}ms, "
                  f"{data.get('creditsConsumed')} credits)")
            break
        elif state == "fail":
            sys.exit(f"Generation failed: {data.get('failMsg')}")
        if (i + 1) % 12 == 0:
            print(f"  Still waiting... ({(i + 1) * 5}s)")
    else:
        sys.exit("Generation timed out")

    url = json.loads(data["resultJson"])["resultUrls"][0]
    print(f"Result URL: {url}")
    return url


def download(url: str) -> None:
    print("Downloading video...")
    # kie.ai CDN requires a User-Agent header
    r = requests.get(url, headers={"User-Agent": "Mozilla/5.0"}, timeout=600)
    r.raise_for_status()
    OUT.write_bytes(r.content)
    print(f"Saved to {OUT} ({OUT.stat().st_size / 1024 / 1024:.1f} MB)")


def main():
    url = generate()
    download(url)
    print(f"\nVideo URL: {url}")


if __name__ == "__main__":
    main()
