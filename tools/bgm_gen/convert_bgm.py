"""Turn the raw Suno MP3s into loop-ready, level-matched OGG background beds.

Per track:
  1. Find where the track settles, and start the loop region there. Suno almost
     always opens from silence with a swell; because the loop's head and its
     tail are the same material, cutting the head from that swell puts the
     crescendo on BOTH ends of the file. That is what makes an otherwise calm
     pad sound eerie coming in and going out.
  2. Trim Suno's tail fade (the last few seconds always ramp to silence).
  3. Wrap the tail into the head with a crossfade so the file loops seamlessly
     under AudioService's ReleaseMode.loop.
  4. Gently shelve off harsh treble (auditory hypersensitivity).
  5. Normalise to -20 LUFS so music sits under the voice-over, never over it.
  6. Measure loudness range and reject anything too dynamic to be a calm bed.
"""

import json
import pathlib
import subprocess
import sys

import imageio_ffmpeg
import numpy as np

FFMPEG = imageio_ffmpeg.get_ffmpeg_exe()
HERE = pathlib.Path(__file__).parent
RAW = HERE / "bgm_raw"
DEST_ROOT = pathlib.Path(r"E:\Projects\aumazing\packages\assets\audio\BG_Music")

TAIL_TRIM = 3.0      # seconds of Suno's fade-out to discard
XFADE = 2.5          # seconds of tail-into-head crossfade
TARGET_LUFS = -20.0  # background bed, leaves headroom for speech
LRA_LIMIT = 7.0      # loudness range above this is too dynamic for a calm bed

SEARCH_MAX_S = 40.0    # how far in to look for a good loop point
SEARCH_STEP_S = 0.5    # resolution of that search
MIN_LOOP_LEN_S = 75.0  # don't buy flatness with a short, repetitive loop


def level_envelope(path, win=0.25, sr=22050):
    """Short-term loudness of a file, in dB, one value per `win` seconds."""
    raw = subprocess.run(
        [FFMPEG, "-hide_banner", "-nostdin", "-v", "error", "-i", str(path),
         "-f", "f32le", "-ac", "1", "-ar", str(sr), "-"],
        capture_output=True).stdout
    a = np.frombuffer(raw, "<f4")
    step = int(sr * win)
    if len(a) < step * 4:
        return np.array([]), win
    env = np.array([np.sqrt(np.mean(a[i:i + step] ** 2))
                    for i in range(0, len(a) - step, step)])
    return 20 * np.log10(np.maximum(env, 1e-6)), win


def find_loop_start(path, latest, body_end):
    """Pick where the loop should begin: the steadiest window in the track.

    Both ends of the finished file are made from `[loop_start, +XFADE]`, so
    whatever is here is heard twice per lap. Suno usually opens from silence
    with a swell, and starting at 0 puts that swell on both ends — which is
    what makes an otherwise calm pad sound eerie coming in and going out.

    Naively "skip past the intro" is not enough: on a track that swells all the
    way through, the next point can be just as uneven. So this scores candidate
    windows on how close they sit to the track's own median level and how
    little they move within themselves, and takes the best.
    """
    db, win = level_envelope(path)
    if db.size == 0:
        return 0.0
    median = float(np.median(db))
    # Score twice the crossfade: [loop_start, +XFADE] becomes the file's tail,
    # and the audio immediately after it becomes the file's opening. Scoring
    # only the first half optimises the tail and lets the opening land in a
    # hole.
    span = int(2 * XFADE / win)
    scored = []

    for start in np.arange(0.0, min(latest, SEARCH_MAX_S), SEARCH_STEP_S):
        i = int(start / win)
        window = db[i:i + span]
        if window.size < span:
            break
        # Penalise being off the track's normal level, and penalise moving
        # about within the window. Movement matters more: a window that is
        # quiet but steady still loops cleanly.
        score = abs(float(window.mean()) - median) + 1.5 * float(window.std())
        out_len = body_end - (float(start) + XFADE)
        scored.append((float(start), score, out_len))

    if not scored:
        return 0.0

    # A later loop point buys flatness by throwing away the front of the track,
    # and a 30-second loop going round every half minute is its own irritant.
    # So only consider points that keep the loop reasonably long; if none do,
    # fall back to whichever keeps the most.
    roomy = [s for s in scored if s[2] >= MIN_LOOP_LEN_S]
    if roomy:
        return min(roomy, key=lambda s: s[1])[0]
    return max(scored, key=lambda s: s[2])[0]


def run(args):
    return subprocess.run([FFMPEG, "-hide_banner", "-nostdin", *args],
                          capture_output=True, text=True)


def probe_duration(path):
    out = run(["-i", str(path), "-f", "null", "-"]).stderr
    for line in reversed(out.splitlines()):
        if "time=" in line:
            stamp = line.split("time=")[1].split()[0]
            h, m, s = stamp.split(":")
            return int(h) * 3600 + int(m) * 60 + float(s)
    raise RuntimeError(f"could not probe {path}")


def measure(path):
    """Return loudnorm's analysis of a file (integrated LUFS, LRA, true peak)."""
    res = run(["-i", str(path), "-af",
               "loudnorm=I=-20:TP=-2:LRA=7:print_format=json", "-f", "null", "-"])
    blob = res.stderr[res.stderr.rindex("{"):res.stderr.rindex("}") + 1]
    return json.loads(blob)


def convert(src, dest):
    total = probe_duration(src)
    body_end = total - TAIL_TRIM

    # Leave at least 3 crossfades of body after the head, so a late loop point
    # cannot truncate the track to nothing.
    latest = max(0.0, body_end - XFADE * 4)
    loop_start = find_loop_start(src, latest, body_end)

    body_start = loop_start + XFADE
    if body_end - body_start < XFADE * 2:
        raise RuntimeError(f"{src.name} too short ({total:.1f}s)")

    # [head] = loop_start..+XFADE, [body] = the rest up to the tail trim.
    # Crossfading body into head makes the output's last XFADE seconds
    # identical to its own first ones — which is exactly why head must not come
    # from the intro swell: whatever is here is heard at BOTH ends.
    # acrossfade deadlocks when both of its inputs are asplit branches of the
    # same source, so cut body and head to real files first, then join them.
    tmp = dest.parent / f".{dest.stem}"
    body_wav, head_wav = tmp.with_suffix(".body.wav"), tmp.with_suffix(".head.wav")
    eq_wav = tmp.with_suffix(".eq.wav")
    try:
        # Tone-shape FIRST, on the whole source. highshelf and lowpass are IIR
        # filters: applied after the join they leave a startup transient on the
        # file's first ~20 ms while its end is fully settled, which is itself a
        # discontinuity at the loop wrap. Filtering upstream means both cut
        # points come from already-settled audio.
        r = run(["-y", "-i", str(src), "-af",
                 "highshelf=f=6000:g=-4,lowpass=f=13000,aresample=44100",
                 "-c:a", "pcm_s16le", "-ac", "2", str(eq_wav)])
        if r.returncode != 0:
            raise RuntimeError(r.stderr[-1200:])

        for out_path, start, end in ((body_wav, body_start, body_end),
                                     (head_wav, loop_start, loop_start + XFADE)):
            r = run(["-y", "-i", str(eq_wav), "-ss", str(start), "-to", str(end),
                     "-c:a", "pcm_s16le", "-ac", "2", str(out_path)])
            if r.returncode != 0:
                raise RuntimeError(r.stderr[-1200:])

        # Join the loop. No stateful filters here — nothing to warm up.
        joined = tmp.with_suffix(".join.wav")
        res = run(["-y", "-i", str(body_wav), "-i", str(head_wav),
                   "-filter_complex",
                   f"[0:a][1:a]acrossfade=d={XFADE}:c1=tri:c2=tri[out]",
                   "-map", "[out]",
                   "-c:a", "pcm_s16le", "-ac", "2", str(joined)])
        if res.returncode != 0:
            raise RuntimeError(res.stderr[-1500:])

        # Measure, then apply a single static gain. loudnorm's one-pass mode
        # rides the gain over time, which would both compress the dynamics we
        # deliberately kept narrow and break the loop join's start/end match.
        stats = measure(joined)
        gain = TARGET_LUFS - float(stats["input_i"])
        # Keep true peak under -2 dBTP without engaging a limiter.
        gain = min(gain, -2.0 - float(stats["input_tp"]))
        res = run(["-y", "-i", str(joined), "-af", f"volume={gain:.2f}dB",
                   "-c:a", "libvorbis", "-q:a", "4", "-ac", "2", str(dest)])
        joined.unlink(missing_ok=True)
        if res.returncode != 0:
            raise RuntimeError(res.stderr[-1500:])
    finally:
        for p in (body_wav, head_wav, eq_wav):
            p.unlink(missing_ok=True)
    # ffmpeg exits 0 even when the filter graph produced no frames, so check.
    if dest.stat().st_size < 20_000:
        raise RuntimeError(f"empty output ({dest.stat().st_size} B): "
                           f"{res.stderr[-800:]}")
    return loop_start


def main():
    manifest = json.loads((RAW / "manifest.json").read_text())
    out_manifest = []
    warnings = []

    for entry in manifest:
        src = pathlib.Path(entry["mp3"])
        cat_dir = DEST_ROOT / entry["category"]
        cat_dir.mkdir(parents=True, exist_ok=True)
        dest = cat_dir / f"{entry['slug']}.ogg"
        try:
            loop_start = convert(src, dest)
        except Exception as exc:
            warnings.append(f"{entry['slug']}: CONVERT FAILED {exc}")
            continue

        stats = measure(dest)
        lra = float(stats["input_lra"])
        entry_out = {
            **{k: entry[k] for k in
               ("category", "slug", "title", "prompt_title", "style", "sunoId")},
            "file": str(dest.relative_to(DEST_ROOT.parents[3])).replace("\\", "/"),
            "duration_s": round(probe_duration(dest), 2),
            "loop_start_s": round(loop_start, 2),
            "lufs": round(float(stats["input_i"]), 2),
            "lra_lu": round(lra, 2),
            "true_peak_db": round(float(stats["input_tp"]), 2),
            "bytes": dest.stat().st_size,
        }
        # A dropout is worse than a wide loudness range and LRA barely sees it:
        # one candidate measured the *best* LRA in its batch while containing
        # seven seconds of digital silence. Sudden silence is its own startle.
        db, win = level_envelope(dest)
        gap_s = float((db < np.median(db) - 25).sum()) * win
        if gap_s > 0.5:
            entry_out["qa_flag"] = f"{gap_s:.1f}s of near-silence (dropout)"
            warnings.append(f"{entry['slug']}: {gap_s:.1f}s near-silent")
        elif lra > LRA_LIMIT:
            entry_out["qa_flag"] = f"loudness range {lra:.1f} LU exceeds {LRA_LIMIT} LU"
            warnings.append(f"{entry['slug']}: LRA {lra:.1f} LU")
        entry_out["silent_gap_s"] = round(gap_s, 2)
        out_manifest.append(entry_out)
        print(f"[ok] {entry_out['file']}  {entry_out['duration_s']}s  "
              f"LRA {lra:.1f}LU", flush=True)

    (HERE / "converted_manifest.json").write_text(json.dumps(out_manifest, indent=2))
    print(f"\nconverted {len(out_manifest)} tracks")
    if warnings:
        print("WARNINGS:")
        for w in warnings:
            print("  " + w)


if __name__ == "__main__":
    sys.exit(main())
