(function () {
  'use strict';

  // The loading page. Before the app starts it saves only what the app needs
  // to open — its code, engine and fonts, about 20 MB — so the app opens in
  // seconds instead of waiting for every game file. Everything else a child
  // needs is then saved quietly in the background while the child plays,
  // most-needed first: pictures, the voice lines and sound effects for the
  // child's language, the assessment models, music, then videos. Voices for
  // other languages follow last. A file a game asks for before it has been
  // saved simply loads from the network, and the worker saves it then; the
  // background download picks up where it left off on the next visit.
  //
  // The files go into the same cache the offline service worker
  // (offline_sw.js) serves from, tagged the same way, so the worker's install
  // finds them already saved instead of downloading them a second time.
  // offline_manifest.json (tool/build_offline_web.dart) lists every file with
  // its content hash and size.
  //
  // How far the background download has got is published as
  // window.aumazingOffline, with an `aumazing-offline` event on each change,
  // for the app's Offline Play tile in Settings
  // (lib/core/web/offline_save_status_web.dart).

  const CACHE_PREFIX = 'aumazing-offline-';
  const REV_HEADER = 'x-aumazing-rev';
  const MANIFEST_PATH = 'offline_manifest.json';
  // Shared with offline_sw.js: Flutter's engine fonts (Roboto, emoji,
  // symbols), downloaded from fonts.gstatic.com.
  const FONT_CACHE = 'aumazing-fonts';
  const BASE = new URL('.', document.baseURI);

  const FOREGROUND_CONCURRENCY = 8;
  // Low, so the background download never slows a game's own requests.
  const BACKGROUND_CONCURRENCY = 3;
  // After this long a parent may start before the app's files are saved.
  const OFFER_START_AFTER_MS = 20000;
  // Lets the first screens load before the background download begins.
  const BACKGROUND_START_DELAY_MS = 3000;
  // Waits before retrying files that failed while still online.
  const RETRY_DELAYS_MS = [15000, 60000, 300000];
  const PUBLISH_INTERVAL_MS = 500;

  // Only opened on request (install guide, licences), never mid-game.
  const ON_DEMAND = new Set(['ios-install-guide.png', 'assets/NOTICES']);
  const AUDIO_DIR = 'assets/packages/shared_audio/assets/audio/';
  const FALLBACK_DIR = 'audio_fallback/';
  const VOICE_PACK = /^assets\/packages\/shared_audio\/assets\/audio\/voice_over\/([a-z]+)_[^/]+\//;
  const SEED_CARD_AUDIO = /^assets\/packages\/shared_ui\/assets\/seed_cards\/audio\/([a-z]+)\//;
  const MUSIC = /(^|\/)(bgm\/|bg_music[^/]*$)/;

  // Background order, most-needed first.
  const PICTURES = 0;
  const CHILD_AUDIO = 1;
  const MODELS = 2;
  const SONGS = 3;
  const VIDEOS = 4;
  const OTHER_LANGUAGES = 5;
  const LEAVE_OUT = -1;

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

  // ── Progress, for the app ───────────────────────────────────────────────

  // status: 'checking' | 'saving' | 'paused' | 'ready' | 'unavailable'.
  // reason, while paused: 'offline' or 'retrying'. done/total are bytes of
  // the files this device's children need (other languages are not counted).
  const progress = { status: 'checking', reason: null, done: 0, total: 0 };
  let publishTimer = null;

  function publish(change) {
    Object.assign(progress, change);
    if (publishTimer !== null) {
      clearTimeout(publishTimer);
      publishTimer = null;
    }
    window.aumazingOffline = Object.assign({}, progress);
    window.dispatchEvent(new Event('aumazing-offline'));
  }

  // For the stream of per-file updates: at most one event per interval.
  function publishSoon(change) {
    Object.assign(progress, change);
    if (publishTimer === null) {
      publishTimer = setTimeout(() => publish({}), PUBLISH_INTERVAL_MS);
    }
  }

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

  // Runs [task] over [items], [limit] at a time; returns the items that
  // failed. [onDone] is told after each item, and whether it was saved.
  async function pool(items, limit, task, onDone) {
    let next = 0;
    const failed = [];
    async function worker() {
      while (next < items.length) {
        const item = items[next++];
        let ok = true;
        try {
          await task(item);
        } catch (e) {
          ok = false;
          failed.push(item);
          console.warn('[loader]', e && e.message ? e.message : e);
        }
        if (onDone) onDone(item, ok);
      }
    }
    await Promise.all(Array.from({ length: Math.min(limit, items.length) }, worker));
    return failed;
  }

  const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

  const backOnline = () => new Promise((resolve) => {
    window.addEventListener('online', resolve, { once: true });
  });

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

  // Engine fonts not saved yet: without them a child offline sees
  // crossed-out boxes wherever a game draws an object as an emoji.
  async function missingFonts(manifest) {
    const base = manifest.fontBaseUrl;
    if (!base || !Array.isArray(manifest.fonts)) return [];
    const cache = await caches.open(FONT_CACHE);
    const missing = [];
    for (const path of manifest.fonts) {
      const url = base + path;
      if (!(await cache.match(url))) missing.push(url);
    }
    return missing;
  }

  async function saveFont(url) {
    const res = await fetch(url, { mode: 'cors' });
    if (!res.ok) throw new Error(`${url}: HTTP ${res.status}`);
    await (await caches.open(FONT_CACHE)).put(url, res);
  }

  // Where [path] goes in the background queue.
  function rank(path, langs, oggOk, lazy) {
    if (ON_DEMAND.has(path)) return LEAVE_OUT;
    // Same choice as the app's music player: .ogg where the browser plays
    // it, otherwise the .mp3 copy under audio_fallback/.
    if (path.startsWith(FALLBACK_DIR)) return oggOk ? LEAVE_OUT : SONGS;
    if (!oggOk && path.startsWith(AUDIO_DIR) && path.endsWith('.ogg')) {
      const mp3 = FALLBACK_DIR + path.slice(AUDIO_DIR.length).replace(/\.ogg$/, '.mp3');
      if (mp3 in lazy) return LEAVE_OUT;
    }
    const language = VOICE_PACK.exec(path) || SEED_CARD_AUDIO.exec(path);
    if (language) return langs.has(language[1]) ? CHILD_AUDIO : OTHER_LANGUAGES;
    if (path.startsWith(AUDIO_DIR)) {
      return MUSIC.test(path.slice(AUDIO_DIR.length)) ? SONGS : CHILD_AUDIO;
    }
    if (path.startsWith('assets/assets/videos/')) return VIDEOS;
    if (path.startsWith('ort/') || path.startsWith('assets/assets/models/')) return MODELS;
    return PICTURES;
  }

  // Splits the build into the files saved before the app starts ([boot]),
  // the ones saved in the background in order of need ([background]), and
  // other languages' voices ([later]).
  function plan(manifest) {
    const langs = chosenLanguages();
    const oggOk = !!document.createElement('audio')
      .canPlayType('audio/ogg; codecs="vorbis"');
    // Manifests from before the boot tier opened the app on the core.
    const bootFiles = manifest.boot || manifest.core;
    const queued = Object.assign({}, manifest.lazy, manifest.boot ? manifest.core : {});
    const ranked = [];
    for (const [path, rev] of Object.entries(queued)) {
      const r = rank(path, langs, oggOk, manifest.lazy);
      if (r !== LEAVE_OUT) ranked.push([r, [path, rev]]);
    }
    ranked.sort((a, b) => a[0] - b[0]);
    return {
      boot: Object.entries(bootFiles),
      background: ranked.filter(([r]) => r < OTHER_LANGUAGES).map(([, file]) => file),
      later: ranked.filter(([r]) => r === OTHER_LANGUAGES).map(([, file]) => file),
    };
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

  // Saves [files] (in order) while the child plays, reporting progress, and
  // keeps going until every one is saved: paused while the device is
  // offline, and retried after a while when a download fails. Then saves
  // [later] without reporting it.
  async function saveInBackground(manifest, cacheName, files, later) {
    publish({ status: 'checking' });
    const sizes = manifest.sizes || {};
    const sizeOf = ([path]) => sizes[path] || 0;
    const cache = await caches.open(cacheName);
    // Fonts ride along first, as [url, null] entries.
    const fonts = (await missingFonts(manifest)).map((url) => [url, null]);
    let pending = fonts.concat(await missingFrom(cache, files));
    const total = files.reduce((sum, f) => sum + sizeOf(f), 0);
    let done = total - pending.reduce((sum, f) => sum + sizeOf(f), 0);

    for (let round = 0; pending.length > 0; round++) {
      if (!navigator.onLine) {
        publish({ status: 'paused', reason: 'offline', done, total });
        await backOnline();
      }
      publish({ status: 'saving', reason: null, done, total });
      const older = await olderCachesThan(cacheName);
      pending = await pool(pending, BACKGROUND_CONCURRENCY,
        ([path, rev]) => (rev === null ? saveFont(path) : save(cache, older, path, rev)),
        (file, ok) => {
          if (!ok) return;
          done += sizeOf(file);
          publishSoon({ done });
        });
      if (pending.length === 0) break;
      publish({ status: 'paused', reason: navigator.onLine ? 'retrying' : 'offline', done, total });
      const wait = RETRY_DELAYS_MS[Math.min(round, RETRY_DELAYS_MS.length - 1)];
      await Promise.race([sleep(wait), backOnline()]);
    }
    publish({ status: 'ready', reason: null, done: total, total });

    const rest = await missingFrom(cache, later);
    if (rest.length === 0 || !navigator.onLine) return;
    const older = await olderCachesThan(cacheName);
    await pool(rest, BACKGROUND_CONCURRENCY, ([path, rev]) => save(cache, older, path, rev));
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
    const { boot, background, later } = plan(manifest);
    publish({ status: 'checking' });

    // However the app ends up starting, the rest follows once it is up.
    whenStarted.push(() => setTimeout(() => {
      saveInBackground(manifest, cacheName, background, later).catch((e) => {
        console.warn('[loader] background saving stopped:', e && e.message ? e.message : e);
      });
    }, BACKGROUND_START_DELAY_MS));

    let missing = await missingFrom(cache, boot);
    if (missing.length > 0 && navigator.onLine) {
      const older = await olderCachesThan(cacheName);
      const total = boot.reduce((sum, f) => sum + sizeOf(f), 0);
      let done = total - missing.reduce((sum, f) => sum + sizeOf(f), 0);
      ui.message('Opening Aumazing',
        'Saving the app so it opens without internet next time.');
      ui.progress(done, total);
      // Starting early keeps the download going; anything not saved yet is
      // fetched when the app first needs it.
      const startNow = () => { takeOver(); startApp(); };
      const offer = setTimeout(() => ui.offerStart(startNow), OFFER_START_AFTER_MS);

      for (let attempt = 0; attempt < 3 && missing.length > 0 && !started; attempt++) {
        missing = await pool(missing, FOREGROUND_CONCURRENCY,
          ([path, rev]) => save(cache, older, path, rev),
          (file, ok) => {
            if (started || !ok) return;
            done += sizeOf(file);
            ui.progress(done, total);
          });
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
  }

  if (!('serviceWorker' in navigator) || !('caches' in window)) {
    // No offline support (e.g. a private window in some browsers): start
    // normally and load files as they are needed.
    publish({ status: 'unavailable' });
    startApp();
    return;
  }
  run().catch((e) => {
    console.warn('[loader] stopped:', e && e.message ? e.message : e);
    startApp();
  });
})();
