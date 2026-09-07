#!/usr/bin/env python3
"""Generate Aumazing app logo concepts using kie.ai nano-banana.

Usage:
  python tools/logo_gen/generate_logos.py

Output:
  tools/logo_gen/logo_concept_{1,2,3}.png
"""

import json
import os
import sys
import time
from pathlib import Path

import requests

SCRIPT_DIR = Path(__file__).resolve().parent
JOBS_API = "https://api.kie.ai"

# API key provided by user
KIE_API_KEY = os.environ["KIE_API_KEY"]  # source tools/voice_gen/.env first


def headers() -> dict:
    return {
        "Authorization": f"Bearer {KIE_API_KEY}",
        "Content-Type": "application/json"
    }


LOGO_CONCEPTS = {
    "concept_1_mascot": {
        "prompt": (
            "A vibrant app icon logo for 'Aumazing', an educational learning app "
            "for children. The design features three adorable chibi-style cartoon "
            "characters (a teddy bear, a panda, and a pig) grouped together in a "
            "circular composition. They are surrounded by playful learning elements: "
            "colorful stars, ABC letters, numbers 123, small books, and sparkles. "
            "Bright, cheerful colors: sky blue, rose pink, mint green, butter yellow, "
            "and lavender. Clean, thick dark outlines. Flat 2D children's illustration "
            "style. The design is balanced, friendly, and instantly recognizable as an "
            "educational kids' app. White or transparent background. Square format "
            "suitable for app icon."
        ),
        "desc": "Character mascot logo with BPS friends"
    },
    "concept_2_geometric": {
        "prompt": (
            "A modern, playful app icon logo for 'Aumazing', an educational learning "
            "app. The design features a stylized open book shape combined with a "
            "smiling star or lightbulb symbol, representing learning and discovery. "
            "Geometric and clean with smooth rounded corners. Gradient color scheme "
            "from warm orange (#F59E0B) to bright yellow (#FBBF24), with accents of "
            "sky blue (#3B82F6). The 'A' letter from 'Aumazing' is cleverly integrated "
            "into the geometric design. Modern flat design with subtle depth through "
            "color layering. Professional yet playful and child-friendly. White or "
            "transparent background. Square format suitable for app icon."
        ),
        "desc": "Geometric educational symbol logo"
    },
    "concept_3_wordmark": {
        "prompt": (
            "A cheerful wordmark logo for 'Aumazing', an educational kids' app. "
            "The text 'Aumazing' is written in a bold, friendly, rounded sans-serif "
            "font with playful character. The letter 'A' is styled as a cute cartoon "
            "character with eyes and a smile. Small decorative elements surround the "
            "text: colorful stars, sparkles, and hearts. Rainbow-inspired color scheme "
            "with each letter in vibrant hues: red, orange, yellow, green, blue, and "
            "purple gradient. Thick outlines, child-friendly aesthetic. The design is "
            "energetic, fun, and clearly reads as 'Aumazing'. White or transparent "
            "background. Horizontal rectangular format optimized for app branding."
        ),
        "desc": "Playful wordmark with character 'A'"
    }
}


def generate_logo(concept_id: str, prompt: str, desc: str) -> Path:
    """Generate a single logo concept using kie.ai nano-banana."""
    output_path = SCRIPT_DIR / f"{concept_id}.png"

    if output_path.exists():
        print(f"[{concept_id}] already exists, skipping")
        return output_path

    print(f"\n[{concept_id}] {desc}")
    print(f"  Generating...")

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
        sys.exit(f"[{concept_id}] createTask failed: {d}")

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
            sys.exit(f"[{concept_id}] failed: {data.get('failMsg')}")
        elif attempt % 6 == 0:
            print(f"  ... still generating ({attempt*5}s)")
    else:
        sys.exit(f"[{concept_id}] timed out after 450s")

    # Download result
    result_json = json.loads(data["resultJson"])
    url = result_json["resultUrls"][0]

    print(f"  Downloading from: {url}")
    img_data = requests.get(url, timeout=600).content
    output_path.write_bytes(img_data)

    print(f"  [OK] Saved to: {output_path}")
    print(f"    Size: {len(img_data) / 1024:.1f} KB")

    return output_path


def main():
    SCRIPT_DIR.mkdir(parents=True, exist_ok=True)

    print("=" * 60)
    print("Aumazing Logo Generator")
    print("=" * 60)
    print(f"Generating 3 logo concepts...")

    results = []
    for concept_id, config in LOGO_CONCEPTS.items():
        try:
            path = generate_logo(concept_id, config["prompt"], config["desc"])
            results.append((concept_id, config["desc"], path))
        except Exception as e:
            print(f"[ERROR] [{concept_id}] Error: {e}")
            continue

    print("\n" + "=" * 60)
    print("Generation Complete!")
    print("=" * 60)
    for concept_id, desc, path in results:
        print(f"  • {path.name}")
        print(f"    {desc}")
    print()


if __name__ == "__main__":
    main()
