"""Install the shipping subset of the BGM library into shared_audio.

Picks one variant per prompt — the two variants of a prompt are the same
musical idea, so taking both would spend bundle size on near-duplicates —
re-encodes at a bundle-friendly bitrate, and generates the Dart track list.
"""

import json
import pathlib
import re
import subprocess

import imageio_ffmpeg

FF = imageio_ffmpeg.get_ffmpeg_exe()
HERE = pathlib.Path(__file__).parent
REPO = pathlib.Path(r"E:\Projects\aumazing")
MASTERS = REPO / "packages" / "assets" / "audio" / "BG_Music"
DEST = REPO / "packages" / "shared_audio" / "assets" / "audio" / "bgm"
DART = REPO / "packages" / "shared_audio" / "lib" / "src" / "bgm_library.dart"

QUALITY = "1"        # libvorbis -q:a; ~0.75 MB per 2-minute bed
PER_CATEGORY = 5     # one per prompt
MIN_DURATION = 85.0  # prefer tracks long enough not to feel repetitive

import sys
sys.path.insert(0, str(HERE))
from bgm_catalog import CATEGORIES  # noqa: E402


def slugify(title):
    return re.sub(r"[^a-z0-9]+", "_", title.lower()).strip("_")


def pick(tracks):
    """Choose the better of a prompt's variants.

    Order matters: a dropout beats every other consideration. A few seconds of
    near-silence in the middle of a bed is a startle in its own right, and it
    *lowers* the loudness range, so ranking on LRA alone actively prefers the
    broken take.
    """
    clean = [t for t in tracks if t.get("silent_gap_s", 0) <= 0.5]
    pool = clean or tracks
    long_enough = [t for t in pool if t["duration_s"] >= MIN_DURATION]
    pool = long_enough or pool
    return min(pool, key=lambda t: t["lra_lu"])


def main():
    entries = json.loads((HERE / "converted_manifest.json").read_text())
    by_cat = {}
    for e in entries:
        by_cat.setdefault(e["category"], {}).setdefault(
            e["prompt_title"], []).append(e)

    shipped = {}
    for cat_key in CATEGORIES:
        prompts = by_cat.get(cat_key, {})
        chosen = [pick(v) for v in prompts.values()][:PER_CATEGORY]
        chosen.sort(key=lambda t: t["prompt_title"])
        out_dir = DEST / cat_key
        out_dir.mkdir(parents=True, exist_ok=True)
        # Drop anything previously installed so removed picks don't linger.
        for old in out_dir.glob("*.ogg"):
            old.unlink()

        rows = []
        for t in chosen:
            src = MASTERS / cat_key / f"{t['slug']}.ogg"
            name = f"{slugify(t['prompt_title'])}.ogg"
            dest = out_dir / name
            r = subprocess.run(
                [FF, "-hide_banner", "-nostdin", "-v", "error", "-y",
                 "-i", str(src), "-c:a", "libvorbis", "-q:a", QUALITY,
                 str(dest)], capture_output=True, text=True)
            if r.returncode != 0 or dest.stat().st_size < 20_000:
                raise RuntimeError(f"{name}: {r.stderr[-600:]}")
            rows.append({
                "file": name,
                "title": t["prompt_title"],
                "durationS": t["duration_s"],
                "bytes": dest.stat().st_size,
            })
            print(f"[ok] {cat_key}/{name}  {dest.stat().st_size/1e6:.2f} MB")
        shipped[cat_key] = rows

    total = sum(r["bytes"] for rows in shipped.values() for r in rows)
    print(f"\ninstalled {sum(len(r) for r in shipped.values())} tracks, "
          f"{total/1e6:.1f} MB")

    # ── generated Dart library ──────────────────────────────────────────
    out = [
        "// GENERATED FILE — do not edit by hand.",
        "// Written by tools/bgm_gen/install_bgm.py. Re-run that script to",
        "// change which tracks ship. See docs/asd-friendly-bgm.md.",
        "",
        "/// One background-music track.",
        "///",
        "/// [title] is parent-facing — it is what the settings preview lists —",
        "/// while [file] is the asset on disk.",
        "class BgmTrack {",
        "  const BgmTrack({required this.file, required this.title});",
        "",
        "  /// Filename within the category folder.",
        "  final String file;",
        "",
        "  /// Human-readable name shown to the parent.",
        "  final String title;",
        "}",
        "",
        "/// A parent-selectable background-music category.",
        "///",
        "/// Every track in every category is instrumental, loudness-matched to",
        "/// -20 LUFS and loops seamlessly, so switching category changes the",
        "/// character of the music but never how loud or how startling it is.",
        "class BgmCategory {",
        "  const BgmCategory({",
        "    required this.key,",
        "    required this.label,",
        "    required this.description,",
        "    required this.tracks,",
        "  });",
        "",
        "  /// Stable identifier persisted in the child's profile.",
        "  final String key;",
        "",
        "  /// Short name shown to the parent.",
        "  final String label;",
        "",
        "  /// One-line guidance shown under the label in the picker.",
        "  final String description;",
        "",
        "  /// The tracks in this category, in the order the picker lists them.",
        "  final List<BgmTrack> tracks;",
        "",
        "  /// Path accepted by [AudioService.playMusic].",
        "  String trackPath(BgmTrack track) => 'bgm/$key/${track.file}';",
        "}",
        "",
        "/// The category used when a child has no stored preference.",
        "const String kDefaultBgmCategory = 'soft_relaxing';",
        "",
        "/// Every category available to the parent picker.",
        "const List<BgmCategory> kBgmCategories = <BgmCategory>[",
    ]
    for cat_key, rows in shipped.items():
        cat = CATEGORIES[cat_key]
        desc = " ".join(cat["description"].split()).replace("'", r"\'")
        out += [
            "  BgmCategory(",
            f"    key: '{cat_key}',",
            f"    label: '{cat['label']}',",
            f"    description: '{desc}',",
            "    tracks: <BgmTrack>[",
        ]
        out += [
            f"      BgmTrack(file: '{r['file']}', "
            f"title: '{r['title'].replace(chr(39), chr(92) + chr(39))}'),"
            for r in rows
        ]
        out += ["    ],", "  ),"]
    out += [
        "];",
        "",
        "/// Look up a category by its persisted [key].",
        "///",
        "/// Returns null when the key is unknown, which happens if a profile was",
        "/// written by a build that shipped a category this build does not have.",
        "BgmCategory? bgmCategoryByKey(String? key) {",
        "  for (final category in kBgmCategories) {",
        "    if (category.key == key) return category;",
        "  }",
        "  return null;",
        "}",
        "",
        "/// The category for [key], falling back to the default when unknown.",
        "BgmCategory bgmCategoryOrDefault(String? key) =>",
        "    bgmCategoryByKey(key) ?? bgmCategoryByKey(kDefaultBgmCategory)!;",
        "",
    ]
    DART.write_text("\n".join(out), encoding="utf-8")
    print(f"wrote {DART.relative_to(REPO)}")

    (HERE / "shipped_manifest.json").write_text(
        json.dumps(shipped, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
