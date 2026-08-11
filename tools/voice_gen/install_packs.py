"""Install generated voice packs into shared_audio, and emit the code they need.

Copies `out/mp3/<lang>/<tier>_<voice>/` into
`packages/shared_audio/assets/audio/voice_over/<lang>_<tier>_<voice>/`, then
writes the two generated blocks that have to match those folders exactly:

  build/voice_packs.dart.txt   entries for kVoicePacks in voice_pack.dart
  build/pubspec_assets.txt     asset lines for shared_audio/pubspec.yaml

Both are generated rather than hand-written because Flutter cannot glob asset
directories -- every leaf folder needs its own line, and a typo is a cue that
silently falls back to the default voice at runtime.

Existing packs (en, tl, ceb, ceb_lexianne) are never touched: they stay WAV and
stay first in the registry, so each language keeps its current default voice.

  python install_packs.py --dry-run
  python install_packs.py
"""
import argparse
import json
import os
import shutil
import sys

import voices as VOX

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
ASSET_ROOT = os.path.join(REPO, 'packages', 'shared_audio', 'assets', 'audio',
                          'voice_over')
CATEGORIES = ['assessment_style', 'attention_and_regulation', 'core_praise',
              'gently_retry', 'instruction', 'reward_and_celebration',
              'transition', 'turn_taking', 'dynamic', 'colors', 'shapes',
              'letters', 'numbers', 'items', 'phrases', 'routines']
TIER_LABEL = {'adult': 'Adult', 'young': 'Young', 'child': 'Child'}


def packs(src_root):
    """(lang, tier, key, voice, folder, src_dir) for every generated pack."""
    out = []
    for lang in VOX.LANGUAGES:
        for tier, key, voice, _label, _pitch in VOX.resolve('gemini'):
            src = os.path.join(src_root, lang, '%s_%s' % (tier, key))
            if not os.path.isdir(src):
                continue
            out.append((lang, tier, key, voice,
                        '%s_%s_%s' % (lang, tier, key), src))
    return out


DART_BEGIN = '  // BEGIN generated voice packs'
DART_END = '  // END generated voice packs'
YAML_BEGIN = '    # BEGIN generated voice packs'
YAML_END = '    # END generated voice packs'


def replace_block(text, begin, end, body, after=None):
    """Swap the marked block for [body], inserting it if not present yet.

    Markers make re-running safe: changing the roster replaces the previous
    block instead of stacking a second one on top of it.

    [after] anchors a first-time insert to the end of a specific construct --
    the closing bracket is found by scanning forward from [after], never by
    searching the whole file, which would land in whichever list happens to
    come last.
    """
    block = '%s\n%s\n%s' % (begin, body, end)
    if begin in text and end in text:
        head = text[:text.index(begin)]
        tail = text[text.index(end) + len(end):]
        return head + block + tail
    if after is None:
        return text.rstrip('\n') + '\n' + block + '\n'
    start = text.index(after) + len(after)
    close = text.index('\n];', start)
    return text[:close + 1] + block + '\n' + text[close + 1:]


def dart_entries(rows):
    lines = [
        '  // Written by tools/voice_gen/install_packs.py -- do not hand-edit.',
        '  // Each language keeps its original pack above as the default; these',
        '  // are additional choices offered in Settings.',
    ]
    for lang, tier, key, voice, folder, _src in rows:
        lines += [
            '  VoicePack(',
            "    id: '%s'," % folder,
            "    languageSlug: '%s'," % lang,
            "    label: '%s'," % VOX.LABELS.get(key, voice),
            "    assetFolder: '%s'," % folder,
            "    tier: '%s'," % tier,
            "    fileExtension: '.mp3',",
            '  ),',
        ]
    return '\n'.join(lines)


def prune(keep_folders, dry_run):
    """Delete generated pack folders that the current roster no longer lists.

    Generated folders are always `<lang>_<tier>_<key>`; the original recorded
    packs (en, tl, ceb, ceb_lexianne) never match that shape, so they are never
    at risk here.
    """
    import re
    pattern = re.compile(r'^(%s)_(%s)_[a-z0-9]+$'
                         % ('|'.join(VOX.LANGUAGES), '|'.join(VOX.TIERS)))
    removed = []
    for name in sorted(os.listdir(ASSET_ROOT)):
        path = os.path.join(ASSET_ROOT, name)
        if os.path.isdir(path) and pattern.match(name) and name not in keep_folders:
            removed.append(name)
            if not dry_run:
                shutil.rmtree(path)
    return removed


def pubspec_lines(rows):
    lines = ['    # Written by tools/voice_gen/install_packs.py.']
    for lang, tier, key, _voice, folder, _src in rows:
        lines.append('    # %s %s / %s' % (lang, tier, key))
        for cat in CATEGORIES:
            lines.append('    - assets/audio/voice_over/%s/%s/' % (folder, cat))
    return '\n'.join(lines)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--src', default=os.path.join('out', 'mp3'))
    ap.add_argument('--dry-run', action='store_true')
    args = ap.parse_args()

    rows = packs(args.src)
    if not rows:
        sys.exit('No generated packs found under %s' % args.src)

    total = sum(len(fs) for r in rows for _root, _d, fs in os.walk(r[5]))
    print('packs: %d   destination: %s' % (len(rows), ASSET_ROOT))

    stale = prune({r[4] for r in rows}, args.dry_run)
    if stale:
        print('%s %d stale pack folder(s): %s%s'
              % ('would remove' if args.dry_run else 'removed', len(stale),
                 ', '.join(stale[:4]), ' ...' if len(stale) > 4 else ''))

    copied = 0
    for lang, tier, key, voice, folder, src in rows:
        dst = os.path.join(ASSET_ROOT, folder)
        n = sum(len(fs) for _r, _d, fs in os.walk(src))
        print('  %-24s <- %s (%d files)' % (folder, src, n))
        if args.dry_run:
            continue
        for root, _dirs, files in os.walk(src):
            rel = os.path.relpath(root, src)
            target = os.path.join(dst, rel) if rel != '.' else dst
            os.makedirs(target, exist_ok=True)
            for name in files:
                shutil.copy2(os.path.join(root, name),
                             os.path.join(target, name))
                copied += 1

    dart_path = os.path.join(REPO, 'packages', 'shared_audio', 'lib', 'src',
                             'voice_pack.dart')
    yaml_path = os.path.join(REPO, 'packages', 'shared_audio', 'pubspec.yaml')

    dart = open(dart_path, encoding='utf-8').read()
    dart_new = replace_block(dart, DART_BEGIN, DART_END, dart_entries(rows),
                             after='const List<VoicePack> kVoicePacks = [')
    yaml = open(yaml_path, encoding='utf-8').read()
    yaml_new = replace_block(yaml, YAML_BEGIN, YAML_END, pubspec_lines(rows))

    if not args.dry_run:
        open(dart_path, 'w', encoding='utf-8').write(dart_new)
        open(yaml_path, 'w', encoding='utf-8').write(yaml_new)

    print('\n%s %d file(s)' % ('would copy' if args.dry_run else 'copied',
                               total if args.dry_run else copied))
    print('%s voice_pack.dart (%d entries) and pubspec.yaml (%d asset dirs)'
          % ('would update' if args.dry_run else 'updated', len(rows),
             len(rows) * len(CATEGORIES)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
