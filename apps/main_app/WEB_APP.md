# Aumazing — web app

The web app is the full Aumazing app running on Flutter web, with the same
features as the Android app: guest mode and accounts, games, pre- and
post-assessments with on-device AI, the parent dashboard and reports,
Premium, and offline play. Where a plugin has no browser version, the web app
uses a browser equivalent:

| Area | On Android | On the web |
|---|---|---|
| On-device AI (`onnxruntime`) | Native ONNX Runtime | `onnxruntime-web` (WASM) through `web/ort_bridge.mjs`, behind the conditional export in `on_device_ai_assessment_service.dart` — the same models, no server |
| Local database (`sqflite`) | SQLite | `core/services/db_web_factory.dart` installs `databaseFactoryFfiWebNoWebWorker` (WASM SQLite, persisted in IndexedDB) |
| Premium checkout (`webview_flutter`) | In-app WebView | Same tab: `create-checkout` gets the app's own address as `return_url`, PayMongo returns with `?payment=success` or `?payment=cancelled`, and `WebCheckoutReturnBanner` confirms the upgrade once the backend activates it |
| PDF reports and gameplay export | Temporary file + share sheet | Built in memory (`XFile.fromData`); the browser opens its share sheet, or downloads the files where sharing files is not supported |
| Google sign-in | Native Google Sign-In | Supabase OAuth redirect |
| Offline play | Everything ships in the APK | The loading page saves what the app needs to open; everything else saves in the background while the child plays (below) |

Premium is gated exactly as on Android: the web app no longer unlocks it for
everyone.

## Building

```bash
cd apps/main_app
flutter pub get
flutter build web --base-href /Aumazing-Front-Page/app/ --dart-define-from-file=env/dev.json
dart run tool/build_offline_web.dart
```

Output lands in `apps/main_app/build/web/`. Deploy it under the front page at
`Aumazing-Front-Page/app/` (the front page links to `app/` — see its
`index.html` "Use in Browser" buttons). The base href must match the path the
site is served from, or every file 404s.

**Always run `tool/build_offline_web.dart` after `flutter build web`.** Skipping
it does not break the app, but it silently becomes online-only again (see below).

## Loading page and offline play (AUM-334, AUM-345)

Before the app starts, a loading page (`web/offline.js`, markup in
`web/index.html`, styles in `web/loader.css`) saves only what the app needs to
open, then starts it. Everything else a child needs is saved quietly in the
background while the child plays, so after one visit the app works with no
connection:

- Before start: the boot files (shell, engine, code, fonts, asset manifests),
  about 23 MB, with progress in MB. A return visit opens straight away.
- In the background, three files at a time, most-needed first: pictures, then
  the voice lines, picture-card audio and sound effects for the languages the
  children on this device use (English before any child is set up), then the
  assessment models, music and the startup videos, then other languages'
  voices. The download starts a few seconds after the first frame, pauses
  while the device is offline, retries failed files after a while, and picks
  up where it left off on the next visit.
- A file a game asks for before it has been saved loads from the network, and
  the service worker saves it then. Until the background download finishes
  the app needs a connection for the games it has not saved yet.
- **Settings › Offline Play** (web only) shows the progress: saving with a
  percentage and bar, paused, or "Ready: every game plays without internet".
  The loading page publishes it as `window.aumazingOffline` with an
  `aumazing-offline` event; `lib/core/web/offline_save_status.dart` mirrors
  it for the app.
- Music is saved in one format only: `.ogg` where the browser plays it,
  otherwise the `.mp3` copy under `audio_fallback/`, the same choice the app's
  music player makes.
- After 20 s on the loading page a parent may tap **Start now**; anything not
  saved yet is fetched when the app first needs it. If boot files fail after
  three tries, the page offers **Try again** or **Start now**.
- The files go into the cache `web/offline_sw.js` serves from, tagged the same
  way, so the service worker's install finds them already saved rather than
  downloading the app a second time. The app starts only once the worker
  serves the page.
- `tool/build_offline_web.dart` writes `offline_manifest.json` (every file with
  a content hash and size, split into boot, core (pictures, models, videos)
  and lazy (audio); the wasm-only CanvasKit variants are left out) and stamps
  the build version into `offline_sw.js`. The worker's first install
  precaches only the boot files; an update precaches boot and core, so a
  device that was ready offline stays ready. After a deploy only files whose
  hash changed are downloaded again.
- A new version takes over only after every tab or Home Screen instance of the
  old one has closed, so files never change under a child mid-game.
- `web/flutter_bootstrap.js` loads CanvasKit from `canvaskit/` in the build
  instead of Google's CDN, and the Nunito/Poppins files google_fonts would
  download are bundled under `packages/shared_ui/assets/google_fonts/`.
- Flutter's engine still downloads Roboto and its fallback fonts (emoji,
  symbols) from `fonts.gstatic.com`. The build tool lists the ones the app can
  need (read from the Flutter SDK's engine sources), the loading page saves
  them into the `aumazing-fonts` cache, and the service worker serves them from
  there — otherwise games that draw objects as emoji show crossed-out boxes
  offline.

Still online-only: sign-in, cloud sync (progress is saved locally and uploaded
later), therapy-center map tiles and premium checkout.

On iPhone/iPad, Safari may clear a website's saved files after about 7 days
without use, **unless it has been added to the Home Screen** — which the
install banner asks for.

To test locally, serve `build/web` under the build's base href over
`http://127.0.0.1` (service workers need HTTPS or localhost), open it once and
wait for Settings › Offline Play to say Ready, then stop the server and reload.

## ⚠️ The sqlite3.wasm version gotcha

`dart run sqflite_common_ffi_web:setup` downloads a `sqlite3.wasm` that is **too
old** for the resolved `sqlite3` Dart package (3.5.2). Using it throws at
runtime:

```
WebAssembly.instantiate(): Import #25 "env": module is not an object or function
```

The fix (already applied — `web/sqlite3.wasm` is the correct build) is to use the
wasm whose release tag matches the `sqlite3` package version:

```bash
# Match the sqlite3 version in pubspec.lock (currently 3.5.2)
curl -sL https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-3.5.2/sqlite3.wasm \
  -o apps/main_app/web/sqlite3.wasm
```

Do **not** re-run `sqflite_common_ffi_web:setup` without re-applying this, or the
web DB will break again. `flutter build web` copies `web/sqlite3.wasm` into the
build, so keeping the correct one in `web/` is enough.

## Browser notes

- **Google sign-in** needs the site's address in the Supabase auth redirect
  allow-list and the Google OAuth client's authorized origins. The console
  `SyntaxError: Unexpected token '...'` comes from Google Identity Services
  probing and is harmless.
- **Checkout return addresses** are allow-listed in `create-checkout`
  (`ALLOWED_RETURN_ORIGINS`, default the GitHub Pages site; localhost is always
  allowed for development).
- **Data** lives in this browser (IndexedDB) until the parent signs in and
  syncs; a different browser or cleared site data starts from the cloud copy.
- **iPhone/iPad**: add the app to the Home Screen so Safari keeps its saved
  files; vibration is not available in iOS browsers.
