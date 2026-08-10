#!/usr/bin/env python3
"""
Batch-generate EMOTIONAL voice-over WAV files for Aumazing (en/tl/ceb).

Engine: Microsoft Edge neural TTS (edge-tts) with per-category emotion
profiles — praise sounds proud, celebration sounds excited, regulation
sounds calm and slow, instructions sound clear and friendly. Each cue's
category selects a prosody profile (rate/pitch) applied to an already
expressive neural voice.

Voices:
  en  → en-US-AnaNeural       (Microsoft's child voice — warm, kid-friendly)
  tl  → fil-PH-BlessicaNeural (natural Filipino female)
  ceb → fil-PH-BlessicaNeural (no neural TTS supports Cebuano; the
        Filipino voice reads the Cebuano text — phonetics overlap
        closely, so pronunciation stays intelligible. Documented
        limitation for the manuscript.)

Usage:
  pip install edge-tts imageio-ffmpeg
  python scripts/generate_voice_lines.py            # all languages
  python scripts/generate_voice_lines.py tl ceb     # subset

Output:
  packages/shared_audio/assets/audio/voice_over/{lang}/{category}/{CueName}.wav
  (24 kHz mono WAV — the format the app's VoiceOverService expects.)
"""

import asyncio
import subprocess
import sys
import time
from pathlib import Path

# ── Project root (relative to this script) ───────────────────────────
SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parent
OUTPUT_ROOT = PROJECT_ROOT / "packages" / "shared_audio" / "assets" / "audio" / "voice_over"

# ── Language → Edge neural voice mapping ─────────────────────────────
LANGUAGE_MODELS = {
    "en":  "en-US-AnaNeural",
    "tl":  "fil-PH-BlessicaNeural",
    "ceb": "fil-PH-BlessicaNeural",
}

# ── Emotion profiles per cue category ────────────────────────────────
# Emotional register is delivered through prosody (rate/pitch) on top of
# the neural voice's natural expressiveness. Calibrated for ASD listeners:
# celebration is bright but never shrill; regulation is slow and low.
EMOTION_PROFILES = {
    "core_praise":              {"rate": "+8%",  "pitch": "+18Hz"},  # happy, proud
    "reward_and_celebration":   {"rate": "+12%", "pitch": "+25Hz"},  # excited, joyful
    "gently_retry":             {"rate": "-12%", "pitch": "+5Hz"},   # gentle, encouraging
    "attention_and_regulation": {"rate": "-20%", "pitch": "-8Hz"},   # calm, soothing
    "instruction":              {"rate": "-8%",  "pitch": "+8Hz"},   # clear, friendly
    "assessment_style":         {"rate": "-8%",  "pitch": "+10Hz"},  # warm, inviting
    "transition":               {"rate": "+0%",  "pitch": "+12Hz"},  # upbeat
    "turn_taking":              {"rate": "-5%",  "pitch": "+8Hz"},   # warm, social
    "colors":                   {"rate": "-15%", "pitch": "+10Hz"},  # slow word-teaching
    "shapes":                   {"rate": "-15%", "pitch": "+10Hz"},  # slow word-teaching
    "dynamic":                  {"rate": "-12%", "pitch": "+8Hz"},   # clear fragments
}
DEFAULT_PROFILE = {"rate": "-5%", "pitch": "+8Hz"}

# ── Voice line definitions ───────────────────────────────────────────
# Structure: { "CueName": { "category": "...", "en": "...", "tl": "...", "ceb": "..." } }
VOICE_LINES = {
    # ── Assessment Style (10) ────────────────────────────────────────
    "CanYouCopyMe": {
        "category": "assessment_style",
        "en": "Can you copy me?",
        "tl": "Magaya mo ba ako?",
        "ceb": "Ma sundog ko nimo?",
    },
    "CanYouMatchThis": {
        "category": "assessment_style",
        "en": "Can you match this?",
        "tl": "Itugma mo ito.",
        "ceb": "Ma i-match nimo ni?",
    },
    "FindTheRightOne": {
        "category": "assessment_style",
        "en": "Find the right one.",
        "tl": "Hanapin ang tama.",
        "ceb": "Pangitaa ang sakto.",
    },
    "GoodListening": {
        "category": "assessment_style",
        "en": "Good listening!",
        "tl": "Magaling makinig!",
        "ceb": "Maayong pagpaminaw!",
    },
    "GoodLooking": {
        "category": "assessment_style",
        "en": "Good looking!",
        "tl": "Magaling tumingin!",
        "ceb": "Nindot nga pagtan-aw!",
    },
    "LetSeeWhatYouCanDo": {
        "category": "assessment_style",
        "en": "Let's see what you can do.",
        "tl": "Tingnan natin ang kaya mong gawin.",
        "ceb": "Tan-awon nato unsang kaya nimo.",
    },
    "LetsTryTheNextTask": {
        "category": "assessment_style",
        "en": "Let's try the next task.",
        "tl": "Subukan natin ang susunod.",
        "ceb": "Sulayan nato ang sunod.",
    },
    "ShowMe": {
        "category": "assessment_style",
        "en": "Show me.",
        "tl": "Ipakita mo sa akin.",
        "ceb": "Ipakita nako.",
    },
    "WhatComesNext": {
        "category": "assessment_style",
        "en": "What comes next?",
        "tl": "Ano ang susunod?",
        "ceb": "Unsa ang sunod?",
    },
    "WhichOneIsTheSame": {
        "category": "assessment_style",
        "en": "Which one is the same?",
        "tl": "Alin ang pareho?",
        "ceb": "Asa man ang parehas?",
    },

    # ── Attention and Regulation (10) ────────────────────────────────
    "CalmBody": {
        "category": "attention_and_regulation",
        "en": "Calm body.",
        "tl": "Maging mahinahon.",
        "ceb": "Kalma lang.",
    },
    "EyesHere": {
        "category": "attention_and_regulation",
        "en": "Eyes here.",
        "tl": "Tingin dito.",
        "ceb": "Tan-aw diri.",
    },
    "GoodCalmingDown": {
        "category": "attention_and_regulation",
        "en": "Good calming down!",
        "tl": "Magaling magpakalma!",
        "ceb": "Maayong pagpakalma!",
    },
    "ItsOkay": {
        "category": "attention_and_regulation",
        "en": "It's okay.",
        "tl": "Ok lang yan.",
        "ceb": "Ok ra na.",
    },
    "LetsContinue": {
        "category": "attention_and_regulation",
        "en": "Let's continue.",
        "tl": "Ituloy natin.",
        "ceb": "Padayon ta.",
    },
    "LetsSlowDown": {
        "category": "attention_and_regulation",
        "en": "Let's slow down.",
        "tl": "Dahan-dahan lang.",
        "ceb": "Hinay-hinay lang.",
    },
    "ListenCarefully": {
        "category": "attention_and_regulation",
        "en": "Listen carefully.",
        "tl": "Makinig nang mabuti.",
        "ceb": "Paminaw og maayo.",
    },
    "ReadyAgain": {
        "category": "attention_and_regulation",
        "en": "Ready again?",
        "tl": "Handa ka na ba ulit?",
        "ceb": "Andam na pud?",
    },
    "TakeABreath": {
        "category": "attention_and_regulation",
        "en": "Take a breath.",
        "tl": "Huminga nang malalim.",
        "ceb": "Ginhawa og lawom.",
    },
    "YouAreSafe": {
        "category": "attention_and_regulation",
        "en": "You are safe.",
        "tl": "Ligtas ka.",
        "ceb": "Luwas ka.",
    },

    # ── Core Praise (12) ─────────────────────────────────────────────
    "Aumazing": {
        "category": "core_praise",
        "en": "Aumazing!",
        "tl": "Aumazing!",
        "ceb": "Aumazing!",
    },
    "Ausome": {
        "category": "core_praise",
        "en": "Ausome!",
        "tl": "Ausome!",
        "ceb": "Ausome!",
    },
    "Correct": {
        "category": "core_praise",
        "en": "Correct!",
        "tl": "Tama!",
        "ceb": "Sakto!",
    },
    "Excellent": {
        "category": "core_praise",
        "en": "Excellent!",
        "tl": "Napakahusay!",
        "ceb": "Maayo kaayo!",
    },
    # "GoodTry" deliberately absent from core_praise: it praises the attempt,
    # not the result, so a correct answer could be met with a line that reads as
    # consolation. gently_retry/NiceTry already says it, in the right register.
    "GreatJob": {
        "category": "core_praise",
        "en": "Great job!",
        "tl": "Magaling!",
        "ceb": "Maayo kaayo!",
    },
    "NiceWork": {
        "category": "core_praise",
        "en": "Nice work!",
        "tl": "Mahusay ang ginawa mo!",
        "ceb": "Maayong pagkabuhat!",
    },
    "ThatsRight": {
        "category": "core_praise",
        "en": "That's right!",
        "tl": "Tama yan!",
        "ceb": "Sakto na!",
    },
    "VeryGood": {
        "category": "core_praise",
        "en": "Very good!",
        "tl": "Napakagaling!",
        "ceb": "Maayo kaayo!",
    },
    "WellDone": {
        "category": "core_praise",
        "en": "Well done!",
        "tl": "Mahusay!",
        "ceb": "Maayong pagkabuhat!",
    },
    "YayYouGotIt": {
        "category": "core_praise",
        "en": "Yay! You got it!",
        "tl": "Yehey! Nakuha mo!",
        "ceb": "Yehey! Nakuha nimo!",
    },
    "YouDidIt": {
        "category": "core_praise",
        "en": "You did it!",
        "tl": "Nagawa mo!",
        "ceb": "Nabuhat nimo!",
    },

    # ── Gently Retry (10) ────────────────────────────────────────────
    "AlmostThere": {
        "category": "gently_retry",
        "en": "Almost there.",
        "tl": "Malapit na.",
        "ceb": "Hapit na.",
    },
    "GiveItAnotherTry": {
        "category": "gently_retry",
        "en": "Give it another try.",
        "tl": "Subukan mong muli.",
        "ceb": "Sulayi pag-usab.",
    },
    "KeepGoing": {
        "category": "gently_retry",
        "en": "Keep going.",
        "tl": "Ituloy mo lang.",
        "ceb": "Padayon lang.",
    },
    "LetsDoItOneMoreTime": {
        "category": "gently_retry",
        "en": "Let's do it one more time.",
        "tl": "Gawin natin ulit ng isa pang beses.",
        "ceb": "Buhaton nato og kausa pa.",
    },
    "LetsPracticeAgain": {
        "category": "gently_retry",
        "en": "Let's practice again.",
        "tl": "Mag-ensayo tayo ulit.",
        "ceb": "Magpraktis ta pag-usab.",
    },
    "LetsTryAgain": {
        "category": "gently_retry",
        "en": "Let's try again.",
        "tl": "Subukan natin ulit.",
        "ceb": "Sulayan nato pag-usab.",
    },
    "NiceTry": {
        "category": "gently_retry",
        "en": "Nice try.",
        "tl": "Magandang subok.",
        "ceb": "Nindot nga pagsulay.",
    },
    "NotYet": {
        "category": "gently_retry",
        "en": "Not yet.",
        "tl": "Hindi pa.",
        "ceb": "Dili pa.",
    },
    "TryAgain": {
        "category": "gently_retry",
        "en": "Try again.",
        "tl": "Subukan ulit.",
        "ceb": "Sulayi pag-usab.",
    },
    "YouCanDoIt": {
        "category": "gently_retry",
        "en": "You can do it!",
        "tl": "Kaya mo yan!",
        "ceb": "Kaya nimo na!",
    },

    # ── Instruction (16) ─────────────────────────────────────────────
    "ChooseOne": {
        "category": "instruction",
        "en": "Choose one.",
        "tl": "Pumili ng isa.",
        "ceb": "Pili og usa.",
    },
    "CopyMe": {
        "category": "instruction",
        "en": "Copy me.",
        "tl": "Magaya mo ba ako?",
        "ceb": "Sundoga ko.",
    },
    "CountWithMe": {
        "category": "instruction",
        "en": "Count with me.",
        "tl": "Sumabay ka sa aking magbilang.",
        "ceb": "Mag-count ta.",
    },
    "DragIt": {
        "category": "instruction",
        "en": "Drag it.",
        "tl": "I-drag ito.",
        "ceb": "I-drag ni.",
    },
    "FindTheSame": {
        "category": "instruction",
        "en": "Find the same.",
        "tl": "Hanapin ang pareho.",
        "ceb": "Pangitaa ang parehas.",
    },
    "FollowMe": {
        "category": "instruction",
        "en": "Follow me.",
        "tl": "Sundan mo ako.",
        "ceb": "Sunda ko.",
    },
    "LetsBegin": {
        "category": "instruction",
        "en": "Let's begin.",
        "tl": "Magsimula na tayo.",
        "ceb": "Magsugod na ta.",
    },
    "Listen": {
        "category": "instruction",
        "en": "Listen.",
        "tl": "Makinig.",
        "ceb": "Paminaw.",
    },
    "MatchIt": {
        "category": "instruction",
        "en": "Match it.",
        "tl": "Itugma ito.",
        "ceb": "I-match ni.",
    },
    "MyTurn": {
        "category": "instruction",
        "en": "My turn.",
        "tl": "Ako naman.",
        "ceb": "Ako na pud.",
    },
    "PickTheColor": {
        "category": "instruction",
        "en": "Pick the color.",
        "tl": "Piliin ang kulay.",
        "ceb": "Pili-a ang color.",
    },
    "PickTheShape": {
        "category": "instruction",
        "en": "Pick the shape.",
        "tl": "Piliin ang hugis.",
        "ceb": "Pili-a ang shape.",
    },
    "TapHere": {
        "category": "instruction",
        "en": "Tap here.",
        "tl": "Pindutin dito.",
        "ceb": "I-tap diri.",
    },
    "TouchThePicture": {
        "category": "instruction",
        "en": "Touch the picture.",
        "tl": "Hawakan ang larawan.",
        "ceb": "I-touch ang picture.",
    },
    "WatchCarefully": {
        "category": "instruction",
        "en": "Watch carefully.",
        "tl": "Manood nang mabuti.",
        "ceb": "Tan-aw og maayo.",
    },
    "YourTurn": {
        "category": "instruction",
        "en": "Your turn.",
        "tl": "Ikaw naman.",
        "ceb": "Ikaw na pud.",
    },

    # ── Reward & Celebration (9) ─────────────────────────────────────
    "AwesomeWorkToday": {
        "category": "reward_and_celebration",
        "en": "Awesome work today!",
        "tl": "Napakahusay ng gawa mo ngayon!",
        "ceb": "Awesome kaayo ka karon!",
    },
    "BigHighFive": {
        "category": "reward_and_celebration",
        "en": "Big high five!",
        "tl": "Apaw na high five!",
        "ceb": "Dako nga high five!",
    },
    "Fantastic": {
        "category": "reward_and_celebration",
        "en": "Fantastic!",
        "tl": "Kamangha-mangha!",
        "ceb": "Fantastic!",
    },
    "GreatPlaying": {
        "category": "reward_and_celebration",
        "en": "Great playing!",
        "tl": "Mahusay na paglalaro!",
        "ceb": "Maayong pagdula!",
    },
    "Hooray": {
        "category": "reward_and_celebration",
        "en": "Hooray!",
        "tl": "Yehey!",
        "ceb": "Yehey!",
    },
    "SuperJob": {
        "category": "reward_and_celebration",
        "en": "Super job!",
        "tl": "Super galing!",
        "ceb": "Super nice!",
    },
    "YouDidSoWell": {
        "category": "reward_and_celebration",
        "en": "You did so well!",
        "tl": "Napakagaling mo!",
        "ceb": "Maayo kaayo ka!",
    },
    "YouFinishedIt": {
        "category": "reward_and_celebration",
        "en": "You finished it!",
        "tl": "Natapos mo rin!",
        "ceb": "Nahuman nimo!",
    },
    "YoureAmazing": {
        "category": "reward_and_celebration",
        "en": "You're amazing!",
        "tl": "Kahanga-hanga ka!",
        "ceb": "Amazing kaayo ka!",
    },

    # ── Transition (10) ──────────────────────────────────────────────
    "GameFinished": {
        "category": "transition",
        "en": "Game finished.",
        "tl": "Tapos na ang laro.",
        "ceb": "Game finished na!",
    },
    "GetReady": {
        "category": "transition",
        "en": "Get ready.",
        "tl": "Humanda ka.",
        "ceb": "Get ready!",
    },
    "GoodJobMovingOn": {
        "category": "transition",
        "en": "Good job! Moving on.",
        "tl": "Magaling! Susunod na.",
        "ceb": "Good job! Sunod na pud.",
    },
    "LetsGo": {
        "category": "transition",
        "en": "Let's go!",
        "tl": "Tara na!",
        "ceb": "Tana!",
    },
    "LetsPlayAgain": {
        "category": "transition",
        "en": "Let's play again.",
        "tl": "Maglaro tayo ulit.",
        "ceb": "Mag-play ta pag-usab.",
    },
    "LevelComplete": {
        "category": "transition",
        "en": "Level complete.",
        "tl": "Kumpleto na ang antas.",
        "ceb": "Level complete na!",
    },
    "NewGame": {
        "category": "transition",
        "en": "New game.",
        "tl": "Bagong laro.",
        "ceb": "Bag-ong game.",
    },
    "NextActivity": {
        "category": "transition",
        "en": "Next activity.",
        "tl": "Susunod na aktibidad.",
        "ceb": "Next activity na.",
    },
    "NextOne": {
        "category": "transition",
        "en": "Next one.",
        "tl": "Ang susunod.",
        "ceb": "Ang sunod.",
    },
    "TimeForTheNextOne": {
        "category": "transition",
        "en": "Time for the next one.",
        "tl": "Oras na para sa susunod.",
        "ceb": "Oras na sa sunod.",
    },

    # ── Turn Taking (10) ─────────────────────────────────────────────
    "GoodWaiting": {
        "category": "turn_taking",
        "en": "Good waiting!",
        "tl": "Magaling maghintay!",
        "ceb": "Maayong paghulat!",
    },
    "HereWeGo": {
        "category": "turn_taking",
        "en": "Here we go!",
        "tl": "Heto na tayo!",
        "ceb": "Kini na!",
    },
    "LetsTakeTurns": {
        "category": "turn_taking",
        "en": "Let's take turns.",
        "tl": "Magpalitan tayo.",
        "ceb": "Magpuli-puli ta.",
    },
    "MyTurnTT": {
        "category": "turn_taking",
        "en": "My turn.",
        "tl": "Ako naman.",
        "ceb": "Ako na pud.",
        "filename": "MyTurn",
    },
    "NowYouTry": {
        "category": "turn_taking",
        "en": "Now you try.",
        "tl": "Subukan mo naman.",
        "ceb": "Sulayi na pud.",
    },
    "Ready": {
        "category": "turn_taking",
        "en": "Ready?",
        "tl": "Handa ka na ba?",
        "ceb": "Andam na?",
    },
    "ThankYouForWaiting": {
        "category": "turn_taking",
        "en": "Thank you for waiting.",
        "tl": "Salamat sa paghihintay.",
        "ceb": "Salamat sa paghulat.",
    },
    "Wait": {
        "category": "turn_taking",
        "en": "Wait.",
        "tl": "Sandali.",
        "ceb": "Hulat lang.",
    },
    "WatchMeFirst": {
        "category": "turn_taking",
        "en": "Watch me first.",
        "tl": "Panoorin mo muna ako.",
        "ceb": "Tan-awa ko una.",
    },
    "YourTurnTT": {
        "category": "turn_taking",
        "en": "Your turn.",
        "tl": "Ikaw naman.",
        "ceb": "Ikaw na pud.",
        "filename": "YourTurn",
    },

    # ── Dynamic Action Cues (3) ──────────────────────────────────────
    "TapThe": {
        "category": "dynamic",
        "en": "Tap the",
        "tl": "Pindutin ang",
        "ceb": "I-tap ang",
    },
    "DragThe": {
        "category": "dynamic",
        "en": "Drag the",
        "tl": "I-drag ang",
        "ceb": "I-drag ang",
    },
    "DropThe": {
        "category": "dynamic",
        "en": "Drop the",
        "tl": "I-drop ang",
        "ceb": "I-drop ang",
    },

    # ── Color Cues (6) ───────────────────────────────────────────────
    "Red": {
        "category": "colors",
        "en": "Red",
        "tl": "Pula",
        "ceb": "Pula",
    },
    "Blue": {
        "category": "colors",
        "en": "Blue",
        "tl": "Asul",
        "ceb": "Asul",
    },
    "Green": {
        "category": "colors",
        "en": "Green",
        "tl": "Berde",
        "ceb": "Berde",
    },
    "Yellow": {
        "category": "colors",
        "en": "Yellow",
        "tl": "Dilaw",
        "ceb": "Yellow",
    },
    "Purple": {
        "category": "colors",
        "en": "Purple",
        "tl": "Lila",
        "ceb": "Purple",
    },
    "Orange": {
        "category": "colors",
        "en": "Orange",
        "tl": "Kahel",
        "ceb": "Orange",
    },

    # ── Shape Cues (4) ───────────────────────────────────────────────
    "Circle": {
        "category": "shapes",
        "en": "Circle",
        "tl": "Bilog",
        "ceb": "Circle",
    },
    "Star": {
        "category": "shapes",
        "en": "Star",
        "tl": "Bituin",
        "ceb": "Star",
    },
    "Triangle": {
        "category": "shapes",
        "en": "Triangle",
        "tl": "Tatsulok",
        "ceb": "Triangle",
    },
    "Diamond": {
        "category": "shapes",
        "en": "Diamond",
        "tl": "Diyamante",
        "ceb": "Diamond",
    },
}


def _ffmpeg_exe() -> str:
    """Bundled ffmpeg (no system install needed)."""
    import imageio_ffmpeg

    return imageio_ffmpeg.get_ffmpeg_exe()


async def _synthesize_one(
    semaphore: "asyncio.Semaphore",
    ffmpeg: str,
    lang_code: str,
    cue_name: str,
    cue_data: dict,
) -> tuple[str, str, str | None]:
    """Generate one emotional WAV. Returns (lang, cue, error-or-None)."""
    import edge_tts

    text = cue_data.get(lang_code) or cue_data["en"]
    category = cue_data["category"]
    profile = EMOTION_PROFILES.get(category, DEFAULT_PROFILE)
    voice = LANGUAGE_MODELS[lang_code]

    out_dir = OUTPUT_ROOT / lang_code / category
    out_dir.mkdir(parents=True, exist_ok=True)
    fname = cue_data.get("filename", cue_name)
    wav_path = out_dir / f"{fname}.wav"
    mp3_path = out_dir / f"{fname}.tmp.mp3"

    async with semaphore:
        last_error = None
        for attempt in range(3):  # the free Edge endpoint can rate-limit
            try:
                communicate = edge_tts.Communicate(
                    text,
                    voice,
                    rate=profile["rate"],
                    pitch=profile["pitch"],
                )
                await communicate.save(str(mp3_path))

                # mp3 → 24 kHz mono WAV (the format VoiceOverService expects)
                result = subprocess.run(
                    [ffmpeg, "-y", "-i", str(mp3_path),
                     "-ar", "24000", "-ac", "1", str(wav_path)],
                    capture_output=True,
                )
                if result.returncode != 0:
                    raise RuntimeError(
                        f"ffmpeg: {result.stderr.decode(errors='ignore')[-200:]}")

                print(f"  [OK] [{lang_code}] {category}/{fname}.wav "
                      f"(rate {profile['rate']}, pitch {profile['pitch']})")
                return (lang_code, cue_name, None)
            except Exception as e:  # noqa: BLE001 — retried, then reported
                last_error = str(e)
                await asyncio.sleep(1.5 * (attempt + 1))
            finally:
                mp3_path.unlink(missing_ok=True)

        print(f"  [ERR] [{lang_code}] {category}/{fname}.wav — {last_error}")
        return (lang_code, cue_name, last_error)


async def generate_all_async(languages):
    ffmpeg = _ffmpeg_exe()
    # Gentle concurrency: fast enough for 300 files, kind to the endpoint.
    semaphore = asyncio.Semaphore(4)

    tasks = [
        _synthesize_one(semaphore, ffmpeg, lang, cue_name, cue_data)
        for lang in languages
        for cue_name, cue_data in VOICE_LINES.items()
    ]
    results = await asyncio.gather(*tasks)

    errors = [(l, c, e) for (l, c, e) in results if e is not None]
    print(f"\n{'='*60}")
    print("[DONE] Emotional voice-over generation complete!")
    print(f"   Generated: {len(results) - len(errors)}/{len(results)} files")
    print(f"   Output:    {OUTPUT_ROOT}")
    if errors:
        print(f"   Errors:    {len(errors)}")
        for lang, cue, err in errors:
            print(f"     - [{lang}] {cue}: {err}")
    print(f"{'='*60}")
    return len(errors)


def main():
    """Entry point with optional language filtering via CLI args."""
    languages = sys.argv[1:] if len(sys.argv) > 1 else None

    if languages:
        invalid = [l for l in languages if l not in LANGUAGE_MODELS]
        if invalid:
            print(f"[WARN] Unknown language codes: {invalid}")
            print(f"  Available: {list(LANGUAGE_MODELS.keys())}")
            sys.exit(1)
        print(f"Generating for languages: {languages}")
    else:
        languages = list(LANGUAGE_MODELS.keys())
        print(f"Generating for ALL languages: {languages}")

    start = time.time()
    error_count = asyncio.run(generate_all_async(languages))
    elapsed = time.time() - start
    print(f"\nTotal time: {elapsed:.1f}s")
    sys.exit(1 if error_count else 0)


if __name__ == "__main__":
    main()
