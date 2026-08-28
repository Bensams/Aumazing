"""Verify every background track actually loops without an audible click.

A seamless wrap means the file's last sample and its first sample are close
enough that the step across the join is no larger than an ordinary
sample-to-sample step inside the audio. Ratios well under 1.0 are inaudible;
anything above ~3 is worth listening to.

This catches the failure mode that is invisible to loudness measurement: a
stateful filter (highshelf, lowpass) applied after the loop join leaves a
startup transient at the head of the file, so the file no longer wraps onto
itself even though every other metric looks perfect.
"""

import json
import pathlib
import subprocess

import imageio_ffmpeg
import numpy as np

FF = imageio_ffmpeg.get_ffmpeg_exe()
HERE = pathlib.Path(__file__).parent
ROOT = pathlib.Path(r"E:\Projects\aumazing\packages\assets\audio\BG_Music")
RATIO_LIMIT = 3.0


def pcm(path):
    out = subprocess.run(
        [FF, "-hide_banner", "-nostdin", "-v", "error", "-i", str(path),
         "-f", "f32le", "-ac", "1", "-ar", "44100", "-"],
        capture_output=True).stdout
    return np.frombuffer(out, "<f4")


def main():
    entries = json.loads((HERE / "converted_manifest.json").read_text())
    rows = []
    for e in entries:
        f = ROOT / e["category"] / f"{e['slug']}.ogg"
        a = pcm(f)
        if len(a) < 44100:
            print(f"[skip] {e['slug']}: too short")
            continue
        seam = abs(float(a[0]) - float(a[-1]))
        internal = float(np.percentile(np.abs(np.diff(a[:44100])), 99))
        rows.append((e["slug"], seam, internal, seam / max(internal, 1e-9)))

    ratios = [r[3] for r in rows]
    bad = sorted((r for r in rows if r[3] > RATIO_LIMIT), key=lambda x: -x[3])
    (HERE / "loop_report.json").write_text(json.dumps({
        "checked": len(rows),
        "ratioLimit": RATIO_LIMIT,
        "medianRatio": round(float(np.median(ratios)), 3),
        "maxRatio": round(float(max(ratios)), 3),
        "failed": [r[0] for r in bad],
    }, indent=2), encoding="utf-8")
    print(f"checked {len(rows)} files")
    print(f"seam/internal ratio — median {np.median(ratios):.2f}  "
          f"max {max(ratios):.2f}")
    print(f"above {RATIO_LIMIT}x: {len(bad)}")
    for slug, seam, internal, ratio in bad[:10]:
        print(f"   {slug:<28} seam {seam:.5f}  internal {internal:.5f}  "
              f"ratio {ratio:.1f}")
    return 1 if bad else 0


if __name__ == "__main__":
    raise SystemExit(main())
