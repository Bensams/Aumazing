#!/usr/bin/env python3
"""Assemble the AVP animatic: narration + animated BPS/Reiz + title cards.

Produces a complete, watchable 1080p cut with ONE deliberate hole: section 3
is a placeholder slate listing the seven screens to capture. Nothing here can
record your app, and a fake demo would be worse than an obvious gap — the
brief requires real screen recording there.

Everything else is finished picture. Drop your capture over the slate and
replace the scratch narration block by block (`avp_out/voice/*.wav`) without
re-cutting anything: each shot is timed to its own audio file, so a real
recording of the same line slots straight in.

Inputs
  avp_out/voice/*.wav        scripts/generate_avp_voice.py
  avp_out/cutouts/*.mov      scripts/generate_avp.py cutouts

Usage:
  python scripts/generate_avp.py cutouts        # if not already done
  python scripts/generate_avp_voice.py --yes
  python scripts/build_avp.py

Output: avp_out/aumazing_avp.mp4
"""

import json
import re
import subprocess
import sys
import wave
from pathlib import Path

import imageio_ffmpeg
import numpy as np
from PIL import Image, ImageDraw, ImageFont

# Before importing `lipsync`: running this file directly puts scripts/ on the
# path implicitly, but importing it as a module from anywhere else does not.
sys.path.insert(0, str(Path(__file__).resolve().parent))

import lipsync  # noqa: E402

PROJECT_ROOT = Path(__file__).resolve().parent.parent
OUT = PROJECT_ROOT / "avp_out"
VOICE = OUT / "voice"
CUTOUTS = OUT / "cutouts"
WORK = OUT / "build"

W, H, FPS = 1920, 1080, 30

# Picture leads sound. The visual a line refers to has to be on screen and
# readable BEFORE the line starts describing it — at 0.3s the words landed
# while the screen capture was still settling, which reads as the video
# lagging the narration. Nearly a second is the difference between "he is
# describing this" and "he described that a moment ago".
LEAD = 0.95         # silence at the head of a shot, before the line starts
TRAIL = 0.40        # silence after the line, before the cut
TAIL = 2.5          # end card hold after the last word

# Playback rate for the narration. Chatterbox at exaggeration 0.6 delivers
# faster than a pitch wants; <1.0 slows it without changing pitch.
#
# The stretch is applied ONCE, to a copy of the wav, and everything downstream
# — shot duration, lip sync, and the muxed audio — reads that copy. Stretching
# only the audio at mux time would leave the mouths running at the original
# rate and drifting further out of sync with every word.
TEMPO = 0.88

# Calm, low-contrast palette — the app is built for low sensory load and a
# strobing pitch video would undercut that claim on screen.
CREAM = (244, 239, 230)
INK = (32, 43, 48)
TEAL = (18, 59, 71)
ACCENT = (196, 118, 74)
MUTED = (120, 130, 134)
CARD = (255, 252, 247)

F = "C:/Windows/Fonts/segoeui%s.ttf"


def font(size: int, weight: str = "") -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(F % weight, size)


def ffmpeg() -> str:
    return imageio_ffmpeg.get_ffmpeg_exe()


def wrap(draw, text, fnt, max_w):
    lines, cur = [], ""
    for word in text.split():
        trial = f"{cur} {word}".strip()
        if draw.textlength(trial, font=fnt) <= max_w:
            cur = trial
        else:
            if cur:
                lines.append(cur)
            cur = word
    if cur:
        lines.append(cur)
    return lines


def draw_wrapped(d, xy, text, fnt, fill, max_w, leading=1.30):
    x, y = xy
    for line in wrap(d, text, fnt, max_w):
        d.text((x, y), line, font=fnt, fill=fill)
        y += int(fnt.size * leading)
    return y


# ── Backgrounds ───────────────────────────────────────────────────────
# One per shot. Rebuilding the whole frame each time is what gives the
# progressive reveals (cards appearing one at a time) for free.
PROBLEM_CARDS = [
    ("\u20b1700\u2013800", "per therapy session"),
    ("~1,160", "clients, citywide capacity"),
    ("2 hrs/day", "parent prep, replaced"),
]
FLOW = ["Gamified\nPre-Assessment", "AI Recommends\nModules", "Post-Assessment\n& Dashboard"]
DEMO_STEPS = [
    "Child profile + sensory preferences",
    "Mini-game: one instruction, one response",
    "BPS reacting \u2014 gentle, never upset",
    "Result screen + recommended modules",
    "Parent dashboard + screen-time limits",
    "Therapy locator \u2014 free vs Premium",
    "Airplane mode \u2014 games keep working",
]
STACK = ["Flutter + Flame", "Supabase", "SQLite (offline-first)",
         "XGBoost", "PayMongo", "Google Maps SDK + Haversine"]
SPLASH = PROJECT_ROOT / "packages" / "assets" / "videos" / "Aumazing_Splash_Screen_Generation.webm"
SPLASH_IN, SPLASH_LEN = 0.9, 4.6   # logo lands ~1s in and the tail fades to black

# Background bed. Both shipped tracks are Lyria 3 Pro generations, not stock \u2014
# see the licensing note in docs/AVP_SCRIPT.md before publishing.
MUSIC = PROJECT_ROOT / "packages" / "shared_audio" / "assets" / "audio" / "bg_music.ogg"
MUSIC_GAIN = 0.16       # bed level before ducking
DUCK_THRESHOLD = 0.02   # voice level that starts pushing the bed down

# ── Classroom (computer laboratory) set for the demo section ──────────
WALL = (228, 226, 219)
WALL_HI = (238, 236, 230)
FLOOR = (196, 187, 174)
BOARD = (252, 252, 250)
BOARD_TRIM = (166, 160, 151)
TV_BODY = (34, 38, 42)
DESK = (178, 152, 124)
DESK_EDGE = (150, 126, 100)
MONITOR = (58, 64, 70)

HORIZON = 726                       # wall meets floor
BOARD_BOX = [58, 128, 604, 586]     # whiteboard, carries the demo checklist
# Wall-mounted, and kept entirely ABOVE the horizon: a TV whose bottom edge
# crosses the floor line reads as standing in the room, and the workstations
# in front of it then collide with the panel.
TV_FRAME = [640, 56, 1880, 700]
BEZEL = 26
# The capture window IS the TV screen — deliberately the largest element in
# frame, because a client watching on a phone has to read the app UI in it.
SLATE_BOX = [TV_FRAME[0] + BEZEL, TV_FRAME[1] + BEZEL,
             TV_FRAME[2] - BEZEL, TV_FRAME[3] - BEZEL]
CAPTURE_DIR = Path("C:/Users/bened/Videos/Capcut")
CAPTURES = {
    "s3_profile":   "Child profile and sensory preferences1.mp4",
    "s3_game":      "Mini Game.mp4",
    "s3_mascot":    "BPs reacting to a wrong answer.mp4",
    "s3_result":    "ResultScreen.mp4",
    "s3_dashboard": "Parent Dashboard.mp4",
    "s3_locator":   "TherapyLocator.mp4",
    "s3_offline":   "AirplaneMode or Lost Connection.mp4",
}

AI_USE = ["Character animation \u2014 kie.ai (image-to-video)",
          "Narration \u2014 our own voices, cloned with Chatterbox",
          "AI coding assistants during development",
          "All AI output reviewed before use",
          "No real child's data in this video"]


def base():
    img = Image.new("RGB", (W, H), CREAM)
    d = ImageDraw.Draw(img)
    d.rectangle([0, H - 8, W, H], fill=TEAL)
    return img, d


def bg_title(step):
    img, d = base()
    d.text((W // 2, 300), "Aumazing", font=font(140, "b"), fill=TEAL, anchor="mm")
    d.text((W // 2, 410),
           "A Gamified Learning App for Children with Autism Spectrum Disorder",
           font=font(38), fill=INK, anchor="mm")
    # Name plates sit directly above each character's head. The y is derived
    # from the same PLACEMENT the compositor uses, so the label follows the
    # character if its size or position is ever retuned.
    for (cx, frac), name in zip(PLACEMENT["title"], ("BPs", "Reiz")):
        top = int(H * 0.93) - int(H * frac)
        d.text((cx, top - 34), name, font=font(40, "b"), fill=TEAL, anchor="mm")
    d.text((W // 2, H - 150), "Assumption College of Davao  \u00b7  BSIT Capstone",
           font=font(28), fill=MUTED, anchor="mm")
    return img


def bg_problem(step):
    img, d = base()
    d.text((700, 130), "The problem", font=font(76, "b"), fill=TEAL)
    y = 260
    for i, (big, small) in enumerate(PROBLEM_CARDS[:step]):
        d.rounded_rectangle([700, y, 1820, y + 160], 22, fill=CARD)
        d.text((750, y + 42), big, font=font(62, "b"), fill=ACCENT)
        d.text((750, y + 112), small, font=font(30), fill=MUTED)
        y += 190
    return img


def bg_flow(step):
    img, d = base()
    d.text((640, 130), "One cycle, no guesswork", font=font(70, "b"), fill=TEAL)
    y = 300
    for i, label in enumerate(FLOW[:step]):
        d.rounded_rectangle([640, y, 1820, y + 150], 22, fill=CARD)
        d.text((690, y + 40), label.replace("\n", "  "), font=font(40, "b"), fill=INK)
        if i < min(step, len(FLOW)) - 1:
            d.text((1230, y + 165), "\u2193", font=font(40, "b"), fill=ACCENT, anchor="mm")
        y += 215
    return img


def bg_demo(step, placeholder=True):
    """The computer-laboratory set: whiteboard, wall TV, workstations.

    Flat-drawn rather than a photo or a generated image, so it sits in the same
    visual language as the chibi characters and the rest of the deck \u2014 and so
    the TV rectangle is known exactly, which is what the capture is composited
    into.
    """
    img = Image.new("RGB", (W, H), WALL)
    d = ImageDraw.Draw(img)

    # Room: a soft pool of light on the back wall, then the floor.
    d.ellipse([W // 2 - 900, -420, W // 2 + 900, 620], fill=WALL_HI)
    d.rectangle([0, HORIZON, W, H], fill=FLOOR)
    d.rectangle([0, HORIZON - 12, W, HORIZON], fill=BOARD_TRIM)
    # Floor recedes to a vanishing point roughly behind the TV.
    for x in range(-600, W + 900, 300):
        d.line([(x, H), (W // 2 + 380, HORIZON)], fill=(186, 177, 164), width=2)

    # \u2500\u2500 Whiteboard: the agenda for the demo \u2500\u2500
    x0, y0, x1, y1 = BOARD_BOX
    d.rounded_rectangle([x0 - 10, y0 - 10, x1 + 10, y1 + 10], 8, fill=BOARD_TRIM)
    d.rounded_rectangle(BOARD_BOX, 4, fill=BOARD)
    d.rounded_rectangle([x0 + 60, y1 + 10, x0 + 240, y1 + 26], 6, fill=(206, 200, 191))
    d.text((x0 + 28, y0 + 24), "Live demo", font=font(40, "b"), fill=TEAL)
    d.line([(x0 + 28, y0 + 80), (x1 - 28, y0 + 80)], fill=(214, 210, 203), width=3)

    y = y0 + 104
    for i, item in enumerate(DEMO_STEPS):
        on = i < step
        d.text((x0 + 30, y + 2), "\u25cf" if on else "\u25cb", font=font(19),
               fill=ACCENT if on else MUTED)
        y = draw_wrapped(d, (x0 + 60, y - 4), item, font(22, "b" if on else ""),
                         INK if on else MUTED, 470, leading=1.22) + 22

    # \u2500\u2500 Wall TV: the biggest thing in frame, on purpose \u2500\u2500
    d.rounded_rectangle([TV_FRAME[0] + 14, TV_FRAME[1] + 18,
                         TV_FRAME[2] + 14, TV_FRAME[3] + 18], 20,
                        fill=(206, 200, 191))          # cast shadow
    d.rounded_rectangle(TV_FRAME, 20, fill=TV_BODY)
    d.rectangle(SLATE_BOX, fill=(16, 18, 20))
    mid = (TV_FRAME[0] + TV_FRAME[2]) // 2
    d.rectangle([mid - 46, TV_FRAME[3], mid + 46, TV_FRAME[3] + 46], fill=(46, 50, 54))
    d.rounded_rectangle([mid - 190, TV_FRAME[3] + 46, mid + 190, TV_FRAME[3] + 64],
                        8, fill=(46, 50, 54))
    if placeholder:
        cx, cy = mid, (SLATE_BOX[1] + SLATE_BOX[3]) // 2
        d.text((cx, cy - 22), "SCREEN RECORDING", font=font(48, "b"),
               fill=(120, 126, 132), anchor="mm")
        d.text((cx, cy + 34), "drop your device capture here",
               font=font(30), fill=(86, 92, 98), anchor="mm")

    # \u2500\u2500 Workstation bench along the back, under the TV \u2500\u2500
    bx0, bx1, by = 620, 1900, 836
    d.rectangle([bx0, by, bx1, by + 20], fill=DESK)
    d.rectangle([bx0, by + 20, bx1, by + 30], fill=DESK_EDGE)
    for mx in range(bx0 + 120, bx1 - 60, 330):
        d.rectangle([mx - 7, by - 14, mx + 7, by], fill=(96, 100, 106))
        d.rounded_rectangle([mx - 64, by - 96, mx + 64, by - 14], 6, fill=MONITOR)
        d.rounded_rectangle([mx - 57, by - 89, mx + 57, by - 23], 4, fill=(120, 150, 168))
    return img


def bg_credits(step):
    img, d = base()
    d.text((640, 110), "What we used", font=font(70, "b"), fill=TEAL)
    y = 240
    for item in STACK:
        d.text((660, y), "\u2022  " + item, font=font(36), fill=INK)
        y += 58
    if step >= 2:
        d.text((640, y + 40), "AI assistance, disclosed", font=font(40, "b"), fill=ACCENT)
        y += 110
        for item in AI_USE:
            y = draw_wrapped(d, (660, y), "\u2022  " + item, font(30), INK, 1160) + 10
    return img


def bg_end(step):
    img, d = base()
    d.text((W // 2, 190), "Aumazing", font=font(110, "b"), fill=TEAL, anchor="mm")
    if step >= 2:
        d.text((W // 2, 300), "Next: parent & child testing in Davao",
               font=font(38), fill=INK, anchor="mm")
    if step >= 3:
        d.text((W // 2, 370), "We'd like your feedback",
               font=font(38, "b"), fill=ACCENT, anchor="mm")
    d.text((W // 2, H - 230), "Ruel Mendio  \u00b7  Benedict Paul Samson",
           font=font(34, "b"), fill=INK, anchor="mm")
    d.text((W // 2, H - 175), "BSIT Capstone \u00b7 Assumption College of Davao",
           font=font(28), fill=MUTED, anchor="mm")
    return img


BUILDERS = {"title": bg_title, "problem": bg_problem, "flow": bg_flow,
            "demo": bg_demo, "credits": bg_credits, "end": bg_end}

# (block id, character clips, background, reveal step)
#
# "lip:<name>" builds a mouth track synced to THAT shot's narration instead of
# using a fixed clip. Everything else is a cutout played as-is.
#
# One narrator, one character: narrator "a" is BPS and narrator "b" is Reiz,
# each cloned from their own reference recording, so the character whose
# mouth moves is the one being heard. Mixing them reads as the wrong
# character speaking, which is worse than no lip sync at all. Give Reiz the "b" shots back (s3_*, s4_*) as
# soon as his reference lands. Gesture
# shots (wave, oops, point, celebrate) keep their clip — the gesture is the
# point of those, and their heads move, so a pasted mouth would not track.
SHOTS = [
    ("s1_intro",     ["bps_wave", "reiz_wave"],         "title", 0),
    ("s1_chars",     ["bps_wave", "reiz_wave"],         "title", 1),
    ("s2_cost",      ["lip:bps"],                       "problem", 1),
    ("s2_capacity",  ["lip:bps"],                       "problem", 2),
    ("s2_gap",       ["bps_oops"],                      "problem", 3),
    ("s2_solution",  ["lip:bps"],                       "flow", 1),
    ("s2_cycle",     ["bps_present"],                   "flow", 3),
    ("s3_profile",   ["lip:reiz", "bps_listen"],        "demo", 1),
    ("s3_game",      ["lip:reiz", "bps_nod"],           "demo", 2),
    # The line is "notice BPS reacting", so BPS performs it: his `oops` loops
    # for the first half of the shot, then he leaves frame and Reiz — who is
    # the one actually speaking here — takes over to finish the line.
    ("s3_mascot",    ["bps_oops@0:4.4", "lip:reiz@4.4:99"], "demo", 3),
    ("s3_result",    ["lip:reiz", "bps_listen"],        "demo", 4),
    ("s3_dashboard", ["lip:reiz", "bps_nod"],           "demo", 5),
    ("s3_locator",   ["reiz_present", "bps_listen"],    "demo", 6),
    ("s3_offline",   ["reiz_point", "bps_nod"],         "demo", 7),
    ("s4_stack",     ["lip:reiz"],                      "credits", 1),
    ("s4_ai",        ["lip:reiz"],                      "credits", 2),
    ("s5_status",    ["bps_celebrate", "reiz_celebrate"], "end", 1),
    # Narrator "a" speaks, so only BPS's mouth moves; Reiz stands and listens.
    ("s5_next",      ["lip:bps", "reiz_idle"],          "end", 2),
    ("s5_cta",       ["bps_wave", "reiz_wave"],         "end", 3),
]

# Where characters sit, by background. Height is a fraction of frame height.
PLACEMENT = {
    "title":   [(430, 0.42), (1490, 0.42)],
    "problem": [(330, 0.52)],
    "flow":    [(320, 0.52)],
    # Both on the classroom floor, left of the TV: the speaker forward, the
    # other a step back and smaller, so the pair reads as two people
    # discussing what is on screen rather than two labels.
    "demo":    [(232, 0.34), (452, 0.29)],
    "credits": [(300, 0.52)],
    "end":     [(560, 0.34), (1360, 0.34)],
}


def duration(path: Path) -> float:
    """Seconds of a narration block.

    stdlib `wave`, not soundfile: the voice-over is written as 16-bit PCM by
    `voice_lib.save_16bit`, so this needs no dependency and lets the build run
    on whichever interpreter has Pillow and imageio-ffmpeg.
    """
    with wave.open(str(path), "rb") as w:
        return w.getnframes() / w.getframerate()


def paced(bid: str) -> Path:
    """The narration block at playback speed, TEMPO applied.

    Returns the source untouched at TEMPO == 1.0 so the no-stretch path stays
    bit-identical. `atempo` preserves pitch and takes 0.5–100 in one pass, so
    any sane TEMPO needs no filter chaining.
    """
    src = VOICE / f"{bid}.wav"
    if abs(TEMPO - 1.0) < 1e-6:
        return src
    # Tempo is in the filename: without it, changing TEMPO would silently reuse
    # the previous run's stretch and the change would appear to do nothing.
    dest = WORK / "audio" / f"{bid}_t{TEMPO:.3f}.wav"
    if dest.exists():
        return dest
    dest.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run([ffmpeg(), "-v", "error", "-y", "-i", str(src),
                    "-filter:a", f"atempo={TEMPO}", str(dest)], check=True)
    return dest


def build_shot(i, shot) -> Path:
    bid, spec_clips, bg_name, step = shot
    # "name@start:end" limits a clip to part of the shot, so one character can
    # hand the frame to another mid-shot. Split before anything else reads the
    # names — the range is not part of the filename. Rebuilt into a new list
    # rather than mutated in place, so SHOTS stays the declaration it looks like.
    clips, ranges = [], []
    for c in spec_clips:
        name, _, rng = c.partition("@")
        clips.append(name)
        ranges.append(tuple(float(v) for v in rng.split(":")) if rng else None)

    wav = paced(bid)
    dest = WORK / f"{i:02d}_{bid}.mp4"
    dur = LEAD + duration(wav) + TRAIL + (TAIL if i == len(SHOTS) - 1 else 0)

    capture = CAPTURE_DIR / CAPTURES[bid] if bid in CAPTURES else None
    if capture and not capture.exists():
        capture = None

    bg = WORK / f"{i:02d}_{bid}.png"
    if bg_name == "demo":
        BUILDERS[bg_name](step, placeholder=capture is None).save(bg)
    else:
        BUILDERS[bg_name](step).save(bg)

    args = [ffmpeg(), "-v", "error", "-y", "-loop", "1", "-i", str(bg)]
    for c in clips:
        if c.startswith("lip:"):
            # Built to this shot's exact length, with the same lead-in the
            # audio gets, so the mouth cannot drift against the line.
            src = lipsync.track(c[4:], wav, dur, LEAD,
                                WORK / f"{i:02d}_{bid}_{c[4:]}_lip.mov", FPS)
        else:
            src = CUTOUTS / f"{c}.mov"
        args += ["-stream_loop", "-1", "-i", str(src)]
    args += ["-i", str(wav)]
    if capture:
        args += ["-i", str(capture)]

    spots = PLACEMENT[bg_name]
    # Every stage gets an explicit label and the final one is what gets mapped.
    # Leaving the last overlay unlabelled (ffmpeg's usual shorthand) breaks the
    # moment a shot has two characters, because then the label being mapped is
    # the one that was never emitted.
    parts, prev = [], "0:v"
    if capture:
        x0, y0, x1, y1 = SLATE_BOX
        bw, bh = x1 - x0, y1 - y0
        # Fit inside the slate without distorting: the phone captures are
        # portrait and the emulator ones landscape, and non-uniform scaling to
        # fill would make either look broken. `tpad` holds the final frame if
        # the capture runs out before the line does, rather than dropping to an
        # empty slate. Capture audio is discarded — the narration is the bed.
        parts.append(
            f"[{len(clips) + 2}:v]setpts=PTS-STARTPTS,"
            f"scale=w={bw}:h={bh}:force_original_aspect_ratio=decrease,"
            f"tpad=stop_mode=clone:stop_duration=30[cap]")
        parts.append(f"[0:v][cap]overlay=x={x0}+({bw}-w)/2:y={y0}+({bh}-h)/2[bgc]")
        prev = "bgc"
    for n, _ in enumerate(clips):
        cx, frac = spots[n % len(spots)]
        parts.append(f"[{n + 1}:v]setpts=PTS-STARTPTS,"
                     f"scale=-1:{int(H * frac)}[c{n}]")
        # Feet on a shared baseline; x is the character's centre.
        window = (f":enable='between(t,{ranges[n][0]},{ranges[n][1]})'"
                  if ranges[n] else "")
        parts.append(f"[{prev}][c{n}]overlay=x={cx}-w/2:"
                     f"y={int(H * 0.93)}-h{window}[v{n}]")
        prev = f"v{n}"
    # Audio starts after a beat of silence so the picture is up before the line.
    pad = int(LEAD * 1000)
    parts.append(f"[{len(clips) + 1}:a]adelay={pad}|{pad}[a]")

    args += ["-filter_complex", ";".join(parts), "-map", f"[{prev}]",
             "-map", "[a]", "-t", f"{dur:.3f}",
             "-r", str(FPS), "-c:v", "libx264", "-preset", "medium", "-crf", "18",
             "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k", "-ar", "48000",
             "-ac", "2", str(dest)]
    subprocess.run(args, check=True)
    print(f"[{i:02d}] {bid:14s} {dur:5.2f}s  {bg_name}/{step}  {'+'.join(clips)}")
    return dest


SUB_LINE = 34        # max chars per subtitle line
SUB_LINES = 2        # max lines per caption
# Captions read as out of sync long before they are numerically wrong: a long
# caption puts words on screen seconds before they are spoken and leaves them
# there after. Shorter captions cover less speech each, which is what makes
# them feel locked to the voice. The small lead is standard subtitling practice
# — landing marginally early reads as synced, landing late reads as broken.
SUB_LEAD = 0.12      # seconds a caption appears before its first word


def block_text(bid: str) -> str:
    """The spoken text for a block, read from generate_avp_voice.py.

    Parsed rather than imported: that module pulls in soundfile via voice_lib,
    which is only installed in the voice venv, and the build must run on the
    interpreter that has Pillow and imageio-ffmpeg.
    """
    src = (PROJECT_ROOT / "scripts" / "generate_avp_voice.py").read_text(encoding="utf-8")
    m = re.search(r'\("' + re.escape(bid) + r'",\s*\d+,\s*"[ab]",\s*((?:\s*"[^"]*")+)\)', src)
    if not m:
        return ""
    return re.sub(r"\s+", " ", "".join(re.findall(r'"([^"]*)"', m.group(1)))).strip()


def _lines(text: str) -> list[str]:
    """Greedy word wrap at SUB_LINE characters."""
    out, line = [], ""
    for word in text.split():
        t = f"{line} {word}".strip()
        if len(t) <= SUB_LINE or not line:
            line = t
        else:
            out.append(line)
            line = word
    if line:
        out.append(line)
    return out


def _fits(text: str) -> bool:
    """Whether `text` wraps into at most SUB_LINES lines.

    Tested by wrapping, not by character count: a 65-character string can still
    need three lines once word boundaries are respected, and a three-line block
    is exactly the caption that sits on screen too long and reads as delayed.
    """
    return len(_lines(text)) <= SUB_LINES


def captions(text: str) -> list[str]:
    """Break a narration block into captions that each fit on two lines.

    Clause boundaries first, so a caption never breaks mid-phrase; any clause
    still too long to fit is broken on word boundaries as a fallback.
    """
    pieces = re.split(r"(?<=[.!?])\s+|(?<=—)\s+|(?<=,)\s+|(?<=;)\s+|(?<=:)\s+", text)

    out, cur = [], ""
    for piece in pieces:
        if _fits(f"{cur} {piece}".strip()):
            cur = f"{cur} {piece}".strip()
            continue
        if cur:
            out.append(cur)
            cur = ""
        # The clause alone may still overflow — fill word by word.
        for word in piece.split():
            if _fits(f"{cur} {word}".strip()) or not cur:
                cur = f"{cur} {word}".strip()
            else:
                out.append(cur)
                cur = word
    if cur:
        out.append(cur)
    return ["\n".join(_lines(c)) for c in out]


def stamp(t: float) -> str:
    h, rem = divmod(max(0.0, t), 3600)
    m, s = divmod(rem, 60)
    return f"{int(h):02d}:{int(m):02d}:{s:06.3f}".replace(".", ",")


def speech_clock(wav: Path, hop: float = 0.02):
    """Map a fraction of the spoken text to the time it is actually spoken.

    Allocating caption time by character count alone assumes the voice never
    pauses. It does — between sentences and at commas — so captions drift late
    across a long block and the last one lands after the audio has stopped.

    This builds the cumulative *voiced* time through the block, so a caption is
    placed by how much speech has happened rather than how much wall clock. A
    pause is absorbed into whichever caption spans it, and every boundary lands
    on a real word.
    """
    with wave.open(str(wav), "rb") as w:
        sr, n = w.getframerate(), w.getnframes()
        x = np.frombuffer(w.readframes(n), dtype="<i2").astype(np.float32) / 32768.0
        if w.getnchannels() == 2:
            x = x.reshape(-1, 2).mean(1)

    step = max(1, int(sr * hop))
    frames = [x[i:i + step] for i in range(0, len(x), step)]
    rms = np.array([float(np.sqrt(np.mean(f * f))) if len(f) else 0.0 for f in frames])
    voiced = rms > (rms.max() * 0.06 if rms.size and rms.max() > 0 else 1.0)
    cum = np.concatenate([[0.0], np.cumsum(voiced) * hop])
    total = cum[-1]

    def at(fraction: float) -> float:
        if total <= 0:
            return fraction * len(x) / sr
        return float(np.searchsorted(cum, fraction * total) * hop)

    return at


def pauses(wav: Path, hop: float = 0.01, min_gap: float = 0.14) -> list[float]:
    """Midpoints of the silences inside a block.

    Captions are split at clause boundaries — sentence ends, em-dashes, commas
    — which is exactly where a speaker pauses. So the honest place to change a
    caption is a real pause, not a computed fraction. Proportional timing gets
    the boundary roughly right; snapping to these puts it on the beat.
    """
    with wave.open(str(wav), "rb") as w:
        sr, n = w.getframerate(), w.getnframes()
        x = np.frombuffer(w.readframes(n), dtype="<i2").astype(np.float32) / 32768.0
        if w.getnchannels() == 2:
            x = x.reshape(-1, 2).mean(1)

    step = max(1, int(sr * hop))
    rms = np.array([float(np.sqrt(np.mean(f * f))) if len(f) else 0.0
                    for f in (x[i:i + step] for i in range(0, len(x), step))])
    if not rms.size or rms.max() <= 0:
        return []
    quiet = rms < rms.max() * 0.06

    out, run = [], 0
    for i, q in enumerate(quiet):
        if q:
            run += 1
            continue
        if run * hop >= min_gap:
            out.append((i - run / 2) * hop)
        run = 0
    return out


def write_srt(dest: Path) -> Path:
    """Subtitles for the whole timeline, timed off the same shot durations.

    Within a block, captions are allotted time in proportion to their length —
    a rough but reliable stand-in for real word timings, and accurate enough
    that the caption on screen is always the sentence being spoken.
    """
    entries, t = [], SPLASH_LEN          # the splash carries no narration
    for i, (bid, _, _, _) in enumerate(SHOTS):
        speech = duration(paced(bid))
        start = t + LEAD                 # matches the `adelay` applied to the audio
        caps = captions(block_text(bid))
        total_chars = sum(len(c) for c in caps) or 1
        clock = speech_clock(paced(bid))
        gaps = pauses(paced(bid))

        # Proportional estimate first, then snap each internal boundary to the
        # nearest real pause. Snapping is monotonic — a gap already claimed by
        # an earlier boundary cannot be reused, so captions can never overlap
        # or run backwards even if the estimate is well off.
        bounds, done = [], 0
        for cap in caps[:-1]:
            done += len(cap)
            bounds.append(clock(done / total_chars))
        snapped, floor = [], 0.0
        for est in bounds:
            near = [g for g in gaps if g > floor]
            pick = min(near, key=lambda g: abs(g - est)) if near else est
            # A pause more than a second from the estimate is a hesitation
            # mid-clause, not the clause break — trust the estimate instead.
            pick = pick if abs(pick - est) <= 1.0 else max(est, floor)
            snapped.append(pick)
            floor = pick
        edges = [0.0] + snapped + [speech]
        for k, cap in enumerate(caps):
            a = start + edges[k] - (SUB_LEAD if k else 0)
            entries.append((max(start, a), start + min(edges[k + 1], speech), cap))
        t += LEAD + speech + TRAIL + (TAIL if i == len(SHOTS) - 1 else 0)

    dest.write_text("".join(
        f"{n}\n{stamp(a)} --> {stamp(b)}\n{txt}\n\n"
        for n, (a, b, txt) in enumerate(entries, 1)), encoding="utf-8")
    print(f"[--] {'subtitles':14s} {len(entries)} captions -> {dest.name}")
    return dest


def build_splash() -> Path:
    """The app's own splash animation as the opening shot, with its own sound.

    The splash carries its own audio sting, which is the app's identity — the
    music bed is held back until this has played (see `add_music`) rather than
    laid over the top of it.

    Encoded to exactly the same codec/rate/layout as every narrated shot: the
    concat demuxer joins streams without re-encoding, so a shot that differs in
    sample rate or channel count silently desyncs everything after it.
    """
    dest = WORK / "00_splash.mp4"
    subprocess.run([
        ffmpeg(), "-v", "error", "-y",
        "-ss", str(SPLASH_IN), "-i", str(SPLASH),
        "-filter_complex",
        f"[0:v]setpts=PTS-STARTPTS,scale=w={W}:h={H}:force_original_aspect_ratio=decrease,"
        f"pad={W}:{H}:(ow-iw)/2:(oh-ih)/2:color=0x{CREAM[0]:02x}{CREAM[1]:02x}{CREAM[2]:02x}[v];"
        f"[0:a]aresample=48000,asetpts=PTS-STARTPTS,"
        f"afade=t=out:st={max(0.1, SPLASH_LEN - 0.6):.2f}:d=0.6[a]",
        "-map", "[v]", "-map", "[a]", "-t", f"{SPLASH_LEN:.3f}",
        "-r", str(FPS), "-c:v", "libx264", "-preset", "medium", "-crf", "18",
        "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k", "-ar", "48000",
        "-ac", "2", str(dest)], check=True)
    print(f"[--] {'splash':14s} {SPLASH_LEN:5.2f}s  app splash screen")
    return dest


def add_music(video: Path, dest: Path, total: float, srt: Path | None) -> None:
    """Lay the music bed under the finished cut, ducked by the narration.

    `sidechaincompress` keyed on the voice track, not a fixed low volume: a bed
    quiet enough to never fight the narration is also too quiet to hear in the
    gaps. Ducking lets it breathe between lines and get out of the way under
    them. The voice is never touched — only the bed moves.
    """
    if not MUSIC.exists():
        print(f"no music at {MUSIC}; leaving audio as-is")
        video.replace(dest)
        return
    subprocess.run([
        ffmpeg(), "-v", "error", "-y", "-i", str(video),
        "-stream_loop", "-1", "-i", str(MUSIC),
        "-filter_complex",
        # Both legs are resampled to 48k FIRST. The bed is 44.1k and the shots
        # are 48k; letting sidechaincompress resolve that itself pulled the
        # whole mix off-rate and `-shortest` then trimmed 7.6s off the end —
        # silently eating the closing shot.
        # The bed is held off until the splash sting has finished, so the app's
        # own audio identity opens the video rather than competing with music.
        f"[1:a]aresample=48000,volume={MUSIC_GAIN},"
        f"adelay={int(SPLASH_LEN * 1000)}|{int(SPLASH_LEN * 1000)},"
        f"afade=t=in:st={SPLASH_LEN:.2f}:d=1.5[bed];"
        f"[0:a]aresample=48000,asplit=2[v1][v2];"
        f"[bed][v1]sidechaincompress=threshold={DUCK_THRESHOLD}:ratio=12:"
        f"attack=15:release=350:makeup=1[duck];"
        f"[duck][v2]amix=inputs=2:normalize=0:dropout_transition=0[mix];"
        f"[mix]afade=t=out:st={max(0.1, total - 2.0):.2f}:d=2,"
        f"alimiter=limit=0.95[a]",
        # `-t` rather than `-shortest`: the looped bed is infinite, so the cut
        # length must be stated rather than inferred from the graph.
        # Captions are burned in the same pass, so the video is re-encoded once
        # rather than twice. libass wants a posix-ish path with the drive colon
        # escaped, even on Windows.
        *(["-vf", f"subtitles='{srt.as_posix().replace(':', chr(92) + ':')}'"
               # FontSize is in libass units against a 288px canvas, NOT pixels
               # — it is scaled up ~3.75x at 1080p, so 12 here renders ~45px.
               # MarginV keeps captions inside the band reserved at the bottom,
               # below the slate and clear of the footer lines.
               # BorderStyle=1 is outline-only (no box). White fill with a heavy
               # black outline rather than dark-on-light: captions pass over the
               # cream background AND over the screen captures, which can be any
               # colour, and this pairing is the one that reads on both.
               f":force_style='FontName=Segoe UI,FontSize=12,Bold=1,"
               f"BorderStyle=1,PrimaryColour=&H00FFFFFF,OutlineColour=&H00000000,"
               f"Outline=2.6,Shadow=0.8,MarginV=10,Alignment=2'"] if srt else []),
        "-map", "0:v", "-map", "[a]", "-t", f"{total:.3f}",
        *(["-c:v", "libx264", "-preset", "medium", "-crf", "19",
           "-pix_fmt", "yuv420p", "-r", str(FPS)] if srt else ["-c:v", "copy"]),
        "-c:a", "aac", "-b:a", "192k", "-ar", "48000",
        str(dest)], check=True)


def main() -> None:
    if not (VOICE / "blocks.json").exists():
        sys.exit("no narration; run scripts/generate_avp_voice.py first")
    have = {b["id"] for b in json.loads((VOICE / "blocks.json").read_text())}
    missing = [s[0] for s in SHOTS if s[0] not in have]
    if missing:
        sys.exit(f"missing narration for: {', '.join(missing)}")
    for _, clips, _, _ in SHOTS:
        for c in clips:
            spec = c.split("@")[0]
            if spec.startswith("lip:"):
                continue
            if not (CUTOUTS / f"{spec}.mov").exists():
                sys.exit(f"missing cutout {spec}.mov; run generate_avp.py cutouts")

    missing_caps = [b for b in CAPTURES if not (CAPTURE_DIR / CAPTURES[b]).exists()]
    if missing_caps:
        print(f"note: no capture for {', '.join(missing_caps)} — placeholder slate\n")

    WORK.mkdir(parents=True, exist_ok=True)
    parts = [build_splash()] + [build_shot(i, s) for i, s in enumerate(SHOTS)]

    listing = WORK / "concat.txt"
    listing.write_text("".join(f"file '{p.name}'\n" for p in parts), encoding="utf-8")
    silent = WORK / "_nomusic.mp4"
    subprocess.run([ffmpeg(), "-v", "error", "-y", "-f", "concat", "-safe", "0",
                    "-i", str(listing), "-c", "copy", str(silent)], check=True)

    total = (SPLASH_LEN + sum(duration(paced(s[0])) for s in SHOTS)
             + (LEAD + TRAIL) * len(SHOTS) + TAIL)
    srt = write_srt(OUT / "aumazing_avp.srt")
    dest = OUT / "aumazing_avp.mp4"
    add_music(silent, dest, total, srt)
    plain = OUT / "aumazing_avp_no_captions.mp4"
    add_music(silent, plain, total, None)
    print(f"{plain.relative_to(PROJECT_ROOT)}  (same cut, no burned-in captions)")
    print(f"\n{dest.relative_to(PROJECT_ROOT)}  {int(total // 60)}:{total % 60:04.1f}")


if __name__ == "__main__":
    main()
