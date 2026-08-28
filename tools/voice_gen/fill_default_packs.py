"""OBSOLETE as of 2026-08-07 -- kept only as the record of what was tried.

The `en` / `tl` / `ceb` default packs this script filled have been removed from
the registry: borrowing cues across speakers is exactly the seam that made them
sound inconsistent, and every language now defaults to a single-speaker
`*_adult_woman` pack instead. Running this script does nothing useful.

Fill gaps in the hand-made default voice packs from a generated pack.

`en`, `tl` and `ceb` are the packs a child hears out of the box, and they were
made before `generate_kie.py` existed -- nothing in the repo records how. That
means a cue added to the library later cannot be produced in their voice, and
because a default pack is the end of the fallback chain, a cue it lacks plays
*nothing*. Trace It and Sari-Sari Sort would be silent on exactly the voice most
children use.

So each default pack borrows its missing cues from whichever generated pack
sounds most like it. Those sources were measured, not guessed -- median F0 and
median MFCC over thirteen cues present in both, the same features
`repair_consistency.py` scores with:

    default   F0     best generated match        dF0      dMFCC
    en        314    child/girl      (316 Hz)     1.5      47.7   <- close
    tl        258    young/girl      (289 Hz)    31.6      69.0   <- weak
    ceb       240    adult/woman     (231 Hz)     9.7      82.6   <- pitch only

**Only `en` is a convincing match.** For `tl` and `ceb` the borrowed cues will
read as a related but different speaker. That was judged better than silence on
every correct answer, but it is a product decision and it is reversible: delete
the copied files, or commit to the alternative below.

The alternative, if the seams are audible: regenerate a whole default pack from
one voice, so it is internally consistent throughout. That changes the voice the
app ships with, which is why it is not the default behaviour here.

    python generate_kie.py --lang tl --voices young/girl --yes
    python fill_default_packs.py --lang tl --replace-all

Usage:

    python fill_default_packs.py --dry-run
    python fill_default_packs.py
"""
import argparse
import csv
import os
import shutil
import sys

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
ASSETS = os.path.join(REPO, 'packages', 'shared_audio', 'assets', 'audio',
                      'voice_over')
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                   'out', 'kie', 'gemini')

MANIFEST = {'en': 'lines.csv', 'tl': 'tagalog_lines.csv',
            'ceb': 'cebuano_lines.csv'}

# Measured in the docstring above. Change only with fresh measurements.
SOURCE = {'en': 'child_girl', 'tl': 'young_girl', 'ceb': 'adult_woman'}


def cue_paths(lang):
    """Every cue path the manifest declares, without extension."""
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                        MANIFEST[lang])
    out = []
    with open(path, newline='', encoding='utf-8') as fh:
        for i, row in enumerate(csv.reader(fh)):
            if i == 0 or not row:
                continue
            stem = row[0]
            if stem.endswith('.wav'):
                stem = stem[:-4]
            out.append(stem)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--lang', choices=sorted(MANIFEST), action='append',
                    help='limit to these languages (default: all three)')
    ap.add_argument('--replace-all', action='store_true',
                    help='overwrite every cue, not just the missing ones -- '
                         'makes the whole pack one voice, and changes the '
                         'voice the app ships with')
    ap.add_argument('--dry-run', action='store_true')
    args = ap.parse_args()

    langs = args.lang or sorted(MANIFEST)
    total_copied = total_missing = 0

    for lang in langs:
        src_dir = os.path.join(OUT, lang, SOURCE[lang])
        dst_dir = os.path.join(ASSETS, lang)
        if not os.path.isdir(src_dir):
            print('%-4s SKIP  no generated pack at %s' % (lang, src_dir))
            continue

        copied, missing = [], []
        for stem in cue_paths(lang):
            src = os.path.join(src_dir, stem.replace('/', os.sep) + '.wav')
            dst = os.path.join(dst_dir, stem.replace('/', os.sep) + '.wav')
            if os.path.exists(dst) and not args.replace_all:
                continue
            if not os.path.exists(src):
                missing.append(stem)
                continue
            if not args.dry_run:
                os.makedirs(os.path.dirname(dst), exist_ok=True)
                shutil.copy2(src, dst)
            copied.append(stem)

        total_copied += len(copied)
        total_missing += len(missing)
        print('%-4s <- %-12s  %d cue(s)%s' %
              (lang, SOURCE[lang], len(copied),
               '  [%d unavailable]' % len(missing) if missing else ''))
        for stem in copied:
            print('       + %s' % stem)
        for stem in missing:
            print('       ! %s  not generated' % stem)

    print('\n%d cue(s) %s, %d unavailable'
          % (total_copied, 'would be copied' if args.dry_run else 'copied',
             total_missing))
    if total_copied and not args.dry_run:
        print('Add any new category folders to shared_audio/pubspec.yaml, '
              'then run check_library.py.')
    return 1 if total_missing else 0


if __name__ == '__main__':
    sys.exit(main())
