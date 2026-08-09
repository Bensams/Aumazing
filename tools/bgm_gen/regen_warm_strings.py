"""Regenerate 'Warm Strings Haze'.

The original was reported as eerie at the intro and the end. Two causes: the
loop head was cut from Suno's fade-in swell (fixed in convert_bgm.py), and
sustained string pads drift toward minor/suspense colour unless the prompt
pins them to a major key. This pins them, and bans the horror vocabulary
outright.
"""

import concurrent.futures as cf
import json
import os
import pathlib
import time

import requests

API_KEY = os.environ["KIE_API_KEY"]
BASE = "https://api.kie.ai/api/v1"
HEADERS = {"Authorization": f"Bearer {API_KEY}", "Content-Type": "application/json"}
OUT = pathlib.Path(__file__).parent / "bgm_regen"
OUT.mkdir(exist_ok=True)

# Deliberately harsher than the library default: every word here is a colour
# this track drifted into.
NEGATIVE = (
    "vocals, drums, percussion, crescendo, swell, fade in, eerie, haunting, "
    "ominous, suspense, horror, minor key, dissonance, tremolo, sudden "
    "dynamics, tempo change, loud, dramatic, tension"
)

SUFFIX = (
    "instrumental only, bright major key throughout, warm and consonant, "
    "starts immediately at full level with no fade in, completely steady "
    "volume, no swells or crescendos, simple repeating chord cycle, "
    "reassuring and gentle, mixed quiet as a background bed under speech"
)

CANDIDATES = [
    ("Warm Strings Haze",
     "gentle warm string ensemble in C major, 58 BPM, soft sustained major "
     "triads, no vibrato, close and intimate, like a slow lullaby harmony"),
    ("Warm Strings Haze",
     "soft warm cello and viola ensemble in F major, 60 BPM, smooth sustained "
     "consonant chords, mellow and rounded, comforting and simple"),
    ("Warm Strings Haze",
     "warm string pad with soft felt piano in G major, 58 BPM, sustained "
     "gentle major harmony, calm and even, tender and safe"),
]


def submit(title, style):
    payload = {
        "customMode": True, "instrumental": True, "model": "V5_5",
        "duration": 120, "title": title,
        "style": f"{style}, {SUFFIX}",
        "prompt": "instrumental",
        "negativeTags": NEGATIVE,
        "styleWeight": 0.85, "weirdnessConstraint": 0.05, "audioWeight": 0.65,
        "callBackUrl": "https://example.com/callback",
    }
    delay = 5
    for _ in range(8):
        body = requests.post(f"{BASE}/generate", json=payload,
                             headers=HEADERS, timeout=60).json()
        if body.get("code") == 200:
            return body["data"]["taskId"]
        if body.get("code") != 429:
            raise RuntimeError(body)
        time.sleep(delay)
        delay = min(delay * 2, 60)
    raise RuntimeError("rate limited out")


def poll(task_id, timeout=900):
    end = time.time() + timeout
    while time.time() < end:
        d = requests.get(f"{BASE}/generate/record-info",
                         params={"taskId": task_id},
                         headers=HEADERS, timeout=60).json().get("data") or {}
        if d.get("status") == "SUCCESS":
            return d["response"]["sunoData"]
        if d.get("status", "").endswith(("FAILED", "ERROR", "EXCEPTION")):
            raise RuntimeError(d)
        time.sleep(15)
    raise TimeoutError(task_id)


def main():
    tasks = []
    for i, (title, style) in enumerate(CANDIDATES, start=1):
        tasks.append((i, submit(title, style)))
        print(f"[sub] candidate {i}", flush=True)
        time.sleep(4)

    manifest = []
    with cf.ThreadPoolExecutor(max_workers=3) as pool:
        futs = {pool.submit(poll, t): i for i, t in tasks}
        for fut in cf.as_completed(futs):
            i = futs[fut]
            for v, track in enumerate(fut.result(), start=1):
                dest = OUT / f"cand{i}_v{v}.mp3"
                with requests.get(track["audioUrl"], stream=True,
                                  timeout=180) as r:
                    r.raise_for_status()
                    dest.write_bytes(r.content)
                manifest.append({"cand": i, "variant": v, "mp3": str(dest),
                                 "duration": track.get("duration")})
                print(f"[ok] {dest.name} {track.get('duration')}s", flush=True)

    (OUT / "manifest.json").write_text(json.dumps(manifest, indent=2))
    print(f"done: {len(manifest)} candidates")


if __name__ == "__main__":
    main()
