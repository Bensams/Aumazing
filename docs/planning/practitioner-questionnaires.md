# Practitioner-authored parent questionnaires (AUM-344)

Pre-final defense note: *"Roles and functionality for approved
practitioner/therapist to add pre and post follow survey or questionnaire to
parents in pre-assessment."*

## What exists

| Piece | Where | Status |
|---|---|---|
| `practitioners` table: apply → admin approves | `supabase/migrations/20260927_practitioner_questionnaires.sql` | **written, not applied** |
| `questionnaire_templates` table + access rules | same migration | **written, not applied** |
| App reads the active template, caches it for offline use, falls back to the bundled draft | `apps/main_app/lib/features/questionnaire/questionnaire_template_repository.dart` | done |
| Parent questionnaire screen and pre/post comparison | AUM-341 | done |
| Practitioner self-service authoring screen | — | phase 2 |

Until the migration is applied the app behaves exactly as before: the query
fails, nothing is cached, and the bundled draft is shown.

## Access rules

- **Anyone signed in** may apply as a practitioner, only for themselves, and
  only as `pending`.
- **Only an admin** (`public.is_admin()`) approves, revokes or edits a
  practitioner.
- **Approved practitioners** create and edit their own templates. An **admin**
  may also enter one on a practitioner's behalf.
- **Only an admin** can make a template active or mark it `validated`. When a
  practitioner edits the text of an active template, it is taken out of use
  until an admin re-activates it, so parents never see unreviewed wording.
- **At most one template is active per assessment type** (`pre`, `post`,
  `both`).
- **Parents and guests** can only read the active template.

## Operating it (phase 1, admin SQL)

1. Apply the migration (Supabase dashboard → SQL, or `supabase db push`).

2. The practitioner signs in to the app once, so they have a user id. They
   apply as a practitioner:

   ```sql
   insert into public.practitioners (user_id, full_name, profession, license_number)
   values (auth.uid(), 'Ma''am Lea Famor', 'SPED teacher', '<licence no.>');
   ```

   Or an admin enters it for them, using their user id.

3. An admin verifies the credentials, then approves:

   ```sql
   update public.practitioners
      set status = 'approved', approved_by = auth.uid(), approved_at = now()
    where user_id = '<practitioner user id>';
   ```

4. The practitioner (or an admin for them) adds a template. It needs every
   domain (`communication`, `play`, `social`, `attention`) covered by at least
   one item, and unique item ids. Otherwise the app ignores it and keeps the
   bundled draft.

   ```sql
   insert into public.questionnaire_templates
     (template_key, version, questionnaire_type, title, intro, items, authored_by)
   values (
     'sped_parent_checklist', 1, 'both',
     'A few questions about your child',
     'Think about the last two weeks at home...',
     '[{"id":"comm_name","domain":"communication","text":"My child responds when I call their name."},
       {"id":"play_pretend","domain":"play","text":"My child plays pretend."},
       {"id":"social_turn","domain":"social","text":"My child waits for their turn in a simple game."},
       {"id":"attn_finish","domain":"attention","text":"My child finishes a short activity with me."}]',
     '<practitioner user id>'
   );
   ```

5. An admin reviews it and activates it, marking it validated if it has been
   validated:

   ```sql
   update public.questionnaire_templates
      set is_active = true, status = 'validated'
    where template_key = 'sped_parent_checklist' and version = 1;
   ```

The next parent who finishes an assessment gets it. Every stored answer
records `template_id`, `template_version` and `template_status`, so answers
from different templates are never mixed.

## Phase 2 (Future Recommendations if not built)

- A practitioner portal (web) for applying, authoring and previewing templates.
- With explicit parent consent (RA 10173), sharing a family's questionnaire
  results with the practitioner whose template they answered.
