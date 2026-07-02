# Manuscript Revision 2 — Chapter 3 (Paste-Ready)

> **How to use this file:** Each section below is labeled
> `### REPLACE 3.x.y — <Section Title>`. Open the **Revision1** tab of the
> Google Doc, find the matching subsection heading, **delete the current
> body** of that subsection (keep the heading), and **paste the block
> directly under it**. Do not paste the `### REPLACE …` line itself.
>
> **Scope lock (v2, May 2026):** Removed — Specialist/Doctor portal,
> Jitsi/video conferencing, consultation booking, in-app messaging.
> Added — Freemium model with Google Maps SDK + monthly subscription,
> trial assessment cycle, offline games always free, Interactive Therapy
> Locator (Premium), Basic vs. Advanced Dashboard.

---

## CHAPTER III — METHODOLOGY

### REPLACE 3.1.1 — Rationale for Using Agile-Kanban

The team adopted **Agile-Kanban** (Atlassian, 2025) for three reasons that
match the project's constraints. First, the team is small (two developers)
and the scope was deliberately narrowed mid-cycle — conditions where
pull-based, continuous-flow development outperforms timeboxed Scrum
because work can be re-prioritized the moment validator feedback arrives.
Second, the project has heterogeneous work types (mobile UI, AI model
training, LBS integration, billing) that do not fit neatly into uniform
sprints; Kanban allows each work type to flow through the same board at
its own natural cadence. Third, Kanban's explicit **work-in-progress
(WIP) limits** and visual flow surface bottlenecks early, which is
critical given the limited capstone timeline.

---

### REPLACE 3.1.2 — Kanban Workflow Stages

The team uses a Trello board with the following columns and WIP limits:

| Column | Purpose | WIP Limit |
|---|---|---|
| Backlog | Unrefined ideas, pending stories | ∞ |
| Ready | Refined, estimated, acceptance-criteria written | 6 |
| In Progress | Currently being implemented | 2 per developer |
| In Review | Peer review / adviser review | 3 total |
| Testing | UAT against acceptance criteria | 3 total |
| Done | Merged and deployed to staging | ∞ |

When a WIP limit is reached, the team **swarms** to clear the bottleneck
before pulling new work. Each card carries: user-story ID, acceptance
criteria, size (S/M/L), a blocked flag, and links to wireframes, code,
and test cases.

---

### REPLACE 3.1.3 — Development Activities in the Framework

Development is organized around four continuous activities rather than
sprints:

1. **Replenishment** (weekly): refill `Ready` from `Backlog` after
   re-prioritization with the adviser.
2. **Daily stand-up** (10 minutes): identify blocked cards and confirm
   WIP compliance.
3. **Delivery on demand**: any card that clears `Testing` is merged and
   shipped to staging immediately.
4. **Retrospective** (bi-weekly): inspect lead time, cycle time, and
   cumulative-flow data to adjust WIP limits and process.

Two flow metrics are tracked weekly: **lead time** (days from
`Backlog → Done`) and **cycle time** (days from `In Progress → Done`).
A simple **cumulative flow diagram** plots card counts per column per
week to expose WIP bloat and throughput trends.

---

### REPLACE 3.1.4 — Artifacts of the Chosen Framework

The Kanban implementation produces the following artifacts, all of which
are referenced from later chapters:

- **Product backlog** (Trello): the canonical list of user stories.
- **Kanban board snapshots** (Figures 3.1, 3.2, 3.3): early-, mid-, and
  late-project board states showing WIP evolution.
- **Cumulative flow diagram** (Figure 3.4): weekly column counts.
- **Lead-time and cycle-time chart** (Figure 3.5).
- **Definition of Done checklist:** code reviewed, unit tests green,
  acceptance criteria met, deployed to staging.

---

### REPLACE 3.2.1 — User Requirements

The system has **three** user roles. The Specialist/Doctor role has been
intentionally excluded to keep the prototype scope focused on the
AI-driven assessment and the freemium therapy locator.

| Role | Description |
|---|---|
| **Parent (Free)** | Primary caregiver of a child aged 2–6 with early-stage ASD. Can complete one full assessment cycle, play offline games freely, and view the directory at city level. |
| **Parent (Premium)** | Same as above plus continuous AI-driven personalization, the Interactive Therapy Locator with map and GPS-based ranking, and the Advanced Dashboard. |
| **Administrator** | Manages content (modules, games), therapy-center records, and users via a web portal. |

---

### REPLACE 3.2.2 — Functional Requirements

| ID | Requirement | Tier |
|---|---|---|
| FR-01 | The system shall allow parents to register, sign in, or use Guest Mode. | Free |
| FR-02 | The system shall allow a parent to create and edit one or more child profiles (display name, birth date, sex, avatar, optional developmental notes, sensory preferences). | Free |
| FR-03 | The system shall deliver one full free assessment cycle per child: gamified Pre-Assessment → AI-recommended Learning Modules for that cycle → Post-Assessment. | Free |
| FR-04 | The system shall classify the child's skill band per domain (communication, social, play) using an XGBoost model trained on gameplay features. | Free (during trial) / Premium (continuous) |
| FR-05 | The system shall allow unrestricted access to the offline games library regardless of subscription tier and regardless of network availability. | Free |
| FR-06 | The system shall present a **Basic Dashboard** showing the latest cycle summary (overall band, modules completed, time on task). | Free |
| FR-07 | The system shall enforce parent-defined daily screen-time limits and lock further play once the limit is reached. | Free |
| FR-08 | The system shall display a **Therapy Directory** that lists each center's name and city only. | Free |
| FR-09 | The system shall offer a monthly subscription to upgrade the parent account to **Premium**, processed through the Google Play Billing Library. | All |
| FR-10 | The system shall, for Premium users, continue generating personalized module recommendations after every completed assessment cycle, indefinitely while the subscription is active. | Premium |
| FR-11 | The system shall, for Premium users, present the **Interactive Therapy Locator** with full center details (address, contact, services, hours). | Premium |
| FR-12 | The system shall, with the parent's just-in-time location permission, retrieve the device's GPS coordinates and rank therapy centers by ascending distance using the **Haversine formula**. | Premium |
| FR-13 | The system shall render an in-app Google Map (Google Maps SDK for Android) showing the parent's location and nearby therapy centers as markers. | Premium |
| FR-14 | The system shall provide a "Get Directions" action that hands off to the device's default maps application via Android Intent (`google.navigation:` / `geo:` URI); the system itself does **not** compute or render routes. | Premium |
| FR-15 | The system shall present an **Advanced Dashboard** with skill-band trend lines and per-domain history across cycles. | Premium |
| FR-16 | The system shall verify subscription status against a Google Play receipt and a Supabase `entitlements` record, and shall honor `expires_at` while offline. | All |
| FR-17 | The system shall allow administrators to manage modules, games, therapy centers, and users through a web portal. | Admin |
| FR-18 | The system shall persist all parent and child data locally (SQLite) first and synchronize to Supabase when online and authenticated. | All |

---

### REPLACE 3.2.3 — Non-Functional Requirements

| ID | Category | Requirement |
|---|---|---|
| NFR-01 | **Usability (ASD-aligned)** | All primary controls shall be ≥ 64 dp, use a soft palette, and avoid sudden motion or audio peaks. |
| NFR-02 | **Performance** | Pre/post-assessment screens shall render within 2 s on a mid-range Android device (4 GB RAM, Android 10+). |
| NFR-03 | **Offline-first** | The app shall remain fully usable for offline games, dashboard viewing, and screen-time enforcement without network connectivity. |
| NFR-04 | **Privacy — Location** | GPS shall be requested **just-in-time** on the Locator screen using foreground-only permission; coordinates shall **not** be persisted, logged, or transmitted to Supabase. |
| NFR-05 | **Privacy — Child data** | Developmental notes are optional and treated as parent-reported context, never as a clinical diagnosis. |
| NFR-06 | **Security** | All Supabase tables shall enforce Row-Level Security; subscription receipts shall be verified server-side before granting premium entitlements. |
| NFR-07 | **Reliability** | Local writes shall never block the UI; sync failures shall retry with exponential backoff. |
| NFR-08 | **Cost control** | Map tile and Places usage shall stay within Google Maps Platform's free monthly tier through aggressive caching of center coordinates and a per-session map-load cap. |
| NFR-09 | **Accessibility** | Color contrast shall meet WCAG 2.1 AA; all icons shall be paired with short text labels. |
| NFR-10 | **Maintainability** | The codebase shall follow the offline-first repository pattern (local SQLite → sync to Supabase) for every data entity. |

---

### REPLACE 3.3.1 — Software Requirements for Development

| Category | Tool | Purpose |
|---|---|---|
| IDE | Android Studio, VS Code | Flutter and Dart development |
| Framework | Flutter (stable channel) | Cross-platform mobile UI |
| Game engine | Flame Engine | 2D mini-games |
| Backend | Supabase (Auth, Postgres, Storage, RLS) | Cloud database and authentication |
| Local DB | SQLite (`sqflite`) | Offline-first storage |
| AI runtime | Python + XGBoost (training) · ONNX Runtime Mobile (inference) | Skill-band classification |
| Maps | **Google Maps SDK for Android**, Google Maps Platform Places (basic data) | Premium Therapy Locator |
| Billing | **Google Play Billing Library v6** | Monthly subscription |
| API layer | FastAPI | Inference and admin endpoints |
| Design | Figma | Wireframes and prototypes |
| VCS / CI | GitHub + GitHub Actions | Source control and signed APK builds |
| Project tracking | Trello | Kanban board |

*Removed from prior version:* Jitsi Meet SDK and any video-conferencing
dependency are no longer part of the stack.

---

### REPLACE 3.3.3 — Hardware and Software Requirements for End Users

**Parent / Child (Mobile App)**

- Android 8.0 (API 26) or higher.
- 2 GB RAM minimum, 4 GB recommended.
- 200 MB free storage.
- GPS-capable device (required only for the Premium Locator).
- Internet connection optional except for sign-in, sync, subscription
  verification, and map tile loading.

**Administrator (Web Portal)**

- Modern desktop browser (Chrome, Edge, or Firefox, latest two versions).
- Stable broadband internet connection.

---

### REPLACE 3.4.1 — Economic Feasibility

The project is economically feasible. One-time development costs are
absorbed as academic work; recurring operating costs are limited to
(a) Supabase free/Pro tier sized for prototype usage, (b) Google Maps
Platform usage capped within the free monthly tier through caching, and
(c) Google Play developer account fees. Premium monthly subscriptions
provide a recurring revenue stream that, per the cost-benefit analysis
in §3.6, recovers operating costs after a small validator-tester base
converts. Free-tier users incur near-zero variable cost because they do
not consume map tiles or AI inference beyond the trial cycle.

---

### REPLACE 3.4.2 — Technical Feasibility

All chosen technologies are mature, well-documented, and free for
prototype-scale use. The most novel component, the XGBoost-based
skill-band classifier, is supported by published evidence on small
tabular data (Grinsztajn et al., 2022; Velarde et al., 2024). The
Locator uses the Google Maps SDK's standard map view and the
**Haversine formula** for distance ranking — a closed-form computation
that imposes no server load. Navigation is delegated to the user's
installed maps app via Android Intent, eliminating the need to build a
routing engine. Removing video conferencing, booking, and the specialist
portal materially reduces integration risk.

---

### REPLACE 3.4.3 — Operational Feasibility

Parents already use Android phones daily; the freemium model lets them
adopt the app at zero cost and pay only when they need continuous
personalization or the locator. Therapy-center information is curated by
the administrator, so directory accuracy does not depend on therapist
participation — a critical operational simplification compared with the
previous tele-health design.

---

### REPLACE 3.6 — Cost-Benefit Analysis (entire section)

**Purpose.** This analysis decides whether Aumazing should proceed to
prototype deployment by comparing the recurring cost of the manual
home-intervention status quo against the projected operating cost of the
proposed system over a three-year horizon. The decision rule is:
**proceed if payback ≤ 3 years and projected annual savings per
household ≥ ₱3,000**.

**A. Present annual cost of the manual process (per household).**

| Line item | Computation | Annual cost |
|---|---|---|
| Printed worksheets / flashcards | 50 pages × ₱2 × 12 | ₱1,200 |
| Photocopies of therapist handouts | ₱200 × 4 quarters | ₱800 |
| Reward stickers / reinforcers | ₱150 × 12 | ₱1,800 |
| Transportation for follow-ups | ₱500 × 8 trips | ₱4,000 |
| **Cash subtotal** | | **₱7,800** |
| Parent preparation time (disclosed, not counted) | 2 h/day × 30 × ₱10 × 12 | ₱7,200 |

**B. Projected annual operating cost of Aumazing (per household,
conservative).**

| Line item | Computation | Annual cost |
|---|---|---|
| Supabase usage (prototype share) | prorated | ₱600 |
| Google Maps Platform usage (within free tier with caching) | ₱0 expected; ₱600 buffer | ₱600 |
| Google Play developer fee (one-time $25, amortized) | prorated | ₱150 |
| Google Play Billing fee on subscriptions (15% on first year) | computed against revenue, not user cost | — |
| **Operating subtotal (cost to operator)** | | **₱1,350** |

**C. Premium subscription pricing.**

| SKU | Price | Net to operator after Play 15% fee |
|---|---|---|
| Premium Monthly | ₱149/month | ₱126.65/month ≈ ₱1,520/year |

**D. Annual savings per converted household.**

Even when a household upgrades to Premium for the entire year, the
parent still avoids most printing, photocopy, and transport costs because
activities and the locator replace them:

> Savings = ₱7,800 (manual) − ₱149 × 12 (subscription) − ₱1,000
> (residual incidentals) = **₱5,012 / year per Premium household**.

Free-tier households still save approximately ₱3,200/year through one
trial cycle plus offline games (reduced printing, no transport for
routine practice).

**E. Payback period.**

One-time prototype infrastructure cost (domains, signing keys, dev
account, design tools) ≈ **₱12,000**.

> Payback (per Premium household) = ₱12,000 ÷ ₱5,012 ≈ **2.4 years
> ≈ 2 years 5 months**.

**F. Decision.** Both thresholds are satisfied (payback < 3 years;
annual savings > ₱3,000). The study **recommends proceeding** with
prototype deployment under the freemium model.

---

### REPLACE 3.7 — Risk Management

| ID | Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|---|
| R-01 | XGBoost model underperforms on small validator dataset | Medium | High | Use cross-validation, fallback rule-based recommender if model confidence < threshold. |
| R-02 | Google Maps Platform monthly free quota exceeded | Low | Medium | Cache center coordinates locally; cap map loads per session; monitor billing alerts. |
| R-03 | Parent denies GPS permission | Medium | Low | Graceful fallback: rank centers by parent-entered city only; show clear rationale before request. |
| R-04 | Subscription receipt validation fails offline | Low | Medium | Cache last verified `expires_at`; honor offline; re-verify on next online launch. |
| R-05 | Therapy-center data becomes stale | Medium | Medium | Administrator portal supports periodic updates; show `last_updated` per center. |
| R-06 | Sync conflicts between local SQLite and Supabase | Medium | Medium | Last-write-wins per row with `updated_at`; pending-write queue with retry. |
| R-07 | Sensory-trigger content slips into a module | Low | High | Sensory-review checklist in Definition of Done; validator sign-off per module. |
| R-08 | Scope creep back into tele-health features | Low | High | Scope is contractually locked in this revision; future tele-health work is reserved for post-capstone. |

---

### REPLACE 3.8 — Testing Plan

Testing follows a layered strategy aligned with the freemium model:

| Layer | Scope | Tools | Pass criteria |
|---|---|---|---|
| Unit | Repositories, Haversine ranking, entitlement gate, recommender rules | Dart `test`, Python `pytest` | ≥ 80% line coverage on `core/` |
| Widget / UI | Each ASD-aligned screen | `flutter_test` | All goldens match; no overflow |
| Integration | Offline-first sync, subscription receipt flow, GPS permission flow | `integration_test` | All happy paths green; airplane-mode path green |
| Model | XGBoost classifier | `pytest` + held-out set | Macro-F1 ≥ baseline rule-based |
| UAT | Validator scripts per user story | Manual + checklist | 100% acceptance criteria met per cycle |

**Premium-specific test cases**

1. Free user blocked at second cycle with upgrade prompt.
2. Premium user receives new modules after every completed cycle.
3. Locator hidden for free users.
4. GPS denied falls back to city-level list.
5. "Get Directions" opens the native maps app via intent.
6. Subscription expiry downgrades the account at next launch.

---

### REPLACE 3.9 — Deployment Plan

Deployment proceeds in six phases:

1. **Environment setup.** Provision dev, staging, and demo environments.
   Configure Gradle flavors (`dev`, `staging`, `prod`), Android signing
   keys, and a GitHub Actions pipeline producing signed APKs on tagged
   commits.
2. **Supabase configuration.** Apply migrations, enable Row-Level
   Security on every table, configure email and Google auth, seed
   reference data (modules, therapy centers), and store keys in the team
   secret manager.
3. **Google Play and billing setup.** Create the Play Console listing,
   configure the Premium Monthly subscription SKU, register
   license-testing accounts, and verify receipt validation against a
   Supabase Edge Function.
4. **Maps configuration.** Enable Google Maps SDK for Android in Google
   Cloud, restrict the API key by package name and SHA-1, set up billing
   alerts at 50%, 80%, and 100% of the free tier, and verify caching of
   center coordinates.
5. **Validator distribution.** Distribute a signed internal-testing APK
   via Play Console internal track, accompanied by an install guide,
   consent form, and a 15-minute walkthrough video. Pre-provision sandbox
   accounts.
6. **Validator training and support.** Run a 1-hour synchronous
   orientation on evaluation criteria, then provide async support via a
   dedicated channel. Issues are triaged on the Kanban board and
   addressed in the next build.

---

## Summary of Chapter 3 changes

- **Removed everywhere:** Jitsi, video conferencing, booking, specialist
  portal, in-app messaging.
- **New requirements:** entitlement gating (FR-09, FR-10, FR-16), Locator
  + Haversine + Google Maps SDK + native-map intent (FR-11–FR-14), basic
  vs. advanced dashboard (FR-06, FR-15), trial cycle semantics (FR-03,
  FR-04).
- **Privacy hardened:** NFR-04 forbids persisting GPS coordinates;
  foreground-only just-in-time permission.
- **CBA rebuilt:** itemized line items, Premium pricing math (₱149/month),
  ₱5,012/year savings per Premium household, payback ≈ 2 years 5 months
  → proceed.
- **Risk register:** added map-quota, GPS-denial, receipt-validation, and
  scope-creep risks.
