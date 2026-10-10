-- In-app APK updates.
--
-- The Android app is sideloaded from GitHub Releases rather than installed
-- from a store, so nothing tells an installed copy that a newer build exists.
-- Each published APK gets one row here. On launch the app compares its own
-- versionCode against the newest published row; when it is behind, it offers
-- to download the APK, checks it against `sha256`, and hands it to Android's
-- package installer. Android keeps the app's data across the update and
-- refuses any APK not signed with the same release key.
--
-- Rows are public by design: they describe a public download. Only
-- administrators may publish, edit or withdraw one.

CREATE TABLE IF NOT EXISTS public.app_releases (
  id                 uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  platform           text        NOT NULL DEFAULT 'android'
                                 CHECK (platform IN ('android')),
  -- pubspec `version: 1.6.0+8` → version_name '1.6.0', version_code 8.
  version_name       text        NOT NULL,
  version_code       integer     NOT NULL CHECK (version_code > 0),
  download_url       text        NOT NULL CHECK (download_url LIKE 'https://%'),
  -- Lower-case hex SHA-256 of the APK. The app discards a download that
  -- does not match, so a truncated or swapped file is never installed.
  sha256             text        NOT NULL CHECK (sha256 ~ '^[0-9a-f]{64}$'),
  release_notes      text,
  -- Installed builds below this code must update before continuing to use
  -- the app (for example after a breaking backend change). Null = optional.
  min_supported_code integer     CHECK (
                                   min_supported_code IS NULL
                                   OR min_supported_code BETWEEN 1 AND version_code
                                 ),
  is_published       boolean     NOT NULL DEFAULT true,
  published_at       timestamptz NOT NULL DEFAULT now(),
  created_at         timestamptz NOT NULL DEFAULT now(),
  UNIQUE (platform, version_code)
);

CREATE INDEX IF NOT EXISTS app_releases_latest_idx
  ON public.app_releases (platform, version_code DESC)
  WHERE is_published;

ALTER TABLE public.app_releases ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can read published app releases"
  ON public.app_releases;
CREATE POLICY "Anyone can read published app releases"
  ON public.app_releases FOR SELECT
  TO anon, authenticated
  USING (is_published OR public.is_admin());

DROP POLICY IF EXISTS "Admins can publish app releases" ON public.app_releases;
CREATE POLICY "Admins can publish app releases"
  ON public.app_releases FOR INSERT
  TO authenticated
  WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS "Admins can edit app releases" ON public.app_releases;
CREATE POLICY "Admins can edit app releases"
  ON public.app_releases FOR UPDATE
  TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS "Admins can delete app releases" ON public.app_releases;
CREATE POLICY "Admins can delete app releases"
  ON public.app_releases FOR DELETE
  TO authenticated
  USING (public.is_admin());

GRANT SELECT ON public.app_releases TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.app_releases TO authenticated;

COMMENT ON TABLE public.app_releases IS
  'Published Android APK builds. The app offers an in-app update when its '
  'versionCode is below the newest published row.';
