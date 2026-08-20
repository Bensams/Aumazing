#!/usr/bin/env python3
"""Generate the Ano'ng Nararamdaman? emotion, scene and response cards, starring BPS.

Engine: kie.ai `google/nano-banana-edit`. This is `generate_routine_cards.py`
with a different card list, and the two hard-won rules from that script apply
here unchanged — read its header before touching this one.

  1. TWO reference images per call. The character's chibi artwork carries
     identity (face, hair, outfit); a strip of three shipped routine cards
     carries the drawing style. Prompted from the chibi alone the model returns
     chibi art — huge head, cel shading — a different book from the card set.
     Prompted from the style strip alone it returns the generic child the strip
     already shows.
  2. ONE character across the whole set. It matters more here than it did
     there. A sequencing task asks "what does he do next?" and a second face
     merely changes the subject; a *recognition* task asks "how does he feel?",
     and a second face makes the child decide whether the new boy is a new
     person before they can look at his expression at all. BPS throughout,
     matching the routine cards, so the boy in this game is the boy the child
     already knows from Ano'ng Susunod.

Three kinds of card come out of this, and they are not interchangeable:

  face_*    a head-and-shoulders portrait, ONE emotion, nothing else in frame.
            These are the answer cards and the buddy. They carry the entire
            game: a face that is ambiguous, or that leans on a prop to be
            read, makes every trial that uses it unscoreable. Hence the
            per-emotion `features` line — the brow, eye and mouth geometry is
            SPELLED OUT rather than left to the word "sad", because the model
            renders emotion words as generic cartoon moods and renders
            described geometry as the thing you described.
  scene_*   what happened. The boy may appear, but the OBJECT is the subject
            and his face must stay neutral — a scene that already shows the
            answer turns the face card into decoration.
  do_*      a caring response for tier 3.

Everything here is deliberately mild. A dropped ice cream is the ceiling for a
negative event; nothing frightening, nothing showing a child hurt or left out.
The two scared scenes keep the threat behind a fence or outside a window.

Usage:
  pip install pillow numpy scipy requests
  export KIE_API_KEY=...           # never commit this
  python scripts/generate_emotion_cards.py                  # all twenty
  python scripts/generate_emotion_cards.py --only face_sad,scene_gift
  python scripts/generate_emotion_cards.py --faces-only
  python scripts/generate_emotion_cards.py --post-only      # re-run the
                                                            # post-process on
                                                            # cached raw output

Output:
  packages/shared_ui/assets/emotion_cards/{name}.png   512px, RGBA, palettised

Raw generations are cached in .card_cache/ (gitignored) so a re-run costs
nothing for cards that already came back, and a rejected card can be inspected
before it is regenerated.
"""

import argparse
import base64
import json
import os
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import numpy as np
import requests
from PIL import Image
from scipy import ndimage

# ── Paths ─────────────────────────────────────────────────────────────
SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parent
DEST = PROJECT_ROOT / "packages" / "shared_ui" / "assets" / "emotion_cards"
CHARACTER_ART = PROJECT_ROOT / "packages" / "assets" / "images" / "Character"
CACHE = PROJECT_ROOT / ".card_cache"

JOBS_API = "https://api.kie.ai"
UPLOAD_API = "https://kieai.redpandaai.co"      # NOT api.kie.ai; the docs are wrong

# ── Output geometry ───────────────────────────────────────────────────
CARD_PX = 512
CONTENT = 0.94        # drawing width as a fraction of the square, after trim
WHITE_CUT = 232       # channel value above which a pixel reads as page
INK_SOFT = 30.0       # edge-feather ramp, in channel values
COLORS = 255

# ── References ────────────────────────────────────────────────────────
# The face cards are generated once PER CHARACTER, so the buddy the child reads
# emotions on is the character their parent picked — the same figure they see as
# the mascot everywhere else, not a stranger. The single-character rule in the
# file header still holds WITHIN one child's session: a session renders exactly
# one character's faces, chosen by profile, never a mix.
#
# `subj`/`poss`/`noun` carry the pronouns into the geometry prompts, which were
# all written for BPS as "He/his/boy". They are the only per-character axis the
# expression text needs; the brow, eye and mouth geometry is identical across
# characters because an emotion is the same regardless of who wears it.
CHARACTERS = {
    "bps": {
        "art": CHARACTER_ART / "BPS_chibi.png",
        "face": ("a cheerful young Filipino boy with fair skin, warm brown "
                 "eyes, and messy spiky black hair"),
        # Spelled out rather than left to the reference image because
        # nano-banana reliably drops the garment it is not told about, and BPS
        # without his plaid overshirt is just a boy in a white tee.
        "clothes": ("an open pale blue and orange plaid button-up shirt over a "
                    "plain white t-shirt"),
        "subj": "he", "poss": "his", "noun": "boy",
    },
    "reiz": {
        "art": CHARACTER_ART / "Reiz_Chibi_nb.png",
        "face": ("a friendly young Filipino boy with fair skin, dark grey "
                 "eyes, and tousled dark charcoal-black hair"),
        "clothes": ("a black blazer over a plain white t-shirt, with a thin "
                    "silver dog-tag necklace"),
        "subj": "he", "poss": "his", "noun": "boy",
    },
    "lexianne": {
        "art": CHARACTER_ART / "Lexianne_chibi.png",
        "face": ("a cheerful young Filipina girl with fair skin, warm brown "
                 "eyes, and long wavy dark brown hair"),
        "clothes": ("a white short-puff-sleeve dress with a thin gold "
                    "necklace"),
        "subj": "she", "poss": "her", "noun": "girl",
    },
}
for _c in CHARACTERS.values():
    _c["look"] = f"{_c['face']}, wearing {_c['clothes']}"

# The style reference committed alongside the routine-card script, reused
# unchanged: this set has to sit beside those cards in the same app, drawn by
# the same hand. Rebuilding it from THIS folder would be the trap that script's
# header describes — a bad take becoming next run's house style.
STYLE_REF = SCRIPT_DIR / "assets" / "routine_card_style.png"

STYLE = (
    "STYLE: copy the drawing style of the second reference image exactly — a "
    "flat 2D children's picture-card illustration, simple and clean, with "
    "thick even dark charcoal outlines of a single weight, soft flat pastel "
    "fill colours (mint green, sky blue, peach, butter yellow, lavender), "
    "small round rosy cheeks and simple dot eyes. No gradients, no textures, "
    "no cel shading, no drop shadows, no outline thickness variation, no "
    "sketchy or painterly marks. "
    "IMPORTANT: this is NOT the chibi style of the first reference image — do "
    "not draw a large chibi head, do not use cel shading or soft rendering. "
    "COMPOSITION: one single scene, centred, filling the frame with a clear "
    "even margin on all four sides. At most one child in the picture unless "
    "the scene says otherwise, and no other people. "
    "BACKGROUND: plain solid pure white and completely empty. No border, no "
    "frame, no panel, no rounded card outline drawn around the scene, no "
    "floor line, no wall, no background scenery, no text, no letters, no "
    "numbers, no labels, no captions, no watermark, no logo."
)

# Portraits are framed and proportioned differently from scenes, so they get
# their own block rather than a flag on each line.
FACE_FRAMING = (
    "COMPOSITION: a head-and-shoulders portrait, facing the viewer straight "
    "on, head filling most of the frame. Normal picture-book child head "
    "proportions. Nothing else in the picture at all — no hands, no props, no "
    "objects, no background, no speech bubbles, no emoji, no symbols. The "
    "expression is the entire content of the card."
)

# name -> the expression, described as GEOMETRY.
#
# Every one of these was written as features rather than as a mood word, and
# that is the difference between a usable card set and an unusable one. Ask for
# "a sad boy" and the model returns its average of sad — often a slight frown
# that a child cannot separate from thinking, and often one carrying a prop
# (rain, a broken toy) that answers the question the card is supposed to ask.
# Ask for "inner eyebrow ends raised, mouth curved down at the corners" and it
# draws that.
#
# The five differ from each other in at least two of brow angle, eye size and
# mouth shape. Sad and scared, and scared and surprised, are the pairs children
# actually confuse, so those are the ones checked hardest before adoption: they
# must be TELLABLE APART by an adult at card size, or tier 2 is unfair.
# A panel drawn around the scene is INK, not page, so the white key in
# `cutout` cannot remove it — it survives as a box the card is trapped inside.
# The routine-card script hit this on `get_toy` and `play`; the two cards below
# that carry it are the two that came back framed here.
NOPANEL = (
    " Do NOT draw a square, a panel, a frame or any outlined box around the "
    "scene — the drawing sits directly on empty white with nothing enclosing "
    "it.")

# Written with {subj}/{poss}/{noun} tokens so one geometry description serves
# every character — an emotion is the same face movement whoever wears it, and
# only the pronouns change. `{Subj}`/`{Poss}` are the sentence-start capitals.
# Filled by `str.format` in `prompt_for`; keep any literal brace out of these.
FACES = {
    "face_neutral": (
        "{Poss} face is calm and relaxed: eyebrows level and straight, eyes "
        "normal size and open, mouth a small straight line with only the "
        "faintest hint of a curve. {Subj} is not smiling and not frowning — "
        "this is {poss} resting face."),
    "face_happy": (
        "{Subj} is HAPPY: a big open smile showing the upper teeth, mouth "
        "corners pulled up high, eyes crinkled into cheerful upward curves, "
        "eyebrows relaxed and slightly raised, cheeks round and rosy."),
    "face_sad": (
        "{Subj} is SAD: the INNER ends of both eyebrows are pulled UP and "
        "together into a little peak above the nose, eyes looking slightly "
        "downward, mouth closed and curved clearly DOWN at both corners, and "
        "one single small blue tear on {poss} left cheek. {Subj} is not crying "
        "loudly and {poss} mouth is not open."),
    # The hardest card in the set, and the one that came back wrong first time.
    # Asked for "scared" with the brow described only as "raised and pulled
    # together", the model drew a lowered V-shaped scowl — the ANGRY brow — and
    # returned a child who looks annoyed. Scared and angry are then two cards a
    # child cannot tell apart, and angry is one of the answers, so half the
    # trials using either become guesses. The fix is to forbid the wrong shape
    # explicitly, not just to describe the right one.
    "face_scared": (
        "{Subj} is SCARED and frightened, NOT angry: both eyebrows are lifted "
        "HIGH UP towards {poss} hairline and curve UPWARDS in worried arcs, "
        "with the inner ends the HIGHEST point. The eyebrows must NOT slant "
        "down towards the nose, must NOT form a V or an angry frown, and must "
        "NOT be lowered over the eyes. Eyes stretched wide open and round with "
        "a lot of white showing around small dark pupils. Mouth open in a "
        "small tense oval, corners pulled slightly down. One small pale blue "
        "sweat bead at {poss} temple. {Poss} face is pale rather than rosy. "
        "{Subj} looks worried and timid."),
    "face_surprised": (
        "{Subj} is SURPRISED: eyes wide and round, both eyebrows raised high "
        "and STRAIGHT ACROSS in flat arcs (their inner ends are NOT pulled up "
        "into a peak), and the mouth open in a big round O shape. {Poss} "
        "expression is startled but not frightened — no sweat, no pale skin, "
        "no lifted shoulders."),
    "face_angry": (
        "{Subj} is ANGRY: the INNER ends of both eyebrows are pushed DOWN and "
        "together into a hard V frown above the nose, eyes narrowed, mouth "
        "closed and pressed into a firm downward curve, cheeks flushed red. "
        "{Subj} is scowling, not crying — no tears."),
}

# name -> the situation. The object is the subject; his face stays neutral so
# the scene does not answer the question the face card asks.
SCENES = {
    "scene_gift": (
        "A small wrapped birthday present sitting on the floor: a rose pink "
        "box tied with a butter yellow ribbon and a big bow on top, with two "
        "hands entering from the right offering it forward. No faces in the "
        "picture." + NOPANEL),
    "scene_finished_drawing": (
        "A finished child's drawing lying on a table: a sheet of white paper "
        "showing a crayon picture of a yellow sun and a small mint green "
        "house, with three coloured crayons lying beside it. No people in the "
        "picture."),
    "scene_ice_cream_fell": (
        "A dropped ice cream on the ground: an empty light brown cone lying "
        "on its side and a single round scoop of peach ice cream fallen onto "
        "the ground just beside it, with two small motion lines above the "
        "scoop to show it has just fallen. No people in the picture."),
    "scene_spilled_drink": (
        "A knocked-over cup: a white cup lying on its side on a table with a "
        "puddle of pale blue juice spreading out from it. No people in the "
        "picture."),
    "scene_dog_barked": (
        "A friendly-looking small brown dog standing BEHIND a white wooden "
        "picket fence, its mouth open barking, with two small curved sound "
        "lines beside its head. The fence is clearly in front of the dog and "
        "runs across the whole width of the picture. The dog is cute and "
        "cartoonish, not frightening, not snarling, and shows no teeth. No "
        "people in the picture."),
    "scene_loud_thunder": (
        "A window seen from indoors: a simple square window frame, and "
        "outside it a grey cloud with a butter yellow lightning bolt below "
        "it, with two small sound lines beside the bolt. Calm and simple, not "
        "dramatic and not dark. No people in the picture."),
    "scene_jack_in_box": (
        "A jack-in-the-box toy that has just popped open: a sky blue box on "
        "the floor with its lavender lid flung open at an angle and a smiling "
        "butter yellow puppet head on a zig-zag spring springing up out of it. "
        "No people in the picture."),
    "scene_surprise_balloons": (
        "Three party balloons floating together with their strings hanging "
        "down: one rose pink, one butter yellow, one mint green, with a few "
        "small sparkle marks around them. No people in the picture."),
    "scene_tower_fell": (
        "A toppled tower of toy building blocks: one mint green block still "
        "standing upright and three more blocks — sky blue, rose pink and "
        "butter yellow — lying scattered and tilted on the ground around it, "
        "with two small motion lines above them. No people in the picture."),
    "scene_puzzle_stuck": (
        "A jigsaw puzzle that will not fit: a lavender puzzle board lying "
        "flat with one square gap missing from its middle, and a single peach "
        "puzzle piece held at an angle above the gap, with two small strain "
        "lines beside the piece to show it will not go in. No people in the "
        "picture."),
}

# name -> the caring response. These DO show the boy, because the card is about
# something a person does.
RESPONSES = {
    "do_hug": (
        "The boy is giving a warm hug: he and one other child of the same "
        "size stand facing each other with their arms around each other's "
        "backs, both smiling gently, seen from the side. This is the one card "
        "in the set with two children in it."),
    "do_share": (
        "The boy is sharing a toy: he stands facing the viewer holding a "
        "rose pink ball out in front of him in both hands, arms extended "
        "forward as if offering it to someone, smiling kindly."),
    "do_sorry": (
        "The boy is saying sorry: he stands facing the viewer with one hand "
        "flat on his own chest, head tilted slightly down, with a gentle "
        "apologetic expression — eyebrows raised in the middle and a small "
        "closed mouth. Beside his head is a simple empty white speech bubble "
        "containing one small rose pink heart and NO text or letters."),
    "do_clap": (
        "The boy is clapping happily: he stands facing the viewer with both "
        "hands together in front of his chest mid-clap, smiling widely, with "
        "three short motion lines around his hands to show the clapping."
        + NOPANEL),
}

CARDS = {**FACES, **SCENES, **RESPONSES}


def key() -> str:
    k = os.environ.get("KIE_API_KEY")
    if not k:
        sys.exit("KIE_API_KEY is not set")
    return k


def headers() -> dict:
    return {"Authorization": f"Bearer {key()}", "Content-Type": "application/json"}


# ── References ────────────────────────────────────────────────────────
MAX_REF_PX = 1024     # the model renders far smaller; more is only slower upload


def character_ref(char: str) -> Path:
    """A character's artwork, flattened onto white and scaled for upload."""
    src = CHARACTERS[char]["art"]
    if not src.exists():
        sys.exit(f"character artwork not found at {src}")
    im = Image.open(src).convert("RGBA")
    flat = Image.new("RGB", im.size, (255, 255, 255))
    flat.paste(im, (0, 0), im)
    flat.thumbnail((MAX_REF_PX, MAX_REF_PX), Image.LANCZOS)
    out = CACHE / f"ref_{char}.png"
    flat.save(out)
    return out


def upload(path: Path) -> str:
    b64 = base64.b64encode(path.read_bytes()).decode()
    r = requests.post(f"{UPLOAD_API}/api/file-base64-upload", headers=headers(),
                      json={"base64Data": f"data:image/png;base64,{b64}",
                            "uploadPath": "images/aumazing",
                            "fileName": path.name},
                      timeout=300)
    r.raise_for_status()
    d = r.json()
    if not d.get("success"):
        sys.exit(f"upload failed: {d}")
    return d["data"]["downloadUrl"]


# ── Generation ────────────────────────────────────────────────────────
def prompt_for(name: str, char: str) -> str:
    is_face = name in FACES
    is_scene = name in SCENES

    if is_scene:
        # No character reference language at all: naming them invites them into
        # a picture that is supposed to be about the object, and a scene with a
        # face in it hands the child the answer.
        return (
            "Draw a single children's picture card showing an object or a "
            "small situation.\n\n"
            "The FIRST reference image shows the art style's character for "
            "context only — do NOT draw any person in this card.\n\n"
            "The SECOND reference image shows three finished cards from the "
            "same set. Match their drawing style, line weight, colour palette "
            "and framing exactly, so this card belongs beside them.\n\n"
            f"SCENE: {CARDS[name]}\n\n" + STYLE
        )

    c = CHARACTERS[char]
    obj = "him" if c["subj"] == "he" else "her"
    who = (
        f"The FIRST reference image is the character. Keep {obj} recognisably "
        f"the same {c['noun']}: {c['look']}. Same hair shape, same hair "
        "colour, same eye colour and same skin tone in every card.\n\n"
        "The SECOND reference image shows three finished cards from the same "
        "set. Match their drawing style, line weight, colour palette and "
        "framing exactly, so this card belongs beside them.\n\n"
    )

    if is_face:
        body = CARDS[name].format(
            Subj=c["subj"].capitalize(), subj=c["subj"],
            Poss=c["poss"].capitalize(), poss=c["poss"], noun=c["noun"])
        return (
            f"Draw a single children's picture card: a portrait of one "
            f"{c['noun']}'s face showing one clear emotion.\n\n" + who +
            f"EXPRESSION: {body}\n\n" + FACE_FRAMING + "\n\n" + STYLE
        )

    return (
        f"Draw a single children's picture card showing a {c['noun']} doing a "
        f"kind thing.\n\n" + who + f"SCENE: {CARDS[name]}\n\n" + STYLE
    )


# A scene has no character in it, so its raw and its output are shared by every
# character; a face or a response is per-character and carries the name in both.
def raw_path(name: str, char: str) -> Path:
    return CACHE / (f"raw_{name}.png" if name in SCENES
                    else f"raw_{char}_{name}.png")


def out_name(name: str, char: str) -> str:
    # face_sad -> face_lexianne_sad, so the game can load the child's own
    # character's set and fall back to the generic face_*.png if one is missing.
    return name.replace("face_", f"face_{char}_") if name in FACES else name


def generate(name: str, char: str, char_url: str, style_url: str) -> Path:
    raw = raw_path(name, char)
    tag = name if name in SCENES else f"{char}/{name}"
    if raw.exists():
        print(f"[{tag}] cached")
        return raw

    body = {
        "model": "google/nano-banana-edit",
        "input": {
            "prompt": prompt_for(name, char),
            "image_urls": [char_url, style_url],
            "output_format": "png",
            "image_size": "1:1",
        },
    }
    r = requests.post(f"{JOBS_API}/api/v1/jobs/createTask",
                      headers=headers(), json=body, timeout=60)
    r.raise_for_status()
    d = r.json()
    if d.get("code") != 200:
        sys.exit(f"[{tag}] createTask failed: {d}")
    task_id = d["data"]["taskId"]
    print(f"[{tag}] -> task {task_id}")

    data = {}
    for _ in range(90):
        time.sleep(5)
        data = (requests.get(f"{JOBS_API}/api/v1/jobs/recordInfo",
                             headers=headers(), params={"taskId": task_id},
                             timeout=60).json().get("data") or {})
        if data.get("state") == "success":
            print(f"[{tag}] {data.get('costTime')}ms, "
                  f"{data.get('creditsConsumed')} credits")
            break
        if data.get("state") == "fail":
            sys.exit(f"[{tag}] failed: {data.get('failMsg')}")
    else:
        sys.exit(f"[{tag}] timed out")

    url = json.loads(data["resultJson"])["resultUrls"][0]
    raw.write_bytes(requests.get(url, timeout=600).content)
    return raw


# ── Post-processing ───────────────────────────────────────────────────
def cutout(a: np.ndarray) -> np.ndarray:
    """RGB -> RGBA, removing only page white that reaches the frame border.

    A plain white key would punch through white *inside* a drawing — the
    whites of the eyes, teeth, a speech bubble, BPS's t-shirt. Those regions
    are enclosed by the dark outline so they never connect to the border, and
    they survive. On this set that matters more than it did on the routine
    cards: eye whites are most of what makes a scared face scared.
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


def content_box(rgba: np.ndarray) -> tuple:
    """Bounding box of the drawing, with compression specks discarded."""
    m = rgba[..., 3] > 16
    lbl, n = ndimage.label(m)
    if n > 1:
        sizes = ndimage.sum(m, lbl, range(1, n + 1))
        keep = [i + 1 for i, s in enumerate(sizes) if s >= 0.005 * sizes.max()]
        m = np.isin(lbl, keep)
    ys, xs = np.where(m)
    return xs.min(), ys.min(), xs.max() + 1, ys.max() + 1


def postprocess(raw: Path, name: str, char: str) -> Path:
    """Key out the page, trim to the drawing, re-pad square, shrink, palettise.

    Squaring every card here is what lets the game position art with one rule
    instead of twenty: `drawFace`/`drawScene` draw into a square box and trust
    the picture to already be centred in one.
    """
    src = Image.open(raw).convert("RGB")
    rgba = cutout(np.asarray(src).astype(np.int16))
    x0, y0, x1, y1 = content_box(rgba)
    drawing = Image.fromarray(rgba).crop((x0, y0, x1, y1))

    inner = round(CARD_PX * CONTENT)
    scale = inner / max(drawing.width, drawing.height)
    drawing = drawing.resize((max(1, round(drawing.width * scale)),
                              max(1, round(drawing.height * scale))),
                             Image.LANCZOS)

    card = Image.new("RGBA", (CARD_PX, CARD_PX), (0, 0, 0, 0))
    card.alpha_composite(drawing, ((CARD_PX - drawing.width) // 2,
                                   (CARD_PX - drawing.height) // 2))

    DEST.mkdir(parents=True, exist_ok=True)
    out = DEST / f"{out_name(name, char)}.png"
    card.quantize(colors=COLORS, method=Image.FASTOCTREE).save(out, optimize=True)
    print(f"  {out.name:26} {x1-x0:4}x{y1-y0:4} -> {CARD_PX}px  "
          f"{out.stat().st_size/1e3:5.0f} KB")
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", help="comma-separated subset of card names")
    ap.add_argument("--faces-only", action="store_true",
                    help="just the six face cards — the ones worth iterating on")
    ap.add_argument("--character",
                    help="comma-separated subset of characters "
                         f"({', '.join(CHARACTERS)}); default all. Faces are "
                         "generated once per character; scenes and responses "
                         "are drawn once, as BPS.")
    ap.add_argument("--post-only", action="store_true",
                    help="skip the API, re-run post-processing on cached raws")
    ap.add_argument("--force", action="store_true",
                    help="regenerate even if a raw is already cached")
    ap.add_argument("--jobs", type=int, default=4, help="concurrent generations")
    args = ap.parse_args()

    if args.only:
        names = args.only.split(",")
    elif args.faces_only:
        names = list(FACES)
    else:
        names = list(CARDS)
    for n in names:
        if n not in CARDS:
            sys.exit(f"unknown card: {n}")

    chars = args.character.split(",") if args.character else list(CHARACTERS)
    for ch in chars:
        if ch not in CHARACTERS:
            sys.exit(f"unknown character: {ch}")

    # The unit of work is a (card, character) pair. Faces are drawn for every
    # requested character; a scene has no person in it and a response card is
    # tier-3 filler, so both are drawn once as BPS regardless of --character —
    # the child's own character is what matters on the face cards they read.
    jobs = [(n, ch) for ch in chars for n in names if n in FACES]
    jobs += [(n, "bps") for n in names if n not in FACES]

    CACHE.mkdir(parents=True, exist_ok=True)
    if args.force:
        for n, ch in jobs:
            raw_path(n, ch).unlink(missing_ok=True)

    if args.post_only:
        raws = {(n, ch): raw_path(n, ch) for n, ch in jobs}
        missing = [f"{ch}/{n}" for (n, ch), p in raws.items() if not p.exists()]
        if missing:
            sys.exit(f"no cached raw for: {', '.join(missing)}")
    else:
        # Uploaded once and shared by every card: the references are what make
        # the set consistent, so they must be byte-identical across the batch.
        if not STYLE_REF.exists():
            sys.exit(f"style reference missing: {STYLE_REF}\n"
                     f"rebuild it with generate_routine_cards.py "
                     f"--rebuild-style-ref")
        style_url = upload(STYLE_REF)
        print(f"style -> {style_url}")
        needed = sorted({ch for _, ch in jobs})
        char_urls = {ch: upload(character_ref(ch)) for ch in needed}
        for ch, u in char_urls.items():
            print(f"{ch:9} -> {u}")

        with ThreadPoolExecutor(max_workers=args.jobs) as ex:
            futs = {(n, ch): ex.submit(generate, n, ch, char_urls[ch],
                                       style_url)
                    for n, ch in jobs}
            raws = {k: f.result() for k, f in futs.items()}

    print("\npost-processing")
    for n, ch in jobs:
        postprocess(raws[(n, ch)], n, ch)


if __name__ == "__main__":
    main()
