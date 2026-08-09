"""Cross-check the voice-over library: manifests, cue table, and shipped assets.

Adding a line touches four places that have to agree, and nothing else notices
when they drift -- a cue missing from one language's manifest just plays in the
default voice instead, which is easy to miss and hard to trace later.

Checks, in the order they usually break:

  1. The three manifests cover the same paths (a line added to lines.csv but
     not to tagalog_lines.csv silently leaves tl short).
  2. Every manifest line has a VoiceOverCue (otherwise the audio is generated,
     shipped, and unreachable).
  3. Every cue has a manifest line (otherwise it can never be regenerated).
  4. enum / _cueCategories / _cueAssetPaths agree with each other.
  5. Every registered pack has a file for every cue, with that pack's own
     extension.

Exits non-zero if anything is wrong, so it can gate a commit.

  python check_library.py
  python check_library.py --quiet
"""
import argparse
import csv
import os
import re
import sys

import voices as VOX

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
SHARED = os.path.join(REPO, 'packages', 'shared_audio')
SERVICE = os.path.join(SHARED, 'lib', 'src', 'voice_over_service.dart')
REGISTRY = os.path.join(SHARED, 'lib', 'src', 'voice_pack.dart')
ASSETS = os.path.join(SHARED, 'assets', 'audio')


def read(path):
    with open(path, encoding='utf-8') as f:
        return f.read()


def dart_tables():
    src = read(SERVICE)
    enum_block = src.split('enum VoiceOverCue {')[1].split('}')[0]
    enum_names = set(re.findall(r'^\s*(\w+),', enum_block, re.M))
    cats = set(re.findall(r'VoiceOverCue\.(\w+):',
                          src.split('_cueCategories = {')[1].split('};')[0]))
    paths = dict(re.findall(r"VoiceOverCue\.(\w+):\s*\n?\s*'(voice_over/[^']+)'",
                            src.split('_cueAssetPaths = {')[1].split('};')[0]))
    return enum_names, cats, paths


def registered_packs():
    src = read(REGISTRY)
    out = []
    for block in src.split('VoicePack(')[1:]:
        head = block.split('),')[0]
        folder = re.search(r"assetFolder: '([^']+)'", head)
        ext = re.search(r"fileExtension: '([^']+)'", head)
        if folder:
            out.append((folder.group(1), ext.group(1) if ext else '.wav'))
    return out


def manifest_paths(manifest):
    out = {}
    with open(manifest, encoding='utf-8') as f:
        for row in csv.DictReader(f):
            rel = (row.get('path') or '').strip()
            if not rel:
                continue
            if not rel.lower().endswith('.wav'):
                rel += '.wav'
            out[rel] = (row.get('text') or '').strip()
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--quiet', action='store_true',
                    help='only print problems')
    args = ap.parse_args()

    problems = []
    note = (lambda *a: None) if args.quiet else print

    manifests = {lang: manifest_paths(cfg['manifest'])
                 for lang, cfg in VOX.LANGUAGES.items()}
    base_lang = 'en'
    base = set(manifests[base_lang])

    note('manifests: %s' % ', '.join('%s=%d' % (l, len(m))
                                     for l, m in manifests.items()))
    for lang, paths in manifests.items():
        missing = base - set(paths)
        extra = set(paths) - base
        for m in sorted(missing):
            problems.append('%s manifest is missing %s (present in %s)'
                            % (lang, m, base_lang))
        for e in sorted(extra):
            problems.append('%s manifest has %s, absent from %s'
                            % (lang, e, base_lang))
        blank = [p for p, t in paths.items() if not t]
        for b in sorted(blank):
            problems.append('%s manifest has no text for %s' % (lang, b))

    enum_names, cats, paths = dart_tables()
    note('cue table: enum=%d categories=%d assetPaths=%d'
         % (len(enum_names), len(cats), len(paths)))
    for name in sorted(enum_names - cats):
        problems.append('cue %s has no category' % name)
    for name in sorted(enum_names - set(paths)):
        problems.append('cue %s has no asset path' % name)
    for name in sorted(set(paths) - enum_names):
        problems.append('asset path for unknown cue %s' % name)

    mapped = {v.replace('voice_over/', '') for v in paths.values()}
    for orphan in sorted(base - mapped):
        problems.append('manifest line %s has no cue -- generated and shipped '
                        'but the app can never play it' % orphan)
    for missing in sorted(mapped - base):
        problems.append('cue path %s is not in the %s manifest -- it cannot be '
                        'regenerated' % (missing, base_lang))

    packs = registered_packs()
    note('packs: %d registered' % len(packs))
    for folder, ext in packs:
        absent = []
        for rel in sorted(mapped):
            target = os.path.join(ASSETS, 'voice_over', folder,
                                  os.path.splitext(rel)[0] + ext)
            if not os.path.isfile(target):
                absent.append(rel)
        if absent:
            # A pack missing cues still plays via the language default, so this
            # is a warning about coverage rather than a hard break.
            problems.append('pack %s is missing %d cue file(s), e.g. %s '
                            '(falls back to the default voice)'
                            % (folder, len(absent), absent[0]))

    if problems:
        print('\n%d problem(s):' % len(problems))
        for p in problems:
            print('  - %s' % p)
        return 1
    note('\nEverything agrees.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
