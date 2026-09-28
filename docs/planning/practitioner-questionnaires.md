# Practitioner-authored parent questionnaires (AUM-344)

Pre-final defense note: *"Roles and functionality for approved
practitioner/therapist to add pre and post follow survey or questionnaire to
parents in pre-assessment."*

## What exists

| Piece | Where | Status |
|---|---|---|
| `practitioners` table: apply → admin approves | `supabase/migrations/20260927_practitioner_questionnaires.sql` | applied 2026-09-28 |
| `questionnaire_templates` table + access rules | same migration, plus the `20260928_*` follow-ups | applied 2026-09-28 |
| Three question sets per template `kind`: `home` (the home questionnaire), `intake` ("Before your child starts") and `observation` ("What did you see?") | `20260928_questionnaire_template_kinds.sql` | applied 2026-09-28 (AUM-352) |
| Shared template model and validation, used by the app and the portal | `packages/questionnaire_core` | done |
| App reads the active template of each kind, caches it for offline use, falls back to the bundled questions | `apps/main_app/lib/features/questionnaire/questionnaire_template_repository.dart` | done |
| Portal: practitioners apply and write templates; admins approve practitioners and choose what is in use | `apps/admin_portal` (Questionnaires, Practitioners) | done (AUM-352) |

Until an admin puts a template in use, the app behaves exactly as before:
nothing is active, nothing is cached, and the bundled questions are shown.
Who is watching (parent, guardian, SPED teacher, therapist) is always asked
by the app itself, because it is stored as each record's
`completed_by_role`.

## Access rules

- **Anyone signed in** may apply as a practitioner, only for themselves, and
  only as `pending`.
- **Only an admin** (`public.is_admin()`) approves, revokes or edits a
  practitioner.
- **Approved practitioners** create and edit their own templates. An **admin**
  may also enter one on a practitioner's behalf.
- **Only an admin** can make a template active or mark it `validated`. When a
  practitioner edits the text of an active template, it is taken out of use
  and returned to `draft` until an admin re-activates it, so parents never
  see unreviewed wording.
- **At most one template is active per assessment type** (`pre`, `post`,
  `both`).
- **Parents and guests** can only read the active template.

## Operating it (portal)

1. The practitioner signs in to the portal (email and password, or Google)
   and fills in the application: full name, profession, PRC licence number.
2. An admin opens **Practitioners**, checks the licence, and approves.
3. The practitioner opens **Questionnaires** → **New questionnaire**, picks
   the question set (Home questionnaire / Before the session / After the
   session) and which assessment it serves, and writes the questions —
   or presses **Start from the built-in questions** and edits those. The
   page shows what still needs fixing and a preview, and only saves what
   the app will accept.
   - Home: statements rated Never → Always, each in one of the four areas;
     every area needs at least one.
   - Before / after the session: choose-one, choose-any or written
     questions. After-session questions can repeat **for each game**
     (at least one must). An answer can carry a **flag** shown beside that
     game's score (for example "Played with help"); **Hide** leaves an answer
     out of the results summary ("Prefer not to say"); **Only** clears the
     other answers ("None").
4. An admin reviews it in **Questionnaires**, optionally **Mark validated**,
   and presses **Use this**. That takes the previous template of the same
   set and assessment out of use.

The next assessment uses it. Every stored answer records `template_id`,
`template_version` and `template_status`, and before/after records keep the
summary and flags worked out when they were saved, so rewording a template
never changes old results.

## Future recommendations

- With explicit parent consent (RA 10173), sharing a family's questionnaire
  results with the practitioner whose template they answered.
