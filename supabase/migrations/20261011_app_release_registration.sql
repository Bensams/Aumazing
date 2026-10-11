-- Automatic in-app update rows.
--
-- Publishing a GitHub release runs the Android Register Release workflow,
-- which calls register_app_release() through the public API to add the
-- release's public.app_releases row. Installed copies then offer the update
-- without anyone running SQL by hand.
--
-- The workflow authenticates with a dedicated release token, not the service
-- role key. Only the token's SHA-256 is stored here, so a database read never
-- reveals it, and the function can do exactly one thing: add a release row
-- that points at this repository's GitHub releases. A leaked token cannot
-- read or change any family's data, and Android still refuses an APK that is
-- not signed with the app's release key.

CREATE TABLE IF NOT EXISTS public.app_release_publishers (
  id           uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  label        text        NOT NULL,
  -- Lower-case hex SHA-256 of the token held as a GitHub Actions secret.
  token_sha256 text        NOT NULL UNIQUE CHECK (token_sha256 ~ '^[0-9a-f]{64}$'),
  created_at   timestamptz NOT NULL DEFAULT now(),
  -- Set to retire a token without deleting the record of it.
  revoked_at   timestamptz
);

-- No policies: only the owner (and register_app_release, which runs as the
-- owner) can see token hashes.
ALTER TABLE public.app_release_publishers ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.app_release_publishers FROM anon, authenticated;

COMMENT ON TABLE public.app_release_publishers IS
  'Hashes of the tokens allowed to call register_app_release(). Rotate by '
  'inserting a new hash and setting revoked_at on the old one.';

CREATE OR REPLACE FUNCTION public.register_app_release(
  p_token         text,
  p_version_name  text,
  p_version_code  integer,
  p_download_url  text,
  p_sha256        text,
  p_release_notes text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_notes    text := nullif(btrim(coalesce(p_release_notes, '')), '');
  v_existing public.app_releases%ROWTYPE;
BEGIN
  IF p_token IS NULL OR NOT EXISTS (
    SELECT 1
      FROM public.app_release_publishers
     WHERE revoked_at IS NULL
       AND token_sha256 = encode(sha256(convert_to(p_token, 'UTF8')), 'hex')
  ) THEN
    RAISE EXCEPTION 'not authorised to register releases'
      USING ERRCODE = '42501';
  END IF;

  IF p_version_name IS NULL OR p_version_name !~ '^[0-9]+\.[0-9]+\.[0-9]+$' THEN
    RAISE EXCEPTION 'version_name must look like 1.6.1'
      USING ERRCODE = '22023';
  END IF;
  IF p_version_code IS NULL OR p_version_code < 1 THEN
    RAISE EXCEPTION 'version_code must be a positive integer'
      USING ERRCODE = '22023';
  END IF;
  -- Only this repository's release downloads. The app trusts the row's link,
  -- so the token must not be able to point phones anywhere else.
  IF p_download_url IS NULL
     OR p_download_url !~ '^https://github\.com/Bensams/Aumazing/releases/download/[^/?#]+/aumazing\.apk$' THEN
    RAISE EXCEPTION 'download_url must be an aumazing.apk on this repository''s releases'
      USING ERRCODE = '22023';
  END IF;
  IF p_sha256 IS NULL OR p_sha256 !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'sha256 must be 64 lower-case hex characters'
      USING ERRCODE = '22023';
  END IF;
  IF v_notes IS NOT NULL AND length(v_notes) > 1000 THEN
    RAISE EXCEPTION 'release_notes must be 1000 characters or fewer'
      USING ERRCODE = '22023';
  END IF;

  -- Re-running the workflow for the same build is a no-op. A different file
  -- under an already-registered version code is refused rather than swapped
  -- in, so phones never receive an APK that does not match its notes.
  SELECT * INTO v_existing
    FROM public.app_releases
   WHERE platform = 'android' AND version_code = p_version_code;
  IF FOUND THEN
    IF v_existing.sha256 = p_sha256 AND v_existing.download_url = p_download_url THEN
      RETURN jsonb_build_object(
        'status', 'already_registered',
        'version_name', v_existing.version_name,
        'version_code', v_existing.version_code);
    END IF;
    RAISE EXCEPTION 'version_code % is already registered with a different APK; bump the version',
      p_version_code
      USING ERRCODE = '23505';
  END IF;

  -- min_supported_code (forced updates) stays a deliberate manual change.
  INSERT INTO public.app_releases
    (platform, version_name, version_code, download_url, sha256, release_notes)
  VALUES
    ('android', p_version_name, p_version_code, p_download_url, p_sha256, v_notes);

  RETURN jsonb_build_object(
    'status', 'registered',
    'version_name', p_version_name,
    'version_code', p_version_code);
END;
$$;

REVOKE ALL ON FUNCTION public.register_app_release(text, text, integer, text, text, text)
  FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.register_app_release(text, text, integer, text, text, text)
  TO anon, authenticated;

COMMENT ON FUNCTION public.register_app_release(text, text, integer, text, text, text) IS
  'Adds an Android release to public.app_releases. Called by the Android '
  'Register Release workflow with a token whose hash is in '
  'app_release_publishers.';
