# Manuscript Revision 2 — Chapter 1 (Paste-Ready)

> **How to use this file:** Each section below is labeled
> `### REPLACE 1.x …` (replace the body under the existing heading) or
> `### REPLACE 1.x — paragraph …` (replace just one paragraph inside a
> larger section, leaving the rest intact). Do not paste the
> `### REPLACE …` line itself.
>
> **Scope lock (v2, May 2026):** Specialist portal, Jitsi/video
> conferencing, booking, and in-app messaging are removed. The
> tele-health gateway is replaced by a **Freemium Therapy Directory** —
> Free users see name + city only; **Premium (₱149/month)** unlocks the
> Interactive Therapy Locator (Google Maps SDK, Haversine ranking,
> native-map navigation hand-off). The Free tier also includes one
> trial assessment cycle and unlimited offline games.

---

## CHAPTER I — INTRODUCTION

### REPLACE 1.1 — Background of the Study (final paragraph only)

> **Find the paragraph that begins with** *"To solve these occurring
> problems and improve the home-based intervention process …"* and
> replace **that paragraph only**. All earlier paragraphs (statistics,
> WHO, Quilendrino et al., DCSNICC, Marc's testimony) remain unchanged.

To solve these occurring problems and improve the home-based intervention
process, the proponents intend to conduct the capstone project entitled
**Aumazing: A Gamified 2D Learning Application with AI-Driven
Assessment for Children with Early-Stage Autism Spectrum Disorder**.
The proposed system will replace manual, unstructured home practices
with a guided digital platform that provides gamified pre-assessments,
leveled learning modules, and post-assessments tailored for young
learners. By integrating an AI-driven assessment framework, the system
will analyze the child's performance — evaluating response time,
accuracy, and interaction patterns — to automatically recommend suitable
learning activities, eliminating the parent's guesswork. The application
adopts a **freemium delivery model**: every parent receives one
complete assessment cycle (pre-assessment → AI-recommended modules →
post-assessment) and unlimited access to an offline games library at
no cost, while a monthly Premium subscription unlocks continuous
personalized recommendations and an **Interactive Therapy Locator** that
uses the device's GPS and the Haversine formula to show nearby therapy
centers and hands off turn-by-turn navigation to the parent's default
maps application. Through this project, continuous, data-driven
developmental intervention becomes a structured and accessible reality
for families in Davao City, while the freemium structure keeps the core
assessment experience financially inclusive.

---

### REPLACE 1.2 — Objectives of the Study (entire section)

The general objective of the study is to develop a gamified 2D mobile
learning application that uses AI-driven assessment and analytics, with
a freemium delivery model, to support the early intervention and
home-based therapy of children aged two to six with early-stage Autism
Spectrum Disorder.

Specifically, this study aims:

1. To **design and develop a 2D gaming environment** that incorporates
   gamified pre-assessments, leveled learning modules, and
   post-assessments tailored to the behavioral and psychological needs
   of children with early-stage ASD, together with an offline games
   library that remains accessible to all users.
2. To **implement an AI-based assessment framework using XGBoost** to
   analyze child performance during gameplay, paired with a rule-based
   and content-based recommender that delivers one full free assessment
   cycle to every user and continuous personalized recommendations to
   Premium subscribers.
3. To **incorporate a screen-time management system and a tiered parent
   dashboard** — a Basic Dashboard available to all users and an
   Advanced Dashboard with skill-band trend lines and per-domain
   history available to Premium subscribers — to ensure balanced usage
   and provide parents with data-driven insights into their child's
   improvement.
4. To **build a Freemium Therapy Directory with a Location-Based
   Interactive Locator**, where Free users see each center's name and
   city, and Premium users access full center details, GPS-aware
   nearest-center ranking via the Haversine formula on an in-app
   Google Map, and a native-map hand-off for turn-by-turn navigation.
5. To **implement a subscription and entitlement system** through the
   Google Play Billing Library, with server-side receipt verification
   on Supabase and offline-tolerant entitlement caching, so that the
   freemium gating is accurate, secure, and resilient to intermittent
   connectivity.

> **Removed from prior version:** the previous Objective 4 ("therapy
> gateway featuring paid video conferencing … remote sessions and
> physical consultations") is fully retired and superseded by the new
> Objectives 4 and 5 above.

---

### REPLACE 1.3 — Significance of the Study (Therapists / Therapy Centers entry only)

> **Find the paragraph that begins with** *"Therapists and therapy
> centers."* and replace it with the version below. The other
> beneficiary entries (Children, Parents, Schools, Future researchers)
> remain unchanged.

**Therapy centers and therapists.** Public services such as DCSNICC
operate at strict capacity, and many parents struggle to discover which
nearby facilities offer the services they need. The Aumazing freemium
directory addresses this discoverability gap directly: every parent can
freely browse the names and cities of registered therapy centers, and
Premium subscribers can locate the nearest providers on an in-app map
and launch turn-by-turn navigation to them through their default maps
application. For therapy centers, this functions as a curated, no-cost
visibility channel that brings them in front of parents at the exact
moment those parents are seeking professional help. Centers retain full
control over their listing accuracy through administrator-coordinated
updates, and no clinical responsibility, scheduling obligation, or
tele-consultation workload is imposed on them by the platform.

---

### REPLACE 1.4.1 — Scope (entire subsection)

The study covers the design and development of **Aumazing**, a gamified
2D mobile learning application for the early intervention and
home-based therapy of children aged two to six with early-stage Autism
Spectrum Disorder (ASD). The system is delivered as an Android mobile
application (Flutter + Flame) for parents and children, supported by a
web-based **Administrator Portal** for content and directory management.
Specifically, the scope includes:

1. **Gamified assessment engine.** Pre-assessment, leveled learning
   modules, and post-assessment activities, all designed around
   ASD-aligned principles (predictability, low sensory load, large
   touch targets, optional reduced motion).
2. **AI-driven recommender.** An XGBoost classifier (trained offline,
   served on-device through ONNX Runtime Mobile) that estimates
   skill bands per domain (communication, social, play) from gameplay
   features, combined with a rule-based and content-based recommender
   that produces module suggestions.
3. **Freemium delivery model.**
   - **Free tier:** one complete assessment cycle per child;
     unrestricted access to the offline games library; Basic Dashboard
     (latest cycle summary); screen-time controls; Therapy Directory
     view-only (name and city).
   - **Premium tier (Premium Monthly subscription via Google Play
     Billing):** continuous personalized recommendations after every
     completed assessment cycle; Advanced Dashboard with skill-band
     trend lines and per-domain history; **Interactive Therapy
     Locator** with full center details, an in-app Google Map,
     GPS-based nearest-center ranking using the **Haversine formula**,
     and a native-map navigation hand-off via Android Intent.
4. **Offline-first architecture.** Local SQLite storage for all parent,
   child, gameplay, and entitlement data, synchronized to Supabase
   when online and authenticated.
5. **Administrator Portal (web).** CRUD for assessment items, learning
   modules, offline games, therapy-center records (including `lat`,
   `lng`), users, and aggregate reports.
6. **Validator-led testing in Davao City.** Field testing with parents,
   developmental specialists, and DCSNICC-affiliated reviewers within
   the capstone period.

---

### REPLACE 1.4.2 — Delimitation (entire subsection)

The study is deliberately delimited as follows:

1. **Platform.** The parent/child application is built for **Android
   only** (API 26 and above) and is not delivered as an iOS or desktop
   build within the capstone timeline. The Administrator Portal is
   web-based and accessed exclusively from desktop browsers.
2. **Age range.** The system targets children aged **two to six** with
   early-stage ASD; older children, severe profiles, and adult ASD are
   out of scope.
3. **Diagnosis.** Aumazing is **not a diagnostic tool**. The skill-band
   classifier produces educational recommendations, not clinical
   labels, and developmental notes entered by parents are treated as
   parent-reported context only.
4. **No tele-health features.** This revision **does not include**
   in-app video consultation, appointment booking, calendar
   scheduling, in-app parent–therapist messaging, or any specialist or
   doctor portal. These were removed from scope to focus the prototype
   on the AI-driven assessment and the freemium directory.
5. **Therapy Locator boundaries.** The Locator displays therapy centers
   curated by the administrator; it does not crowdsource listings,
   process payments to centers, or guarantee the availability or
   pricing of services. Routing and turn-by-turn navigation are
   delegated to the device's default maps application; Aumazing does
   not compute or render its own routes.
6. **Privacy boundaries.** The parent's GPS coordinates are used only
   to rank nearby centers in memory and are **never persisted** to
   local or cloud storage.
7. **Geographic focus.** Therapy-center records and validator testing
   are scoped to **Davao City**; expansion to other cities is reserved
   for post-capstone work.
8. **Connectivity.** The application is designed offline-first, but
   sign-in, data synchronization, subscription verification, and map
   tile loading still require network connectivity.

---

### REPLACE 1.6 — Operational Definition of Terms (additions and revisions; keep all existing entries that don't conflict)

> The following entries should be **added** or **revised** in §1.6.
> Remove any prior entries that referenced video conferencing,
> appointment booking, or a specialist portal.

- **Aumazing.** The gamified 2D mobile learning application developed
  in this study, delivered under a freemium model on Android.
- **Freemium model.** A pricing structure in which a core set of
  features is offered at no cost while an enhanced set of features is
  unlocked through a paid subscription. In Aumazing, the core
  comprises one trial assessment cycle, the offline games library, the
  Basic Dashboard, screen-time controls, and the view-only Therapy
  Directory.
- **Premium subscription.** A monthly recurring purchase (₱149/month)
  processed via the Google Play Billing Library that unlocks
  continuous personalized recommendations, the Advanced Dashboard, and
  the Interactive Therapy Locator.
- **Trial assessment cycle.** The single, free pre-assessment →
  AI-recommended learning modules → post-assessment sequence available
  to every child profile before any subscription is required.
- **Skill band.** A categorical level (Emerging / Developing /
  Proficient) predicted per domain by the XGBoost classifier from
  gameplay features.
- **Domain.** A behavioral area assessed by the system: communication,
  social, or play.
- **Basic Dashboard.** The free dashboard view that summarizes the
  child's most recent assessment cycle.
- **Advanced Dashboard.** The Premium dashboard view that adds
  per-domain skill-band trend lines and history across cycles.
- **Therapy Directory.** The administrator-curated list of registered
  therapy centers. Free users see each center's name and city only.
- **Interactive Therapy Locator.** The Premium feature that renders
  therapy centers on an in-app Google Map and ranks them by GPS
  proximity.
- **Location-Based Services (LBS).** Software functionality that uses
  the device's geographic position to provide context-aware features;
  in Aumazing, used to rank nearby therapy centers on the Locator
  screen.
- **Haversine formula.** A closed-form equation that computes the
  great-circle distance between two latitude/longitude points on a
  sphere, used by Aumazing to rank therapy centers by ascending
  distance from the parent's GPS fix.
- **Native-map hand-off.** A pattern in which the application launches
  the device's default maps application via an Android Intent
  (`google.navigation:` / `geo:` URI) to provide turn-by-turn
  navigation, instead of rendering a routing engine in-app.
- **Entitlement.** A server-verified record (`tier`, `started_at`,
  `expires_at`, `source`) that determines which features the parent
  account can access.
- **Offline-first.** A design pattern in which all data is written to
  local storage first and synchronized to the cloud opportunistically,
  so the application remains usable without connectivity.
- **Just-in-time permission.** A permission-request strategy in which
  the application asks for sensitive access (e.g., location) only at
  the moment the corresponding feature is invoked, paired with a
  clear in-context rationale.
- **Administrator Portal.** The web interface used by Aumazing
  administrators to manage modules, games, therapy centers, and users.

> **Removed entries (delete if they currently appear in §1.6):**
> *Video Consultation*, *Tele-therapy Session*, *Specialist Portal*,
> *Appointment Booking*, *In-App Messaging*, *Therapy Gateway* (in its
> former tele-health sense).

---

### REPLACE 1.7 — Conceptual Framework (entire section)

The conceptual framework of Aumazing follows an **Input–Process–Output
(IPO)** model with two reinforcing feedback loops: an *assessment loop*
and an *entitlement loop*.

**Inputs**

1. **Child profile:** age, sex, sensory preferences, optional
   parent-reported developmental notes.
2. **Gameplay telemetry:** per-trial response time, accuracy, prompt
   level, error type, session length, and quit events captured by the
   Flame-based GameEngine.
3. **Parent configuration:** screen-time limits, focus-area
   preferences, tier (Free or Premium), and trial-cycle status.
4. **Therapy-center records and parent GPS fix** *(used only when the
   parent opens the Premium Locator and grants location permission)*.

**Process**

1. Raw telemetry is aggregated per session into a feature vector and
   classified by an **XGBoost** model (Velarde et al., 2024;
   Grinsztajn et al., 2022) into a skill band per domain
   (communication, social, play).
2. A **rule-based and content-based recommender** maps the predicted
   bands and the parent's focus areas to the next learning modules,
   applying rules such as *"if accuracy < 60% on the last two
   sessions, repeat at the current level before advancing"*.
3. The **EntitlementService** gates the recommender's output: Free
   users receive one full cycle of recommendations; once the
   post-assessment closes, further personalization is paused with an
   upgrade prompt while the offline games library and Basic Dashboard
   remain accessible. Premium users receive a fresh recommendation set
   after every completed cycle.
4. On the Locator screen (Premium only), the system requests a
   foreground GPS fix just-in-time and ranks therapy centers by
   ascending Haversine distance, then renders the map and list.
   Coordinates are not persisted.
5. All writes go to local SQLite first; the SyncService pushes pending
   rows and pulls deltas to Supabase when the device is online and
   authenticated.

**Outputs**

1. **For the child:** the next personalized learning module (or, for
   Free users beyond the trial cycle, continued access to offline
   games) and an updated reward state.
2. **For the parent:** a Basic Dashboard for all users, an Advanced
   Dashboard for Premium users, and — for Premium users — a ranked map
   and list of nearby therapy centers with a Get Directions hand-off.
3. **For the administrator:** aggregate reports on usage, conversion,
   module completion, and locator engagement, with no exposure of
   individual child data.

**Feedback loops**

- *Assessment loop.* New gameplay outcomes become inputs to the next
  classifier run, so recommendations adapt continuously to the child's
  progress.
- *Entitlement loop.* Subscription state (active, expired, restored)
  is re-verified at every online launch; expired Premium accounts are
  gracefully downgraded without data loss, and Premium features
  reactivate immediately on renewal.

> **Diagram update for Figure 1.7:** redraw the conceptual framework
> diagram with three Input swimlanes (Child Profile, Gameplay
> Telemetry, Parent + Tier Config), a Process column containing
> XGBoost → Recommender → Entitlement Gate → (optional) Locator +
> Haversine, and three Output swimlanes (Child, Parent, Administrator).
> Remove any boxes referring to video consultation, booking, or a
> specialist portal.

---

## Summary of Chapter 1 changes

- **1.1 Background** — replaced only the closing solution paragraph;
  problem and statistics paragraphs untouched.
- **1.2 Objectives** — Objective 4 (tele-health) retired; new
  Objectives 4 (Freemium Therapy Directory + LBS Locator) and 5
  (subscription / entitlement system) added.
- **1.3 Significance** — Therapists/Therapy Centers entry rewritten
  around discoverability rather than tele-consultation.
- **1.4.1 Scope** — restructured around the freemium tiers and the
  Administrator-only web surface.
- **1.4.2 Delimitation** — explicit "no tele-health" delimitation,
  GPS-not-persisted privacy boundary, and Davao City geographic
  scope.
- **1.6 Operational Definition of Terms** — added freemium-, LBS-, and
  entitlement-related terms; removed tele-health terms.
- **1.7 Conceptual Framework** — rewritten as an IPO model with
  assessment and entitlement feedback loops; figure redraw notes
  included.
