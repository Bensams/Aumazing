#!/usr/bin/env python3
"""Batch-generate mascot sprite sheets for Aumazing from a single rest pose.

Engine: kie.ai `bytedance/seedance-2` (image-to-video). Each action is
generated as a short locked-camera clip from the character's CANONICAL REST
frame, then frames are cut, background-keyed to alpha, and composed into the
uniform grids that `CharacterSprites` slices at runtime.

Why video and not one image per frame: identity and lighting stay locked
across a clip, which is exactly the consistency a sprite sheet needs.

Two rules make the output usable:
  * Every action for a character starts from the SAME rest frame, so sheets
    hand off to each other without a pop.
  * Every sheet is normalised to the same character height and footing, so
    CalmMascot never changes size or slides sideways between sheets.

Usage:
  pip install pillow numpy scipy requests imageio-ffmpeg
  set KIE_API_KEY=...            # never commit this
  python scripts/generate_sprites.py reiz            # one character
  python scripts/generate_sprites.py reiz bps        # several
  python scripts/generate_sprites.py reiz --only nod,point
  python scripts/generate_sprites.py reiz --compose-only

Output:
  packages/shared_ui/assets/characters/{name}_{action}.png

See scripts/SPRITES.md for the API quirks, the invariants that keep sheets
usable, and the recipes for adding an action or a character.
"""

import argparse
import base64
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
from scipy import ndimage

# ── Paths ─────────────────────────────────────────────────────────────
SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parent
DEST = PROJECT_ROOT / "packages" / "shared_ui" / "assets" / "characters"
# Discarded takes live in a SUBDIRECTORY of the asset folder on purpose:
# pubspec.yaml declares `assets/characters/`, and Flutter's directory entries
# are not recursive, so nothing in here is bundled into the app.
ARCHIVE = DEST / "Archive"
CACHE = PROJECT_ROOT / ".sprite_cache"          # clips + frames, gitignored

JOBS_API = "https://api.kie.ai"
UPLOAD_API = "https://kieai.redpandaai.co"      # NOT api.kie.ai; the docs are wrong

# ── Sheet geometry ────────────────────────────────────────────────────
# Shared by every sheet of a character so the mascot never jumps.
CELL_H = 490
TARGET_H = 478        # character head-to-feet height inside the cell
BOTTOM_PAD = 6
WHITE_CUT = 225       # channel value above which a pixel reads as background
INK_SOFT = 30.0       # edge-feather ramp

# ── Prompts ───────────────────────────────────────────────────────────
# The camera/scale clauses are what let the compositor trust one transform
# per clip. Without them seedance drifts and the frames stop lining up.
STYLE = (
    " STRICT REQUIREMENTS: absolutely static locked-off camera, no camera movement, "
    "no zoom, no pan, no parallax. The character stays perfectly centered and never "
    "walks, drifts, rotates, or changes size or position in frame. Plain solid pure "
    "white background, completely empty, no shadows on the background, no props, no "
    "text, no added objects, no logos or brand marks. Keep the exact same flat 2D "
    "cartoon anime chibi art style, same thick clean outlines, same colors, same "
    "hairstyle and same outfit as the reference image. "
    # seedance drifts into close-ups whenever a prompt draws attention to the
    # face or hands, which crops the feet and makes the clip unusable as a
    # sheet. Framing is therefore spelled out in explicit proportions.
    "FRAMING: wide full-body shot exactly matching the reference image framing. "
    "The whole character from the top of the hair to the soles of the shoes stays "
    "inside the frame at all times, occupying only the middle portion of the height "
    "with clear empty white space above the head and below the feet. Never zoom in, "
    "never crop, never move closer, no close-up of the face or hands. "
    "Gentle, calm, child-friendly motion."
)

# action -> (cols, rows, frames, selection strategy, prompt)
ACTIONS = {
    "idle": (3, 2, 5, "blink",
             "The chibi character stands completely still in exactly the starting pose "
             "and blinks slowly twice, with a soft gentle breathing motion. ONLY the "
             "eyelids move. No head turn, no body movement, no arm or hand movement."),
    # Mouth-only cycle. `spread` rather than `gesture`: the whole clip is in
    # motion so a velocity-trimmed span would be the entire clip anyway, and
    # what a talk sheet needs is not lip sync — nothing cues it to phonemes —
    # but a handful of DISTINCT mouth openings the app can cycle arbitrarily.
    # An even spread across a continuous cycle is exactly that.
    "talk": (3, 2, 6, "spread",
             "The chibi character talks to the viewer: the mouth opens and "
             "closes continuously and naturally as if speaking, cycling "
             "through small varied mouth shapes, some wide open and some "
             "nearly closed. The eyes stay open with a warm friendly "
             "expression. ONLY the mouth moves. No head turn, no head tilt, "
             "no body movement, no arm or hand movement, no gesturing. The "
             "character stays in exactly the starting pose throughout."),
    "wave": (4, 3, 12, "gesture",
             "The chibi character waves hello: raises one hand up beside the head and "
             "waves it gently side to side twice, then lowers it back down to the exact "
             "starting pose. Warm friendly smile throughout. The final pose is identical "
             "to the first pose."),
    # Walked IN PLACE on purpose: the horizontal travel is done by the Flutter
    # widget, and a character that also approaches would change size between
    # frames and break the compositor's single-transform-per-clip assumption.
    "walk": (4, 3, 12, "gesture",
             "The chibi character walks in place with a gentle bouncy step, "
             "marching softly on the spot: the legs step alternately, the arms "
             "swing naturally at the sides, and the body bobs very slightly up "
             "and down with each step. It stays facing the viewer with a warm "
             "friendly smile, and does NOT move closer or further away, does "
             "not travel across the frame, and does not change size. Smooth, "
             "even, continuous stepping at a steady pace."),
    "celebrate": (4, 3, 12, "gesture",
                  "The chibi character celebrates happily: claps both hands together "
                  "twice and gives a joyful cheer with a big open smile, then settles "
                  "back to the exact starting pose. Keep both feet on the ground, no "
                  "jumping."),
    "nod": (3, 2, 6, "gesture",
            "The chibi character nods its head gently downward and back up once, in a "
            "clear warm 'yes' gesture, with a kind encouraging smile. ONLY the head "
            "moves. The body, arms and hands stay exactly in the starting pose."),
    # If the character is holding something the model tends to keep BOTH hands
    # busy and only twitch a thumb, so the free arm is called out explicitly.
    "point": (3, 2, 6, "late",
              "The chibi character lifts its FREE arm — the arm that is not holding "
              "anything — and points clearly to its own left side. The arm is fully "
              "extended outward at shoulder height with the index finger straight and "
              "clearly pointing, held steadily. Any object already in the other hand "
              "stays held down at that side. The character looks in the direction it "
              "is pointing with a friendly helpful expression."),
    # The softer sibling of `point`. A stiff index finger reads as instruction;
    # an open palm reads as invitation, which is what a hand-off to something
    # on screen wants. Deliberately the SAME side as `point` (the character's
    # own left, which lands on frame RIGHT): that direction is proven to
    # generate cleanly, and mirroring the clip to get the other side is not an
    # option — it reverses the lettering on BPS's book and swaps Reiz's lapel
    # and necklace.
    "present": (3, 2, 6, "late",
                "The chibi character lifts its FREE arm — the arm that is not "
                "holding anything — and presents to its own left side with an "
                "OPEN FLAT PALM facing upward, fingers together and relaxed, "
                "the arm extended outward at chest height in a welcoming "
                "'here it is' presenting gesture, held steadily. It is an "
                "open palm, NOT a pointing finger and NOT a thumbs-up. Any "
                "object already in the other hand stays held down at that "
                "side. The character looks toward what it is presenting with "
                "a friendly helpful expression. "
                # First take of bps_present came back MIRRORED: the book moved
                # to the other hand and the gesture pointed the opposite way
                # from `point`, so the two sheets could not be cut together.
                # An open-palm reach is symmetric enough that "its own left"
                # alone does not pin the handedness — the object has to.
                "CRITICAL: the character is NOT mirrored, NOT flipped and does "
                "NOT turn around. Whichever hand holds an object in the "
                "reference image keeps holding that object, in that same hand, "
                "on that same side of the frame, in every single frame. The "
                "presenting arm is the other arm."),
    # The reaction to a wrong answer. Disappointment, NOT distress: a crying or
    # angry mascot models distress at a child who has just made a mistake,
    # which is the one reaction this app must not have. The prompt spells out
    # the recovery too — the clip must end back near rest so the sheet hands
    # over cleanly to the encouraging pose that follows it.
    "oops": (3, 2, 6, "gesture",
             "The chibi character reacts to a small mistake with gentle "
             "disappointment: the smile softens into a small closed-mouth "
             "'aww' expression, the shoulders dip down slightly and the head "
             "tips gently downward to look at the floor for a moment, then "
             "lifts back up to the exact starting pose with a soft kind "
             "expression. The movement is small, slow and soft. The character "
             "is NOT crying, NOT sobbing, has NO tears, is NOT angry, NOT "
             "frowning harshly, NOT upset or distressed, and never covers its "
             "face. It stays calm and gentle throughout, more sympathetic "
             "than sad. Both feet stay on the ground."),
    "encourage": (1, 1, 1, "still",
                  "The chibi character gives a warm reassuring thumbs-up with open "
                  "welcoming body language and a kind encouraging smile. It reaches "
                  "this pose within the first second and then holds it completely "
                  "still and unchanged for the rest of the video."),
    "listen": (1, 1, 1, "still",
               "The chibi character tilts its head clearly and distinctly to one side, "
               "about twenty degrees, in an attentive listening pose, with one hand "
               "raised and cupped beside its ear, eyes open and a soft curious "
               "closed-mouth smile. It reaches this pose within the first second and "
               "then holds it completely still and unchanged for the rest of the video."),
    "sleepy": (1, 1, 1, "still",
               "The chibi character looks very sleepy: the eyes are clearly half-closed "
               "with heavy drooping eyelids, the head tips gently to one side, the "
               "shoulders relax downward and it gives a small quiet yawn, in a calm "
               "wind-down pose. It reaches this sleepy pose within the first second and "
               "then holds it completely still and unchanged for the rest of the video."),
    "think": (1, 1, 1, "still",
              "The chibi character rests one hand near its chin in a gentle thoughtful "
              "wondering pose, looking slightly upward with a curious expression, and "
              "holds that pose steadily without moving."),
}

# character -> how to obtain its canonical rest frame.
#   from_sheet: cell 0 of an existing idle sheet (established characters)
#   from_image: a standalone artwork PNG (bootstrapping a NEW character, which
#               has no sheet yet — see the Lexianne entry)
CHARACTERS = {
    "bps": {"from_sheet": DEST / "bps_idle.png", "grid": (3, 2)},
    "reiz": {"from_sheet": DEST / "reiz_idle.png", "grid": (3, 2)},
    "lexianne": {
        "from_image": (PROJECT_ROOT / "packages" / "assets" / "images"
                       / "Character" / "Lexianne_chibi.png"),
        # Widest cell of the three; her dress and hair are broader than the
        # boys'. Re-pin this from the generated sheets if arms get clipped.
        "cell_w": 430,
    },
}


class SheetTooTight(RuntimeError):
    """Raised when a clip zoomed in far enough to crop the character."""


def archive(path: Path, why: str) -> Path | None:
    """Move a discarded sheet into Archive/ instead of letting it be overwritten.

    Generations cost credits, so a rejected take is kept for inspection rather
    than destroyed — it is usually the fastest way to see what the model did
    wrong before re-prompting.
    """
    if not path.exists():
        return None
    ARCHIVE.mkdir(parents=True, exist_ok=True)
    stamp = time.strftime("%Y%m%d-%H%M%S")
    # `why` lands in a filename, and NTFS rejects : * ? " < > | — a rejected
    # take losing its reason is a nuisance, but an OSError in the middle of a
    # paid run that throws the sheet away with it is not.
    slug = "".join(c if c.isalnum() or c in "-_" else "-" for c in why)[:60]
    out = ARCHIVE / f"{path.stem}_{slug.strip('-')}_{stamp}{path.suffix}"
    path.replace(out)
    return out


def key() -> str:
    k = os.environ.get("KIE_API_KEY")
    if not k:
        sys.exit("KIE_API_KEY is not set")
    return k


def headers() -> dict:
    return {"Authorization": f"Bearer {key()}", "Content-Type": "application/json"}


# ── Rest frame ────────────────────────────────────────────────────────
REST_FILL = 0.66      # character height as a fraction of the rest frame
MAX_REST_H = 1400     # clips render at 720p; a taller rest frame is wasted upload


def rest_frame(name: str) -> Path:
    """Cell 0 of the character's idle sheet, flattened onto white for the API.

    Padded so the character fills only ~66% of the height. seedance tends to
    creep closer over a clip, and the headroom means even a zoomed take keeps
    the feet in frame — the compositor renormalises the scale afterwards, so
    the extra margin costs nothing.
    """
    cfg = CHARACTERS[name]
    if "from_image" in cfg:
        # Bootstrapping a new character from standalone artwork: key the white
        # background out first so the character can be measured and centred the
        # same way a sheet cell would be.
        src = Path(cfg["from_image"])
        if not src.exists():
            sys.exit(f"{name}: rest artwork not found at {src}")
        raw = Image.open(src).convert("RGB")
        cell = Image.fromarray(cutout(np.asarray(raw).astype(np.int16)))
    else:
        sheet = Image.open(cfg["from_sheet"]).convert("RGBA")
        cols, rows = cfg["grid"]
        cw, ch = sheet.width // cols, sheet.height // rows
        cell = sheet.crop((0, 0, cw, ch))

    alpha = np.asarray(cell)[..., 3] > 16
    ys = np.where(alpha.any(axis=1))[0]
    char_h = ys.max() - ys.min() + 1

    frame_h = int(round(char_h / REST_FILL))
    frame_w = int(round(frame_h * 3 / 4))
    flat = Image.new("RGB", (frame_w, frame_h), (255, 255, 255))
    xs = np.where(alpha.any(axis=0))[0]
    flat.paste(cell, (int(round(frame_w / 2 - (xs.min() + xs.max()) / 2)),
                      int(round(frame_h / 2 - (ys.min() + ys.max()) / 2))), cell)

    # Clips render at 720p, so anything larger is only a slower upload. Raw
    # character artwork can be several thousand pixels tall.
    if flat.height > MAX_REST_H:
        flat = flat.resize(
            (round(flat.width * MAX_REST_H / flat.height), MAX_REST_H),
            Image.LANCZOS)

    out = CACHE / f"{name}_rest.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    flat.save(out)
    return out


def upload(path: Path) -> str:
    b64 = base64.b64encode(path.read_bytes()).decode()
    r = requests.post(f"{UPLOAD_API}/api/file-base64-upload", headers=headers(),
                      json={"base64Data": f"data:image/png;base64,{b64}",
                            "uploadPath": "images/aumazing", "fileName": path.name},
                      timeout=300)
    r.raise_for_status()
    d = r.json()
    if not d.get("success"):
        sys.exit(f"upload failed: {d}")
    return d["data"]["downloadUrl"]


# ── Generation ────────────────────────────────────────────────────────
def generate(name: str, action: str, first_frame_url: str) -> Path:
    tag = f"{name}_{action}"
    frames_dir = CACHE / f"frames_{tag}"
    if frames_dir.exists() and any(frames_dir.glob("*.png")):
        print(f"[{tag}] cached")
        return frames_dir

    prompt = ACTIONS[action][4] + STYLE
    body = {"model": "bytedance/seedance-2",
            "input": {"prompt": prompt, "first_frame_url": first_frame_url,
                      "generate_audio": False, "resolution": "720p",
                      "aspect_ratio": "3:4", "duration": 4}}
    r = requests.post(f"{JOBS_API}/api/v1/jobs/createTask",
                      headers=headers(), json=body, timeout=60)
    r.raise_for_status()
    d = r.json()
    if d.get("code") != 200:
        sys.exit(f"[{tag}] createTask failed: {d}")
    task_id = d["data"]["taskId"]
    print(f"[{tag}] task {task_id}")

    data = {}
    for i in range(150):
        time.sleep(10)
        data = (requests.get(f"{JOBS_API}/api/v1/jobs/recordInfo", headers=headers(),
                             params={"taskId": task_id}, timeout=60).json()
                .get("data") or {})
        if data.get("state") == "success":
            print(f"[{tag}] {data.get('costTime')}s, {data.get('creditsConsumed')} credits")
            break
        if data.get("state") == "fail":
            sys.exit(f"[{tag}] failed: {data.get('failMsg')}")
    else:
        sys.exit(f"[{tag}] timed out")

    mp4 = CACHE / f"{tag}.mp4"
    mp4.write_bytes(requests.get(json.loads(data["resultJson"])["resultUrls"][0],
                                 timeout=600).content)
    frames_dir.mkdir(parents=True, exist_ok=True)
    subprocess.run([imageio_ffmpeg.get_ffmpeg_exe(), "-v", "error", "-i", str(mp4),
                    str(frames_dir / "f%04d.png")], check=True)
    return frames_dir


# ── Frame selection ───────────────────────────────────────────────────
def pick(files: list[Path], strategy: str, n: int) -> list[Path]:
    if strategy == "spread":
        return [files[round(i * (len(files) - 1) / (n - 1))] for i in range(n)]
    if strategy == "gesture":
        return pick_gesture(files, n)
    if strategy == "late":
        # For gestures the model reaches late and then holds (pointing), an
        # even spread wastes most frames on the pre-gesture rest pose.
        files = files[int(len(files) * 0.45):]
        return [files[round(i * (len(files) - 1) / (n - 1))] for i in range(n)]
    if strategy == "still":
        # 60% in: the pose has settled, and proportion drift grows later.
        return [files[int(len(files) * 0.60)]]
    if strategy == "blink":
        return pick_blink(files)
    raise ValueError(strategy)


def pick_gesture(files: list[Path], n: int) -> list[Path]:
    """Sample across the window where the character is actually moving.

    seedance spends the head and tail of a clip sitting in the rest pose. An
    even spread therefore burns several of the few frames a sheet has on
    identical stills, which reads as a stutter: the gesture snaps past and then
    the mascot freezes. Measuring motion and sampling only the active span puts
    every frame to work, while the padding keeps the first and last frames near
    rest so the sheet still hands off cleanly to idle.
    """
    small = [np.asarray(Image.open(f).convert("L").resize((104, 139)),
                        dtype=np.float32) for f in files]
    # Frame-to-frame velocity, NOT difference from frame 0: proportions drift
    # over a clip, so the character's final rest pose no longer matches its
    # first one and a difference-from-start metric reads the static tail as
    # motion. Velocity is ~0 whenever the character is holding still.
    vel = np.array([0.0] + [float(np.abs(small[i] - small[i - 1]).mean())
                            for i in range(1, len(small))])
    vel = np.convolve(vel, np.ones(5) / 5, mode="same")     # denoise
    if vel.max() <= 1e-6:
        return [files[round(i * (len(files) - 1) / (n - 1))] for i in range(n)]

    active = np.where(vel > 0.25 * vel.max())[0]
    pad = max(1, len(files) // 25)
    lo = max(0, int(active[0]) - pad)
    hi = min(len(files) - 1, int(active[-1]) + pad)
    if hi - lo < n:                       # degenerate; fall back to the clip
        lo, hi = 0, len(files) - 1
    print(f"    motion window frames {lo+1}-{hi+1} of {len(files)}")
    return [files[lo + round(i * (hi - lo) / (n - 1))] for i in range(n)]


def pick_blink(files: list[Path]) -> list[Path]:
    """rest, half-closed, closed, half-open, open -- all from one tight window.

    Only the eyelids are meant to move, so the highest-variance pixels across
    the clip *are* the eyes; no face detection needed.
    """
    stack = np.stack([np.asarray(Image.open(f).convert("L")).astype(np.float32)
                      for f in files])
    var = stack.std(axis=0)
    ys, xs = np.where(var > np.percentile(var, 99.6))
    band = stack[:, ys.min():ys.max() + 1, xs.min():xs.max() + 1]
    o = (band < 110).sum(axis=(1, 2)).astype(float)
    o = (o - o.min()) / (o.max() - o.min() + 1e-9)

    lo, hi = len(o) // 2, min(len(o), int(len(o) * 0.88))
    c = lo + int(np.argmin(o[lo:hi]))

    def nearest(rng, target):
        rng = [i for i in rng if 0 <= i < len(o)]
        return min(rng, key=lambda i: abs(o[i] - target)) if rng else c

    # Proportions drift slowly over a clip, so keep every pick near the blink.
    rest = nearest(range(c - 14, c - 2), 1.0)
    idx = [rest, nearest(range(rest + 1, c), 0.5), c,
           nearest(range(c + 1, c + 10), 0.5), nearest(range(c + 6, c + 16), 1.0)]
    return [files[i] for i in idx]


# ── Compositing ───────────────────────────────────────────────────────
def cutout(a: np.ndarray) -> np.ndarray:
    """RGB -> RGBA, removing only background that reaches the frame border.

    A plain white key would punch through white clothing; the characters wear
    white shirts and dresses enclosed by dark outlines, so those regions never
    touch the border and survive.
    """
    near_white = a.min(axis=2) > WHITE_CUT
    lbl, _ = ndimage.label(near_white)
    border = set(lbl[0, :]) | set(lbl[-1, :]) | set(lbl[:, 0]) | set(lbl[:, -1])
    border.discard(0)
    bg = np.isin(lbl, list(border))

    alpha = np.where(bg, 0.0, 1.0)
    ring = ndimage.binary_dilation(bg, iterations=2) & ~bg
    ink = np.clip((255 - a.min(axis=2)) / INK_SOFT, 0, 1)
    alpha = np.where(ring, np.minimum(alpha, ink), alpha)

    out = np.zeros((*a.shape[:2], 4), np.uint8)
    out[..., :3] = a.astype(np.uint8)
    out[..., 3] = (alpha * 255).astype(np.uint8)
    return out


def body_mask(rgba: np.ndarray) -> np.ndarray:
    """The character's own pixels, with stray specks discarded.

    Video compression leaves isolated dark pixels near the frame edges. They
    survive background removal, and a raw min/max over the alpha channel then
    reports the character as spanning the whole frame — which silently corrupts
    the scale normalisation and trips the crop guard. The character is by far
    the largest connected component, so anything under 1% of it is dropped.
    """
    m = rgba[..., 3] > 16
    lbl, n = ndimage.label(m)
    if n <= 1:
        return m
    sizes = ndimage.sum(m, lbl, range(1, n + 1))
    keep = {i + 1 for i, s in enumerate(sizes) if s >= 0.01 * sizes.max()}
    return np.isin(lbl, list(keep))


def metrics(rgba: np.ndarray):
    """(top, bottom, height, feet-x) of the character in an RGBA frame."""
    m = body_mask(rgba)
    ys, xs = np.where(m)
    y0, y1 = ys.min(), ys.max()
    h = y1 - y0 + 1
    band = m[max(y0, y1 - int(0.20 * h)):y1 + 1]
    bxs = np.where(band.any(axis=0))[0]
    return y0, y1, h, float((bxs.min() + bxs.max()) / 2)


def compose(name: str, action: str, frames_dir: Path, cell_w: int) -> Path:
    cols, rows, n, strategy, _ = ACTIONS[action]
    files = sorted(frames_dir.glob("*.png"))
    picks = pick(files, strategy, n)

    cut = [cutout(np.asarray(Image.open(f).convert("RGB")).astype(np.int16))
           for f in picks]
    met = [metrics(c) for c in cut]

    # A clip where the subject reaches the frame edge has been cropped by a
    # zoom-in, so its "head-to-feet" height is really head-to-frame-edge and
    # the normalisation below would silently scale the character wrong. Healthy
    # clips leave a margin; refuse rather than emit a broken sheet.
    fh, fw = cut[0].shape[:2]
    worst = max((y1 for _, y1, _, _ in met), default=0)
    fill = max(h for _, _, h, _ in met) / fh
    if worst >= fh - 2 or fill > 0.95:
        raise SheetTooTight(
            f"{name}_{action}: subject fills {fill:.0%} of frame height "
            f"(bottom gap {fh - 1 - worst}px) — the clip zoomed in and cropped "
            f"the character. Re-generate; do not ship this sheet.")

    # ONE transform for the whole clip (median over its frames): cross-sheet
    # consistency without introducing intra-clip jitter that isn't in the source.
    scale = TARGET_H / float(np.median([m[2] for m in met]))
    feet_x = float(np.median([m[3] for m in met]))
    base_y = float(np.median([m[1] for m in met]))

    sheet = Image.new("RGBA", (cell_w * cols, CELL_H * rows), (0, 0, 0, 0))
    for i, c in enumerate(cut):
        im = Image.fromarray(c)
        big = im.resize((round(im.width * scale), round(im.height * scale)),
                        Image.LANCZOS)
        ox = round(cell_w / 2 - feet_x * scale)
        oy = round(CELL_H - BOTTOM_PAD - (base_y + 1) * scale)
        cell = Image.new("RGBA", (cell_w, CELL_H), (0, 0, 0, 0))
        cell.alpha_composite(big, (ox, oy))
        sheet.paste(cell, ((i % cols) * cell_w, (i // cols) * CELL_H))

    out = DEST / f"{name}_{action}.png"
    sheet.save(out, optimize=True)
    print(f"  {out.name:26} {str(sheet.size):12} {out.stat().st_size/1e3:6.0f} KB  "
          f"{n} frames in {cols}x{rows}")
    return out


def cell_width_for(name: str) -> int:
    """Cell width for a character — every one of its sheets must share it.

    Established characters inherit the width their idle sheet already set, so
    new actions stay compatible with sheets already shipped. A new character
    has no sheet yet and takes the pinned `cell_w` from CHARACTERS.
    """
    cfg = CHARACTERS[name]
    if "from_sheet" in cfg and Path(cfg["from_sheet"]).exists():
        return Image.open(cfg["from_sheet"]).width // cfg["grid"][0]
    if "cell_w" in cfg:
        return int(cfg["cell_w"])
    sys.exit(f"{name}: no idle sheet yet — pin a 'cell_w' in CHARACTERS")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("characters", nargs="+", choices=sorted(CHARACTERS))
    ap.add_argument("--only", help="comma-separated subset of actions")
    ap.add_argument("--compose-only", action="store_true",
                    help="skip the API, rebuild sheets from cached frames")
    ap.add_argument("--jobs", type=int, default=4, help="concurrent generations")
    args = ap.parse_args()

    actions = args.only.split(",") if args.only else list(ACTIONS)
    for a in actions:
        if a not in ACTIONS:
            sys.exit(f"unknown action: {a}")
    CACHE.mkdir(parents=True, exist_ok=True)

    for name in args.characters:
        print(f"\n=== {name} ===")
        cell_w = cell_width_for(name)
        if args.compose_only:
            dirs = {a: CACHE / f"frames_{name}_{a}" for a in actions}
        else:
            url = upload(rest_frame(name))
            print(f"canonical rest -> {url}")
            with ThreadPoolExecutor(max_workers=args.jobs) as ex:
                futs = {a: ex.submit(generate, name, a, url) for a in actions}
                dirs = {a: f.result() for a, f in futs.items()}
        print(f"composing at cell {cell_w}x{CELL_H}")
        rejected = []
        for a in actions:
            if dirs[a].exists() and any(dirs[a].glob("*.png")):
                try:
                    compose(name, a, dirs[a], cell_w)
                except SheetTooTight as e:
                    rejected.append(a)
                    moved = archive(DEST / f"{name}_{a}.png", "cropped")
                    print(f"  REJECTED {e}")
                    if moved:
                        print(f"           archived previous sheet -> "
                              f"Archive/{moved.name}")
        if rejected:
            print(f"\n{len(rejected)} sheet(s) rejected for {name}: "
                  f"{', '.join(rejected)}\n  clear .sprite_cache/frames_{name}_"
                  f"<action> and re-run to regenerate them.")


if __name__ == "__main__":
    main()
