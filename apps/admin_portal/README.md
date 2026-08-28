# Aumazing Admin Portal

Flutter web UI for system administrators. It talks to the same Supabase
project as the mobile app. Authorization is **not** “anyone who can
authenticate”: `admin_users` + `is_admin()` RLS still gate every
privileged query. Google sign-in only creates a Supabase session; a
Google account that is not on the allowlist is signed back out by the
shell.

Run:

```sh
cd apps/admin_portal
flutter run -d chrome --dart-define-from-file=../main_app/env/dev.json
```

## Google OAuth setup

Do this in the Google Cloud console and the Supabase dashboard. Do **not**
put client secrets in this repo or in dart-defines.

1. **Google Cloud** → APIs & Services → Credentials → Create OAuth client
   ID, type **Web application**.
   - Authorized JavaScript origins: the portal origin, e.g.
     `http://localhost:xxxxx` (the port `flutter run -d chrome` prints)
     and the production origin.
   - Authorized redirect URIs: the Supabase callback
     `https://<project-ref>.supabase.co/auth/v1/callback`.

2. **Supabase** → Authentication → Providers → **Google**: enable it and
   paste the Web client ID and client secret from step 1.

3. **Supabase** → Authentication → URL Configuration:
   - Site URL: the portal origin you actually serve (local or production).
   - Redirect URLs must include that same origin, e.g.
     `http://localhost:xxxxx/` and `https://admin.example.com/`.
     The app sends `redirectTo` as origin + `/` only (no hash, no query),
     so the allow-list entry must match that.

4. Add the Google account’s email to `admin_users` before expecting the
   shell to open. OAuth does not grant admin rights.

Credentials stay in the Supabase project settings. This app only uses the
existing `SUPABASE_URL` / `SUPABASE_ANON_KEY` dart-defines.
