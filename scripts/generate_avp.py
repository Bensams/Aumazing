#!/usr/bin/env python3
"""Build the BPS / Reiz animated presenter layer for the capstone AVP.

Two subcommands, and the split between them is the whole point:

  cutouts   FREE. Turns the clips already sitting in `.sprite_cache/` into
            alpha-channel .mov files you can drop straight onto a timeline
            over your screen recording. No API calls, no credits, seconds
            to run. Twenty-two clips of BPS and Reiz are already paid for.

  shots     COSTS CREDITS. Generates NEW 16:9 landscape scenes via kie.ai
            for the handful of moments the sprite clips cannot cover —
            the two characters on screen together, the title card, the
            closing wave. Prompts live in `SHOTS` below.

Do `cutouts` first and cut the video with it. Only spend on `shots` for the
gaps that are still empty; every hero shot is ~164 credits and 80-360s.

Usage:
  pip install pillow numpy scipy requests imageio-ffmpeg
  python scripts/generate_avp.py cutouts                 # free, do this first
  python scripts/generate_avp.py cutouts --format webm
  python scripts/generate_avp.py shots --list            # prompts + cost, no spend
  set KIE_API_KEY=...
  python scripts/generate_avp.py shots --only title,handoff --yes

Output: `avp_out/cutouts/*.mov`, `avp_out/shots/*.mp4`  (both gitignored)

The generation half reuses `generate_sprites.py` wholesale — same auth, same
upload host, same background-removal. See scripts/SPRITES.md for the API
quirks; they all apply here too.
"""

import argparse
import json
import os
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import imageio_ffmpeg
import numpy as np
import requests
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from generate_sprites import (  # noqa: E402
    CACHE, JOBS_API, PROJECT_ROOT, body_mask, cutout, headers, upload,
)

OUT = PROJECT_ROOT / "avp_out"
FPS = 24
CREDITS_PER_SHOT = 164

# ── Hero shots ────────────────────────────────────────────────────────
# Landscape scenes the portrait sprite clips cannot give you. Each entry is
# (cast, prompt); `cast` is the characters staged into the first frame, left
# to right. Keep this list short — every entry is real money.
STYLE = (
    " STRICT REQUIREMENTS: locked-off camera, no zoom, no pan, no parallax. "
    "Plain solid pure white background, completely empty, no shadows on the "
    "background, no props, no text, no letters, no numbers, no logos or brand "
    "marks. Keep the exact same flat 2D cartoon anime chibi art style, same "
    "thick clean outlines, same colors, same hairstyles and same outfits as the "
    "reference image. FRAMING: wide full-body shot exactly matching the "
    "reference framing. Every character stays fully inside the frame from the "
    "top of the hair to the soles of the shoes, with clear empty white space "
    "above and below. Never zoom in, never crop, no close-up of faces or hands. "
    "Gentle, calm, child-friendly motion."
)

SHOTS = {
    # Opening. Both proponents on screen, the shot the AVP opens on.
    "title": (["bps", "reiz"],
              "Both chibi characters stand side by side and wave hello to the "
              "viewer with their free hands, warm friendly smiles, then lower "
              "their hands back to the starting pose. They stay in place and "
              "do not step toward each other or the camera."),
    # Section 2 of the brief: the problem. Sympathetic, never bleak — this
    # sits under narration about parents struggling, and a mascot that looks
    # distressed reads as pity rather than empathy.
    "problem": (["bps"],
                "The chibi character looks thoughtful and gently concerned: "
                "brings one hand near the chin, tilts the head slightly, and "
                "looks off to one side with a soft caring expression, then "
                "settles. It is NOT sad, NOT crying, NOT frowning harshly. "
                "Small, slow, calm movement."),
    # Section 3: hand-off into the screen recording. The point gesture aims at
    # empty frame-left so you can key the app capture in beside them.
    "handoff": (["bps", "reiz"],
                "Both chibi characters turn slightly toward each other, then "
                "the character on the right extends one arm outward to its "
                "own left at shoulder height, index finger clearly pointing "
                "off to the side, and holds it steadily while the other "
                "character nods once in agreement. Friendly helpful "
                "expressions. Both keep both feet on the ground."),
    # Section 4: the responsible-use / licensing beat. Calm and matter-of-fact.
    "credits": (["reiz"],
                "The chibi character gives a small confident nod and an open "
                "palms-up explaining gesture, as if calmly listing something "
                "to the viewer, then returns to the starting pose. Steady, "
                "unhurried, sincere expression."),
    # Section 5: the close. Ends on rest so it can hold under an end card.
    "closing": (["bps", "reiz"],
                "Both chibi characters celebrate together: they clap twice "
                "with big joyful smiles, then give a warm two-handed wave "
                "goodbye to the viewer and settle back to the starting pose. "
                "Both keep both feet on the ground, no jumping, and neither "
                "moves closer to the camera."),
}

STAGE_FILL = 0.62     # character height as a fraction of the 16:9 frame
STAGE_H = 1080


def ffmpeg() -> str:
    return imageio_ffmpeg.get_ffmpeg_exe()


# ── Free path: cached clips -> alpha .mov ─────────────────────────────
def clip_frames(tag: str) -> list[Path]:
    """Extracted frames for a cached clip, extracting them if needed."""
    d = CACHE / f"frames_{tag}"
    if d.exists() and any(d.glob("*.png")):
        return sorted(d.glob("*.png"))
    mp4 = CACHE / f"{tag}.mp4"
    if not mp4.exists():
        return []
    d.mkdir(parents=True, exist_ok=True)
    subprocess.run([ffmpeg(), "-v", "error", "-i", str(mp4),
                    str(d / "f%04d.png")], check=True)
    return sorted(d.glob("*.png"))


def cut_clip(tag: str, fmt: str) -> Path | None:
    """Key the white background out of one cached clip and encode with alpha.

    The crop box is measured ONCE over the whole clip and applied to every
    frame — the same single-transform-per-clip rule the sprite compositor
    follows. Cropping each frame to its own bounding box would add jitter
    that is not in the source footage.
    """
    frames = clip_frames(tag)
    if not frames:
        return None

    work = OUT / "work" / tag
    work.mkdir(parents=True, exist_ok=True)
    keyed = []
    for f in frames:
        rgba = cutout(np.asarray(Image.open(f).convert("RGB")).astype(np.int16))
        keyed.append(rgba)

    # Union of every frame's body mask, so a raised hand in frame 40 is not
    # sliced off by a box measured on the rest pose in frame 1.
    union = np.zeros(keyed[0].shape[:2], bool)
    for rgba in keyed:
        union |= body_mask(rgba)
    ys, xs = np.where(union)
    pad = 12
    y0, y1 = max(0, ys.min() - pad), min(union.shape[0], ys.max() + 1 + pad)
    x0, x1 = max(0, xs.min() - pad), min(union.shape[1], xs.max() + 1 + pad)
    # yuva420p needs even dimensions; grow rather than shrink so nothing is lost.
    if (y1 - y0) % 2:
        y1 = min(union.shape[0], y1 + 1) if y1 < union.shape[0] else y0 - 1
    if (x1 - x0) % 2:
        x1 = min(union.shape[1], x1 + 1) if x1 < union.shape[1] else x0 - 1

    for i, rgba in enumerate(keyed):
        Image.fromarray(rgba[y0:y1, x0:x1]).save(work / f"f{i:04d}.png")

    OUT.joinpath("cutouts").mkdir(parents=True, exist_ok=True)
    if fmt == "webm":
        dest = OUT / "cutouts" / f"{tag}.webm"
        codec = ["-c:v", "libvpx-vp9", "-pix_fmt", "yuva420p",
                 "-auto-alt-ref", "0", "-b:v", "3M"]
    else:
        dest = OUT / "cutouts" / f"{tag}.mov"
        codec = ["-c:v", "prores_ks", "-profile:v", "4444",
                 "-pix_fmt", "yuva444p10le"]
    subprocess.run([ffmpeg(), "-v", "error", "-y", "-framerate", str(FPS),
                    "-i", str(work / "f%04d.png"), *codec, str(dest)], check=True)
    print(f"[{tag}] {dest.relative_to(PROJECT_ROOT)}  {x1 - x0}x{y1 - y0}, "
          f"{len(frames)} frames")
    return dest


def cmd_cutouts(args) -> None:
    # Frames dirs as well as .mp4s: some clips were extracted before the mp4
    # was cleaned up, and their frames are just as usable as a source.
    tags = sorted({p.stem for p in CACHE.glob("*.mp4")}
                  | {p.name[len("frames_"):] for p in CACHE.glob("frames_*")
                     if p.is_dir() and any(p.glob("*.png"))})
    if args.only:
        want = {t.strip() for t in args.only.split(",")}
        tags = [t for t in tags if t in want or t.split("_")[0] in want]
    if not tags:
        sys.exit(f"no cached clips in {CACHE}")
    print(f"{len(tags)} clip(s) -> {args.format}, no API calls\n")
    with ThreadPoolExecutor(max_workers=4) as pool:
        list(pool.map(lambda t: cut_clip(t, args.format), tags))
    print(f"\ndone -> {(OUT / 'cutouts').relative_to(PROJECT_ROOT)}")


# ── Paid path: new landscape hero shots ───────────────────────────────
def rest_rgba(name: str) -> Image.Image:
    """A character's canonical rest pose, cut out, as a trimmed RGBA image.

    Cell 0 of its idle sheet — the same rest pose every sprite sheet starts
    from, so a hero shot cuts against the sprite clips without a pop.
    """
    sheet_path = (PROJECT_ROOT / "packages" / "shared_ui" / "assets"
                  / "characters" / f"{name}_idle.png")
    if sheet_path.exists():
        sheet = Image.open(sheet_path).convert("RGBA")
        cell = sheet.crop((0, 0, sheet.width // 3, sheet.height // 2))
    else:
        art = (PROJECT_ROOT / "packages" / "assets" / "images" / "Character"
               / f"{name.capitalize()}_chibi.png")
        if not art.exists():
            sys.exit(f"{name}: no idle sheet and no artwork at {art}")
        cell = Image.fromarray(
            cutout(np.asarray(Image.open(art).convert("RGB")).astype(np.int16)))
    return cell.crop(cell.getbbox())


def stage(cast: list[str]) -> Path:
    """Compose the cast onto a 16:9 white first frame, evenly spaced.

    Characters fill only ~62% of the height for the same reason the sprite
    rest frame uses 0.66: seedance creeps closer over a clip, and without
    headroom it crops the feet and the take is wasted.
    """
    frame_h, frame_w = STAGE_H, round(STAGE_H * 16 / 9)
    canvas = Image.new("RGB", (frame_w, frame_h), (255, 255, 255))
    target_h = round(frame_h * STAGE_FILL)

    scaled = []
    for name in cast:
        img = rest_rgba(name)
        scaled.append(img.resize(
            (max(1, round(img.width * target_h / img.height)), target_h),
            Image.LANCZOS))

    # Centred as a GROUP with a small gap, not spread across the full width.
    # Evenly-spaced slots leave a huge empty gutter between two chibi figures,
    # and seedance reads that as room to move into — the pair drifts together
    # over the clip. Standing them close already reads as "side by side".
    gap = round(frame_w * 0.03)
    total = sum(i.width for i in scaled) + gap * (len(scaled) - 1)
    baseline = round(frame_h * 0.90)
    x = round((frame_w - total) / 2)
    for img in scaled:
        canvas.paste(img, (x, baseline - img.height), img)
        x += img.width + gap

    OUT.mkdir(parents=True, exist_ok=True)
    dest = OUT / f"stage_{'_'.join(cast)}.png"
    canvas.save(dest)
    return dest


def render(shot: str, first_frame_url: str) -> Path | None:
    dest = OUT / "shots" / f"{shot}.mp4"
    if dest.exists():
        print(f"[{shot}] already generated, skipping")
        return dest

    body = {"model": "bytedance/seedance-2",
            "input": {"prompt": SHOTS[shot][1] + STYLE,
                      "first_frame_url": first_frame_url,
                      "generate_audio": False, "resolution": "720p",
                      "aspect_ratio": "16:9", "duration": 4}}
    r = requests.post(f"{JOBS_API}/api/v1/jobs/createTask",
                      headers=headers(), json=body, timeout=60)
    r.raise_for_status()
    d = r.json()
    if d.get("code") != 200:
        print(f"[{shot}] createTask failed: {d}")
        return None
    task_id = d["data"]["taskId"]
    print(f"[{shot}] task {task_id}")

    data = {}
    for _ in range(150):
        time.sleep(10)
        data = (requests.get(f"{JOBS_API}/api/v1/jobs/recordInfo",
                             headers=headers(), params={"taskId": task_id},
                             timeout=60).json().get("data") or {})
        if data.get("state") == "success":
            print(f"[{shot}] {data.get('costTime')}s, "
                  f"{data.get('creditsConsumed')} credits")
            break
        if data.get("state") == "fail":
            print(f"[{shot}] failed: {data.get('failMsg')}")
            return None
    else:
        print(f"[{shot}] timed out")
        return None

    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_bytes(requests.get(
        json.loads(data["resultJson"])["resultUrls"][0], timeout=600).content)
    print(f"[{shot}] {dest.relative_to(PROJECT_ROOT)}")
    return dest


def cmd_shots(args) -> None:
    names = list(SHOTS)
    if args.only:
        want = [s.strip() for s in args.only.split(",")]
        unknown = [s for s in want if s not in SHOTS]
        if unknown:
            sys.exit(f"unknown shot(s): {', '.join(unknown)}")
        names = want

    if args.list:
        for n in names:
            cast, prompt = SHOTS[n]
            print(f"\n{n}  [{', '.join(cast)}]\n  {prompt}")
        print(f"\n{len(names)} shot(s) = ~{len(names) * CREDITS_PER_SHOT} credits")
        return

    cost = len(names) * CREDITS_PER_SHOT
    print(f"{len(names)} shot(s): {', '.join(names)}")
    print(f"estimated cost: ~{cost} credits")
    if not args.yes:
        sys.exit("refusing to spend credits without --yes")
    if not os.environ.get("KIE_API_KEY"):
        sys.exit("KIE_API_KEY is not set")

    # One upload per distinct cast, shared by every shot that uses it.
    urls = {}
    for n in names:
        cast_key = tuple(SHOTS[n][0])
        if cast_key not in urls:
            urls[cast_key] = upload(stage(list(cast_key)))
            print(f"staged {'+'.join(cast_key)}")

    with ThreadPoolExecutor(max_workers=4) as pool:
        list(pool.map(lambda n: render(n, urls[tuple(SHOTS[n][0])]), names))


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)

    c = sub.add_parser("cutouts", help="FREE: cached clips -> alpha .mov/.webm")
    c.add_argument("--only", help="clip tags or character names, comma separated")
    c.add_argument("--format", choices=["mov", "webm"], default="mov",
                   help="mov = ProRes 4444 (Premiere/DaVinci); webm = VP9 alpha")
    c.set_defaults(func=cmd_cutouts)

    s = sub.add_parser("shots", help="COSTS CREDITS: new 16:9 hero scenes")
    s.add_argument("--only", help="shot names, comma separated")
    s.add_argument("--list", action="store_true", help="print prompts and cost only")
    s.add_argument("--yes", action="store_true", help="confirm credit spend")
    s.set_defaults(func=cmd_shots)

    args = ap.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
