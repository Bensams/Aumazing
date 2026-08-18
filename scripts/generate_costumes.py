#!/usr/bin/env python3
"""Generate the Star Shop costume art: each of the three characters in each animal onesie.

Engine: kie.ai `google/nano-banana-edit`, same job API as
`generate_emotion_cards.py`. Read that script's header first — the reference
rules below are its rules, adapted.

TWO reference images per call, and which two is the whole trick:

  1. the character's base chibi  -> identity and POSE. BPS holds his code book
     with his right hand on his hip; Reiz is mid thumbs-up; Lexianne stands
     arms-down. The costume must not restage them, because every sprite sheet
     is later cut from this frame and a character who changes stance when the
     parent buys a hat reads as a different character.
  2. a Teddy costume            -> the costume convention. This is what makes
     the set a set. Prompted from a written description alone the model returns
     a different garment each time — a hood here, a mascot fursuit there, an
     animal-headed creature that is no longer a child in the third. Handed a
     Teddy it copies the established thing: fleece onesie, hood up with the
     animal's head on the CROWN, plaid pocket and knee patches, paw slippers.

Teddy is therefore the parent of all the others. Prefer the character's OWN
Teddy; `teddy_ref_for()` falls back to any other character's when it is
missing, which is what makes the set recoverable from a single surviving file
(see the note on that function).

The one failure worth naming, because it is the one the model reaches for
unprompted: putting the animal's face ON the child's face. That is a mask, not
a costume — it hides the very thing three months of sprite work exists to show,
and a child cannot find themself in a character whose face is gone. The animal
head rides ABOVE the forehead; the child's face, eyes and fringe stay fully
visible in the hood opening. Hence the blunt NEVER block in STYLE.

Usage:
  export KIE_API_KEY=...           # never commit this
  python scripts/generate_costumes.py                     # all 27
  python scripts/generate_costumes.py --only panda        # one animal, x3
  python scripts/generate_costumes.py --only panda:reiz   # one image
  python scripts/generate_costumes.py --list

Output:
  packages/assets/images/Character/Character_Costume/{Animal}/{Char}_chibi_{Animal}.png

Plain white background and full resolution, matching the base chibis — this is
source art for `generate_sprites.py`, not a runtime asset. No cutout, no
downscale, no sprite sheets; those come later.

Raw generations are cached in ~/.cache/aumazing/costumes — deliberately OUTSIDE
the repository. An in-repo cache was wiped by a `git clean -fd` along with the
finished art, which turned a free re-install into a regeneration; being outside
the working tree means housekeeping in the repo cannot touch it. Override with
COSTUME_CACHE_DIR.
"""

import argparse
import base64
import json
import os
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import requests
from PIL import Image

# ── Paths ─────────────────────────────────────────────────────────────
SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parent
CHARACTER_ART = PROJECT_ROOT / "packages" / "assets" / "images" / "Character"
COSTUME_DIR = CHARACTER_ART / "Character_Costume"

# Outside the working tree on purpose — see the module docstring.
CACHE = Path(os.environ.get(
    "COSTUME_CACHE_DIR", Path.home() / ".cache" / "aumazing" / "costumes"))

JOBS_API = "https://api.kie.ai"
UPLOAD_API = "https://kieai.redpandaai.co"      # NOT api.kie.ai; the docs are wrong

MAX_REF_PX = 1024     # the model renders far smaller; more is only slower upload

# ── Characters ────────────────────────────────────────────────────────
# `look` spells out what the reference already shows, because nano-banana
# reliably drops the detail it is not told about — and these details ARE the
# character. Reiz without the dog tags is a boy in black; Lexianne without the
# hair volume is any girl.
#
# `keep` is the part that survives the costume: the signature prop and the
# pose. The Teddy references show exactly this being honoured, which is why
# one is handed over as the second image.
CHARACTERS = {
    "bps": {
        "file": "BPs",
        "art": CHARACTER_ART / "BPS_chibi.png",
        "look": ("a cheerful young Filipino boy with fair skin, warm brown "
                 "eyes, thick dark eyebrows and messy spiky black hair with a "
                 "jagged fringe"),
        "keep": ("He keeps holding his small brown book in his left hand, held "
                 "low in front of his hip exactly as in the reference, and his "
                 "right arm stays down at his side with the hand resting "
                 "behind his hip. Same closed-mouth smile, same head tilt."),
    },
    "lexianne": {
        "file": "Lexianne",
        "art": CHARACTER_ART / "Lexianne_chibi.png",
        "look": ("a young girl with fair skin, very large round dark brown "
                 "eyes, and long dark brown wavy hair falling well past her "
                 "shoulders"),
        # Her hair is the identity signal and the hood would eat it, so it is
        # called out as spilling out and down — the Teddy does this and it is
        # the single clearest difference between her costume and the others'.
        "keep": ("Her long dark wavy hair spills OUT of the hood on both sides "
                 "and hangs down past her chest, staying clearly visible — the "
                 "hood must not hide or shorten it. She keeps her thin gold "
                 "necklace at the collar. Both arms relaxed straight down at "
                 "her sides, hands empty and open. Same gentle closed-mouth "
                 "smile."),
    },
    "reiz": {
        "file": "Reiz",
        "art": CHARACTER_ART / "Reiz_Chibi_nb.png",
        "look": ("a young child with fair skin, large dark grey eyes, and "
                 "soft layered black hair with a side-swept fringe"),
        "keep": ("They keep their silver dog-tag pendant necklace, worn "
                 "outside the costume at the chest. Their right hand stays "
                 "raised in the same relaxed thumbs-up in front of the chest "
                 "and the left arm stays down at the side, exactly as in the "
                 "reference. Same small closed-mouth smile."),
    },
}

# Candidate Teddy filenames per character, most-preferred first. Two spellings
# because the set has two generations of file: the hand-authored `.jfif`
# originals, and `.png` rebuilds written by this script under the same naming
# scheme as every other costume. Capitalisation is inconsistent between the
# originals and that is how they are on disk, so match rather than guess.
TEDDY_FILES = {
    "bps": ["BPs_chibi_Teddy_Bear.jfif", "BPs_chibi_Teddy.png"],
    "lexianne": ["Lexianne_chibi_Teddy_Bear.jfif", "Lexianne_chibi_Teddy.png"],
    "reiz": ["Reiz_chibi_Teddy_Bear.jfif", "Reiz_chibi_Teddy.png"],
}


def teddy_ref_for(char: str) -> Path:
    """The costume-convention reference for `char`: their Teddy, or any Teddy.

    The character's own Teddy is the better reference — it already shows this
    face inside this hood, so the model has nothing to invent. But the set only
    needs ONE surviving Teddy to be rebuildable, because the first reference
    already carries identity and the second is only being read for garment
    construction. Falling back rather than failing is what made recovering the
    whole set from a single file in Downloads possible after the originals were
    deleted; keep this behaviour.
    """
    for name in TEDDY_FILES[char]:
        own = COSTUME_DIR / "Teddy" / name
        if own.exists():
            return own
    for other, names in TEDDY_FILES.items():
        for name in names:
            alt = COSTUME_DIR / "Teddy" / name
            if alt.exists():
                print(f"[{char}] own Teddy missing; using {other}'s as style ref")
                return alt
    sys.exit(f"no Teddy reference found in {COSTUME_DIR / 'Teddy'} — "
             f"the whole set is derived from one, so at least one must exist")


# ── The costume house style ───────────────────────────────────────────
# Written once and shared, because the costumes differing in anything except
# the animal is what would make the shop look assembled from stock art.
STYLE = (
    "COSTUME CONSTRUCTION: copy the construction of the costume in the SECOND "
    "reference image exactly, changing only which animal it is. A soft fuzzy "
    "fleece one-piece onesie covering the whole body, arms and legs, with "
    "rounded mitten paw hands and soft animal-paw slipper feet. The hood is "
    "pulled UP over the head, and the animal's own head — its ears, its muzzle "
    "and its two small dark eyes — sits on the CROWN of the hood, high above "
    "the child's forehead. "
    "Keep the same flannel plaid accents the Teddy has, in colours that suit "
    "this animal: a plaid kangaroo pocket on the belly, two plaid patches on "
    "the knees, and plaid lining showing at the cuffs and inside the hood "
    "opening. "
    "NEVER put the animal's face over the child's face. The child is NOT "
    "wearing a mask and is NOT turning into the animal. The child's own human "
    "face, eyes, eyebrows, cheeks and hair fringe stay completely visible and "
    "unobstructed inside the round hood opening, exactly as in the second "
    "reference image. Do not add fur, whiskers, a snout, animal ears or animal "
    "markings to the child's actual face. "
    "STYLE: keep the exact art style of both reference images — flat 2D "
    "cartoon anime chibi, large head on a small body, thick clean dark "
    "outlines of even weight, soft cel shading, small round rosy cheeks. No "
    "gradients, no texture, no painterly rendering, no drop shadow, no outline "
    "thickness variation. "
    "POSE: identical to the FIRST reference image — same stance, same arm "
    "positions, same head angle, facing the viewer. Do not restage or "
    "re-pose the character. "
    "FRAMING: full body from the very top of the hood's ears to the soles of "
    "the feet, entirely inside the frame with clear empty margin above and "
    "below. Do not crop any part of the character or the hood ears. Centred "
    "horizontally. Portrait 3:4. "
    "BACKGROUND: plain solid pure white and completely empty. No shadow under "
    "the character, no floor, no gradient, no scenery, no props other than the "
    "ones named, no text, no letters, no labels, no watermark, no logo, no "
    "extra characters."
)

# name -> (folder name, the animal, described as SHAPE AND COLOUR).
#
# Described as geometry rather than by species name for the same reason the
# emotion cards spell out brow angles: asked for "a fox onesie" the model
# returns its average of fox, which is a fursuit as often as it is a onesie.
# Asked for "rust orange fleece, pointed triangular ears with black tips, a
# white muzzle patch on the crown" it builds the thing described.
#
# Every one of these is soft, round and friendly. Nothing with teeth, claws,
# an open mouth or an angry brow — this art is bought by a child as a reward
# and then worn by the character who guides them through the games.
COSTUMES = {
    # Teddy is the house style's origin. It is here so a missing one can be
    # rebuilt from a surviving sibling, NOT so the set gets regenerated
    # casually — a fresh Teddy silently becomes the parent of every future
    # costume, so prefer the authored files whenever they exist.
    "teddy": ("Teddy", (
        "A TEDDY BEAR onesie in warm mid-brown fleece with a slightly paler "
        "muzzle. On the crown of the hood are two small round brown ears with "
        "paler inner circles, two small dark eyes, and a rounded pale-tan "
        "muzzle with a dark brown nose and a small stitched smile. Brown "
        "mitten paws and brown paw slippers with tan pads.")),

    "panda": ("Panda", (
        "A PANDA onesie. The body of the onesie is soft cream white, with "
        "black fleece arms and black fleece legs. On the crown of the hood are "
        "two small round black ears, a black oval patch around each of the "
        "panda's two small dark eyes, and a small rounded black muzzle with a "
        "black nose. Black mitten paws and black paw slippers with cream pads.")),

    "fox": ("Fox", (
        "A FOX onesie in warm rust orange fleece, with a cream white belly "
        "panel and a cream white muzzle. On the crown of the hood are two "
        "upright pointed triangular ears with cream inner lining and soft "
        "black tips, two small dark eyes, and a small pointed cream muzzle "
        "with a black nose. A big bushy rust orange tail with a cream white "
        "tip curves out from behind the hip and is clearly visible beside one "
        "leg. Cream mitten paws and cream paw slippers.")),

    "koala": ("Koala", (
        "A KOALA onesie in soft dove grey fleece with a pale cream belly "
        "panel. On the crown of the hood are two very large round fluffy grey "
        "ears set wide on either side with fuzzy cream inner tufts spilling "
        "out of them, two small dark eyes, and a big rounded dark grey nose "
        "shaped like a wide oval. Grey mitten paws and grey paw slippers.")),

    "frog": ("Frog", (
        "A FROG onesie in bright fresh leaf green fleece with a pale butter "
        "cream belly panel. On the crown of the hood are two large round eye "
        "domes sitting high on top like a frog's, each a green half-sphere "
        "with a big friendly dark eye and a white highlight, and below them a "
        "wide gentle closed smile line across the front of the hood. No ears. "
        "Green mitten paws and green webbed paw slippers with cream toes.")),

    "unicorn": ("Unicorn", (
        "A UNICORN onesie in soft white fleece with a very pale lavender belly "
        "panel. On the crown of the hood is a short spiralled golden horn "
        "standing straight up, two small white ears with soft pink inner "
        "lining on either side of it, two small dark eyes, and a small white "
        "muzzle with a soft pink nose. A soft pastel rainbow mane of pink, "
        "lavender and mint runs down the back of the hood and is visible on "
        "both sides, and a matching pastel rainbow tail curves out from behind "
        "the hip. White mitten paws and white paw slippers with pale pink "
        "pads.")),

    "octopus": ("Octopus", (
        "An OCTOPUS onesie in soft lavender purple fleece. The hood is a big "
        "smooth rounded dome like an octopus's head, with two large friendly "
        "dark eyes near the top of it and a small closed smile below them. No "
        "ears. Around the waist, eight short soft stubby lavender tentacles "
        "hang down all the way around like a little skirt, each curling gently "
        "upward at the tip and showing a row of small pale pink sucker dots "
        "underneath. Lavender mitten paws and lavender paw slippers.")),

    "rabbit": ("Rabbit", (
        "A RABBIT onesie in soft cream white fleece. On the crown of the hood "
        "are two very long upright rabbit ears standing tall, each with a soft "
        "pale pink inner lining, one of them flopping over slightly at the "
        "tip. Below them two small dark eyes and a small cream muzzle with a "
        "tiny pink triangular nose. A small round fluffy white bobtail is just "
        "visible at the hip. Cream mitten paws and cream paw slippers with "
        "pale pink pads.")),

    "pig": ("Pig", (
        "A PIG onesie in soft blush pink fleece. On the crown of the hood are "
        "two small floppy triangular pink ears tipping forward, two small dark "
        "eyes, and a round flat pig snout in a slightly deeper pink with two "
        "small nostril dots. A short curly pink tail springs out from behind "
        "the hip. Pink mitten paws and pink trotter slippers with deeper pink "
        "pads.")),
}


def key() -> str:
    k = os.environ.get("KIE_API_KEY")
    if not k:
        sys.exit("KIE_API_KEY is not set")
    return k


def headers() -> dict:
    return {"Authorization": f"Bearer {key()}", "Content-Type": "application/json"}


# ── References ────────────────────────────────────────────────────────
def flatten(src: Path, tag: str) -> Path:
    """Flatten onto white and scale for upload.

    Two of the three chibis carry alpha and the Teddys are JFIF; uploading a
    transparent PNG lets the model read the hole as part of the drawing and it
    paints into it. White is also what the base art already sits on, so this
    loses nothing.
    """
    if not src.exists():
        sys.exit(f"reference not found: {src}")
    im = Image.open(src)
    flat = Image.new("RGB", im.size, (255, 255, 255))
    if im.mode == "RGBA":
        flat.paste(im, (0, 0), im)
    else:
        flat.paste(im.convert("RGB"), (0, 0))
    flat.thumbnail((MAX_REF_PX, MAX_REF_PX), Image.LANCZOS)
    out = CACHE / f"ref_{tag}.png"
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
def prompt_for(costume: str, char: str) -> str:
    c = CHARACTERS[char]
    _, animal = COSTUMES[costume]
    return (
        "Redraw the character from the first reference image wearing an animal "
        "onesie costume.\n\n"
        "The FIRST reference image is the character. Keep the same child, "
        f"recognisably: {c['look']}. Same face shape, same eye colour, same "
        "skin tone, same hair colour and same hair shape.\n\n"
        "The SECOND reference image shows this same style of costume — a teddy "
        "bear version — worn in this same art style. Match its costume "
        "construction, its art style, its line weight and its framing exactly, "
        "so this new costume belongs beside it in the same set. Note that the "
        "child in the second image may be a different child; take only the "
        "COSTUME and the DRAWING STYLE from it, never the face.\n\n"
        f"COSTUME: {animal}\n\n"
        f"KEEP: {c['keep']}\n\n"
        + STYLE
    )


def generate(costume: str, char: str, char_url: str, teddy_url: str) -> Path:
    name = f"{costume}_{char}"
    raw = CACHE / f"raw_{name}.png"
    if raw.exists():
        print(f"[{name}] cached")
        return raw

    body = {
        "model": "google/nano-banana-edit",
        "input": {
            "prompt": prompt_for(costume, char),
            "image_urls": [char_url, teddy_url],
            "output_format": "png",
            "image_size": "3:4",
        },
    }
    r = requests.post(f"{JOBS_API}/api/v1/jobs/createTask",
                      headers=headers(), json=body, timeout=60)
    r.raise_for_status()
    d = r.json()
    if d.get("code") != 200:
        sys.exit(f"[{name}] createTask failed: {d}")
    task_id = d["data"]["taskId"]
    print(f"[{name}] -> task {task_id}")

    data = {}
    for _ in range(90):
        time.sleep(5)
        data = (requests.get(f"{JOBS_API}/api/v1/jobs/recordInfo",
                             headers=headers(), params={"taskId": task_id},
                             timeout=60).json().get("data") or {})
        if data.get("state") == "success":
            print(f"[{name}] {data.get('costTime')}ms, "
                  f"{data.get('creditsConsumed')} credits")
            break
        if data.get("state") == "fail":
            print(f"[{name}] FAILED: {data.get('failMsg')}")
            return None
    else:
        print(f"[{name}] timed out")
        return None

    url = json.loads(data["resultJson"])["resultUrls"][0]
    # The CDN rejects requests without a browser User-Agent.
    raw.write_bytes(requests.get(
        url, headers={"User-Agent": "Mozilla/5.0"}, timeout=600).content)
    return raw


def install(raw: Path, costume: str, char: str) -> Path:
    """Copy the raw generation into the asset tree under the set's naming."""
    folder, _ = COSTUMES[costume]
    dest_dir = COSTUME_DIR / folder
    dest_dir.mkdir(parents=True, exist_ok=True)
    out = dest_dir / f"{CHARACTERS[char]['file']}_chibi_{folder}.png"
    im = Image.open(raw).convert("RGB")
    im.save(out)
    print(f"  {out.relative_to(PROJECT_ROOT)}  {im.width}x{im.height}  "
          f"{out.stat().st_size/1e3:.0f} KB")
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", help="comma-separated 'costume' or 'costume:character'")
    ap.add_argument("--force", action="store_true",
                    help="regenerate even if a raw is already cached")
    ap.add_argument("--jobs", type=int, default=4, help="concurrent generations")
    ap.add_argument("--list", action="store_true", help="list the pairs and exit")
    args = ap.parse_args()

    pairs = [(c, ch) for c in COSTUMES for ch in CHARACTERS]
    if args.only:
        wanted = []
        for spec in args.only.split(","):
            costume, _, char = spec.partition(":")
            if costume not in COSTUMES:
                sys.exit(f"unknown costume: {costume}")
            if char and char not in CHARACTERS:
                sys.exit(f"unknown character: {char}")
            wanted += [(costume, ch) for ch in ([char] if char else CHARACTERS)]
        pairs = wanted

    if args.list:
        for c, ch in pairs:
            print(f"{c}:{ch}")
        return

    CACHE.mkdir(parents=True, exist_ok=True)
    print(f"cache: {CACHE}")
    if args.force:
        for c, ch in pairs:
            (CACHE / f"raw_{c}_{ch}.png").unlink(missing_ok=True)

    # Uploaded once and shared across the batch: the references are what make
    # the set consistent, so they must be byte-identical for every costume.
    refs = {}
    for ch in CHARACTERS:
        if any(p[1] == ch for p in pairs):
            refs[ch] = (upload(flatten(CHARACTERS[ch]["art"], ch)),
                        upload(flatten(teddy_ref_for(ch), f"{ch}_teddy")))
            print(f"{ch:9} refs uploaded")

    with ThreadPoolExecutor(max_workers=args.jobs) as ex:
        futs = {(c, ch): ex.submit(generate, c, ch, *refs[ch]) for c, ch in pairs}
        raws = {k: f.result() for k, f in futs.items()}

    print("\ninstalling")
    failed = [k for k, v in raws.items() if v is None]
    for (c, ch), raw in raws.items():
        if raw is not None:
            install(raw, c, ch)
    if failed:
        print("\nFAILED: " + ", ".join(f"{c}:{ch}" for c, ch in failed))
        sys.exit(1)


if __name__ == "__main__":
    main()
