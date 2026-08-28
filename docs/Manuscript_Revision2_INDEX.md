# Manuscript Revision 2 — Master Checklist

> Tick each box as you paste the block into the **Revision1** tab of the
> Google Doc. Items are listed in **document order** so you can work
> top-to-bottom in one pass.
>
> Legend:
> - **REPLACE** — overwrite the body under the existing heading.
> - **NEW** — insert as a brand-new subsection at the indicated position.
> - **EXPAND** — append to the end of the existing subsection (do not
>   delete what is already there).
> - **RENAME** — change a heading's text.
> - **FIX** — correct a typo or label.

---

## Chapter 1 — Introduction
*Source file: `docs/Manuscript_Revision2_Chapter1.md`*

- [ ] **REPLACE 1.1** — Background, *final paragraph only* ("To solve these occurring problems…"). Earlier paragraphs untouched.
- [ ] **REPLACE 1.2** — Objectives of the Study (entire section). Old Objective 4 retired; new Objectives 4 (Freemium Locator + LBS) and 5 (subscription/entitlement) added.
- [ ] **REPLACE 1.3** — Significance, *Therapists / Therapy Centers entry only*. Other beneficiary entries untouched.
- [ ] **REPLACE 1.4.1** — Scope (entire subsection).
- [ ] **REPLACE 1.4.2** — Delimitation (entire subsection).
- [ ] *(1.5 Time and Place — no change.)*
- [ ] **REPLACE 1.6** — Operational Definition of Terms. Add new freemium/LBS terms; **delete** Video Consultation, Tele-therapy Session, Specialist Portal, Appointment Booking, In-App Messaging, and the old tele-health *Therapy Gateway* entry if present.
- [ ] **REPLACE 1.7** — Conceptual Framework (entire section). Note: redraw **Figure 1.7** per the diagram instructions in the chapter file.

---

## Chapter 2 — Review of Related Literature, Studies, and Systems
*Source file: `docs/Manuscript_Revision2_Chapter2.md`*

- [ ] **NEW 2.0** — Bridging Introduction. Insert immediately after the Chapter II heading, before §2.1.
- [ ] *(2.1 ASD and Early Intervention — no change.)*
- [ ] **EXPAND 2.2** — Append paragraphs on digital DTT (Scarcella, Yakubova) and Aumazing's discrete-trial implementation.
- [ ] **EXPAND 2.3** — Append paragraphs on Hussein, Papadakis, Wang, Landers, plus the deliberate inclusion/exclusion of gamification elements.
- [ ] **EXPAND 2.4** — Append paragraphs justifying XGBoost over alternatives (Grinsztajn, Shwartz-Ziv, Hakkal, Velarde).
- [ ] *(2.5 Mobile Applications for Home-Based Therapy — no change.)*
- [ ] **EXPAND 2.6** — Append paragraph on dashboard-tier evidence (Lu, Jiang, Pérez-Sola).
- [ ] **RENAME 2.7** — *"Therapy Center Access and Remote Support Systems"* → **"Therapy Center Access and Location-Based Discovery"**.
- [ ] **REPLACE 2.7** — Body rewritten around discoverability + LBS + freemium directory; tele-health framing fully retired.
- [ ] **EXPAND 2.8** — Append comparison paragraph (Otsimo's content-unlock model vs. Aumazing's freemium structure).
- [ ] **EXPAND 2.9** — Append comparison paragraph (AutiSpark vs. Aumazing).
- [ ] **NEW 2.10** — Synthesis Artifacts subsection containing **Table 2.1** (feature comparison) and **Figure 2.1** (ABA → mechanics mapping).

---

## Chapter 3 — Methodology
*Source file: `docs/Manuscript_Revision2_Chapter3.md`*

- [ ] **REPLACE 3.1.1** — Rationale for Using Agile-Kanban.
- [ ] **REPLACE 3.1.2** — Kanban Workflow Stages (with WIP-limit table).
- [ ] **REPLACE 3.1.3** — Development Activities in the Framework.
- [ ] **REPLACE 3.1.4** — Artifacts of the Chosen Framework.
- [ ] **REPLACE 3.2.1** — User Requirements (three roles; specialist removed).
- [ ] **REPLACE 3.2.2** — Functional Requirements (FR-01 … FR-18).
- [ ] **REPLACE 3.2.3** — Non-Functional Requirements (NFR-01 … NFR-10).
- [ ] **REPLACE 3.3.1** — Software Requirements for Development. *Drop Jitsi; add Google Maps SDK and Play Billing.*
- [ ] *(3.3.2 Hardware Requirements for Development — no change.)*
- [ ] **REPLACE 3.3.3** — Hardware/Software Requirements for End Users.
- [ ] **REPLACE 3.4.1** — Economic Feasibility.
- [ ] **REPLACE 3.4.2** — Technical Feasibility.
- [ ] **REPLACE 3.4.3** — Operational Feasibility.
- [ ] *(3.4.4 Schedule Feasibility — no change.)*
- [ ] *(3.5 Work Breakdown Structure — no change.)*
- [ ] **REPLACE 3.6** — Cost-Benefit Analysis (entire section, with itemized tables and payback math).
- [ ] **REPLACE 3.7** — Risk Management (R-01 … R-08).
- [ ] **REPLACE 3.8** — Testing Plan (with premium-specific test cases).
- [ ] **REPLACE 3.9** — Deployment Plan (six phases, includes Maps + Billing setup).

---

## Chapter 4 — System Design
*Source file: `docs/Manuscript_Revision2_Chapter4.md`*

- [ ] **REPLACE 4.1** — Use Case Diagram intro + 18-row use-case table (now includes UC-04a Cloud Classification and UC-11a PayMongo Webhook). Adds Connectivity column. Update **Figure 4.1** accordingly.
- [ ] **REPLACE 4.1.1** — Use Case Description (new entries for UC-04, UC-04a, UC-05, UC-06, UC-11, UC-11a, UC-14, UC-15; retain unchanged ones; remove video/booking/specialist descriptions).
- [ ] **REPLACE 4.2** — Sequence Diagram intro paragraph (now references **five** sequence diagrams).
- [ ] **REPLACE 4.2.1** — Sequence Diagram for User Registration and Login (now includes EntitlementService).
- [ ] **REPLACE 4.2.2** — Sequence Diagram for Gamified Assessment and Module Recommendation (rewritten around cloud FastAPI/XGBoost; offline-queue branch via `pending_classifications`).
- [ ] **REPLACE 4.2.3** — Sequence Diagram for Learning Activity and Progress Tracking (with Basic vs. Advanced Dashboard branch).
- [ ] **RENAME 4.2.4** — *"Sequence Diagram for Therapy Access"* → **"Sequence Diagram for Freemium Therapy Locator"**.
- [ ] **REPLACE 4.2.4** — Body rewritten around entitlement gate, JIT GPS, Haversine ranking, native-map intent. Redraw the figure.
- [ ] **NEW 4.2.5** — Sequence Diagram for **PayMongo Subscription Purchase** (parallel client-redirect / authoritative-webhook branches). Draw new figure.
- [ ] **REPLACE 4.3** — Prototype intro paragraph.
- [ ] **REPLACE 4.3.1** — Splash Screen and Welcome Interface.
- [ ] **REPLACE 4.3.2** — Login and Registration Screen.
- [ ] **REPLACE 4.3.3** — Child Profile Management Screen.
- [ ] **REPLACE 4.3.4** — Sensory Preferences Screen.
- [ ] **REPLACE 4.3.5** — Gamified Pre-Assessment Screen.
- [ ] **REPLACE 4.3.6** — Learning Module Screen (with free-tier upgrade card behavior).
- [ ] **FIX 4.3.7** — Heading typo: *"Pre-Asessment"* → **"Pre-Assessment"**.
- [ ] **REPLACE 4.3.7** — Pre-Assessment Gameplay Activity Screen.
- [ ] **REPLACE 4.3.8** — Parent Dashboard Screen (Basic vs. Advanced).
- [ ] **REPLACE 4.3.9** — Screen-Time Management Screen.
- [ ] **NEW 4.3.10** — Therapy Directory Screen (Free).
- [ ] **NEW 4.3.11** — Premium Paywall Screen *(PayMongo — Custom Tabs + Checkout Sessions)*.
- [ ] **NEW 4.3.12** — Interactive Therapy Locator Screen (Premium).
- [ ] **NEW 4.3.13** — Therapy Center Detail Screen (Premium).
- [ ] **NEW 4.3.14** — Subscription Management Screen *(PayMongo — renewal-per-checkout, no Play Store deep links)*.
- [ ] **NEW 4.3.15** — Web Platform Prototype: Administrator Portal *(extended with Payment Audit + AI Service Health tabs)*.
- [ ] **NEW 4.3.16** — Assessment Result / Pending Screen *(visible justification for cloud-required result generation)*.
- [ ] *(Delete from §4.3 any pre-existing prototype screens for video consultation, booking, or specialist case review.)*
- [ ] **REPLACE 4.4** — Entity Relationship Diagram intro + entity table. Redraw the ERD to drop `consultations`, `appointments`, `specialists`, `messages`, `video_sessions`, and `entitlements.play_purchase_token`; add `entitlements` (revised), `payment_intents`, `webhook_events`, `webhook_dead_letter` (PayMongo Subsystem cluster), `pending_classifications` (offline-queue), and `trial_cycle_completed` on `children`. Add `model_version` and `confidence` to `assessment_cycles`.
- [ ] **REPLACE 4.5** — Data Dictionary entries for `entitlements` (revised), `payment_intents` (new), `webhook_events` (new), `webhook_dead_letter` (new), `assessment_cycles` (revised), `pending_classifications` (new), `therapy_centers`, and `children`. Delete the dictionary entries for the removed tables and the `play_purchase_token` column.
- [ ] **REPLACE 4.6** — Offline-First Sync Architecture (PayMongo entitlement freshness, cloud-required classification with backoff, webhook idempotency, explicit no-persist GPS rule, failure-mode table).

---

## Cross-cutting cleanups (do these last)

- [ ] Search the document for the word **"Jitsi"** — every occurrence must be removed (intro, lit review, methodology, references list, technology references list).
- [ ] Search for **"video conferencing"**, **"video call"**, **"video consultation"**, **"tele-consultation"**, **"appointment booking"**, **"booking"**, **"specialist portal"**, **"in-app messaging"** — remove or rephrase every occurrence.
- [ ] **v2.1:** Search for **"Google Play Billing"**, **"Play Billing"**, **"play_purchase_token"**, **"purchase token"**, **"Play Store"** (in subscription contexts) — replace with PayMongo terminology or delete. Affects §3.3.1, FR-09, FR-16, §3.6 cost model, §3.9 deployment plan.
- [ ] **v2.1:** Search for **"ONNX"**, **"ONNX Runtime Mobile"**, **"on-device classifier"**, **"on-device inference"** — replace with *FastAPI inference service* / *cloud XGBoost*. Affects §3.3.1 software requirements and any chapter referencing the AI runtime.
- [ ] Search for **"therapy gateway"** — replace with *"therapy directory"* or *"freemium therapy locator"* depending on context.
- [ ] In the **Technology References** list, remove the **Jitsi** entry. Confirm Google Maps Platform and Google Play Billing are present (add if missing).
- [ ] In the **Acronyms / Abbreviations** list (if any), remove tele-health-related entries; add **LBS** (Location-Based Services), **GPS**, **SDK**, **API**, **ABA**, **TEACCH**, **JIT** (Just-in-Time), **WCAG**.
- [ ] In the **Table of Figures**, update or insert: Figure 1.7 (Conceptual Framework — redrawn), Figure 2.1 (ABA → mechanics), Figure 4.1 (Use Case — redrawn), Figure 4.2 (Sequence — Login), Figure 4.3 (Sequence — Assessment), Figure 4.4 (Sequence — Progress), **Figure 4.5 (Sequence — Freemium Therapy Locator, replacing the old Therapy Access figure)**, ERD figure under §4.4.
- [ ] In the **Table of Tables**, update or insert: Table 2.1 (Feature Comparison), Table 3.x (Functional Requirements), Table 3.x (Non-Functional Requirements), Table 3.x (Cost-Benefit line items), Table 3.x (Risk Register), Table 4.x (Use Cases).
- [ ] Re-generate the **Table of Contents** in Google Docs after all paste operations (Insert → Table of contents → Refresh).
- [ ] Final read-through to confirm no "Specialist", "Doctor", or "Therapist Portal" actor references remain in any diagram caption or use-case table.

---

## Quick stats (v2.1 — PayMongo + Cloud AI)

- **Total action items:** 53 paste/edit operations + 12 cross-cutting cleanups.
- **REPLACE blocks:** 38
- **NEW blocks:** 10 *(added §4.2.5 PayMongo sequence + §4.3.16 Result/Pending screen)*
- **EXPAND blocks:** 5
- **RENAME / FIX:** 3
- **Chapter 3 follow-up needed:** Play Billing → PayMongo, ONNX → FastAPI propagation.
- **Files to keep open while pasting:**
  - `docs/Manuscript_Revision2_Chapter1.md`
  - `docs/Manuscript_Revision2_Chapter2.md`
  - `docs/Manuscript_Revision2_Chapter3.md`
  - `docs/Manuscript_Revision2_Chapter4.md`
  - `docs/Manuscript_Revision2_INDEX.md` *(this file)*

---

## Recommended paste order

1. Work **top-to-bottom**, chapter by chapter, in document order.
2. After each chapter, do a quick **Find & Replace** sweep for that chapter's removed terms (Jitsi, video, booking, specialist) to catch anything stranded in captions, footnotes, or figure labels.
3. Save the **Cross-cutting cleanups** section for the very end so you don't fight the search-and-replace tool while still pasting new content.
4. Refresh the Table of Contents and the Lists of Figures/Tables only after every other change is complete.
