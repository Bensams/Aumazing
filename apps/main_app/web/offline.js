(function () {
  'use strict';

  // The loading page. Before the app starts, it saves every file a child
  // needs into the offline cache — the app itself, pictures, sound effects,
  // music, and the voice lines for the child's language — so a game never
  // stops to wait for a picture or a voice line, and the app keeps working
  // with no connection. Voices for other languages follow in the background
  // once the app is running.
  //
  // The files go into the same cache the offline service worker
  // (offline_sw.js) serves from, tagged the same way, so the worker's install
  // finds them already saved instead of downloading them a second time.
  // offline_manifest.json (tool/build_offline_web.dart) lists every file with
  // its content hash and size.

  const CACHE_PREFIX = 'aumazing-offline-';
  const REV_HEADER = 'x-aumazing-rev';
  const MANIFEST_PATH = 'offline_manifest.json';
  const BASE = new URL('.', document.baseURI);

  const FOREGROUND_CONCURRENCY = 8;
  const BACKGROUND_CONCURRENCY = 2;
  // After this long a parent may start before everything is saved.
  const OFFER_START_AFTER_MS = 20000;
  const BACKGROUND_DELAY_MS = 15000;

  // Only opened on request (install guide, licences), never mid-game.
  const ON_DEMAND = new Set(['ios-install-guide.png', 'assets/NOTICES']);
  const AUDIO_DIR = 'assets/packages/shared_audio/assets/audio/';
  const FALLBACK_DIR = 'audio_fallback/';
  const VOICE_PACK = /^assets\/packages\/shared_audio\/assets\/audio\/voice_over\/([a-z]+)_[^/]+\//;

  // ── Page ────────────────────────────────────────────────────────────────

  const ui = (() => {
    const root = document.getElementById('aumazing-loader');
    const find = (id) => document.getElementById(id);
    const bar = find('aumazing-loader-bar');
    const title = find('aumazing-loader-title');
    const detail = find('aumazing-loader-detail');
    const actions = find('aumazing-loader-actions');
    const retry = find('aumazing-loader-retry');
    const skip = find('aumazing-loader-skip');
    const meter = find('aumazing-loader-meter');
    const mb = (bytes) => (bytes / 1048576).toFixed(0);
    return {
      progress(done, total) {
        if (!root) return;
        root.classList.add('aumazing-loader-downloading');
        const pct = total > 0 ? Math.min(100, Math.floor((done / total) * 100)) : 100;
        bar.style.width = pct + '%';
        meter.setAttribute('aria-valuenow', String(pct));
        detail.textContent = `${pct}% · ${mb(done)} of ${mb(total)} MB`;
      },
      message(heading, text) {
        if (!root) return;
        title.textContent = heading;
        if (text !== undefined) detail.textContent = text;
      },
      offerStart(onStart, onRetry) {
        if (!root) return;
        actions.hidden = false;
        skip.hidden = !onStart;
        skip.onclick = onStart || null;
        retry.hidden = !onRetry;
        retry.onclick = onRetry || null;
      },
      stopProgress() {
        if (root) root.classList.remove('aumazing-loader-downloading');
      },
      hideActions() {
        if (actions) actions.hidden = true;
      },
      hide() {
        if (!root) return;
        root.classList.add('aumazing-loader-done');
        setTimeout(() => root.remove(), 400);
      },
    };
  })();

  // ── Starting the app ────────────────────────────────────────────────────

  let started = false;
  const whenStarted = [];

  function startApp() {
    if (started) return;
    started = true;
    ui.hideActions();
    ui.stopProgress();
    ui.message('Starting Aumazing…');
    window.addEventListener('flutter-first-frame', () => {
      ui.hide();
      whenStarted.forEach((fn) => fn());
    }, { once: true });
    const script = document.createElement('script');
    script.src = 'flutter_bootstrap.js';
    script.async = true;
    document.body.appendChild(script);
  }

  // ── Cache helpers (same keys and tags as offline_sw.js) ─────────────────

  function cacheKey(path) {
    return new URL(path.split('/').map(encodeURIComponent).join('/'), BASE).href;
  }

  async function isSaved(cache, path, rev) {
    const hit = await cache.match(cacheKey(path));
    return !!hit && hit.headers.get(REV_HEADER) === rev;
  }

  async function save(cache, olderCaches, path, rev) {
    const key = cacheKey(path);
    for (const older of olderCaches) {
      const res = await older.match(key);
      if (res && res.headers.get(REV_HEADER) === rev) {
        await cache.put(key, res);
        return;
      }
    }
    const fresh = await fetch(key, { cache: 'no-cache' });
    if (!fresh.ok) throw new Error(`${path}: HTTP ${fresh.status}`);
    const headers = new Headers(fresh.headers);
    headers.set(REV_HEADER, rev);
    await cache.put(key, new Response(await fresh.blob(), {
      status: 200, statusText: 'OK', headers,
    }));
  }

  // Runs [task] over [items], [limit] at a time; returns the items that failed.
  async function pool(items, limit, task, onDone) {
    let next = 0;
    const failed = [];
    async function worker() {
      while (next < items.length) {
        const item = items[next++];
        try {
          await task(item);
        } catch (e) {
          failed.push(item);
          console.warn('[loader]', e && e.message ? e.message : e);
        }
        if (onDone) onDone(item);
      }
    }
    await Promise.all(Array.from({ length: Math.min(limit, items.length) }, worker));
    return failed;
  }

  // ── What to save ────────────────────────────────────────────────────────

  // Languages the children on this device play in (saved by the app as
  // `language_<child>` / `voice_pack_<child>`). English before any child has
  // been set up, since it is the app's default.
  function chosenLanguages() {
    const langs = new Set();
    try {
      for (let i = 0; i < localStorage.length; i++) {
        const key = localStorage.key(i) || '';
        if (!key.startsWith('flutter.language_') && !key.startsWith('flutter.voice_pack_')) continue;
        const value = JSON.parse(localStorage.getItem(key));
        if (typeof value === 'string' && value) langs.add(value.split('_')[0]);
      }
    } catch (_) {
      // Storage blocked: fall through to the default.
    }
    if (langs.size === 0) langs.add('en');
    return langs;
  }

  // Splits the build into files to save before play ([now]) and after the
  // app has started ([later]). Music the browser cannot play, and pages only
  // opened on request, are left out entirely.
  function plan(manifest) {
    const langs = chosenLanguages();
    const oggOk = !!document.createElement('audio')
      .canPlayType('audio/ogg; codecs="vorbis"');
    const now = [];
    const later = [];
    for (const [path, rev] of Object.entries(manifest.core)) now.push([path, rev]);
    for (const [path, rev] of Object.entries(manifest.lazy)) {
      if (ON_DEMAND.has(path)) continue;
      // Same choice as the app's music player: .ogg where the browser plays
      // it, otherwise the .mp3 copy under audio_fallback/.
      if (path.startsWith(FALLBACK_DIR)) {
        if (oggOk) continue;
      } else if (!oggOk && path.startsWith(AUDIO_DIR) && path.endsWith('.ogg')) {
        const mp3 = FALLBACK_DIR + path.slice(AUDIO_DIR.length).replace(/\.ogg$/, '.mp3');
        if (mp3 in manifest.lazy) continue;
      }
      const pack = VOICE_PACK.exec(path);
      (pack && !langs.has(pack[1]) ? later : now).push([path, rev]);
    }
    return { now, later };
  }

  // ── Service worker ──────────────────────────────────────────────────────

  function withTimeout(promise, ms) {
    return Promise.race([
      promise,
      new Promise((resolve) => setTimeout(() => resolve(null), ms)),
    ]);
  }

  // The build version the running worker serves, or null.
  function workerVersion(worker) {
    return withTimeout(new Promise((resolve) => {
      const channel = new MessageChannel();
      channel.port1.onmessage = (event) => resolve(event.data || null);
      worker.postMessage({ type: 'version' }, [channel.port2]);
    }), 3000);
  }

  // Registers the worker and waits (briefly) until it serves this page, so
  // the app's own files then come from the cache rather than the network.
  async function takeOver() {
    try {
      await navigator.serviceWorker.register('offline_sw.js');
      if (navigator.storage && navigator.storage.persist) {
        navigator.storage.persist().catch(() => {});
      }
      if (navigator.serviceWorker.controller) return;
      await withTimeout(navigator.serviceWorker.ready, 15000);
      if (navigator.serviceWorker.controller) return;
      await withTimeout(new Promise((resolve) => {
        navigator.serviceWorker.addEventListener('controllerchange', resolve, { once: true });
      }), 3000);
    } catch (e) {
      console.warn('[loader] offline worker unavailable:', e.message);
    }
  }

  // ── The loading flow ────────────────────────────────────────────────────

  async function loadManifest() {
    const controller = navigator.serviceWorker.controller;
    if (controller) {
      // A returning visit: check the version that is actually running.
      const running = await workerVersion(controller);
      if (running && running.cache) {
        const cache = await caches.open(running.cache);
        const res = await cache.match(cacheKey(MANIFEST_PATH));
        if (res) return { manifest: await res.json(), cacheName: running.cache };
      }
    }
    const res = await fetch(cacheKey(MANIFEST_PATH), { cache: 'no-store' });
    if (!res.ok) throw new Error(`offline manifest: HTTP ${res.status}`);
    const manifest = await res.clone().json();
    const cacheName = CACHE_PREFIX + manifest.version;
    // The worker reads its manifest from this cache first.
    await (await caches.open(cacheName)).put(cacheKey(MANIFEST_PATH), res);
    return { manifest, cacheName };
  }

  async function missingFrom(cache, files) {
    const missing = [];
    for (const [path, rev] of files) {
      if (!(await isSaved(cache, path, rev))) missing.push([path, rev]);
    }
    return missing;
  }

  async function olderCachesThan(cacheName) {
    const older = [];
    for (const name of await caches.keys()) {
      if (name.startsWith(CACHE_PREFIX) && name !== cacheName) {
        older.push(await caches.open(name));
      }
    }
    return older;
  }

  async function run() {
    let loaded;
    try {
      loaded = await loadManifest();
    } catch (e) {
      console.warn('[loader]', e.message);
      if (navigator.serviceWorker.controller) {
        // Saved earlier and offline now: play with what is saved.
        startApp();
      } else {
        ui.message('Aumazing needs the internet the first time',
          'Connect to Wi-Fi or mobile data, then try again.');
        ui.offerStart(null, () => location.reload());
      }
      return;
    }

    const { manifest, cacheName } = loaded;
    const sizes = manifest.sizes || {};
    const sizeOf = ([path]) => sizes[path] || 0;
    const cache = await caches.open(cacheName);
    const { now, later } = plan(manifest);

    let missing = await missingFrom(cache, now);
    if (missing.length > 0 && navigator.onLine) {
      const older = await olderCachesThan(cacheName);
      const total = now.reduce((sum, f) => sum + sizeOf(f), 0);
      let done = total - missing.reduce((sum, f) => sum + sizeOf(f), 0);
      ui.message('Getting the games ready',
        'Saving pictures, voices and music so play is never interrupted.');
      ui.progress(done, total);
      // Starting early keeps the download going; anything not saved yet is
      // fetched when a game first needs it.
      const startNow = () => { takeOver(); startApp(); };
      const offer = setTimeout(() => ui.offerStart(startNow), OFFER_START_AFTER_MS);

      const saveFile = ([path, rev]) => save(cache, older, path, rev);
      const counted = (file) => { done += sizeOf(file); ui.progress(done, total); };
      for (let attempt = 0; attempt < 3 && missing.length > 0 && !started; attempt++) {
        missing = await pool(missing, FOREGROUND_CONCURRENCY, saveFile, (file) => {
          if (!started) counted(file);
        });
        // A failed file was counted as done; take it back off before retrying.
        done -= missing.reduce((sum, f) => sum + sizeOf(f), 0);
      }
      clearTimeout(offer);
      if (started) return;
      if (missing.length > 0) {
        ui.stopProgress();
        ui.message('Some files did not download',
          `${missing.length} file(s) are still missing. Check the connection and try again.`);
        ui.offerStart(startNow, () => location.reload());
        return;
      }
    }

    await takeOver();
    startApp();

    // Other languages' voices, quietly, once the child is playing.
    if (later.length > 0) {
      whenStarted.push(() => setTimeout(async () => {
        const rest = await missingFrom(cache, later);
        if (rest.length === 0 || !navigator.onLine) return;
        const older = await olderCachesThan(cacheName);
        await pool(rest, BACKGROUND_CONCURRENCY, ([path, rev]) => save(cache, older, path, rev));
      }, BACKGROUND_DELAY_MS));
    }
  }

  if (!('serviceWorker' in navigator) || !('caches' in window)) {
    // No offline support (e.g. a private window in some browsers): start
    // normally and load files as they are needed.
    startApp();
    return;
  }
  run().catch((e) => {
    console.warn('[loader] stopped:', e && e.message ? e.message : e);
    startApp();
  });
})();
