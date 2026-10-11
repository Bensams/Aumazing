# In-app APK updates

The Android app is sideloaded from GitHub Releases, so no store tells an
installed copy that a newer build exists. The app checks for itself.

## How it works

1. At launch, `AppUpdateService` reads the newest published row in
   `public.app_releases` and compares its `version_code` with the installed
   versionCode (the number after `+` in pubspec's `version:`). The check runs
   in the background and stays quiet when offline.
2. If the installed build is behind, the parent dashboard shows a banner, and
   **Settings › App Updates** shows the new version. Nothing appears in child
   mode, so play is never interrupted.
3. **Update now** downloads the APK into the app's cache, checks it against the
   row's `sha256`, and hands it to Android's package installer. The parent taps
   **Install**, and the app restarts on the new version with all its data.

The first time, Android asks the parent to allow Aumazing to install apps
("Allow from this source"). When they come back, the install carries on
without downloading again.

Android refuses an APK that is not signed with the installed app's key, so
every release must be signed with the same release keystore.

**Later** on the banner hides that version until a newer one is published.
A release with `min_supported_code` above the installed versionCode is shown
as required, and its banner cannot be dismissed.

The web app does not use this. It updates through its service worker.

## Publishing a release

1. Bump `version:` in `pubspec.yaml`. The `+N` versionCode must go up.
2. Run the **Android Publish Release** workflow. It creates a draft release
   by default.
3. Write the draft's first paragraph for parents in one or two plain
   sentences. That paragraph is what the update dialog shows.
4. Install the draft's APK on a test phone, then publish the release.

Publishing runs **Android Register Release**, which checksums the published
APK and adds its `public.app_releases` row. Installed copies then offer the
update on their next launch. It refuses a release that still has the
placeholder parent notes; fix the notes and re-run it with the tag from the
Actions tab.

Forced updates stay manual: set `min_supported_code` on the row in the
Supabase SQL editor only when older builds must update. To withdraw a
release, set `is_published = false` on its row.

### How the workflow is allowed to write

The workflow calls `register_app_release()` through the public API with the
`APP_RELEASE_TOKEN` repository secret. The database stores only that token's
SHA-256 in `app_release_publishers`, and the function can do nothing but add
a release row that links to this repository's releases. It refuses a second,
different APK under a version code that is already registered.

To rotate the token, generate a new one, save it as the `APP_RELEASE_TOKEN`
secret, insert its SHA-256 into `app_release_publishers`, and set
`revoked_at` on the old row.

## Pieces

| Where | What |
|---|---|
| `lib/features/app_update/` | service, dashboard banner, update dialog |
| `android/.../AppUpdateChannel.kt` | installed version, install permission, installer hand-off |
| `android/.../res/xml/app_update_paths.xml` | the only folder the installer may read |
| `supabase/migrations/20261011_app_releases.sql` | table and RLS (public read, administrator write) |
| `supabase/migrations/20261011_app_release_registration.sql` | `register_app_release()` and the token hashes it checks |
| `.github/workflows/android-register-release.yml` | adds the row when a release is published |
