# Aumazing — Web demo

The app now builds and runs in a browser as a **demo**. This is the full app
(guest mode, local DB, games, assessments) running on Flutter web, with the
three native-only plugins handled per platform so they don't break the browser.

## What was changed for web

| Plugin | Problem on web | Fix |
|---|---|---|
| `onnxruntime` | Uses `dart:ffi` — won't even compile for web | On-device AI service split behind a conditional export (`on_device_ai_assessment_service.dart` → `_native.dart` / `_web.dart`). The web stub returns `null`, so prediction falls through to the cloud API / rubric path the app already has. |
| `sqflite` | No database factory on web | `core/services/db_web_factory.dart` installs `databaseFactoryFfiWebNoWebWorker` on web (WASM SQLite on the main thread, persisted in IndexedDB). No-op on mobile/desktop. |
| `webview_flutter` | No web implementation | Premium checkout opens the URL in a new browser tab via `url_launcher` on web instead of the in-app WebView. |

## Building the demo

```bash
cd apps/main_app
flutter pub get
flutter build web --base-href /app/ --dart-define-from-file=env/dev.json
dart run tool/build_offline_web.dart
```

Output lands in `apps/main_app/build/web/`. Deploy it under the front page at
`Aumazing-Front-Page/app/` (the front page links to `app/` — see its `index.html`
"Try in Browser" buttons).

**Always run `tool/build_offline_web.dart` after `flutter build web`.** Skipping
it does not break the app, but it silently becomes online-only again (see below).

## Offline play (AUM-334)

Once opened online, the web app keeps working with no connection:

- `web/offline_sw.js` is a service worker. On install it saves the **core**
  files (app shell, engine, code, models, fonts, pictures, startup videos —
  about 85 MB) into a cache named after the build version, and only takes
  over once the whole core is saved. **Lazy** files (game voice lines, sound
  effects, music) are saved the first time they play, and `web/offline.js`
  downloads the rest in the background about 20 s after launch (not when the
  browser asks to save data).
- `tool/build_offline_web.dart` writes `offline_manifest.json` (every file with
  a content hash, split into core and lazy) and stamps the build version into
  `offline_sw.js`. After a deploy only files whose hash changed are downloaded
  again; saved audio carries over.
- A new version takes over only after every tab or Home Screen instance of the
  old one has closed, so files never change under a child mid-game.
- `web/flutter_bootstrap.js` loads CanvasKit from `canvaskit/` in the build
  instead of Google's CDN, and the Nunito/Poppins files google_fonts would
  download are bundled under `packages/shared_ui/assets/google_fonts/`.
- Parents see what is saved, and can save everything at once, under
  **Settings → Offline Play** (web only).

Still online-only: sign-in, cloud sync (progress is saved locally and uploaded
later), therapy-center map tiles and premium checkout.

On iPhone/iPad, Safari may clear a website's saved files after about 7 days
without use, **unless it has been added to the Home Screen** — which the
install banner asks for.

To test locally, serve `build/web` under `/app/` over `http://127.0.0.1`
(service workers need HTTPS or localhost), open it once, wait for
Settings → Offline Play to report the app ready, then stop the server and
reload.

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

## Demo caveats (expected, not bugs)

- **Google Sign-In**: needs `GOOGLE_WEB_CLIENT_ID` set and the serving origin
  added to the OAuth client's authorized JavaScript origins. Until then, use
  **Continue as Guest** — the full app works in guest mode. The console
  `SyntaxError: Unexpected token '...'` comes from Google Identity Services
  probing and is non-fatal.
- **On-device AI**: disabled on web (see above); predictions use the cloud API
  (`AI_API_URL`) or rubric scoring instead.
- **Persistence** is per-browser (IndexedDB), so a different browser / cleared
  site data starts fresh — fine for a try-it demo.
