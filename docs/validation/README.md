# Expert content validation of the questionnaires

The questions parents, guardians and teachers answer around an assessment —
the home questionnaire, "Before your child starts" and "What did you see?" —
were written by the proponents and are not yet validated. This kit is how
they get validated by experts (SPED teachers, therapists) before use.

| File | For |
|---|---|
| `Aumazing_Expert_Content_Validity_Rating_Sheet.docx` | Each expert rates every question's relevance and clarity (1–4), answers yes/no checks, and comments. |
| `Aumazing_Content_Validity_Calculator.xlsx` | The proponents enter the returned ratings (yellow cells) and read I-CVI, modified kappa, S-CVI/Ave and a keep/revise decision per item. |
| `src/` | Rebuilds both from the app's current built-in questions. |

## Procedure

1. Recruit at least three experts, ideally six or more (Lynn, 1986). Record
   each expert's profession, licence and experience on page 1 of the sheet.
2. Each expert rates independently.
3. Enter each sheet as one expert column in the calculator.
4. Items marked **Revise** (I-CVI below 1.00 with 3–5 experts, below .78 with
   6 or more) are reworded using the comments and rated again, or removed.
   Aim for S-CVI/Ave of .90 or higher per part (Polit & Beck, 2006).
5. Enter the final wording in the practitioner portal (Questionnaires) and have
   an administrator mark it **validated** and put it in use. Every answer
   records the template version and status.
6. After a pilot with parents, compute Cronbach's alpha per area of Part A.

## Rebuilding after the questions change

```sh
(cd packages/questionnaire_core && dart run tool/export_templates.dart) > docs/validation/src/templates.json
node docs/validation/src/build_rating_sheet.js        # needs the docx npm package
python docs/validation/src/build_calculator.py         # needs openpyxl
```

## References

- Lynn, M. R. (1986). Determination and quantification of content validity.
  *Nursing Research, 35*(6), 382–385.
- Polit, D. F., & Beck, C. T. (2006). The content validity index: Are you sure
  you know what's being reported? Critique and recommendations. *Research in
  Nursing & Health, 29*(5), 489–497.
- Polit, D. F., Beck, C. T., & Owen, S. V. (2007). Is the CVI an acceptable
  indicator of content validity? Appraisal and recommendations. *Research in
  Nursing & Health, 30*(4), 459–467.
