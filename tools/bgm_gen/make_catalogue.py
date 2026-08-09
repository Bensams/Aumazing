"""Emit the shippable manifest + the human-readable catalogue for the BGM library."""

import collections
import json
import pathlib

from convert_bgm import MIN_LOOP_LEN_S as MIN_LOOP_LEN
from bgm_catalog import (CATEGORIES, GLOBAL_STYLE_SUFFIX, NEGATIVE_TAGS,
                         STYLE_WEIGHT, WEIRDNESS, MODEL)

HERE = pathlib.Path(__file__).parent
REPO = pathlib.Path(r"E:\Projects\aumazing")
DEST_ROOT = REPO / "packages" / "assets" / "audio" / "BG_Music"

tracks = json.loads((HERE / "converted_manifest.json").read_text())

# What actually ships in the app bundle, as chosen by install_bgm.py.
_shipped = json.loads((HERE / "shipped_manifest.json").read_text())
shipped_count = sum(len(v) for v in _shipped.values())
shipped_mb = sum(r["bytes"] for v in _shipped.values() for r in v) / 1e6
by_cat = collections.defaultdict(list)
for t in tracks:
    by_cat[t["category"]].append(t)
for v in by_cat.values():
    v.sort(key=lambda t: t["slug"])

# ── machine-readable manifest, for the parent picker to read ─────────────
manifest = {
    "schemaVersion": 1,
    "generator": f"kie.ai Suno {MODEL}",
    "loudnessTargetLufs": -20.0,
    "categories": [
        {
            "key": key,
            "label": CATEGORIES[key]["label"],
            "description": " ".join(CATEGORIES[key]["description"].split()),
            "tracks": [
                {
                    "slug": t["slug"],
                    "title": t["title"],
                    "file": f"{key}/{t['slug']}.ogg",
                    "durationS": t["duration_s"],
                    "lufs": t["lufs"],
                    "lraLu": t["lra_lu"],
                }
                for t in by_cat[key]
            ],
        }
        for key in CATEGORIES if by_cat[key]
    ],
}
(DEST_ROOT / "bgm_manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")

# ── markdown catalogue ──────────────────────────────────────────────────
total = len(tracks)
flagged = [t for t in tracks if t.get("qa_flag")]

lines = [
    "# ASD-friendly background music library",
    "",
    f"{total} instrumental background tracks across {len(manifest['categories'])} "
    "parent-selectable categories, generated for Aumazing via the kie.ai Suno "
    f"`{MODEL}` API. Every track is designed as a *bed* — something a child can "
    "have running for twenty minutes without it ever demanding attention or "
    "producing a startle.",
    "",
    "> **Licence status: unresolved.** These files are KIE-generated and fall "
    "under exactly the same open question as the voice library — see "
    "[audio-licensing.md](audio-licensing.md) §1. Do not ship them commercially "
    "until KIE's position on redistribution is in writing.",
    "",
    "## Why these constraints",
    "",
    "Autistic children show elevated rates of auditory hypersensitivity and of "
    "distress at unpredictable sound. The design rules below follow from that: "
    "the risk in a children's game is not that the music is boring, it is that "
    "the music *startles*, masks the voice-over, or adds sensory load on top of "
    "the task the child is trying to do.",
    "",
    "| Rule | Why |",
    "|---|---|",
    "| **Instrumental only, no vocals** | Lyrics compete with the app's spoken "
    "prompts for the same language-processing channel, and the voice-over is the "
    "part that carries the instruction. |",
    "| **56–80 BPM, never changing** | Sits at or below resting heart rate. A "
    "constant tempo means the child's prediction of what comes next is never "
    "violated. |",
    "| **Narrow loudness range (target ≤7 LU)** | No crescendos, no swells, no "
    "sudden accents — the single most common startle source in game music. "
    "Measured per track below. |",
    "| **No percussion or transients** | Drum hits, cymbals and stabs are sharp "
    "onsets. Soft, rounded attacks (felt piano, mallets, pads) are not. |",
    "| **Treble shelved −4 dB above 6 kHz, low-passed at 13 kHz** | Auditory "
    "hypersensitivity is most often reported in the upper frequencies. |",
    "| **Normalised to −20 LUFS** | Deliberately quiet, so music never competes "
    "with speech. The voice-over stays clearly on top at any music volume. |",
    "| **Seamless loop, no fade to silence** | The tail is crossfaded into the "
    "head, so a 20-minute session has no repeating dip to silence to notice. |",
    "| **Consonant, simple, repeating** | Predictability is the point. No key "
    "changes, no dissonance, no development. |",
    "",
    "Two of these are enforced mechanically rather than by prompting: loudness "
    "and the loop join are done in post with ffmpeg, because a generative model "
    "cannot be trusted to hit them reliably.",
    "",
    "## Categories",
    "",
    "Categories differ by *arousal level and timbre*, not by how strictly the "
    "rules apply — the rules above hold for all of them. This is what the parent "
    "picker should expose, ideally with the guidance text as a subtitle.",
    "",
]

for cat in manifest["categories"]:
    key = cat["key"]
    lines += [
        f"### {cat['label']}  (`{key}`)",
        "",
        cat["description"],
        "",
        "| # | Track | Length | Loudness | Range |",
        "|---|---|---|---|---|",
    ]
    for i, t in enumerate(by_cat[key], start=1):
        flag = " ⚠️" if next(
            (x for x in tracks if x["slug"] == t["slug"] and x.get("qa_flag")), None
        ) else ""
        lines.append(
            f"| {i} | {t['title']}{flag} | {t['duration_s']:.0f}s | "
            f"{t['lufs']:.1f} LUFS | {t['lra_lu']:.1f} LU |"
        )
    lines.append("")

lines += [
    "## Verification",
    "",
    f"Every file was measured after conversion. {total - len(flagged)} of {total} "
    "passed both checks: loudness range at or under 7 LU, and no near-silent "
    "dropout longer than half a second.",
    "",
]
if flagged:
    lines += ["These did not, and should be auditioned before use:", ""]
    lines += [f"- `{t['slug']}` — {t['qa_flag']}" for t in flagged]
    lines += [""]
else:
    lines += ["No track exceeded the ceiling.", ""]

loop = json.loads((HERE / "loop_report.json").read_text())
lines += [
    f"**Loop joins.** All {loop['checked']} files were checked for the wrap "
    "being seamless, by comparing the step from the last sample back to the "
    "first against a normal sample-to-sample step inside the same file. Median "
    f"ratio {loop['medianRatio']}, worst {loop['maxRatio']} — i.e. the join is "
    "typically a *smaller* jump than the audio's own movement, so it is "
    f"inaudible. {len(loop['failed'])} files exceeded the "
    f"{loop['ratioLimit']}x threshold.",
    "",
    "This check earns its place: the first render passed every loudness metric "
    "while half the files had an audible click at the wrap, because the "
    "tone-shaping IIR filters ran *after* the join and left a startup transient "
    "on the first ~20 ms. Loudness measurement cannot see that. Re-run "
    "`check_loops.py` after any change to the filter chain.",
    "",
    "**Take the loudness flags seriously.** It is tempting to dismiss a wide "
    "range on sparse material as the measurement counting the gaps between "
    "phrases rather than a real crescendo. That reasoning was applied to the "
    "worst-scoring track in the first build, and it was wrong: a listener "
    "immediately described it as eerie coming in and going out. The flag was a "
    "true positive. Audition flagged tracks; do not argue them away.",
    "",
    "**The dropout check exists because loudness range actively hides them.** "
    "Silence lowers a track's measured range, so ranking on LRA alone *prefers* "
    "a take with a hole in it — two replacement candidates scored best in their "
    "batch while containing seven seconds of digital silence. A dropout mid-bed "
    "is a startle in its own right, so it now outranks every other criterion "
    "when choosing which take ships.",
    "",
    "What the measurements do **not** cover: whether a track is musically "
    "pleasant, whether it suits the game it plays under, whether the nature "
    "textures read as 'rain' rather than 'hiss', and whether a loop that is "
    "seamless at the sample level is still *musically* satisfying to hear "
    "repeat every two minutes. Those need a listen, ideally with a child.",
    "",
    "## Reproducing / extending",
    "",
    "Scripts are in `tools/bgm_gen/`. The generation contract:",
    "",
    "```",
    f"model            {MODEL}   (only V5_5 honours `duration`)",
    "instrumental     true",
    "duration         120 s",
    f"styleWeight      {STYLE_WEIGHT}    hold the requested style hard",
    f"weirdnessConstraint {WEIRDNESS}   allow almost no creative deviation",
    "```",
    "",
    "Three behaviours are not in kie.ai's documentation, and the first two will "
    "fail a whole batch:",
    "",
    "- `negativeTags` is capped at **200 characters** (422 above that).",
    "- `/api/v1/generate` rate-limits hard on concurrent submits — submit "
    "serially with a delay, then poll in parallel.",
    "- `duration` is a *request*, not a guarantee. Asking for 120 s returned "
    f"anything from {min(t['duration_s'] for t in tracks):.0f} s to "
    f"{max(t['duration_s'] for t in tracks):.0f} s after trimming. Since these "
    "loop, short tracks are usable — but do not assume a fixed length.",
    "",
    "**Where the loop starts is the subtlest part of this pipeline.** Both "
    "ends of a finished file are cut from the same point, so whatever sits "
    "there is heard twice per lap. Suno almost always opens from silence with "
    "a swell — on the track this was first noticed on, -88 dB to -9.5 dB in "
    "4.5 seconds — and starting at zero puts that swell on the intro *and* the "
    "outro. It reads as eerie, and no loudness metric catches it.",
    "",
    "Naively skipping the intro is not enough: on a track that swells all the "
    "way through, the next point is just as uneven, and skipping far enough in "
    "buys flatness by leaving a short, repetitive loop. The converter searches "
    "for the steadiest window instead, scoring across both the tail region and "
    "the opening, and refuses points that would cut the loop below "
    f"{MIN_LOOP_LEN}s. Measured over the worst offenders plus controls, that "
    "took the mean dip at the loop boundary from -11.8 dB to -7.3 dB with no "
    "track regressing.",
    "",
    "One ffmpeg trap is worth recording too: `acrossfade` yields **zero "
    "frames** when both its inputs are `asplit` branches of the same source, "
    "and ffmpeg still exits 0. The conversion cuts head and body to real files "
    "first, and asserts a minimum output size, because a silent success here "
    "otherwise looks identical to a real one.",
    "",
    "Shared negative prompt (at the 200-char limit):",
    "",
    "```",
    NEGATIVE_TAGS,
    "```",
    "",
    "Shared style suffix appended to every category prompt:",
    "",
    "```",
    GLOBAL_STYLE_SUFFIX,
    "```",
    "",
    "## How it is wired into the app",
    "",
    "Implemented. The parent picks a **category**; the app picks one track "
    "from it per session and loops that track. Music never changes underneath "
    "a child mid-session — variety comes from the next session's pick.",
    "",
    "| Piece | Where |",
    "|---|---|",
    "| Track list (generated) | `packages/shared_audio/lib/src/bgm_library.dart` |",
    "| Playback | `AudioService.playCategoryMusic()` |",
    "| Stored choice | `ChildProfile.musicCategory`, children table v16 |",
    "| Picker UI | Settings → Audio → Music Style |",
    "| Session pick | `GameFlowScreen.initState` (`restart: true`) |",
    "| Bundle guard | `packages/shared_audio/test/bgm_asset_bundle_test.dart` |",
    "",
    "Only a subset of the library ships, to keep the bundle down — "
    f"{shipped_count} tracks ({shipped_mb:.1f} MB) out of {total}. The rest "
    "stay here as masters; `tools/bgm_gen/install_bgm.py` chooses which ship "
    "and regenerates `bgm_library.dart`.",
    "",
    "Three behaviours are deliberate and easy to undo by accident:",
    "",
    "- **`playCategoryMusic` no-ops when the same category is already "
    "playing**, so rebuilds and lifecycle callbacks cannot restart the track "
    "mid-session. Only `restart: true` forces a new pick.",
    "- **Loading and login play the default category**, because no profile is "
    "loaded yet; `HomeScreen` switches to the child's own category once it "
    "is. That is the one mid-run change, and it lands before any game.",
    "- **The picker previews immediately** (`restart: true`). That is the "
    "exception to the rule above, and it is intentional: the parent is "
    "listening on purpose and needs to hear what they picked.",
    "",
    "An unknown category key — a profile written by a build that shipped a "
    "category this build does not have — falls back to the default rather "
    "than leaving the child in silence.",
    "",
]

(REPO / "docs" / "asd-friendly-bgm.md").write_text("\n".join(lines), encoding="utf-8")
print(f"wrote manifest ({total} tracks) and docs/asd-friendly-bgm.md")
