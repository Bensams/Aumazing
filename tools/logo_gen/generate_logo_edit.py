#!/usr/bin/env python3
"""Edit the Aumazing wordmark logo to replace the generic person with our three characters."""

import base64
import json
import os
import sys
import time
from pathlib import Path
from io import BytesIO

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


def upload_image(image_path: Path) -> str:
    """Upload an image to kie.ai and return the download URL."""
    print(f"  Uploading: {image_path.name}")

    if image_path.suffix.lower() in ['.png', '.jpg', '.jpeg']:
        im = Image.open(image_path)
        if im.mode == 'RGBA':
            flat = Image.new("RGB", im.size, (255, 255, 255))
            flat.paste(im, (0, 0), im)
            im = flat
        im.thumbnail((1024, 1024), Image.LANCZOS)

        buffer = BytesIO()
        im.save(buffer, format="PNG")
        b64 = base64.b64encode(buffer.getvalue()).decode()
    else:
        b64 = base64.b64encode(image_path.read_bytes()).decode()

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


def edit_logo(logo_url: str, lexianne_url: str, bps_url: str, reiz_url: str) -> Path:
    """Edit the logo using kie.ai nano-banana-edit."""
    output_path = SCRIPT_DIR / "aumazing_logo_edited.png"

    prompt = """EDIT this logo image by REPLACING the unknown person/character on the LEFT side with THREE specific children characters.

KEEP UNCHANGED:
- The colorful "AUMAZING" text at the bottom (keep it exactly as is)
- The "GAMIFIED LEARNING APP" subtitle (keep it exactly as is)
- The yellow star character on the far left
- All the puzzle pieces (orange, yellow, green, blue, red)
- All the small stars and decorative elements
- The overall composition and colors

REMOVE:
- The generic orange/blue person figure that is currently jumping with arms up

REPLACE WITH (using references 2, 3, 4):
Place THREE children characters from the reference images in a row where that person was:

LEFT: BPS (reference 2) - boy in brown teddy bear costume, smiling
CENTER: LEXIANNE (reference 3) - girl in black/white panda costume, smiling (slightly more prominent)
RIGHT: REIZ (reference 4) - boy in orange fox costume, smiling

Make them cheerful and playful, full body, arranged in a friendly group above the "AUMAZING" text. They should be the same cute chibi style as the references, with big friendly eyes and warm smiles.

Keep the exact same colorful, playful, puzzle-piece theme of the original logo. The three children should look like they belong naturally in this educational app logo."""

    print("\n[Editing logo]")
    print("  Creating task...")

    body = {
        "model": "google/nano-banana-edit",
        "input": {
            "prompt": prompt,
            "image_urls": [logo_url, lexianne_url, bps_url, reiz_url],
            "output_format": "png",
            "image_size": "16:9",
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
            print(f"  ... processing ({attempt*5}s)")
    else:
        sys.exit("Processing timed out after 450s")

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
    if len(sys.argv) < 2:
        print("Usage: python generate_logo_edit.py <logo_image_path>")
        print("Example: python generate_logo_edit.py aumazing_wordmark.png")
        sys.exit(1)

    SCRIPT_DIR.mkdir(parents=True, exist_ok=True)

    logo_path = Path(sys.argv[1])
    if not logo_path.exists():
        sys.exit(f"Logo file not found: {logo_path}")

    print("=" * 60)
    print("Aumazing Logo Editor")
    print("=" * 60)

    # Character paths
    lexianne_path = PROJECT_ROOT / "packages/assets/images/Character/Character_Costume/Panda/Lexianne_chibi_Panda.png"
    bps_path = PROJECT_ROOT / "packages/assets/images/Character/Character_Costume/Teddy/BPs_chibi_Teddy.png"
    reiz_path = PROJECT_ROOT / "packages/assets/images/Character/Character_Costume/Fox/Reiz_chibi_Fox.png"

    for path in [lexianne_path, bps_path, reiz_path]:
        if not path.exists():
            sys.exit(f"Character not found: {path}")

    print(f"\nOriginal logo: {logo_path}")
    print(f"Characters: Lexianne (Panda), BPS (Teddy), Reiz (Fox)")

    # Upload all images
    print("\nUploading images...")
    logo_url = upload_image(logo_path)
    lexianne_url = upload_image(lexianne_path)
    bps_url = upload_image(bps_path)
    reiz_url = upload_image(reiz_path)

    # Edit the logo
    result = edit_logo(logo_url, lexianne_url, bps_url, reiz_url)

    print("\n" + "=" * 60)
    print("Logo Edited Successfully!")
    print("=" * 60)
    print(f"  {result}")
    print()


if __name__ == "__main__":
    main()
