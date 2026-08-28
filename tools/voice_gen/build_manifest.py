"""Build an editable CSV manifest of every voice-over line.

Derives spoken text from the asset filenames, then applies contraction and
punctuation heuristics -- punctuation matters because it drives the model's
prosody ("Yay! You got it!" is delivered very differently from "Yay you got it").

The output is a STARTING POINT. Read it and fix the text before generating:
the heuristics get most lines right but cannot know your intended delivery.

Usage:  python build_manifest.py <voice_over/en dir> [-o lines.csv]
"""
import argparse
import csv
import os
import re

# Filenames drop apostrophes; restore them.
CONTRACTIONS = {
    'Lets': "Let's", 'Its': "It's", 'Thats': "That's",
    'Youre': "You're", 'Dont': "Don't", 'Let': "Let's",  # LetSeeWhatYouCanDo
}

# Lines whose auto-derivation is wrong or whose delivery needs specific marks.
OVERRIDES = {
    'assessment_style/LetSeeWhatYouCanDo': "Let's see what you can do!",
    'core_praise/YayYouGotIt': "Yay! You got it!",
    'core_praise/Aumazing': "Aumazing!",
    'core_praise/Ausome': "Ausome!",
    'turn_taking/MyTurn': "My turn.",
    'turn_taking/YourTurn': "Your turn!",
    'instruction/MyTurn': "My turn.",
    'instruction/YourTurn': "Your turn!",
    'dynamic/TapThe': "Tap the",
    'dynamic/DragThe': "Drag the",
    'dynamic/DropThe': "Drop the",
}

QUESTION_STARTS = ('Can', 'What', 'Which', 'Who', 'How', 'Where')
EXCITED_CATEGORIES = {'core_praise', 'reward_and_celebration', 'transition'}
CALM_CATEGORIES = {'attention_and_regulation'}

# Categories whose clips are single words - these need a carrier phrase,
# because zero-shot TTS handles bare one-word prompts badly.
SHORT_CATEGORIES = {'colors', 'shapes', 'dynamic'}


def derive_text(stem, category):
    words = re.sub(r'(?<!^)(?=[A-Z])', ' ', stem).split()
    words = [CONTRACTIONS.get(w, w) for w in words]
    text = ' '.join(words)
    text = text[0].upper() + text[1:] if text else text
    # Lowercase everything after the first word (filenames are CamelCase).
    parts = text.split()
    text = ' '.join([parts[0]] + [p if p.startswith("'") or p[0].isupper() and p in CONTRACTIONS.values()
                                  else p.lower() for p in parts[1:]])
    if stem.startswith(QUESTION_STARTS):
        text += '?'
    elif category in EXCITED_CATEGORIES:
        text += '!'
    elif category in CALM_CATEGORIES:
        text += '.'
    else:
        text += '.'
    return text


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('src', help='e.g. packages/shared_audio/assets/audio/voice_over/en')
    ap.add_argument('-o', '--out', default='lines.csv')
    args = ap.parse_args()

    rows = []
    for dirpath, _, names in os.walk(args.src):
        for name in sorted(names):
            if not name.lower().endswith('.wav'):
                continue
            rel = os.path.relpath(os.path.join(dirpath, name), args.src).replace('\\', '/')
            category = rel.split('/')[0]
            stem = os.path.splitext(os.path.basename(rel))[0]
            key = '%s/%s' % (category, stem)
            text = OVERRIDES.get(key) or derive_text(stem, category)
            rows.append(dict(
                path=rel,
                text=text,
                carrier='yes' if category in SHORT_CATEGORIES else 'no',
                # Calmer delivery for regulation cues, brighter for praise.
                exaggeration='0.3' if category in CALM_CATEGORIES
                             else '0.6' if category in EXCITED_CATEGORIES else '0.5',
                cfg_weight='0.5',
            ))

    with open(args.out, 'w', newline='', encoding='utf-8') as f:
        w = csv.DictWriter(f, fieldnames=['path', 'text', 'carrier', 'exaggeration', 'cfg_weight'])
        w.writeheader()
        w.writerows(rows)

    n_carrier = sum(1 for r in rows if r['carrier'] == 'yes')
    print('Wrote %s: %d lines (%d using a carrier phrase).' % (args.out, len(rows), n_carrier))
    print('\nReview the text column before generating. Sample:')
    for r in rows[:5] + [r for r in rows if r['carrier'] == 'yes'][:5]:
        print('  %-34s %-28s carrier=%s exag=%s' % (r['path'], repr(r['text']), r['carrier'], r['exaggeration']))


if __name__ == '__main__':
    main()
