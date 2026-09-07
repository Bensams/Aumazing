#!/usr/bin/env python3
"""Generate the Aumazing splash screen (9:16, no text) using kie.ai nano-banana.

Usage:
  export KIE_API_KEY=...   # lives in tools/voice_gen/.env — never commit it
  python tools/logo_gen/generate_splash.py
"""

import json
import os
import sys
import time
from pathlib import Path

import requests

SCRIPT_DIR = Path(__file__).resolve().parent
OUT = SCRIPT_DIR / "splash_screen_9x16.png"

JOBS_API = "https://api.kie.ai"

PROMPT = (
    "A playful and vibrant mobile app splash screen UI, centered around a "
    "whimsical, brightly lit world. Features a giant smiling cartoon star "
    "with a cheerful face, colorful puzzle pieces floating in the air, and a "
    "curved rainbow bridge made of interlocking puzzle pieces arcing across "
    "the scene. Soft pastel gradient background of sky blue and light yellow, "
    "dreamy lighting, clean vector 2D chibi anime art style, bright rainbow "
    "color palette, flat design aesthetics, hyper-detailed, cheerful "
    "atmosphere, mobile splash screen design. Absolutely no text, no font, no "
    "typography, no watermark, no buttons, no phone frame, no mockup frame."
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
        "model": "google/nano-banana",
        "input": {
            "prompt": PROMPT,
            "output_format": "png",
            "image_size": "9:16",
        },
    }

    print("Creating generation task...")
    r = requests.post(f"{JOBS_API}/api/v1/jobs/createTask",
                      headers=headers(), json=body, timeout=60)
    r.raise_for_status()
    d = r.json()
    if d.get("code") != 200:
        sys.exit(f"createTask failed: {d}")

    task_id = d["data"]["taskId"]
    print(f"Task created: {task_id}")

    data = {}
    for i in range(90):
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
        if (i + 1) % 6 == 0:
            print(f"  Still waiting... ({(i + 1) * 5}s)")
    else:
        sys.exit("Generation timed out")

    url = json.loads(data["resultJson"])["resultUrls"][0]
    print(f"Result URL: {url}")
    return url


def download(url: str) -> None:
    # kie.ai CDN requires a User-Agent header
    r = requests.get(url, headers={"User-Agent": "Mozilla/5.0"}, timeout=600)
    r.raise_for_status()
    OUT.write_bytes(r.content)
    print(f"Saved to {OUT} ({OUT.stat().st_size / 1024:.1f} KB)")


def main():
    url = generate()
    download(url)


if __name__ == "__main__":
    main()
