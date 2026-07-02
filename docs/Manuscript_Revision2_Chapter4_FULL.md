# Chapter 4 — Full Revised Text (v2 scope, PayMongo-aligned)

> **How to use this file:** This is the **complete** revised Chapter 4, written in the same manuscript format as the rest of your document. Replace your current Chapter IV content end-to-end with the text below. All v2 changes are integrated: freemium tiering, **PayMongo** payment gateway, the Interactive Therapy Locator (Google Maps SDK + Haversine + native-map intent), Basic vs. Advanced Dashboard, removal of Jitsi/Specialist Portal/Booking/In-app messaging, and continuity with your existing ERD entities (Parent_Account, Child_Profile, etc.). Where the prior version had `Video_Session`, this revision introduces `Subscription`, `Subscription_Event`, and an updated `Therapy_Center` entity with location columns.

---

CHAPTER IV
SYSTEM DESIGN

This chapter presents the system design of **Aumazing**, including the use case diagram and descriptions, sequence diagrams for the major interaction flows, the prototype screens for both the mobile application (parent and child) and the web platform (administrator), the entity relationship diagram, the data dictionary, and the offline-first synchronization architecture. The design reflects the v2 scope of the project: a freemium Android application in which one full assessment cycle and the offline games library are available to every parent at no cost, while a Premium monthly subscription processed through **PayMongo** unlocks continuous AI-driven personalization, the Advanced Dashboard, and the Interactive Therapy Locator that uses Google Maps SDK and the Haversine formula to rank registered therapy centers and hands off turn-by-turn navigation to the device's default maps application. Tele-consultation, appointment booking, in-app messaging, and any specialist or doctor portal are explicitly out of scope and do not appear in any diagram, screen, or data structure described below.

4.1 USE CASE DIAGRAM

The use case diagram presents the interactions between the system and its three actors: the **Parent**, with a Free or Premium tier distinction; the **Child**, who interacts only with the gameplay screens under parental supervision; and the **Administrator**, who manages content and directory records through the web portal. The diagram explicitly indicates which use cases are gated behind the Premium subscription using `<<extend>>` relationships from their Free counterparts.

Figure 4.1. Use Case Diagram of Aumazing

Table 4.1. Use Cases
| ID | Use Case | Actor | Tier |
| UC-01 | Register, Sign In, or Continue as Guest | Parent | Free |
| UC-02 | Manage Child Profile | Parent | Free |
| UC-03 | Configure Sensory Preferences | Parent | Free |
| UC-04 | Take Gamified Pre-Assessment | Child | Free (one cycle) |
| UC-05 | Play Recommended Learning Module | Child | Free (trial) / Premium (continuous) |
| UC-06 | Take Gamified Post-Assessment | Child | Free (one cycle) |
| UC-07 | Play Offline Game | Child | Free (always) |
| UC-08 | View Basic Dashboard | Parent | Free |
| UC-09 | Configure Screen-Time Limit | Parent | Free |
| UC-10 | View Therapy Directory (name and city only) | Parent | Free |
| UC-11 | Subscribe to Premium Monthly via PayMongo | Parent | All |
| UC-12 | Receive Continuous Personalized Modules | Parent and Child | Premium |
| UC-13 | View Advanced Dashboard | Parent | Premium |
| UC-14 | Use Interactive Therapy Locator (map and GPS) | Parent | Premium |
| UC-15 | Get Directions (native-map hand-off) | Parent | Premium |
| UC-16 | Manage Subscription | Parent | All |
| UC-17 | Manage Modules, Games, Centers, and Users | Administrator | Admin |

4.1.1 Use Case Description

This subsection presents narrative descriptions for each use case in the format Actor, Pre-condition, Main Flow, Alternative Flow, and Post-condition. For brevity, only descriptions affected by the v2 scope are reproduced in detail; descriptions for unchanged use cases (UC-01 through UC-03, UC-06 through UC-09) follow the format established in earlier revisions of the document.

**UC-04 Take Gamified Pre-Assessment.** *Actor:* Child, with the parent present. *Pre-condition:* a child profile exists and the trial cycle has not yet been consumed. *Main flow:* the child plays a sequence of items drawn from the four mini-games (Match It, Copy Me, Do What I Say, My Turn Your Turn). The system records per-trial response time, accuracy, prompt level, retries, hints, idle time, and invalid touches. On completion, the system computes a feature vector and persists it locally. *Alternative flow:* the child quits early; the partial session is saved as `incomplete` and may be resumed later. *Post-condition:* a `pre_assessment` record exists and the recommender is triggered.

**UC-05 Play Recommended Learning Module.** *Actor:* Child. *Pre-condition:* a recommendation set exists for the active assessment cycle. *Main flow:* the child plays the recommended module while the system logs gameplay telemetry and updates the module's completion status. *Alternative flow:* if the parent is on the Free tier and the trial cycle has been consumed, the recommender returns an upgrade prompt rather than a new module set; previously delivered modules and the offline games library remain fully accessible. *Post-condition:* a `module_progress` record is updated.

**UC-11 Subscribe to Premium Monthly via PayMongo.** *Actor:* Parent. *Pre-condition:* the parent is signed in (Guest mode is upgraded to a real account first). *Main flow:* the parent taps **Upgrade to Premium**; the application invokes the PayMongo Checkout flow with the Premium Monthly product; the parent selects a payment method (card, GCash, GrabPay, or Maya) and completes payment; PayMongo issues a `payment.paid` and `subscription.created` webhook to a Supabase Edge Function, which validates the webhook signature with the PayMongo merchant secret and writes a `subscription` record with `tier = 'premium'`, `status = 'active'`, `started_at`, and `expires_at`. *Alternative flow:* payment is cancelled or fails; no subscription record is created and the application surfaces a non-blocking error. *Post-condition:* Premium use cases (UC-12 through UC-15) are unlocked until `expires_at`.

**UC-12 Receive Continuous Personalized Modules.** *Actor:* Parent and Child. *Pre-condition:* an active Premium subscription. *Main flow:* after every completed assessment cycle, the system invokes the recommender; because the parent's tier is `premium`, the system returns a fresh module set rather than an upgrade prompt. *Post-condition:* a new `module_recommendation` set is persisted for the cycle.

**UC-13 View Advanced Dashboard.** *Actor:* Parent. *Pre-condition:* an active Premium subscription. *Main flow:* the parent opens the Dashboard tab; the system renders skill-band trend lines, per-domain history across cycles, and a Strengths and Gaps panel computed from `assessment_comparison` records. *Alternative flow:* the parent's subscription has lapsed; the system gracefully downgrades the view to the Basic Dashboard at the next launch.

**UC-14 Use Interactive Therapy Locator.** *Actor:* Parent. *Pre-condition:* an active Premium subscription. *Main flow:* the parent opens the Locator tab; the system requests foreground location permission just-in-time; on grant, the system retrieves a single GPS fix (held only in memory), computes Haversine distances against cached `therapy_center` coordinates, sorts ascending, and renders the map and a ranked list with full center details. *Alternative flow:* permission is denied; the system falls back to a city-filtered list and displays a non-blocking banner explaining the reduced experience and how to re-enable the permission.

**UC-15 Get Directions.** *Actor:* Parent. *Pre-condition:* the parent has selected a therapy center on the Locator. *Main flow:* the parent taps **Get Directions**; the system launches an Android Intent with a `google.navigation:q=lat,lng&mode=d` URI; the device's default maps application takes over for routing and turn-by-turn navigation. *Note:* the Aumazing application does not compute or render its own routes.

**UC-16 Manage Subscription.** *Actor:* Parent. *Main flow:* the parent opens **Subscription Management**, sees the current `tier` and `expires_at`, and may tap **Cancel** to invoke the PayMongo cancellation endpoint. On a successful `subscription.cancelled` webhook, the system marks the local entitlement as `cancelled` while preserving access until `expires_at`. *Post-condition:* on `expires_at`, the next online launch downgrades the account to the Free tier.

**UC-17 Administrator: Manage Modules, Games, Centers, and Users.** *Actor:* Administrator. *Main flow:* the administrator authenticates to the web portal and performs CRUD operations on assessment items, learning modules, offline games, therapy-center records (including `lat` and `lng`), and user accounts. *Note:* the portal does not expose individual child telemetry; only aggregate KPIs are visible.

4.2 SEQUENCE DIAGRAM

This subsection presents four sequence diagrams covering the most important end-to-end interactions: user registration and login, gamified assessment and module recommendation, learning activity and progress tracking, and the freemium therapy locator. The previous *Sequence Diagram for Therapy Access* has been replaced in its entirety by the **Sequence Diagram for the Freemium Therapy Locator**, which depicts the entitlement gate, the just-in-time GPS request, the Haversine ranking, and the native-map navigation hand-off.

4.2.1 Sequence Diagram for User Registration and Login

This sequence diagram shows how the parent or guardian creates an account, signs in, and has the application resolve the correct freemium tier before reaching the home screen. The lifelines are Parent, Mobile App UI, AuthService (Supabase Auth), EntitlementService, SyncService, and Local SQLite.

The flow begins when the Parent submits credentials to the Mobile App UI, which calls `signInWithPassword` on the AuthService. AuthService returns a session JWT, which the Mobile App UI persists to secure storage. If a prior guest session exists, the Mobile App UI invokes `bindGuestData(userId)` against Local SQLite to migrate guest records to the authenticated account. The Mobile App UI then calls `fetchEntitlement(userId)` on the EntitlementService, which reads the latest `subscription` record from Supabase (or, if offline, the locally cached row) and returns the tier (`free` or `premium`). Finally, the Mobile App UI calls `syncNow()` on the SyncService to push any pending writes and pull deltas, and routes the parent to the home screen with the resolved tier. In the Guest path, the AuthService and EntitlementService steps are skipped and the system calls `createLocalProfile()` with `tier = 'free'`.

Figure 4.3. Sequence Diagram for User Registration and Login

4.2.2 Sequence Diagram for Gamified Assessment and Module Recommendation

This sequence diagram shows how the child completes the gamified pre-assessment and how the system generates personalized learning module recommendations, gating the recommender by the parent's tier and the child's trial-cycle status. The lifelines are Child, Mobile App UI, GameEngine (Flame), AssessmentRepository, Recommender, EntitlementService, Local SQLite, and Supabase (when online).

The flow starts when the Child opens the pre-assessment; the GameEngine plays each item from the four mini-games and records per-trial telemetry through the AssessmentRepository, which persists each trial to Local SQLite. On completion, the AssessmentRepository computes a feature vector and sends it to the Recommender, which invokes the on-device XGBoost classifier through ONNX Runtime Mobile to produce a skill band per domain (communication, social, play). The Recommender then queries the EntitlementService. If the parent's tier is `premium`, or if the tier is `free` and the trial cycle has not yet been consumed, the Recommender returns a personalized module set. Otherwise, the Recommender returns an `UpgradeRequired` payload while the offline games library remains fully accessible. On the first completed post-assessment for a Free user, the AssessmentRepository sets the child's `trial_cycle_completed` flag to `true`. Finally, the SyncService pushes pending writes to Supabase if the device is online, and the Mobile App UI renders the result screen.

Figure 4.4. Sequence Diagram for Gamified Pre-Assessment and Module Recommendation

4.2.3 Sequence Diagram for Learning Activity and Progress Tracking

This sequence diagram shows how the child completes a learning activity and how the system updates the dashboard, with an explicit branch for the Advanced Dashboard available to Premium parents. The lifelines are Child, Mobile App UI, GameEngine, ProgressRepository, DashboardService, EntitlementService, Local SQLite, and Supabase.

The Child selects a recommended module; the GameEngine loads its assets from the local cache and records per-event play telemetry through the ProgressRepository. On module completion, the ProgressRepository writes a `module_progress` record and invokes the DashboardService to recompute the **Basic Dashboard** snapshot for the latest cycle. The DashboardService then queries the EntitlementService; if the parent is `premium`, it additionally recomputes the **Advanced Dashboard** snapshot — skill-band trend lines and per-domain history across cycles. The SyncService pushes pending writes when online and the Mobile App UI renders the appropriate dashboard.

Figure 4.5. Sequence Diagram for Learning Activity and Progress Tracking

4.2.4 Sequence Diagram for the Freemium Therapy Locator

This sequence diagram replaces the previous *Sequence Diagram for Therapy Access*. It shows how the parent reaches therapy-center information under the freemium model, including the entitlement gate, the just-in-time location permission, the Haversine ranking, and the native-map navigation hand-off. The lifelines are Parent, Mobile App UI, EntitlementService, TherapyLocatorRepository, LocationService (device GPS), Google Maps SDK, the Native Maps Application, Local SQLite, and Supabase.

The Parent opens the Therapy tab; the Mobile App UI queries the EntitlementService for the parent's tier. In the **Free** branch, the TherapyLocatorRepository loads basic directory data (center `name` and `city` only, served from Local SQLite or Supabase if cache is empty), and the Mobile App UI renders the directory in a list view with an optional **Unlock Full Locator** call to action that routes to UC-11. In the **Premium** branch, the Mobile App UI requests foreground location permission just-in-time. If granted, the LocationService returns a single GPS fix `(lat, lng)` that is held only in memory and never written to local or cloud storage; the TherapyLocatorRepository loads the full center records; the Mobile App UI computes Haversine distances using the formula `d = 2R · asin(√(sin²(Δφ/2) + cos φ₁ · cos φ₂ · sin²(Δλ/2)))`, sorts ascending, and renders the Google Maps SDK map with markers and a ranked bottom-sheet list. If permission is denied, the system falls back to a city-filtered list and shows a non-blocking banner. When the parent taps **Get Directions** on a center detail, the Mobile App UI launches an Android Intent (`Intent.ACTION_VIEW` with a `google.navigation:q=lat,lng&mode=d` URI), and the Native Maps Application handles routing entirely. Control returns to Aumazing on back-press.

Figure 4.6. Sequence Diagram for the Freemium Therapy Locator

4.3 PROTOTYPE

This subsection presents the prototype screens for both the **Mobile Application Prototype** (parent and child) and the **Web Platform Prototype** (administrator only — the prior Specialist portal has been removed). The prototype follows a child-friendly, visually guided, and structured interface suitable for young children with early-stage Autism Spectrum Disorder, while providing clear monitoring tools for parents. Three ASD-aligned principles drawn from TEACCH and ABA literature shape every screen: **predictability** through consistent layout and transitions, **low sensory load** through soft palettes and minimal motion, and **large, forgiving touch targets** of at least 64 dp paired with short text labels. Screens that gate Premium features explicitly show their entitlement state to keep the freemium model transparent.

4.3.1 Splash Screen and Welcome Interface

On launch, the splash screen displays the Aumazing logo against a soft, desaturated background and fades to the welcome screen over approximately 1.5 seconds, establishing a predictable entry ritual that does not startle the child. The welcome screen presents three large options — **Sign In**, **Create Account**, and **Continue as Guest** — together with a one-line privacy reassurance. This screen anchors the offline-first flow, since guest data remains cached locally and is later bound to the account if the parent registers.

Figure 4.7. Splash Screen of Aumazing

4.3.2 Login and Registration Screen

The login screen supports email and password sign-in as well as social login (Google and Facebook), each presented in large fields with inline validation and plain-language error messages. Registration uses the same visual language and asks only for the parent's email, password, and display name. After authentication, the system fetches the parent's entitlement record, performs a guest data bind if applicable, and routes the parent to the home screen with the correct tier resolved. There is no specialist or therapist registration path in this revision.

Figure 4.8. Login and Registration Screen

4.3.3 Child Profile Management Screen

The parent enters display name, birth date, sex, avatar (avatar_1 through avatar_8), and optional developmental notes. The avatar grid uses high-contrast, non-photorealistic characters to support recognition without triggering the face-processing difficulties common in ASD. Developmental notes are clearly labeled as parent-reported context, not a clinical diagnosis. Multiple children are supported per parent account.

Figure 4.9. Child Profile Management Screen

4.3.4 Sensory Preferences Screen

The parent configures sensory preferences per child, including music and SFX volume, vibration on or off, animation intensity, prompt speed, and reward preference (balloons, fireworks, bubbles, candy, or randomized). Defaults are conservative — low motion and moderate audio — to protect children with stronger sensory sensitivities. The GameEngine reads these preferences on every session and applies them globally so that the child experiences a consistent sensory profile across all activities.

Figure 4.10. Sensory Preferences Screen

4.3.5 Gamified Pre-Assessment Screen

The pre-assessment is presented as a sequence of short, gamified items that look and feel like play rather than a test. Items target three domains — communication, social, and play — and adapt difficulty within session. The screen shows minimal chrome: a progress bar, a calm background, and the current item. Per-trial response time, accuracy, prompt level, and other gameplay indicators are silently logged and aggregated into a feature vector that feeds the XGBoost classifier.

Figure 4.11. Gamified Pre-Assessment Starter Screen

Figure 4.12. Sensory Preference Check for Children to Identify Comfort Settings

Figure 4.13. After Pre-Assessment Starter Screen, the Game Begins

4.3.6 Learning Module Screen

The learning module screen lists the recommended modules for the active cycle, each shown as a large card with an illustration, a short focus label (such as **Match**, **Sort**, or **Greet**), and an estimated duration. **Free users** see modules from their single trial cycle; once the post-assessment for that cycle has been completed, the recommended slot displays an **Upgrade to Continue Personalization** card that routes to the paywall, while the offline games library remains fully accessible from the same screen. **Premium users** receive a fresh recommendation set after every completed assessment cycle, with no upgrade prompt.

Figure 4.14. Learning Module Screen

4.3.7 Pre-Assessment Gameplay Activity Screen

This screen renders an individual gameplay activity within the assessment. Controls are large, centered, and fixed in position across items to maintain predictability. Audio cues are short and respect the sensory preferences. Errors are not penalized visually; the child receives a gentle re-prompt instead. All telemetry is captured by the GameEngine and persisted via the AssessmentRepository.

Figure 4.15. Do What I Say Game

Figure 4.16. Match It Game

Figure 4.17. Copy Me Game

Figure 4.18. My Turn, Your Turn Game

Figure 4.19. Post-Game Reward

Figure 4.20. Display of Child Encouragement After Assessment or Module is Done

4.3.8 Parent Dashboard Screen

The Parent Dashboard has two modes that map directly to the freemium tiers. The **Basic Dashboard** (Free) shows the latest assessment cycle summary: overall skill band, modules completed, total time on task, and the day's screen-time usage. A single sparkline summarizes the most recent seven sessions. The **Advanced Dashboard** (Premium) adds per-domain trend lines for communication, social, and play; a skill-band history timeline; and a Strengths and Gaps panel that highlights modules with rising or stalling performance. A subtle **Premium** badge at the top of the Advanced Dashboard makes the entitlement state legible. For Free users, a single inline upsell card invites them to "See your child's progress over time" and routes to the paywall on tap.

Figure 4.21. Parent Dashboard Screen (Basic and Advanced Modes)

4.3.9 Screen-Time Management Screen

The parent sets a daily screen-time limit per child and chooses whether the locked time triggers a calming "rest" screen or a hard exit. When the limit is reached during a session, the GameEngine completes the current trial, plays a soft transition, and locks further play until the next day. This feature is always free because it directly supports child wellbeing.

Figure 4.22. Screen-Time Management Screen

4.3.10 Therapy Directory Screen (Free)

The free Therapy Directory presents an alphabetized list of therapy centers. Each row shows only the **center name** and the **city** in which it operates. Tapping a row reveals a single bottom-sheet card with the same two fields and a clearly labeled **Unlock Full Locator** button. No address, contact number, services list, or map is shown at this tier. The screen serves two purposes: it gives parents who only need to know that providers exist in their city an immediately useful baseline, and it serves as the most contextually relevant entry point to the paywall.

Figure 4.23. Therapy Directory Screen (Free View)

4.3.11 Premium Paywall Screen

The paywall presents a single SKU — **Premium Monthly at ₱149 per month** — with a concise three-bullet value summary: continuous personalized modules, the Interactive Therapy Locator, and the Advanced Dashboard. A *What is still free* footer reassures the parent that the offline games library, screen-time controls, and Basic Dashboard remain available at no cost. The purchase action invokes the PayMongo Checkout flow; on success, the merchant webhook is delivered to the Supabase Edge Function, which writes the subscription entitlement and unlocks Premium features.

Figure 4.24. Premium Paywall Screen

4.3.12 Interactive Therapy Locator Screen (Premium)

The Interactive Therapy Locator presents an in-app Google Map (Google Maps SDK for Android) centered on the parent's current GPS fix, with markers for each therapy center sorted by ascending Haversine distance. A bottom sheet shows the same centers as a scrollable ranked list with distance in kilometers. The location permission is requested just-in-time the first time this screen is opened, with a clear in-context rationale. If permission is denied, the screen falls back to a city-filtered list and shows a non-blocking banner explaining how to enable the permission later. The parent's coordinates are not persisted to local storage or Supabase.

Figure 4.25. Interactive Therapy Locator Screen

4.3.13 Therapy Center Detail Screen (Premium)

Tapping a center marker or list row opens the center detail screen, which displays the center's full address, contact numbers, services offered, operating hours, a small embedded map preview, and a `last_updated` timestamp. The primary action is **Get Directions**, which launches the device's default maps application via an Android Intent (`google.navigation:q=lat,lng&mode=d`) for turn-by-turn navigation. Aumazing does not render its own routing.

Figure 4.26. Therapy Center Detail Screen

4.3.14 Subscription Management Screen (Premium)

The subscription management screen surfaces the parent's current tier, the `expires_at` timestamp, and a deep link that initiates a PayMongo cancellation. When the subscription lapses, the next online launch performs a webhook reconciliation, gracefully downgrades the account to the Free tier, and preserves all locally stored data so the parent can re-subscribe at any time without loss.

Figure 4.27. Subscription Management Screen

4.3.15 Web Platform Prototype: Administrator Portal

The Administrator Portal is the only web surface in this revision. It comprises five screens: an **Admin Sign-In** screen with role check; a **Module and Game Manager** for assessment items, learning modules, and offline games (including sensory metadata); a **Therapy Center Manager** for `therapy_centers` records (`name`, `city`, `address`, `contact`, `services`, `lat`, `lng`, `hours`, `is_active`, `last_updated`) with a small map widget for coordinate validation; a **User Manager** for parent accounts and entitlement tiers (with a manual grant for validator testing); and a **Reports** screen with aggregate KPIs (active users, trial-to-Premium conversion rate, module completion rate, locator opens). No individual child data is exposed to administrators.

Figure 4.28. Administrator Portal — Therapy Center Manager

4.4 ENTITY RELATIONSHIP DIAGRAM

The Entity Relationship Diagram presents the database structure of the proposed system. It shows the major entities, attributes, and relationships, and supports account management, child profiles, gamified assessment data, AI module recommendation, progress tracking, screen-time control, sensory preferences, the freemium therapy directory and locator, and the subscription system. The diagram is implemented in Supabase (PostgreSQL) for cloud storage and in SQLite for offline-first local storage.

A `Parent_Account` manages one or more `Child_Profile` records. Each `Child_Profile` has multiple assessment runs, game sessions, game rounds, session events, assessment results, module recommendations, assessment comparisons, caregiver questionnaires, sensory consent records, sensory round metrics, and sensory preferences. Games map to skill categories through a many-to-many junction table. Therapy features include `Therapy_Center` records with `lat` and `lng` columns for the Locator. The freemium gating is supported by `Subscription` and `Subscription_Event` entities that are written by the PayMongo webhook receiver.

The previous `Video_Session` entity, together with any consultation, appointment, specialist, or message tables, has been **removed** from the schema in this revision and does not appear in the diagram.

Figure 4.29. Entity Relationship Diagram of Aumazing (v2)

Table 4.15. Relationship Structure Summary
| Relationship | Cardinality |
| Parent_Account → Child_Profile | one-to-many |
| Parent_Account → Subscription | one-to-one |
| Subscription → Subscription_Event | one-to-many |
| Child_Profile → Assessment_Run | one-to-many |
| Child_Profile → Game_Session | one-to-many |
| Child_Profile → Assessment_Result | one-to-many |
| Child_Profile → Module_Recommendation | one-to-many |
| Child_Profile → Assessment_Comparison | one-to-many |
| Child_Profile → Caregiver_Questionnaire | one-to-many |
| Child_Profile → Module_Progress | one-to-many |
| Child_Profile → Screen_Time_Setting | one-to-one |
| Child_Profile → Sensory_Consent | one-to-one |
| Child_Profile → Sensory_Preferences | one-to-one |
| Child_Profile → Sensory_Round_Metrics | one-to-many |
| Assessment_Run → Game_Session | one-to-many |
| Assessment_Run → Assessment_Result | one-to-many |
| Game_Session → Game_Round | one-to-many |
| Game_Session → Session_Event | one-to-many |
| Game → Game_Session | one-to-many |
| Game → Game_Skill_Category | one-to-many |
| Skill_Category → Game_Skill_Category | one-to-many |
| Learning_Module → Module_Recommendation | one-to-many |
| Learning_Module → Module_Progress | one-to-many |
| Therapy_Center | (referenced by the Locator; no FK from child data) |

4.5 DATA DICTIONARY

This subsection presents the data dictionary defining the core data elements stored, processed, and retrieved by the application. Tables reflect the actual implementation in Supabase (PostgreSQL) and SQLite. Only entities new or changed in v2 are reproduced in detail below; unchanged entries (`Game`, `Game_Round`, `Session_Event`, `Skill_Category`, `Game_Skill_Category`, `Learning_Module`, `Sensory_Consent`, `Sensory_Round_Metrics`, `Caregiver_Questionnaire`, `Assessment_Run`, `Assessment_Result`, `Assessment_Comparison`, `Module_Recommendation`, `Module_Progress`) follow the format of the prior revision.

Table 4.16. Parent_Account
| Field Name | Data Type | Description | Constraint |
| id | UUID | Unique identifier of the parent | Primary Key |
| full_name | VARCHAR | Full name of the parent | Required |
| email | VARCHAR | Email address used for login | Unique, Required |
| password_hash | TEXT | Encrypted password value | Required |
| contact_number | VARCHAR | Contact number | Optional |
| created_at | TIMESTAMPTZ | Account creation date | Required |
| updated_at | TIMESTAMPTZ | Last update timestamp | Required |

Table 4.17. Child_Profile (revised)
| Field Name | Data Type | Description | Constraint |
| id | UUID | Unique identifier of child profile | Primary Key |
| parent_user_id | UUID | Reference to Parent_Account | Foreign Key |
| display_name | VARCHAR | Display name of the child | Required |
| birth_date | DATE | Date of birth | Required |
| avatar | VARCHAR | Avatar identifier (avatar_1 through avatar_8) | Default avatar_1 |
| sex | VARCHAR | male, female, or prefer_not_to_say | Optional |
| developmental_notes | TEXT | Optional parent-reported context | Optional |
| trial_cycle_completed | BOOLEAN | Indicates whether the free trial assessment cycle has been consumed for this child | Default False |
| music_enabled | BOOLEAN | Background music enabled | Default True |
| music_volume | REAL | Music volume (0.0 to 1.0) | Default 0.5 |
| sfx_volume | REAL | SFX volume (0.0 to 1.0) | Default 0.7 |
| vibration_enabled | BOOLEAN | Haptic vibration enabled | Default True |
| animation_intensity | REAL | Animation intensity (0.0 to 1.0) | Default 1.0 |
| prompt_speed | REAL | Prompt speed (0.0 to 2.0) | Default 1.0 |
| sensory_preferences_set | BOOLEAN | Sensory preferences configured flag | Default False |
| reward_preference | VARCHAR | balloons, fireworks, bubbles, candy, or random | Default bubbles |
| use_random_reward | BOOLEAN | Randomize reward type | Default False |
| created_at | TIMESTAMPTZ | Profile creation date | Required |
| updated_at | TIMESTAMPTZ | Last update timestamp | Required |

Table 4.18. Subscription (new in v2)
| Field Name | Data Type | Description | Constraint |
| id | UUID | Unique identifier of the subscription | Primary Key |
| parent_user_id | UUID | Reference to Parent_Account | Foreign Key, Unique |
| tier | VARCHAR | free or premium | Default free |
| status | VARCHAR | active, cancelled, expired, or paused | Default active |
| source | VARCHAR | trial or monthly_sub | Default trial |
| paymongo_subscription_id | VARCHAR | Identifier returned by PayMongo for the subscription | Optional |
| paymongo_customer_id | VARCHAR | Identifier returned by PayMongo for the merchant customer | Optional |
| started_at | TIMESTAMPTZ | Date the subscription became active | Required |
| expires_at | TIMESTAMPTZ | Date the current period ends | Optional (NULL for free tier) |
| cancelled_at | TIMESTAMPTZ | Date the subscription was cancelled, if applicable | Optional |
| updated_at | TIMESTAMPTZ | Last update timestamp | Required |

Table 4.19. Subscription_Event (new in v2)
| Field Name | Data Type | Description | Constraint |
| id | UUID | Unique identifier of the event | Primary Key |
| subscription_id | UUID | Reference to Subscription | Foreign Key |
| event_type | VARCHAR | PayMongo event name (for example, payment.paid, subscription.created, payment.refunded, subscription.cancelled) | Required |
| payload | JSONB | Raw verified webhook payload | Required |
| signature_valid | BOOLEAN | Whether the PayMongo signature was successfully validated | Required |
| received_at | TIMESTAMPTZ | Server time the event was received | Required |

Table 4.20. Therapy_Center (revised in v2)
| Field Name | Data Type | Description | Constraint |
| id | UUID | Unique identifier of the therapy center | Primary Key |
| name | VARCHAR | Center name (visible at Free tier) | Required |
| city | VARCHAR | City of operation (visible at Free tier) | Required |
| address | TEXT | Street address (Premium-visible) | Optional |
| contact | VARCHAR | Contact number (Premium-visible) | Optional |
| services | TEXT[] | List of services offered (Premium-visible) | Optional |
| lat | DOUBLE PRECISION | Latitude (used for Haversine ranking) | Optional |
| lng | DOUBLE PRECISION | Longitude (used for Haversine ranking) | Optional |
| hours | JSONB | Operating hours by weekday | Optional |
| is_active | BOOLEAN | Soft-delete flag | Default True |
| last_updated | TIMESTAMPTZ | Timestamp of last administrator edit | Required |

Table 4.21. Screen_Time_Setting
| Field Name | Data Type | Description | Constraint |
| child_id | UUID | Reference to Child_Profile | Primary Key, Foreign Key |
| daily_limit_minutes | INTEGER | Daily play limit in minutes | Required |
| lock_behavior | VARCHAR | rest_screen or hard_exit | Default rest_screen |
| updated_at | TIMESTAMPTZ | Last update timestamp | Required |

Table 4.22. Audit_Log (new in v2)
| Field Name | Data Type | Description | Constraint |
| id | UUID | Unique identifier of the log entry | Primary Key |
| actor_user_id | UUID | Acting user (parent or administrator) | Foreign Key |
| action | VARCHAR | Action performed (for example, center_created, entitlement_granted) | Required |
| entity | VARCHAR | Affected entity name | Required |
| entity_id | UUID | Identifier of the affected entity | Required |
| created_at | TIMESTAMPTZ | Server time the action was performed | Required |

The previous `Video_Session` entry, together with any other tele-health-related tables, has been **removed** from the data dictionary in this revision.

4.6 OFFLINE-FIRST SYNC ARCHITECTURE

Aumazing follows a strict local-first architecture: every write is committed to local SQLite first and synchronized to Supabase only when the device is online and the parent is authenticated. Each repository writes to SQLite with a `pending = true` flag and an `updated_at` timestamp. The `SyncService` watches connectivity and authentication; on transition to online and authenticated, it pushes pending rows in FIFO order, then pulls deltas using `updated_at` watermarks. Conflicts are resolved with last-write-wins per row using `updated_at`. Guest data created before sign-up is migrated by a one-shot `bindGuestData(userId)` routine on the first authenticated launch.

Three additional sync rules support the v2 freemium scope. First, **entitlement freshness**: on every cold start that reaches the network, the `EntitlementService` re-verifies subscription state by reconciling against the latest PayMongo webhook events received by the Supabase Edge Function and rewrites the local `subscription` row; while offline, the client honors the cached `expires_at`. Second, **locator data caching**: `Therapy_Center` records are pulled to local SQLite on first sign-in and refreshed opportunistically, allowing the Locator to render maps and rankings without an active network connection — only the map *tiles* require connectivity. Third, the **no-persistence rule for GPS coordinates**: the parent's `(lat, lng)` is held only in memory for the duration of the Locator screen, in compliance with NFR-04, and is never written to local storage, transmitted to Supabase, or recorded in logs.

When `now() > expires_at`, the next online sync downgrades the cached `tier` to `free` and the user interface re-renders accordingly without data loss; the parent may re-subscribe at any time and Premium features reactivate immediately upon receipt of the next valid PayMongo `payment.paid` and `subscription.created` events.
