#!/usr/bin/env python3
"""Generate unified Aumazing logo inspired by AutiSpark and Otsimo style.

Usage:
  python tools/logo_gen/generate_unified_logo.py
"""

import base64
import json
import os
import sys
import time
from pathlib import Path

import requests
from PIL import Image

SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parent.parent
JOBS_API = "https://api.kie.ai"
UPLOAD_API = "https://kieai.redpandaai.co"

KIE_API_KEY = os.environ["KIE_API_KEY"]  # source tools/voice_gen/.env first


def headers() -> dict:
    return {
        "Authorization": f"Bearer {KIE_API_KEY}",
        "Content-Type": "application/json"
    }


def upload_reference(image_path: Path) -> str:
    """Upload a reference image to kie.ai and return the download URL."""
    print(f"  Uploading reference: {image_path.name}")

    # Flatten RGBA to RGB on white background and scale
    im = Image.open(image_path).convert("RGBA")
    flat = Image.new("RGB", im.size, (255, 255, 255))
    flat.paste(im, (0, 0), im)
    flat.thumbnail((1024, 1024), Image.LANCZOS)

    # Convert to base64
    from io import BytesIO
    buffer = BytesIO()
    flat.save(buffer, format="PNG")
    b64 = base64.b64encode(buffer.getvalue()).decode()

    r = requests.post(
        f"{UPLOAD_API}/api/file-base64-upload",
        headers=headers(),
        json={
            "base64Data": f"data:image/png;base64,{b64}",
            "uploadPath": "images/aumazing",
            "fileName": image_path.name
        },
        timeout=300
    )
    r.raise_for_status()
    d = r.json()

    if not d.get("success"):
        sys.exit(f"Upload failed: {d}")

    url = d["data"]["downloadUrl"]
    print(f"  -> {url}")
    return url


def generate_logo(lexianne_url: str, bps_url: str, reiz_url: str) -> Path:
    """Generate the unified logo using kie.ai nano-banana-edit."""
    output_path = SCRIPT_DIR / "aumazing_logo_unified.png"

    prompt = """Create a vibrant app icon logo for 'Aumazing' educational app by EDITING the three reference images.

CRITICAL: You MUST use the EXACT characters from the three reference images provided. Do NOT create new characters, do NOT draw an owl or any other animal. ONLY use the three human children characters shown in the references wearing their animal costumes.

BACKGROUND: Replace the background with a colorful geometric pattern - diagonal triangular sections in bright vivid purple, sunny yellow, bright cyan, lime green, and coral pink. The sections meet at diagonal angles filling the entire square (like AutiSpark style).

CHARACTERS - USE EXACTLY THESE THREE FROM THE REFERENCES:
1. FIRST REFERENCE (Lexianne in panda costume): Place her in the CENTER, slightly larger
2. SECOND REFERENCE (BPS in teddy costume): Place him on the LEFT side
3. THIRD REFERENCE (Reiz in fox costume): Place him on the RIGHT side

Keep ALL THREE characters FULL BODY (head to feet), standing upright. IMPORTANT modifications:
- Enhance their eyes to be LARGER, rounder, with bright blue irises and big white highlights (Otsimo style)
- Make their smiles bigger and friendlier
- Keep their exact costume designs from the references
- All facing forward
- Bold, clean outlines

STYLE:
- Flat 2D with solid colors
- High contrast
- Child-friendly
- The three children should fill the space with colorful background visible around them

EDIT the reference images, don't create from scratch. The characters MUST be recognizable as the same children from the three references.

Square 1024x1024px."""

    print("\n[Generating unified logo]")
    print("  Creating task...")

    body = {
        "model": "google/nano-banana-edit",
        "input": {
            "prompt": prompt,
            "image_urls": [lexianne_url, bps_url, reiz_url],
            "output_format": "png",
            "image_size": "1:1",
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
    print("Aumazing Unified Logo Generator")
    print("=" * 60)

    # Use all three characters with their costumes
    lexianne_path = PROJECT_ROOT / "packages/assets/images/Character/Character_Costume/Panda/Lexianne_chibi_Panda.png"
    bps_path = PROJECT_ROOT / "packages/assets/images/Character/Character_Costume/Teddy/BPs_chibi_Teddy.png"
    reiz_path = PROJECT_ROOT / "packages/assets/images/Character/Character_Costume/Fox/Reiz_chibi_Fox.png"

    for path in [lexianne_path, bps_path, reiz_path]:
        if not path.exists():
            sys.exit(f"Character not found: {path}")

    print(f"\nUsing characters:")
    print(f"  Lexianne (center): {lexianne_path.name}")
    print(f"  BPS (left): {bps_path.name}")
    print(f"  Reiz (right): {reiz_path.name}")

    # Upload references
    lexianne_url = upload_reference(lexianne_path)
    bps_url = upload_reference(bps_path)
    reiz_url = upload_reference(reiz_path)

    # Generate logo
    result = generate_logo(lexianne_url, bps_url, reiz_url)

    print("\n" + "=" * 60)
    print("Logo Generated Successfully!")
    print("=" * 60)
    print(f"  {result}")
    print()


if __name__ == "__main__":
    main()
