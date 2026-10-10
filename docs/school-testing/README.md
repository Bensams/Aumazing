# School testing kit (Kindergarten and Grade 1)

Everything needed to get permission for the user acceptance testing at a
school, run it, and close it properly. All files are Word documents in the
capstone format (Times New Roman 12pt, black text, plain 1pt tables).

## Fill in once, then rebuild

1. Open `src/config.json` and replace each `[bracketed]` value: school,
   principal, class advisers, SPED teacher, dean, dates, venue, contact details.
2. Rebuild:

   ```sh
   node docs/school-testing/src/build_kit.js   # needs the docx npm package
   ```

Anything you leave in brackets prints as a blank you can fill in by hand.

## What is in the kit

| # | File | Who signs | Who gets it |
|---|---|---|---|
| 01 | Study Summary | none | Attach to every letter |
| 02 | Letter to Schools Division Superintendent | Proponents, adviser, dean | **Public schools only** (DepEd Division Office) |
| 03 | Letter to School Principal | Proponents, adviser, dean; principal approves | Principal |
| 04 | Capstone Adviser Endorsement | Adviser, dean | Attach to 02 and 03 |
| 05 | Letter to Class Advisers | Proponents; noted by principal | Kindergarten and Grade 1 advisers |
| 06 | Letter to SPED Teacher | Proponents; SPED teacher conforme; noted by principal | SPED teacher |
| 07 | Parent Letter and Consent, English | Proponents; noted by principal; parent signs the form | Every learner's parent or guardian |
| 08 | Parent Letter and Consent, Bisaya | Same as 07 | Parents who prefer Bisaya |
| 09 | Child Assent Script | none | Read to each child, every session |
| 10 | Testing-Day Forms A–F | Proponents, observers | Used during the testing |
| 11 | Thank-You Letter and Certification | Proponents; principal signs the certification | Principal, after the testing |
| 12 | Certificate of Appreciation | Proponents, adviser, dean | One per teacher who helped (landscape) |

The testing-day forms are: A schedule, B confidential code list, C session
record (one per child per session), D incident and withdrawal log,
E attendance sheet, F day-before and on-the-day checklist.

## Order of steps

| When | Step |
|---|---|
| 3–4 weeks before | Adviser and dean sign 02, 03 and 04. Ask the adviser whether the College needs its own ethics or research clearance for work with minors; attach it if so. |
| 3–4 weeks before | **Public school:** submit 02 + 01 + 04 to the Division Office first and ask for their research request form, if they have one (DepEd Order No. 16, s. 2017). Approval can take one to two weeks. **Private school:** skip 02. |
| 2–3 weeks before | Deliver 03 + 01 + 04 (and the Division approval, if public) to the principal. Bring 05–09 so the principal can see them. |
| After approval | Meet the class advisers and SPED teacher. Hand over 05 and 06, agree the schedule (Form A), and go over the games with the SPED teacher. |
| At least 1 week before | Advisers send home 07 or 08 with every learner. Collect signed forms by the reply-by date. Only learners with a signed form take part. |
| Day before | Run Form F. Fill Form B from the returned consent forms and create one child profile per code. |
| Testing days | Sign the visitor log. Read 09 before every session. Fill Form C per session, Form E daily, Form D for any incident or withdrawal. |
| Within a week after | Give the principal 11 to sign the certification, and hand out 12. Send the results summary to the school once the analysis is done. |
| After the final defense | Destroy Form B and delete the data on the date stated in the consent form. |

## Things to keep straight

- **Child profiles use the code, never the name.** Enter `K-01`, `G1-01` and so
  on as the child's name in the app. For the birth date, use the first day of
  the birth month written on the consent form.
- **Respect each optional consent item.** Check Form B before every session.
  Item 3 (diagnosis and therapy) controls whether the observer may answer the
  optional diagnosis and therapy questions in the app. Item 5 controls photos;
  even when allowed, never show a face.
- **Assent every time.** A signed form is not enough. If the child says no or
  shows distress, do not start, or stop right away. Never coax.
- **Never alone with a child.** A teacher is in the room for every session.
- **Do not describe the app as a diagnostic tool.** It is a learning app; the
  letters say plainly that it does not diagnose autism or any other condition.
- **The Bisaya version should be proofread** by a native speaker, ideally the
  SPED teacher or a class adviser, before printing.
- The usability questionnaire for teachers and the expert content-validity
  rating sheet are separate instruments; the rating sheet is in
  `docs/validation/`.
