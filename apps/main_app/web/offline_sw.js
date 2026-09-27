'use strict';

// Offline support for the web build (AUM-334).
//
// tool/build_offline_web.dart runs after `flutter build web`: it writes
// offline_manifest.json (every file in the build with a content hash, split
// into "core" and "lazy") and stamps that build's version into this file.
// Without that step the placeholder below never matches a manifest, install
// fails, and the app simply behaves as an ordinary online page.
//
// - install:  precache every core file (app shell, engine, code, models,
//             fonts, pictures) into a cache named after the build version.
//             On a first visit the loading page (offline.js) has usually
//             saved them already, so this only confirms they are there.
//             Files whose hash is unchanged are copied from the previous
//             version's cache instead of downloaded again, and lazy files
//             (voice lines, music) already cached carry over too.
// - fetch:    same-origin requests for build files are served cache-first;
//             a lazy file is cached the first time it is fetched. Audio range
//             requests get a proper 206 so Safari can play cached sound.
// - activate: only once no page runs the old version (no skipWaiting), so a
//             child mid-game never has old and new files mixed under them.
// - message:  the loading page asks which build version is running, so it
//             checks and fills that version's cache (offline.js).

const VERSION = '__AUMAZING_OFFLINE_VERSION__';
const CACHE_PREFIX = 'aumazing-offline-';
const CACHE_NAME = CACHE_PREFIX + VERSION;
const REV_HEADER = 'x-aumazing-rev';
const SCOPE = new URL(self.registration.scope);
const MANIFEST_PATH = 'offline_manifest.json';

// Never cached: the worker and its manifest must always come from the
// network, and version.json is how Flutter tooling probes for a new build.
const PASSTHROUGH = new Set([
  'offline_sw.js',
  MANIFEST_PATH,
  'version.json',
  'flutter_service_worker.js',
]);

let manifestPromise = null;

function loadManifest() {
  if (!manifestPromise) {
    manifestPromise = (async () => {
      const key = cacheKey(MANIFEST_PATH);
      const cache = await caches.open(CACHE_NAME);
      let res = await cache.match(key);
      if (!res) {
        res = await fetch(key, { cache: 'no-store' });
        if (!res.ok) throw new Error(`offline manifest: HTTP ${res.status}`);
        await cache.put(key, res.clone());
      }
      const manifest = await res.json();
      if (manifest.version !== VERSION) {
        throw new Error(
          `offline manifest is for build ${manifest.version}, worker is ${VERSION}`);
      }
      manifest.files = Object.assign({}, manifest.lazy, manifest.core);
      return manifest;
    })();
    manifestPromise.catch(() => { manifestPromise = null; });
  }
  return manifestPromise;
}

// Build-relative path of a same-origin URL inside the scope, or null.
function relPath(url) {
  const u = new URL(url);
  if (u.origin !== SCOPE.origin || !u.pathname.startsWith(SCOPE.pathname)) {
    return null;
  }
  let path = u.pathname.slice(SCOPE.pathname.length);
  try {
    path = decodeURIComponent(path);
  } catch (_) {
    // Leave a malformed escape as-is; it simply won't match the manifest.
  }
  return path;
}

// One canonical URL per build file, whatever encoding or query string the
// request used (e.g. `icons/Icon-192.png?v=…`).
function cacheKey(path) {
  return new URL(path.split('/').map(encodeURIComponent).join('/'), SCOPE).href;
}

async function tagged(res, rev) {
  const headers = new Headers(res.headers);
  headers.set(REV_HEADER, rev);
  // Rebuilding the response also drops `redirected`, which browsers refuse
  // to serve for navigations.
  return new Response(await res.blob(), { status: 200, statusText: 'OK', headers });
}

async function fromOlderCache(key, rev) {
  for (const name of await caches.keys()) {
    if (!name.startsWith(CACHE_PREFIX) || name === CACHE_NAME) continue;
    const res = await (await caches.open(name)).match(key);
    if (res && res.headers.get(REV_HEADER) === rev) return res;
  }
  return null;
}

// The cached response for [path] at revision [rev], fetching it if needed.
async function ensureCached(cache, path, rev, { network = true } = {}) {
  const key = cacheKey(path);
  const hit = await cache.match(key);
  if (hit && hit.headers.get(REV_HEADER) === rev) return hit;

  let res = await fromOlderCache(key, rev);
  if (!res) {
    if (!network) return null;
    const fresh = await fetch(key, { cache: 'no-cache' });
    if (!fresh.ok) throw new Error(`${path}: HTTP ${fresh.status}`);
    res = await tagged(fresh, rev);
  }
  await cache.put(key, res.clone());
  return res;
}

// Runs [task] over [items] with at most [limit] in flight. Resolves with the
// number of failures; [onSettled] is told after each item.
async function pool(items, limit, task, onSettled) {
  let next = 0;
  let failed = 0;
  async function worker() {
    while (next < items.length) {
      const item = items[next++];
      try {
        await task(item);
      } catch (e) {
        failed++;
        console.warn('[offline]', e && e.message ? e.message : e);
      }
      if (onSettled) onSettled();
    }
  }
  await Promise.all(Array.from({ length: Math.min(limit, items.length) }, worker));
  return failed;
}

self.addEventListener('install', (event) => {
  event.waitUntil((async () => {
    const manifest = await loadManifest();
    const cache = await caches.open(CACHE_NAME);
    const failed = await pool(Object.entries(manifest.core), 6,
      ([path, rev]) => ensureCached(cache, path, rev));
    // A half-filled shell must not take over: fail and retry next visit.
    if (failed > 0) throw new Error(`${failed} core files could not be cached`);
    // Carry over lazy files a previous version already downloaded.
    await pool(Object.entries(manifest.lazy), 6,
      ([path, rev]) => ensureCached(cache, path, rev, { network: false }));
  })());
});

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    for (const name of await caches.keys()) {
      if (name.startsWith(CACHE_PREFIX) && name !== CACHE_NAME) {
        await caches.delete(name);
      }
    }
    // Control the page that installed us, so the very first visit already
    // works offline without a reload.
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;
  const path = relPath(req.url);
  // Cross-origin traffic (Supabase, map tiles, checkout) is left alone.
  if (path === null || PASSTHROUGH.has(path)) return;
  event.respondWith(respond(req, path));
});

async function respond(req, path) {
  let manifest;
  try {
    manifest = await loadManifest();
  } catch (_) {
    return fetch(req);
  }

  let target = path === '' ? 'index.html' : path;
  // Any in-app navigation is the single-page app; a direct link to a real
  // build file (the full-size install guide) still opens that file.
  if (req.mode === 'navigate' && !(target in manifest.files)) {
    target = 'index.html';
  }

  const rev = manifest.files[target];
  if (rev === undefined) return fetch(req);

  let res;
  try {
    res = await ensureCached(await caches.open(CACHE_NAME), target, rev);
  } catch (_) {
    // Let the browser surface the real network error.
    return fetch(req);
  }
  const range = req.headers.get('range');
  return range ? partial(res, range) : res;
}

async function partial(res, range) {
  const body = await res.arrayBuffer();
  const size = body.byteLength;
  const headers = new Headers(res.headers);
  headers.set('Accept-Ranges', 'bytes');

  const m = /^bytes=(\d*)-(\d*)$/.exec(range.trim());
  if (!m || (m[1] === '' && m[2] === '')) {
    return new Response(body, { status: 200, headers });
  }
  let start;
  let end;
  if (m[1] === '') {
    start = Math.max(0, size - Number(m[2]));
    end = size - 1;
  } else {
    start = Number(m[1]);
    end = m[2] === '' ? size - 1 : Math.min(Number(m[2]), size - 1);
  }
  if (start >= size || start > end) {
    return new Response(null, {
      status: 416,
      headers: { 'Content-Range': `bytes */${size}` },
    });
  }
  headers.set('Content-Range', `bytes ${start}-${end}/${size}`);
  headers.set('Content-Length', String(end - start + 1));
  return new Response(body.slice(start, end + 1), {
    status: 206,
    statusText: 'Partial Content',
    headers,
  });
}

self.addEventListener('message', (event) => {
  const port = event.ports && event.ports[0];
  if (!port || !event.data || event.data.type !== 'version') return;
  port.postMessage({ type: 'result', version: VERSION, cache: CACHE_NAME });
});
