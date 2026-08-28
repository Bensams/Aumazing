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
import shutil
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
# Clips + frames. Overridable, because an in-repo cache is only gitignored —
# not safe. A `git clean -fd` wiped the costume-art cache along with the
# finished art, turning a free recompose into a paid regeneration; at 164
# credits per clip a lost sprite cache is far more expensive than that was.
# Point SPRITE_CACHE_DIR outside the working tree for long runs.
CACHE = Path(os.environ.get("SPRITE_CACHE_DIR",
                            PROJECT_ROOT / ".sprite_cache"))

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

# The eight gaze poses differ only by which way the eyes are rolled, so they
# share one prompt. Together with the idle rest frame they form a 3x3 grid the
# app indexes by where the child's finger is.
#
# Every direction is named RELATIVE TO THE IMAGE, and the prompt says so in
# those words. `point` and `present` phrase their side as "its own left" and
# land correctly mirrored on frame right, so the first gaze takes did the same
# — and the model did not honour it. BPS came back with BOTH poses inverted;
# Reiz drew itself looking left for both, twice, even after a regeneration.
# Character-relative wording is simply not something it resolves consistently
# for eyes. Naming the side of the IMAGE removes the ambiguity: there is
# nothing left to mirror.
#
# Sheet names follow what the child sees. Always confirm with
# scripts/check_gaze.py — direction is the one thing about these poses that no
# geometry check can catch.
_GAZE = (
    "The chibi character looks toward {where} OF THE PICTURE — {where} "
    "as the viewer sees it — WITHOUT MOVING ITS HEAD. The dark pupils and "
    "irises {press} the part of the eye openings nearest {edge} of the image, "
    "with a clear area of eye-white showing on the opposite side of each eye. "
    "Both eyeballs move together toward {edge}. It is obvious at a glance "
    "which way the character is looking. {both}"
    # The one clause that matters most, and the reason it is stated in terms
    # of SIZE rather than of mood: pushed to look down, the model shrank the
    # irises to tiny black dots adrift in huge white eyes and added shadows
    # underneath. It is a genuinely unsettling face, and this app is for
    # autistic children — a mascot that reads as creepy or vacant is worse
    # than no gaze sheet at all.
    "CRITICAL — THE EYES MUST STAY CUTE. The irises stay EXACTLY THE SAME "
    "LARGE SIZE as in the reference image, big and round and filling most of "
    "the eye opening, keeping their colour and their little white catchlight "
    "highlights. They are NEVER shrunk into small dots, pinpricks or tiny "
    "black circles, and the eye is never mostly empty white. Keep the warm, "
    "soft, friendly, curious expression of the reference image. NO dark "
    "shadows, NO bags, NO shading and NO lines under the eyes. The character "
    "is NOT scared, NOT creepy, NOT vacant, NOT staring blankly, NOT "
    "bug-eyed, NOT sad, NOT tired and NOT unwell. It stays an adorable, "
    "gentle, appealing children's cartoon character throughout. "
    # Rolling the eyes up or down drags the lids with them unless this is
    # spelled out, and a downward glance in particular comes back looking like
    # a blink — which the app would then show whenever a child drags something
    # to the bottom of the screen.
    "Both eyes stay open with the eyelids shaped as in the reference image. "
    "The character is NOT blinking, NOT squinting, NOT half-closing its eyes "
    "and NOT sleepy — the eye openings keep their shape, and only the "
    "eyeballs inside them move. "
    "ONLY THE EYEBALLS move: the head does not turn, tilt, nod or lift, the "
    "eyebrows do not move, the face stays squarely facing the viewer, and the "
    "body, shoulders, arms, hands and feet stay exactly in the starting pose. "
    # Same guard as `present`: a one-sided cue is enough to make the model
    # mirror the whole character, which silently swaps the book to the other
    # hand and cannot be cut together with the other sheets.
    "The character is NOT mirrored, NOT flipped and does NOT turn around. "
    "Whichever hand holds an object in the reference image keeps holding that "
    "object, in that same hand, on that same side of the frame. "
    "It reaches this pose within the first second and then holds it completely "
    "still and unchanged for the rest of the video."
)


# Diagonals need BOTH components spelled out. Asked only for "the top-left
# corner" the model reliably delivers one axis and forgets the other — BPS's
# top corners came back separated by 1% horizontally, Reiz's bottom corners by
# less than nothing. Naming the two movements as a pair, with equal weight, is
# what makes a corner a corner.
_BOTH = (
    "This is a DIAGONAL look: the eyeballs move {first} AND {second} AT THE "
    "SAME TIME, by equally large amounts, ending hard against the {corner} "
    "corner of each eye opening, without shrinking. Both movements are equally "
    "strong — it is not mostly {first} with a little {second}, nor mostly "
    "{second} with a little {first}. "
)


# How hard the eyeballs are pushed. Straight down is deliberately the gentle
# one: it is the only direction where the lower lid crops the iris, so "jammed
# hard against the rim" leaves a sliver of pupil and a face full of white.
PRESS_HARD = "are moved firmly over toward"
PRESS_SOFT = "rest gently toward"


def _gaze(where: str, edge: str, both: str = "",
          press: str = PRESS_HARD) -> tuple:
    return (1, 1, 1, "still",
            _GAZE.format(where=where, edge=edge, both=both, press=press))


def _corner(vertical: str, horizontal: str) -> tuple:
    name = f"{vertical}-{horizontal}"
    return _gaze(
        f"THE {name.upper()} CORNER", f"that {name} corner",
        _BOTH.format(first=vertical, second=horizontal, corner=name),
        press=PRESS_SOFT if vertical == "down" else PRESS_HARD)

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
    # The raised open palm, for Kumusta!'s greeting row. `present` was standing
    # in for it: an open palm, but held low at chest height and angled UP like a
    # waiter's tray, which reads as "here, take this" rather than "hit my hand".
    #
    # The discriminator this sheet has to win is against `wave`, not against
    # `present` — both are an open hand up near the head, and on the card row
    # they are separated ONLY by the motion arcs (see paintGreetingGlyph). So
    # the palm is prompted to face the VIEWER and to hold dead still: a raised
    # open hand that moves side to side is a wave, whichever card it belongs to.
    #
    # Deliberately exaggerated. Every other one-armed action here reaches to the
    # side at shoulder height and the model is comfortable there; a high five
    # that only reaches shoulder height is indistinguishable from `present` at
    # mascot size, so the arm is pushed clearly ABOVE the head where the pose
    # has room to read.
    "high_five": (3, 2, 6, "gesture",
                  "The chibi character raises one arm HIGH for a big "
                  "enthusiastic high five: it lifts its FREE arm — the arm "
                  "that is not holding anything — straight up above its head, "
                  "the arm fully extended upward and reaching, and holds it "
                  "there steadily waiting for someone to slap it. The other "
                  "arm stays down at that side. Big happy open smile, looking "
                  "up toward its own raised hand with bright excited eyes. "
                  "HAND SHAPE, the most important part of the image: the hand "
                  "is WIDE OPEN and completely FLAT, all five fingers "
                  "straight, extended and held together pointing upward, with "
                  "the flat front of the palm turned to face the viewer "
                  "directly, like a hand pressed against glass. "
                  "The hand is clearly ABOVE the top of the head. "
                  # The two hands it must not become. `wave` is the dangerous
                  # one: same open hand, same height, separated on the card row
                  # only by motion arcs.
                  "The hand does NOT wave, does NOT swing or rock from side to "
                  "side, and does NOT move back and forth — it goes up once "
                  "and STOPS, completely still. The fingers are NOT curled, "
                  "NOT spread apart into a star, NOT a fist, and the thumb is "
                  "NOT raised on its own. It is NOT a wave, NOT a fist bump "
                  "and NOT a thumbs-up. "
                  "The character does NOT raise both arms, does NOT jump and "
                  "keeps both feet flat on the ground. "
                  "CRITICAL: the character is NOT mirrored, NOT flipped and "
                  "does NOT turn around. Whichever hand holds an object in "
                  "the reference image keeps holding that object, in that "
                  "same hand, on that same side of the frame, in every single "
                  "frame. The raised arm is the other arm."),
    # A single fist offered forward and HELD, for Kumusta!'s greeting row.
    # `celebrate` was standing in for it and is the wrong shape entirely: it
    # raises BOTH closed hands overhead in a cheer, which reads as "I won"
    # rather than "meet me" — and a greeting the child must answer in kind has
    # to be legible as the thing they are being asked to do.
    #
    # Offered to its own left (frame RIGHT), the same side as `point` and
    # `present`. Not a stylistic choice: that is the direction proven to
    # generate cleanly on this model, and it keeps the three one-armed sheets
    # cuttable against each other. A fist punched straight AT the camera is
    # deliberately not asked for — this model will not foreshorten a flat
    # front-facing 2D chibi (see the gaze table in SPRITES.md), so a forward
    # bump would come back either flat or as a full-body turn.
    #
    # Carries `present`'s handedness anchor for `present`'s reason: a closed
    # fist is symmetric enough that naming a side does not pin it, and the
    # model can satisfy "its own left" by flipping the whole character. Tying
    # the constraint to the OBJECT in the other hand is what stops that.
    "fist_bump": (3, 2, 6, "gesture",
                  "The chibi character offers a friendly fist bump: it lifts "
                  "its FREE arm — the arm that is not holding anything — and "
                  "extends it outward to its own left at chest height, the "
                  "hand held steadily out in the air, waiting for someone to "
                  "meet it. It is ONE hand only. The other arm stays down at "
                  "that side. The character faces the viewer with a warm "
                  "friendly smile and looks toward the offered hand. "
                  # Take 1 asked for a "soft relaxed fist" and got an open
                  # cupped hand with the thumb standing clear of it — which in
                  # half the frames reads as a THUMBS-UP. That is the one
                  # failure this sheet cannot have: thumbs-up and high-five are
                  # two of the other three cards in the same row of choices, so
                  # an ambiguous hand does not merely look wrong, it makes the
                  # question unanswerable. "Relaxed" is what invited the open
                  # hand; the shape is now specified finger by finger.
                  "HAND SHAPE, the most important part of the image: the hand "
                  "is a TIGHTLY CLOSED FIST. All four fingers are fully curled "
                  "down into the palm and the thumb is folded flat ACROSS the "
                  "front of the curled fingers. The rounded knuckles face the "
                  "viewer. It is a compact closed ball of a hand with NO "
                  "fingers extended and NO gaps. "
                  "The hand is NOT open, NOT flat, NOT a palm, NOT cupped, "
                  "NOT waving, and the thumb is NOT raised, NOT pointing up "
                  "and NOT sticking out to the side — this is NOT a "
                  "thumbs-up and NOT a high-five. "
                  # Every failure mode `celebrate` would have supplied, named.
                  "The fist is NOT raised above the shoulder, NOT held over "
                  "the head, NOT punching, NOT swinging, and the character "
                  "does NOT raise both arms, does NOT cheer and does NOT "
                  "clap. The movement is small, slow and inviting, and the "
                  "fist comes to rest and stays still. "
                  "CRITICAL: the character is NOT mirrored, NOT flipped and "
                  "does NOT turn around. Whichever hand holds an object in "
                  "the reference image keeps holding that object, in that "
                  "same hand, on that same side of the frame, in every single "
                  "frame. The offering arm is the other arm."),
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
    # The gaze poses. Two HELD stills, not a sweep, and eyes rather than head —
    # both of which took takes to learn (SPRITES.md has the full table).
    #
    # Head rotation is off the table entirely: prompted as motion the character
    # never turns at all, and prompted with the drawing vocabulary that fixes
    # that ("three-quarter view") it swings the whole body round to profile.
    # Eyes-only does work — it is the same kind of single-feature edit as
    # `idle` (eyelids) and `talk` (mouth), both of which generate first-take.
    #
    # But an eye *sweep* does not. Asked politely the pupils travelled 0.9% of
    # body width, which is one pixel at the size the mascot renders; asked in
    # the strongest terms available the model drew an excellent extreme
    # side-eye and then held it for all 97 frames rather than sweeping across.
    # Holding a pose is exactly what `still` asks for, so the take that refused
    # to sweep was really telling us which strategy this belongs in.
    # The 3x3 grid, with the idle rest frame as its centre.
    "look_left": _gaze("THE LEFT-HAND SIDE", "the left edge"),
    "look_right": _gaze("THE RIGHT-HAND SIDE", "the right edge"),
    "look_up": _gaze("THE TOP", "the top edge"),
    # Firm, not gentle — the CUTE guard above is what keeps the iris big, so
    # the press is free to be legible. Reiz needs it: its irises fill almost
    # the whole eye opening, leaving so little white that a soft downward
    # glance is indistinguishable from resting.
    "look_down": _gaze("THE BOTTOM", "the bottom edge"),
    "look_up_left": _corner("up", "left"),
    "look_up_right": _corner("up", "right"),
    "look_down_left": _corner("down", "left"),
    "look_down_right": _corner("down", "right"),
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
        # Widest cell of the three, and wider than her silhouette needs.
        # 430 was pinned from her artwork's proportions, but the cell has to
        # fit the widest ACTION, not the rest pose: `point` extends an arm
        # fully out at shoulder height and is the extreme. BPS's shipped
        # point sheet reaches the entire 203px half-width of its 406 cell
        # (gap 0 — it is touching the edge), and at the same normalised
        # character height Lexianne's idle silhouette is the same width as
        # his, so 430 would have clipped her pointing hand off.
        # CalmMascot constrains height only, so the extra transparent margin
        # costs nothing on screen.
        "cell_w": 500,
    },
}


# (character, action) pairs whose clip must be flipped before composing.
#
# `point` and `present` both ask the character to gesture to "its own left",
# which lands on frame RIGHT — and `BuddyCharacter.pointAt` depends on it:
# "the sheet points to the viewer's right, so a target on the left mirrors the
# character". A sheet pointing the other way makes the buddy point AWAY from
# every target it is trying to indicate.
#
# For Lexianne the model resolved "its own left" as frame LEFT on two separate
# takes of `point` — systematic for her, not the random flip that a re-roll
# fixes. Her `present` came back correctly on frame right, so the two sheets
# also disagreed with each other, which is the failure SPRITES.md records for
# bps_present (the book teleporting between hands).
#
# Flipping is safe HERE and nowhere else: mirroring is ruled out for BPS
# (it reverses the lettering on his book) and Reiz (it swaps his lapel and
# necklace), but Lexianne holds nothing and her outfit is symmetric — a
# centred pendant, a plain dress, plain sandals. The only thing that changes
# is her hair part and which hand points, and the app already mirrors her
# wholesale at runtime whenever a target sits on the left.
#
# Applied to the FRAMES rather than the finished sheet so that `metrics()`
# measures the flipped image and the footing stays correct.
MIRROR = {("lexianne", "point")}


# ── Costume variants ──────────────────────────────────────────────────
# A costumed character is, to this pipeline, just another character bootstrapped
# from standalone artwork — `from_image` keys out the white background exactly
# as it does for Lexianne. Registered as `{character}_{costume}`, so sheets land
# as e.g. `bps_panda_wave.png` alongside `bps_wave.png`.
#
# The cell width is INHERITED FROM THE BASE CHARACTER rather than widened for
# the bulkier silhouette, and that is deliberate: CalmMascot renders at a fixed
# height with BoxFit.contain, so a costume sheet with a different cell aspect
# would make the mascot visibly change size the instant a child equips it —
# the one thing a costume swap must never do. If a costume's arms or hood ears
# come out clipped, fix that with rest-frame headroom, not by widening the cell.
COSTUME_ART = (PROJECT_ROOT / "packages" / "assets" / "images" / "Character"
               / "Character_Costume")

_COSTUME_FILE = {"bps": "BPs", "lexianne": "Lexianne", "reiz": "Reiz"}

for _base in ("bps", "lexianne", "reiz"):
    for _costume in ("Teddy", "Panda", "Pig"):
        CHARACTERS[f"{_base}_{_costume.lower()}"] = {
            "from_image": (COSTUME_ART / _costume
                           / f"{_COSTUME_FILE[_base]}_chibi_{_costume}.png"),
            # Literally inherited, never copied: Lexianne's base moved
            # 430 -> 500 for her `point` reach, and a duplicated number
            # here would have silently kept her costumes at the old cell.
            #
            # Recorded as a REFERENCE to the base and resolved later, not read
            # here. An established character has no "cell_w" at all — its width
            # comes from the idle sheet it already shipped — so reading the key
            # eagerly raised KeyError on `bps` and took the whole module down
            # at import, before argparse could even print --help.
            "inherit_cell_from": _base,
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
        # The key is (character, action) ONLY — it does not cover the prompt.
        # So editing a prompt and re-running silently recomposes the OLD clip
        # and prints nothing to say so; a rejected take can walk straight back
        # into the shipping directory looking like a fresh generation. That
        # happened to bps_fist_bump. Say which lever to pull.
        print(f"[{tag}] cached (prompt NOT re-read — use --fresh to regenerate)")
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
    if (name, action) in MIRROR:
        cut = [c[:, ::-1] for c in cut]
        print(f"    mirrored (see MIRROR in this file)")
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
    # Costumes defer to their base character, whose own width may itself come
    # from a shipped idle sheet. Resolved here rather than at registration so
    # the two never drift apart.
    if "inherit_cell_from" in cfg:
        return cell_width_for(cfg["inherit_cell_from"])
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
    ap.add_argument("--fresh", action="store_true",
                    help="discard cached frames for the named actions and "
                         "regenerate — required after editing a prompt, since "
                         "the cache key does not cover it. COSTS CREDITS.")
    ap.add_argument("--jobs", type=int, default=4, help="concurrent generations")
    args = ap.parse_args()

    actions = args.only.split(",") if args.only else list(ACTIONS)
    for a in actions:
        if a not in ACTIONS:
            sys.exit(f"unknown action: {a}")
    CACHE.mkdir(parents=True, exist_ok=True)

    if args.fresh:
        if args.compose_only:
            sys.exit("--fresh and --compose-only are contradictory")
        for name in args.characters:
            for a in actions:
                stale = CACHE / f"frames_{name}_{a}"
                if stale.exists():
                    shutil.rmtree(stale)
                    print(f"[{name}_{a}] cache cleared, will regenerate")

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
