#!/usr/bin/env python3
"""Generate the Aumazing app icon using kie.ai nano-banana-edit.

Usage:
  pip install pillow requests
  export KIE_API_KEY=...
  python tools/logo_gen/generate_logo.py
"""

import base64
import json
import os
import sys
import time
from pathlib import Path

import requests
from PIL import Image

# ── Paths ─────────────────────────────────────────────────────────────
SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parent.parent
OUT = SCRIPT_DIR / "asd_friendly_simple_square_icon.png"

JOBS_API = "https://api.kie.ai"
UPLOAD_API = "https://kieai.redpandaai.co"

# Reference image URL
REF_URL = "https://tempfile.redpandaai.co/kieai/11736670/images/aumazing/Reiz_chibi_Fox.png"

PROMPT = """A simple square app icon for 'Aumazing'. A cute chibi-style character wearing an orange fox costume with pointy ears on the hood, white chest fur detail, and a playful friendly look. The character sits in the center with legs crossed, looking friendly and approachable. Solid soft yellow background (#FFE66D). Thick dark outlines on the character for maximum clarity. NO gradients, NO shadows, NO decorative elements, NO busy backgrounds, NO text. Just the character on a flat solid color. High visual contrast, predictable square shape, calming and clear. Design follows ASD-friendly principles: simplicity, predictability, high contrast. Square format 1024x1024px."""


def key() -> str:
    k = os.environ.get("KIE_API_KEY")
    if not k:
        sys.exit("KIE_API_KEY is not set")
    return k


def headers() -> dict:
    return {"Authorization": f"Bearer {key()}", "Content-Type": "application/json"}


def generate() -> str:
    """Generate the logo and return the result URL."""
    body = {
        "model": "google/nano-banana-edit",
        "input": {
            "prompt": PROMPT,
            "image_urls": [REF_URL],
            "output_format": "png",
            "image_size": "1:1",
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
    print("Waiting for generation to complete...")

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
        sys.exit("Generation timed out after 450 seconds")

    url = json.loads(data["resultJson"])["resultUrls"][0]
    print(f"Result URL: {url}")
    return url


def download_and_save(url: str) -> None:
    """Download the generated image and save it."""
    print(f"Downloading image...")

    # Add User-Agent header as required by kie.ai CDN
    img_headers = {"User-Agent": "Mozilla/5.0"}
    response = requests.get(url, headers=img_headers, timeout=600)
    response.raise_for_status()

    # Save the image
    SCRIPT_DIR.mkdir(parents=True, exist_ok=True)
    OUT.write_bytes(response.content)

    # Verify it's a valid image
    img = Image.open(OUT)
    print(f"Saved to {OUT}")
    print(f"  Size: {img.size[0]}x{img.size[1]}px")
    print(f"  File size: {OUT.stat().st_size / 1024:.1f} KB")


def main():
    if not os.environ.get("KIE_API_KEY"):
        print("Error: KIE_API_KEY environment variable is not set")
        print("Load it from tools/voice_gen/.env:")
        print("  source tools/voice_gen/.env")
        sys.exit(1)

    url = generate()
    download_and_save(url)

    print("\n" + "="*60)
    print("DONE")
    print(f"Image URL: {url}")
    print(f"Saved to: {OUT}")
    print("="*60)


if __name__ == "__main__":
    main()
