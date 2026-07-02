#!/usr/bin/env python3
"""
Batch-generate voice-over WAV files for Aumazing using Meta MMS (VITS).

This script reads voice line definitions (English, Tagalog, Cebuano) and
generates corresponding .wav files using facebook/mms-tts-* models from
Hugging Face.

Usage:
  pip install transformers torch scipy
  python scripts/generate_voice_lines.py

Output:
  packages/shared_audio/assets/audio/voice_over/{lang}/{category}/{CueName}.wav
"""

import os
import sys
import time
from pathlib import Path

import scipy.io.wavfile
import torch
from transformers import VitsModel, AutoTokenizer

# ── Project root (relative to this script) ───────────────────────────
SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parent
OUTPUT_ROOT = PROJECT_ROOT / "packages" / "shared_audio" / "assets" / "audio" / "voice_over"

# ── Language → HuggingFace model mapping ─────────────────────────────
LANGUAGE_MODELS = {
    "en":  "facebook/mms-tts-eng",
    "tl":  "facebook/mms-tts-tgl",
    "ceb": "facebook/mms-tts-ceb",
}

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
    "GoodTry": {
        "category": "core_praise",
        "en": "Good try!",
        "tl": "Magandang subok!",
        "ceb": "Nindot nga pagsulay!",
    },
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


def generate_all(languages=None):
    """Generate WAV files for all voice lines across specified languages.

    Args:
        languages: List of language codes to generate. Defaults to all.
    """
    if languages is None:
        languages = list(LANGUAGE_MODELS.keys())

    total_files = len(VOICE_LINES) * len(languages)
    generated = 0
    errors = []

    for lang_code in languages:
        model_name = LANGUAGE_MODELS.get(lang_code)
        if not model_name:
            print(f"[WARN] Unknown language code: {lang_code}, skipping.")
            continue

        print(f"\n{'='*60}")
        print(f"Loading model for [{lang_code}]: {model_name}")
        print(f"{'='*60}")

        try:
            model = VitsModel.from_pretrained(model_name)
            tokenizer = AutoTokenizer.from_pretrained(model_name)
        except Exception as e:
            print(f"[ERR] Failed to load model {model_name}: {e}")
            errors.append((lang_code, "MODEL_LOAD", str(e)))
            continue

        for cue_name, cue_data in VOICE_LINES.items():
            text = cue_data.get(lang_code, cue_data["en"])  # Fallback to English
            category = cue_data["category"]

            # Prepare output path
            out_dir = OUTPUT_ROOT / lang_code / category
            out_dir.mkdir(parents=True, exist_ok=True)
            out_path = out_dir / f"{cue_data.get('filename', cue_name)}.wav"

            try:
                # Generate speech
                inputs = tokenizer(text, return_tensors="pt")
                with torch.no_grad():
                    output = model(**inputs)

                waveform = output.waveform[0].cpu().numpy()
                sample_rate = model.config.sampling_rate

                scipy.io.wavfile.write(str(out_path), rate=sample_rate, data=waveform)
                generated += 1
                fname = cue_data.get('filename', cue_name)
                print(f"  [OK] [{lang_code}] {category}/{fname}.wav")

            except Exception as e:
                print(f"  [ERR] [{lang_code}] {category}/{cue_name}.wav - ERROR: {e}")
                errors.append((lang_code, cue_name, str(e)))

    # ── Summary ──────────────────────────────────────────────────────
    print(f"\n{'='*60}")
    print(f"[DONE] Generation complete!")
    print(f"   Generated: {generated}/{total_files} files")
    print(f"   Output:    {OUTPUT_ROOT}")
    if errors:
        print(f"   Errors:    {len(errors)}")
        for lang, cue, err in errors:
            print(f"     - [{lang}] {cue}: {err}")
    print(f"{'='*60}")


def main():
    """Entry point with optional language filtering via CLI args."""
    # Allow filtering: python generate_voice_lines.py en tl
    languages = sys.argv[1:] if len(sys.argv) > 1 else None

    if languages:
        invalid = [l for l in languages if l not in LANGUAGE_MODELS]
        if invalid:
            print(f"[WARN] Unknown language codes: {invalid}")
            print(f"  Available: {list(LANGUAGE_MODELS.keys())}")
            sys.exit(1)
        print(f"Generating for languages: {languages}")
    else:
        print(f"Generating for ALL languages: {list(LANGUAGE_MODELS.keys())}")

    start = time.time()
    generate_all(languages)
    elapsed = time.time() - start
    print(f"\nTotal time: {elapsed:.1f}s")


if __name__ == "__main__":
    main()
