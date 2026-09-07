#!/usr/bin/env python3
"""Generate Aumazing wordmark logo with three characters using kie.ai."""

import json
import os
import sys
import time
from pathlib import Path

import requests

SCRIPT_DIR = Path(__file__).resolve().parent
JOBS_API = "https://api.kie.ai"
KIE_API_KEY = os.environ["KIE_API_KEY"]  # source tools/voice_gen/.env first


def headers() -> dict:
    return {
        "Authorization": f"Bearer {KIE_API_KEY}",
        "Content-Type": "application/json"
    }


def generate_wordmark_logo() -> Path:
    """Generate the Aumazing wordmark logo with three characters."""
    output_path = SCRIPT_DIR / "aumazing_wordmark_final.png"

    prompt = """Create a vibrant, playful logo for 'Aumazing' educational app in a wide horizontal format (16:9 ratio).

TOP SECTION - THREE CHARACTERS:
On the upper portion, arrange THREE cute chibi-style children characters in animal costumes from LEFT to RIGHT:

LEFT: A young Filipino boy (BPS) wearing a soft brown teddy bear onesie costume with round teddy ears on the hood, button eyes on the costume chest. Fair skin, messy spiky black hair, warm brown eyes, big friendly smile.

CENTER (MAIN FOCUS): A young Filipina girl (LEXIANNE) wearing a black and white panda onesie costume with round panda ears on the hood, distinctive black eye patches. Fair skin, long wavy dark brown hair, warm brown eyes, big warm smile. She should be slightly larger and more prominent.

RIGHT: A young Filipino boy (REIZ) wearing an orange fox onesie costume with pointy fox ears on the hood, white chest fur detail. Fair skin, tousled dark charcoal-black hair, dark grey eyes, friendly smile.

All three characters have:
- Large, round, friendly eyes with bright highlights
- Big warm smiles
- Full body visible (head to feet)
- Facing forward
- Thick bold outlines

DECORATIVE ELEMENTS around the characters:
- A large happy yellow star character with a smiling face on the far left
- Colorful puzzle pieces floating around (orange, yellow, green, blue, red puzzle pieces)
- Small sparkle stars scattered throughout
- An open book icon
- Everything cheerful and playful

BOTTOM SECTION - TEXT:
Large, bold, colorful text spelling "AUMAZING" with each letter in a different bright color:
- A: Blue
- U: Blue
- M: Orange
- A: Orange
- Z: Yellow (with a small puzzle piece design integrated into the letter)
- I: Green
- N: Green
- G: Coral red

The letters should be thick, rounded, bubbly, child-friendly font style with slight 3D effect/gradient.

Below that, in smaller blue text: "GAMIFIED LEARNING APP"

STYLE:
- Bright, vibrant colors
- Flat modern illustration style
- High contrast
- Child-friendly and engaging
- Professional app branding quality
- Clean white or very light background
- Cheerful, educational, playful aesthetic

Wide horizontal composition (16:9), with characters and decorations on top, large colorful text on bottom."""

    print("\n[Generating Aumazing wordmark logo]")
    print("  Creating task...")

    body = {
        "model": "google/nano-banana",
        "input": {
            "prompt": prompt,
            "output_format": "png",
            "image_size": "16:9",
            "num_inference_steps": 28,
            "guidance_scale": 3.5
        }
    }

    r = requests.post(
        f"{JOBS_API}/api/v1/jobs/createTask",
        headers=headers(),
        json=body,
        timeout=60
    )
    r.raise_for_status()
    d = r.json()

    if d.get("code") != 200:
        sys.exit(f"createTask failed: {d}")

    task_id = d["data"]["taskId"]
    print(f"  Task ID: {task_id}")

    # Poll for completion
    data = {}
    for attempt in range(90):
        time.sleep(5)
        r = requests.get(
            f"{JOBS_API}/api/v1/jobs/recordInfo",
            headers=headers(),
            params={"taskId": task_id},
            timeout=60
        )
        data = r.json().get("data") or {}

        if data.get("state") == "success":
            print(f"  [OK] Generated in {data.get('costTime')}ms")
            print(f"    Credits: {data.get('creditsConsumed')}")
            break
        elif data.get("state") == "fail":
            sys.exit(f"Generation failed: {data.get('failMsg')}")
        elif attempt % 6 == 0:
            print(f"  ... generating ({attempt*5}s)")
    else:
        sys.exit("Generation timed out after 450s")

    # Download result
    result_json = json.loads(data["resultJson"])
    url = result_json["resultUrls"][0]

    print(f"  Downloading...")
    img_data = requests.get(url, timeout=600).content
    output_path.write_bytes(img_data)

    print(f"  [OK] Saved: {output_path}")
    print(f"    Size: {len(img_data) / 1024:.1f} KB")

    return output_path


def main():
    SCRIPT_DIR.mkdir(parents=True, exist_ok=True)

    print("=" * 60)
    print("Aumazing Wordmark Logo Generator")
    print("=" * 60)
    print("\nGenerating logo with:")
    print("  - Three characters: BPS (Teddy), Lexianne (Panda), Reiz (Fox)")
    print("  - Colorful AUMAZING text")
    print("  - Puzzle pieces and decorations")

    result = generate_wordmark_logo()

    print("\n" + "=" * 60)
    print("Wordmark Logo Generated!")
    print("=" * 60)
    print(f"  {result}")
    print()


if __name__ == "__main__":
    main()
