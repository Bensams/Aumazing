"""Generate the ASD-friendly background-music library via the kie.ai Suno API.

Submits every prompt in bgm_catalog.CATEGORIES, polls to completion, downloads
both variants of each request, and writes a manifest for the conversion step.
"""

import concurrent.futures as cf
import json
import os
import pathlib
import time

import requests

from bgm_catalog import (AUDIO_WEIGHT, CATEGORIES, DURATION, MODEL,
                         NEGATIVE_TAGS, STYLE_WEIGHT, WEIRDNESS, build_style)

API_KEY = os.environ["KIE_API_KEY"]
BASE = "https://api.kie.ai/api/v1"
HEADERS = {"Authorization": f"Bearer {API_KEY}", "Content-Type": "application/json"}

OUT = pathlib.Path(__file__).parent / "bgm_raw"
OUT.mkdir(exist_ok=True)

TERMINAL_OK = {"SUCCESS"}
TERMINAL_BAD = {"CREATE_TASK_FAILED", "GENERATE_AUDIO_FAILED",
                "CALLBACK_EXCEPTION", "SENSITIVE_WORD_ERROR"}


def submit(title, style):
    payload = {
        "customMode": True,
        "instrumental": True,
        "model": MODEL,
        "duration": DURATION,
        "title": title,
        "style": build_style(style),
        "prompt": "instrumental",
        "negativeTags": NEGATIVE_TAGS,
        "styleWeight": STYLE_WEIGHT,
        "weirdnessConstraint": WEIRDNESS,
        "audioWeight": AUDIO_WEIGHT,
        # Required by the API but we poll instead of receiving callbacks.
        "callBackUrl": "https://example.com/callback",
    }
    # The submit endpoint rate-limits aggressively; back off and retry on 429.
    delay = 5
    for attempt in range(8):
        r = requests.post(f"{BASE}/generate", json=payload, headers=HEADERS, timeout=60)
        body = r.json()
        if body.get("code") == 200:
            return body["data"]["taskId"]
        if body.get("code") != 429:
            raise RuntimeError(f"submit failed for {title}: {body}")
        time.sleep(delay)
        delay = min(delay * 2, 60)
    raise RuntimeError(f"submit rate-limited out for {title}")


def poll(task_id, timeout=900):
    deadline = time.time() + timeout
    while time.time() < deadline:
        r = requests.get(f"{BASE}/generate/record-info",
                         params={"taskId": task_id}, headers=HEADERS, timeout=60)
        data = r.json().get("data") or {}
        status = data.get("status")
        if status in TERMINAL_OK:
            return data["response"]["sunoData"]
        if status in TERMINAL_BAD:
            raise RuntimeError(f"{task_id} failed: {status} {data.get('errorMessage')}")
        time.sleep(15)
    raise TimeoutError(task_id)


def download(url, dest):
    with requests.get(url, stream=True, timeout=180) as r:
        r.raise_for_status()
        with open(dest, "wb") as fh:
            for chunk in r.iter_content(1 << 16):
                fh.write(chunk)
    return dest.stat().st_size


def collect(cat_key, idx, title, style, task_id):
    slug = f"{cat_key}_{idx:02d}"
    tracks = poll(task_id)
    results = []
    cat_dir = OUT / cat_key
    cat_dir.mkdir(exist_ok=True)
    for variant, track in enumerate(tracks, start=1):
        dest = cat_dir / f"{slug}_v{variant}.mp3"
        size = download(track["audioUrl"], dest)
        results.append({
            "category": cat_key,
            "slug": f"{slug}_v{variant}",
            "title": f"{title} {variant}",
            "prompt_title": title,
            "style": style,
            "taskId": task_id,
            "sunoId": track["id"],
            "duration": track.get("duration"),
            "bytes": size,
            "mp3": str(dest),
        })
    print(f"[ok] {slug} -> {len(results)} tracks", flush=True)
    return results


def main():
    jobs = []
    for cat_key, cat in CATEGORIES.items():
        for idx, (title, style) in enumerate(cat["prompts"], start=1):
            jobs.append((cat_key, idx, title, style))

    # Submit serially (the endpoint rate-limits), then poll/download in parallel.
    print(f"submitting {len(jobs)} requests -> {len(jobs) * 2} tracks", flush=True)
    submitted = []
    for job in jobs:
        cat_key, idx, title, style = job
        try:
            task_id = submit(title, style)
            submitted.append((*job, task_id))
            print(f"[sub] {cat_key}_{idx:02d} {task_id}", flush=True)
        except Exception as exc:
            print(f"[SUBMIT-FAIL] {cat_key}_{idx:02d}: {exc}", flush=True)
        time.sleep(4)

    manifest = []
    with cf.ThreadPoolExecutor(max_workers=8) as pool:
        futures = {pool.submit(collect, *s): s for s in submitted}
        for fut in cf.as_completed(futures):
            s = futures[fut]
            try:
                manifest.extend(fut.result())
            except Exception as exc:
                print(f"[COLLECT-FAIL] {s[0]}_{s[1]:02d}: {exc}", flush=True)

    manifest.sort(key=lambda m: m["slug"])
    (OUT / "manifest.json").write_text(json.dumps(manifest, indent=2))
    print(f"done: {len(manifest)} tracks", flush=True)


if __name__ == "__main__":
    main()
