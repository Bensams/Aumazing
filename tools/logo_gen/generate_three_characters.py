#!/usr/bin/env python3
"""Generate Aumazing logo with three specific characters positioned correctly."""

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


def generate_logo() -> Path:
    """Generate the logo using nano-banana text-to-image."""
    output_path = SCRIPT_DIR / "aumazing_logo_three_characters.png"

    prompt = """A vibrant square app icon logo for 'Aumazing' educational app, 1024x1024px.

BACKGROUND: Colorful diagonal geometric pattern filling the entire square - bright triangular sections in vivid purple, sunny yellow, bright cyan, lime green, and coral pink meeting at diagonal angles (AutiSpark style).

THREE CHARACTERS standing in a row, full body from head to feet:

LEFT CHARACTER (BPS in teddy bear costume):
- A young Filipino boy with fair skin, warm brown eyes, messy spiky black hair
- Wearing a soft brown teddy bear onesie costume with round teddy ears on the hood, button eyes on the chest
- Big friendly smile, large round eyes with bright blue irises and white highlights
- Standing on the LEFT side of the composition
- Full body visible, facing forward

CENTER CHARACTER (LEXIANNE in panda costume) - MAIN FOCAL POINT:
- A young Filipina girl with fair skin, warm brown eyes, long wavy dark brown hair
- Wearing a black and white panda onesie costume with round panda ears on the hood, distinctive black eye patches
- Big warm smile, large round eyes with bright blue irises and white highlights
- Standing in the CENTER, slightly larger and more prominent than the others
- Full body visible, facing forward
- She is the main character, positioned centrally

RIGHT CHARACTER (REIZ in fox costume):
- A young Filipino boy with fair skin, dark grey eyes, tousled dark charcoal-black hair
- Wearing an orange fox onesie costume with pointy fox ears on the hood, white chest fur detail
- Friendly smile, large round eyes with bright blue irises and white highlights
- Standing on the RIGHT side of the composition
- Full body visible, facing forward

STYLE:
- Cute chibi-style proportions with slightly larger heads
- Flat 2D illustration with solid colors, no gradients
- Thick bold dark outlines for clarity
- Child-friendly, engaging, professional app icon quality
- High contrast between characters and colorful background
- Simple, clean shapes suitable for children with ASD

The three children should be arranged LEFT to RIGHT: BPS (teddy), LEXIANNE (panda - CENTER), REIZ (fox).
All three full body, standing, filling the square with the vibrant geometric background visible around them."""

    print("\n[Generating logo with three characters]")
    print("  Creating task...")

    body = {
        "model": "google/nano-banana",
        "input": {
            "prompt": prompt,
            "output_format": "png",
            "image_size": "1:1",
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
    print("Aumazing Three Characters Logo Generator")
    print("=" * 60)
    print("\nArrangement: BPS (left) - LEXIANNE (center) - REIZ (right)")

    result = generate_logo()

    print("\n" + "=" * 60)
    print("Logo Generated!")
    print("=" * 60)
    print(f"  {result}")
    print()


if __name__ == "__main__":
    main()
