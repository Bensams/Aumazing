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

## Writing questionnaires

Practitioners enter an ordinary questionnaire title and the wording parents
will read. Internal questionnaire, question and answer identifiers are created
automatically; existing identifiers are preserved when wording changes.

The editor guides practitioners through details, questions, and previewing.
Home questions use numbered cards with skill-area guidance and coverage counts.
Questions can be duplicated, moved, or removed with an undo action. A parent
preview is available at every screen size; its answers are never saved.
Additional result settings are expandable within before/after-session questions.

For a questionnaire already in use, select **Create a revised version**. The
current questionnaire stays available until an administrator activates the
revision. Saving alone does not activate a questionnaire.

## Premium for parent accounts

Every new account starts with a free month of Premium (30 days, once per
account). A guest keeps the days left when they link their account.

On **Accounts**, an administrator can **Grant Premium** for 30, 60 or 90 days.
The days are added on top of any Premium the account already has. Grants work
only for linked accounts: a guest must link first, because Premium given to a
guest is lost with the device. **End Premium** ends Premium that was given (a
grant or the free month); paid Premium is ended by refunding it through
PayMongo. Both actions need a reason and are written to the audit log.

## Production hosting

The frontend is hosted on Vercel in the `ecnovators` team's `aumazing-portal`
project at **https://portal.ecnovators.me/**. Supabase provides the backend.
Deploy the compiled Flutter web output, rather than the repository source.
### Background reuse and session check-ins

The before-session editor includes **When to ask**: background can be reused on
later assessments, while **Ask each session** starts with a fresh answer. Existing
intake templates without a `timing` setting retain their background meaning.
Question identity, wording and choices are checked before reuse; copied revisions
preserve this setting. Keep session questions short. After-session game questions
are shown only for games the adult selects for extra details, and session-only
check-in templates are accepted.

These settings are stored in existing template item JSON and need no schema
migration. Publish the updated frontend through Vercel at
https://portal.ecnovators.me/ after verification. The installed mobile app also
needs rebuilding to use these settings.
