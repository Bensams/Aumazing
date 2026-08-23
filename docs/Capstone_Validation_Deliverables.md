# Aumazing Capstone Validation Deliverables

**Document control**

- Project: `____________________________`
- Version/build: `____________________________`
- Study period: `____________` to `____________`
- Adviser: `____________________________`
- Ethics/DPO reference: `____________________________`
- Prepared by: `____________________________`
- Date: `____________`

This packet is an operational template. Replace every bracketed field before signing. It supports educational usability validation only; it does not diagnose autism or replace professional assessment. Obtain institutional approval, school authorization, parent/guardian consent, and child assent where applicable before collecting data.

## 1. Configurable Study Register

| Field | Planned value | Final value |
|---|---|---|
| School/client | `[School name]` | `________________` |
| ASD learners | `[5]` | `______` |
| SPED teachers | `[3]` | `______` |
| Sessions per learner | `[2]` | `______` |
| Games assessed | `[Game IDs]` | `________________` |
| Study coordinator | `[Name/contact]` | `________________` |
| Data retention end date | `[YYYY-MM-DD]` | `________________` |

Participant IDs must be random codes (for example `AUM-001`). Keep the re-identification key separately from exported data. Do not place names, faces, voices, exact birth dates, diagnosis documents, GPS, or unnecessary timestamps in analysis exports.

## 2. Client Approval Letter

**Date:** `____________`

**To:** `[School administrator/client name and title]`

**Subject:** Request for school participation and app validation

Dear `[Title and name]`,

We are capstone researchers from `[institution/program]` developing Aumazing, an educational game prototype intended to support structured practice for learners with autism spectrum disorder. We request permission for `[school/client]` to participate in an evaluation from `[start]` to `[end]`.

Activities are limited to teacher review and supervised gameplay sessions. Participation is voluntary. A parent or authorized guardian must provide informed consent, and the learner may stop at any time without penalty. We will use participant codes, restrict access to the research team, and report aggregated or de-identified results. The app is not a diagnostic or clinical device.

Requested support: identify `[number]` eligible SPED teachers, coordinate `[number]` learner sessions, provide a suitable room/device, and allow teachers to complete the attached rubric. No learner will be excluded from school services for declining.

Please indicate approval below. We will provide the protocol, consent materials, data-retention plan, and a summary report after the study.

Respectfully,  
`[Researcher name/signature]`  
`[Contact]`

**Client decision**

- [ ] Approved as described
- [ ] Approved with conditions: `________________________________`
- [ ] Not approved

Client representative: `____________________________`  Title: `________________`  Signature: `________________`  Date: `____________`

Adviser acknowledgement: `____________________________`  Date: `____________`

## 3. SPED Teacher Validation and Sign-Off

Teacher: `________________`  License/role (optional): `________________`  School: `________________`  Date: `____________`

The teacher observes the orientation and `[number]` gameplay sessions, then rates each criterion from 1 (not acceptable) to 4 (excellent). `N/A` is allowed only when the criterion was not observable and must be explained.

| Criterion | 1 | 2 | 3 | 4 | N/A | Evidence/comment |
|---|---:|---:|---:|---:|---:|---|
| Instructions are understandable | | | | | | |
| Visual/audio presentation is accessible | | | | | | |
| Interaction demands are appropriate | | | | | | |
| Feedback/reinforcement is supportive | | | | | | |
| Pacing and breaks are appropriate | | | | | | |
| Learner can recover from errors | | | | | | |
| Data summary is useful to a teacher | | | | | | |
| Privacy and safety controls are adequate | | | | | | |

**Acceptance rule (configurable):** mean score `>= 3.0/4`; no scored item below `2`; zero unresolved safety/privacy defects. Mean: `______`; lowest item: `______`; defects open: `______`; decision: [ ] Pass [ ] Revise and retest.

Teacher comments/recommendations: `______________________________________________________________`

Teacher signature: `____________________________`  Date: `____________`

Researcher witness: `____________________________`  Date: `____________`

## 4. Child Gameplay Session Proof

Use one form per session. Do not record a child name on this form.

Participant ID: `____________`  Session ID: `____________`  Date (YYYY-MM-DD): `____________`  Facilitator: `____________`

Consent verified: [ ] Yes [ ] No  Assent/observed willingness: [ ] Yes [ ] No [ ] Not applicable  Stop/withdrawal requested: [ ] No [ ] Yes, reason: `________________`

| Measure | Value |
|---|---|
| Game IDs | `________________` |
| Items presented/completed | `____ / ____` |
| Correct/incorrect | `____ / ____` |
| Accuracy | `____%` |
| Attempts/retries | `____ / ____` |
| Hints/prompts | `____` |
| Median response time (s) | `____` |
| Breaks | `____` |
| Completion status | `[complete/partial/withdrawn]` |
| App/model version | `________________` |

Observation notes (objective, non-diagnostic): `__________________________________________________`

Facilitator signature: `________________`  Teacher witness: `________________`  Date: `____________`

**Study completion certificate:** `[School/client]` confirms that `______` learners with parent/guardian authorization completed `______` supervised sessions between `[start]` and `[end]`. This certifies participation only and does not certify a diagnosis or treatment outcome.

School representative: `________________`  Title: `________________`  Signature/seal: `________________`  Date: `____________`

## 5. AI Threshold Validation Report

Dataset version: `____________`  Model version/hash: `____________`  Test participants (unique child IDs): `______`  SPED raters: `______`

Split data by child, never by event. Record exclusions and missingness before calculating metrics. Export CSV/JSON may be used for approved analysis; PDF summaries are for human review and are not training data.

| Metric | Proposed threshold | Observed | Pass? |
|---|---:|---:|---|
| Macro-F1 | `>= 0.70` | `______` | [ ] |
| Balanced accuracy | `>= 0.70` | `______` | [ ] |
| Recall for each skill band | `>= 0.60` | `______` | [ ] |
| Weighted Cohen kappa vs SPED rating | `>= 0.60` | `______` | [ ] |
| Largest approved subgroup gap | `<= 0.15` | `______` | [ ] |
| Calibration error (if probabilities shown) | `<= 0.10` | `______` | [ ] |

Decision: [ ] Meets prototype threshold [ ] Does not meet; remediation required  Limitations: `____________________________`

SPED teacher validator: `________________` Signature: `________________` Date: `____________`

Researcher: `________________` Signature: `________________` Date: `____________`

## 6. Defense Evidence Index

File evidence by participant code and version, then redact before showing a panel: approval letter; protocol and risk controls; consent/assent sample; completed teacher rubric; signed session proofs; aggregate count table; de-identified CSV/JSON sample; PDF summary; data dictionary; model card and metrics; confusion matrix/error analysis; defect/retest log; retention/deletion log; final limitations statement.

## 7. Sign-Off and Privacy Checklist

- [ ] Adviser reviewed protocol and thresholds
- [ ] Ethics/institutional review completed or exemption recorded
- [ ] DPO/privacy review completed
- [ ] School/client authorization signed
- [ ] Parent/guardian consent and child assent process approved
- [ ] Access limited to named study team
- [ ] Export contains no direct identifiers
- [ ] Retention/deletion date recorded
- [ ] Withdrawal and deletion requests logged
- [ ] Results reported as educational prototype evidence, not diagnosis
