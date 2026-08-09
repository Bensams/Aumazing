"""Minimal client for the KIE API (https://kie.ai), used here for ElevenLabs TTS.

Every KIE generation is asynchronous: POST /api/v1/jobs/createTask returns a
taskId, and the result is fetched by polling /api/v1/jobs/recordInfo until the
state settles. A 200 on createTask means "accepted", not "done".

Result URLs expire (KIE documents ~24h), so `synthesize` downloads the bytes
before returning rather than handing back a link.
"""
import io
import json
import os
import random
import threading
import time
from collections import deque

import requests

BASE_URL = os.environ.get('KIE_API_BASE', 'https://api.kie.ai').rstrip('/')
CREATE_PATH = '/api/v1/jobs/createTask'
RECORD_PATH = '/api/v1/jobs/recordInfo'

# KIE documents 20 new generation requests per 10 seconds. Stay under it.
RATE_LIMIT_CALLS = 18
RATE_LIMIT_WINDOW = 10.0

TERMINAL_OK = {'success'}
TERMINAL_FAIL = {'fail', 'failed', 'error'}

POLL_INITIAL = 2.0
POLL_MAX = 8.0
DEFAULT_TIMEOUT = 300.0


class KieError(RuntimeError):
    """A task was rejected, failed, or timed out."""


class RateLimiter:
    """Sliding-window limiter, shared across worker threads."""

    def __init__(self, calls=RATE_LIMIT_CALLS, window=RATE_LIMIT_WINDOW):
        self.calls = calls
        self.window = window
        self._hits = deque()
        self._lock = threading.Lock()

    def acquire(self):
        while True:
            with self._lock:
                now = time.monotonic()
                while self._hits and now - self._hits[0] > self.window:
                    self._hits.popleft()
                if len(self._hits) < self.calls:
                    self._hits.append(now)
                    return
                sleep_for = self.window - (now - self._hits[0]) + 0.01
            time.sleep(sleep_for)


def _iter_urls(node):
    """Yield every http(s) string anywhere in a decoded JSON structure.

    KIE nests result payloads differently per model (and the audio URL has
    lived under resultUrls, resultObject and audio_url across models), so walk
    rather than assume a key.
    """
    if isinstance(node, str):
        s = node.strip()
        if s.startswith('http://') or s.startswith('https://'):
            yield s
        elif s.startswith('{') or s.startswith('['):
            try:
                yield from _iter_urls(json.loads(s))
            except ValueError:
                pass
    elif isinstance(node, dict):
        for v in node.values():
            yield from _iter_urls(v)
    elif isinstance(node, (list, tuple)):
        for v in node:
            yield from _iter_urls(v)


class KieClient:
    def __init__(self, api_key=None, limiter=None, max_retries=4, session=None):
        self.api_key = api_key or os.environ.get('KIE_API_KEY', '')
        if not self.api_key:
            raise KieError('No API key. Set KIE_API_KEY or pass --api-key.')
        self.limiter = limiter or RateLimiter()
        self.max_retries = max_retries
        self.session = session or requests.Session()

    def _headers(self):
        return {'Authorization': 'Bearer %s' % self.api_key,
                'Content-Type': 'application/json'}

    def _request(self, method, path, **kw):
        """One API call with backoff on 429 / 5xx / transport errors."""
        url = BASE_URL + path
        last = None
        for attempt in range(self.max_retries + 1):
            try:
                r = self.session.request(method, url, headers=self._headers(),
                                         timeout=60, **kw)
            except requests.RequestException as exc:
                last = 'transport error: %s' % exc
            else:
                if r.status_code == 200:
                    try:
                        body = r.json()
                    except ValueError:
                        raise KieError('Non-JSON response from %s: %.200s'
                                       % (path, r.text))
                    code = body.get('code', 200)
                    if code not in (200, 0):
                        # Business-level failures are not retryable.
                        raise KieError('KIE %s: code=%s msg=%s'
                                       % (path, code, body.get('msg')))
                    return body.get('data') or {}
                if r.status_code in (429, 500, 502, 503, 504):
                    last = 'HTTP %d: %.200s' % (r.status_code, r.text)
                else:
                    raise KieError('KIE %s HTTP %d: %.300s'
                                   % (path, r.status_code, r.text))
            if attempt < self.max_retries:
                time.sleep(min(2 ** attempt, 16) * (1 + random.random() * 0.3))
        raise KieError('KIE %s failed after %d attempts (%s)'
                       % (path, self.max_retries + 1, last))

    def create_task(self, model, inputs, callback_url=None):
        payload = {'model': model, 'input': inputs}
        if callback_url:
            payload['callBackUrl'] = callback_url
        self.limiter.acquire()
        data = self._request('POST', CREATE_PATH, json=payload)
        task_id = data.get('taskId') or data.get('task_id')
        if not task_id:
            raise KieError('createTask returned no taskId: %r' % (data,))
        return task_id

    def wait(self, task_id, timeout=DEFAULT_TIMEOUT):
        """Poll until the task succeeds; raise on failure or timeout."""
        deadline = time.monotonic() + timeout
        delay = POLL_INITIAL
        while True:
            data = self._request('GET', RECORD_PATH, params={'taskId': task_id})
            state = str(data.get('state') or data.get('status') or '').lower()
            if state in TERMINAL_OK:
                return data
            if state in TERMINAL_FAIL:
                raise KieError('task %s failed: %s' % (
                    task_id, data.get('failMsg') or data.get('msg') or state))
            if time.monotonic() >= deadline:
                raise KieError('task %s still %r after %.0fs'
                               % (task_id, state or 'unknown', timeout))
            time.sleep(delay)
            delay = min(delay * 1.5, POLL_MAX)

    def download(self, url):
        last = None
        for attempt in range(self.max_retries + 1):
            try:
                r = self.session.get(url, timeout=120)
                if r.status_code == 200:
                    return r.content
                last = 'HTTP %d' % r.status_code
            except requests.RequestException as exc:
                last = str(exc)
            if attempt < self.max_retries:
                time.sleep(min(2 ** attempt, 16) * (1 + random.random() * 0.3))
        raise KieError('download failed (%s): %s' % (last, url))

    def synthesize(self, model, inputs, timeout=DEFAULT_TIMEOUT, task_retries=2):
        """Create, wait, and return (audio_bytes, source_url).

        A task can be accepted and still fail generation upstream (KIE reports
        these as a bare "internal error"). Those are often transient, so the
        whole create/wait cycle is retried rather than only the HTTP call.
        """
        last = None
        for attempt in range(task_retries + 1):
            task_id = self.create_task(model, inputs)
            try:
                result = self.wait(task_id, timeout=timeout)
            except KieError as exc:
                last = exc
                if attempt < task_retries:
                    time.sleep(min(2 ** attempt, 8) * (1 + random.random() * 0.3))
                    continue
                raise
            urls = list(dict.fromkeys(_iter_urls(result)))
            if not urls:
                raise KieError('task %s succeeded but exposed no result URL: %.400s'
                               % (task_id, json.dumps(result)[:400]))
            return self.download(urls[0]), urls[0]
        raise last


def decode_audio(raw):
    """Decode returned bytes (usually MP3) to (float32 mono, samplerate)."""
    import numpy as np
    import soundfile as sf
    data, sr = sf.read(io.BytesIO(raw), dtype='float32', always_2d=True)
    return np.asarray(data).mean(axis=1), sr
