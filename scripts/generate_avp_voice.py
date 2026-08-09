#!/usr/bin/env python3
"""Generate the AVP narration track from `docs/AVP_SCRIPT.md`, via kie.ai.

This is a SCRATCH TRACK. The voices are Gemini TTS presets, not the
proponents' — kie.ai does not clone from a reference recording (see
`tools/voice_gen/README.md`). Its job is to lock timing so the video can be
cut now and the real voice-over dropped in over the top later, one block at a
time, without re-editing the picture.

Two speakers, so the split survives into the final recording:
  narrator "a" -> sections 1, 2, 5
  narrator "b" -> sections 3, 4

Engine notes: `google/gemini-3-1-flash-tts` through the existing
`tools/voice_gen/kie_client.py` — same auth, retries and rate limiting as the
in-app voice library. Gemini has no language_code field and infers language
from the text, so `scene` names Philippine English explicitly; that is what
keeps the Taglish lines ("Hi po", "Ang goal namin") from being flattened into
American English or, worse, read as instructions.

Usage:
  pip install requests soundfile numpy soxr librosa imageio-ffmpeg
  set KIE_API_KEY=...
  python scripts/generate_avp_voice.py --list          # free, prints the plan
  python scripts/generate_avp_voice.py --yes

Output: `avp_out/voice/{id}.wav` (24 kHz mono) + `avp_out/voice/blocks.json`
consumed by `scripts/build_avp.py`.
"""

import argparse
import json
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT_ROOT / "tools" / "voice_gen"))

import voice_lib  # noqa: E402
from kie_client import KieClient, KieError, decode_audio  # noqa: E402

OUT = PROJECT_ROOT / "avp_out" / "voice"
MODEL = "google/gemini-3-1-flash-tts"

# Timbre only; the age and manner come from `audio_profile` below.
NARRATORS = {"a": "Charon", "b": "Algieba"}

PROFILE = ("A confident, warm Filipino university student in their early "
           "twenties presenting their capstone project to a client. Sincere "
           "and clear, not salesy, not a hype voice-over.")

# Blocks are (id, section, narrator, text). Split at the points the picture
# cuts, so each block is independently replaceable by a real recording.
BLOCKS = [
    # Scope is deliberately NOT age-gated: what determines which activities
    # suit a child is their assessed skill level per domain, not their age.
    # This is also what the XGBoost skill bands actually measure, so the claim
    # matches the system. Chapter 1's delimitation clause still says "two to
    # six / early-stage" and needs updating to match.
    ("s1_intro", 1, "a",
     "Hi po! We're Ruel Mendio and Benedict Paul Samson from Assumption "
     "College of Davao. This is Aumazing — a gamified learning app for "
     "children with Autism Spectrum Disorder, built around each child's own "
     "skill level rather than their age."),
    ("s1_chars", 1, "a",
     "These are BPS and Reiz. They guide the child through every activity in "
     "the app — and they'll walk you through this presentation too."),

    ("s2_cost", 2, "a",
     "In Davao City, one therapy session costs seven to eight hundred pesos. "
     "A child who needs three hours a day can cost a family over forty "
     "thousand pesos a month."),
    ("s2_capacity", 2, "a",
     "The city's public intervention center offers therapy for free — but it "
     "serves around one thousand one hundred sixty clients, so many families "
     "end up waiting."),
    ("s2_gap", 2, "a",
     "And early intervention only works with daily repetition. Between clinic "
     "visits, that falls on the parents — usually the mother. Without proper "
     "tools, she's guessing which activity to do today."),
    ("s2_solution", 2, "a",
     "Aumazing replaces that guesswork. The child plays a short gamified "
     "pre-assessment, and an AI model turns how they play — accuracy, response "
     "time, retries — into a skill level for communication, social, and play."),
    ("s2_cycle", 2, "a",
     "From that, it recommends which modules to do next. A post-assessment "
     "then shows the parent what actually changed. No worksheets. No "
     "guessing."),

    # Section 3 rides under the screen capture. One block per capture, so the
    # editor can stretch any single one to fit the take without touching the
    # others.
    ("s3_profile", 3, "b",
     "First the parent sets up the child's profile and sensory preferences — "
     "reduced motion, quieter sound. The app adapts to the child."),
    ("s3_game", 3, "b",
     "Every game is one clear instruction, one response, immediate feedback. "
     "That structure comes from Applied Behavior Analysis — and it's also how "
     "the app collects its data."),
    ("s3_mascot", 3, "b",
     "Notice BPS reacting. When the child gets it wrong, he never looks upset "
     "— just gently encouraging, then they try again."),
    ("s3_result", 3, "b",
     "After the cycle, here's the recommendation — explained in plain "
     "language, not scores the parent has to decode."),
    ("s3_dashboard", 3, "b",
     "Parents get a dashboard showing progress per domain, plus screen-time "
     "limits they control."),
    ("s3_locator", 3, "b",
     "And the therapy directory. Free users see the centers; Premium ranks "
     "them by distance and hands off to your maps app."),
    ("s3_offline", 3, "b",
     "And this matters — turn the internet off, and the games keep working. "
     "Everything saves locally and syncs when you're back online."),

    ("s4_stack", 4, "b",
     "We want to be honest about what we used. Aumazing is built with Flutter "
     "and Flame, Supabase for the cloud database, SQLite on the device, "
     "XGBoost for the assessment model, PayMongo for payments, and the Google "
     "Maps SDK for the locator — all under their published licenses."),
    # If the narration is a voice clone, the spoken disclosure has to say so —
    # the whole section is graded on honesty, and an incomplete list is worse
    # than a longer one. Drop the cloning sentence if you record live instead.
    ("s4_ai", 4, "b",
     "We also used AI. BPS and Reiz were drawn as original artwork for this "
     "project, and their animations were generated from that artwork through "
     "the kie dot ai API. The narration you're hearing is our own voices, "
     "cloned from short recordings we made ourselves, using an open-source "
     "model called Chatterbox. "
     "We used AI coding assistants during development, and reviewed everything "
     "before it went in. The research and the manuscript are our own. No real "
     "child's data appears in this video."),

    ("s5_status", 5, "a",
     "Aumazing works today — the games, the assessment, the dashboard, and "
     "offline mode all run on a real device."),
    ("s5_next", 5, "a",
     "Next we're testing with parents and children here in Davao, and "
     "coordinating with therapy centers so the directory reflects what's "
     "really available."),
    ("s5_cta", 5, "a",
     "If you're a parent, a therapist, or a center, we'd like your feedback. "
     "Ang goal namin is simple: that a parent at home knows exactly what to do "
     "next with their child. Thank you po for watching."),
]


def inputs_for(narrator: str, text: str) -> dict:
    return {
        "temperature": 1,
        # Long-form, unlike the in-app library's "one short line" framing.
        # Naming Philippine English is what protects the Taglish, and "speak
        # only the given text" is what stops the framing being read aloud.
        "scene": ("A Filipino university student presents their capstone "
                  "project to a client, speaking in natural Philippine "
                  "English. Some words are Tagalog and should be pronounced "
                  "the Filipino way. Speak only the given text and nothing "
                  "else."),
        "speakers": [{
            "speaker_id": "Speaker 1",
            "voice_name": NARRATORS[narrator],
            "audio_profile": PROFILE,
            # `accent` is an enum, not free text — "Filipino" 422s. The whole
            # language steer therefore lives in `scene` and `audio_profile`.
            "accent": "Neutral",
            "style": "Empathetic",
            "pace": "Natural",
        }],
        "dialogue_turns": [{"speaker_id": "Speaker 1", "text": text}],
    }


def render(client: KieClient, block, force: bool):
    bid, section, narrator, text = block
    dest = OUT / f"{bid}.wav"
    if dest.exists() and not force:
        print(f"[{bid}] cached")
        return bid, True
    try:
        raw, _ = client.synthesize(MODEL, inputs_for(narrator, text))
    except KieError as exc:
        print(f"[{bid}] FAILED: {exc}")
        return bid, False
    x, sr = decode_audio(raw)
    x = voice_lib.resample(x, sr)
    x = voice_lib.normalize(voice_lib.pad_and_fade(x, voice_lib.TARGET_SR))
    voice_lib.save_16bit(dest, x)
    print(f"[{bid}] {len(x) / voice_lib.TARGET_SR:5.1f}s  s{section} {narrator}")
    return bid, True


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--list", action="store_true", help="print the plan, spend nothing")
    ap.add_argument("--only", help="block ids, comma separated")
    ap.add_argument("--force", action="store_true", help="regenerate existing")
    ap.add_argument("--yes", action="store_true", help="confirm the paid run")
    ap.add_argument("--workers", type=int, default=4)
    args = ap.parse_args()

    blocks = BLOCKS
    if args.only:
        want = {b.strip() for b in args.only.split(",")}
        blocks = [b for b in BLOCKS if b[0] in want]
        unknown = want - {b[0] for b in BLOCKS}
        if unknown:
            sys.exit(f"unknown block(s): {', '.join(sorted(unknown))}")

    if args.list:
        words = 0
        for bid, section, narrator, text in blocks:
            words += len(text.split())
            print(f"{bid:16s} s{section} {narrator}  {len(text.split()):3d}w  {text[:64]}...")
        # ~135 wpm is the delivery the script is timed at.
        print(f"\n{len(blocks)} blocks, {words} words, ~{words / 135 * 60:.0f}s spoken")
        return

    if not args.yes:
        sys.exit(f"{len(blocks)} paid TTS calls; re-run with --yes")

    OUT.mkdir(parents=True, exist_ok=True)
    client = KieClient()
    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        results = list(pool.map(lambda b: render(client, b, args.force), blocks))

    failed = [bid for bid, ok in results if not ok]
    # The manifest drives the video build, so it must describe only audio that
    # actually exists — a missing block should shorten the cut, not desync it.
    manifest = [{"id": b[0], "section": b[1], "narrator": b[2], "text": b[3]}
                for b in BLOCKS if (OUT / f"{b[0]}.wav").exists()]
    (OUT / "blocks.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(f"\n{len(manifest)}/{len(BLOCKS)} blocks on disk -> {OUT}")
    if failed:
        print(f"failed: {', '.join(failed)}  (re-run to retry only these)")


if __name__ == "__main__":
    main()
