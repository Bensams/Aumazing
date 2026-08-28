# Chapter 3 — Full Revised Text (v2 scope, PayMongo-aligned)

> **How to use this file:** This is the **complete** revised Chapter 3, written in the same manuscript format as the rest of your document (numbered headings, prose paragraphs, captioned figures, captioned tables). Replace your current Chapter III content end-to-end with the text below. All v2 changes are already integrated: freemium model, PayMongo as the primary payment gateway, removal of Jitsi/specialist portal/booking/in-app messaging, Google Maps SDK + Haversine for the Premium Locator, Basic vs. Advanced Dashboard, and continuity with your existing TC-AU test cases and WBS modules.

---

CHAPTER III
METHODOLOGY

This chapter presents the methodology, software process, requirements, feasibility analysis, work breakdown, cost-benefit analysis, risk management, testing plan, and deployment plan adopted for the development of **Aumazing**. The chapter reflects the revised v2 scope of the project, in which the system is delivered as a freemium Android application: every parent receives one free assessment cycle (pre-assessment → AI-recommended modules → post-assessment) and unlimited access to the offline games library, while a Premium monthly subscription processed through **PayMongo** unlocks continuous personalized recommendations, an Advanced Dashboard, and an Interactive Therapy Locator that uses the device's GPS and the Haversine formula to rank registered therapy centers and hand off turn-by-turn navigation to the device's default maps application. Tele-consultation, appointment booking, in-app messaging, and any specialist or doctor portal are explicitly out of scope and are not part of the methodology described below.

3.1 SOFTWARE PROCESS MODEL

3.1.1 Rationale for Using Agile-Kanban

The proponents adopted **Agile-Kanban** (Atlassian, 2025) as the software process model for this study. Three project conditions made Kanban the most appropriate choice. First, the development team is small (two proponents) and the scope was deliberately narrowed mid-cycle to focus on the AI-driven assessment and the freemium therapy locator; pull-based, continuous flow accommodates such re-prioritization more naturally than time-boxed sprints. Second, the project includes heterogeneous work types — mobile UI development, AI model training, location-based services, payment-gateway integration, and validator coordination — that benefit from a single visual board where each work item is allowed to move at its own natural cadence. Third, Kanban's explicit **work-in-progress (WIP) limits** and visible flow expose bottlenecks early, which is critical given the fixed academic timeline of February to September 2026.

Agile-Kanban also aligns with the offline-first, freemium nature of Aumazing. The system relies on independent vertical slices — the assessment engine, the recommender, the dashboard, the locator, and the subscription system — that can each be built, tested, and validated incrementally without a "big bang" release. Kanban's delivery-on-demand cadence allows each slice to ship to staging the moment it clears testing, supporting iterative validator feedback throughout the development period.

3.1.2 Kanban Workflow Stages

For this study, the proponents organize the project workflow into six Kanban stages, each with an explicit work-in-progress limit. The board is maintained on Trello, with cards carrying the user-story identifier, acceptance criteria, size estimate (S/M/L), a blocked flag, and links to wireframes, source code, and test cases.

Figure 3.1. Kanban Board Stages Diagram

Activities:
- **Backlog.** A holding area for proposed features, technical suggestions, and bug reports gathered from the team, the adviser, and validator-tester sessions. The Backlog has no WIP limit.
- **Ready.** Cards refined with acceptance criteria, sized, and prioritized for imminent implementation. Limited to six cards to keep refinement work focused.
- **Doing.** Cards under active development. Limited to two cards per developer to maintain technical focus and reduce context-switching.
- **In Review.** Cards undergoing peer or adviser review. Limited to three total to prevent review backlog.
- **Testing.** Cards in unit, widget, integration, or acceptance testing. Limited to three total. When a stage limit is reached, the team **swarms** on the blocking card before pulling new work.
- **Done.** Cards that have satisfied the Definition of Done — code reviewed, automated tests green, acceptance criteria met, deployed to staging.

These stages are based on the Kanban principle of visualizing workflow and organizing tasks according to their current status, with WIP limits used to expose and resolve bottlenecks (Atlassian, 2025).

Figure 3.2. Initial Kanban Board in Trello

The Kanban board in Trello illustrates the proponents' application of WIP limits and systematic task prioritization. Task prioritization is delineated through markers below each card: red for critical, orange for urgent, green for important, and blue for low-priority. By operationalizing prioritization in this manner, the team ensures that core functionalities — gamified assessment, AI recommendation, dashboard, locator, and subscription — receive technical focus first, while non-essential refinements are deferred. By regulating work-in-progress, the proponents mitigate technical overload and improve throughput. The team additionally tracks two flow metrics weekly: **lead time** (days from `Backlog → Done`) and **cycle time** (days from `Doing → Done`). A simple **cumulative flow diagram** plots column counts per week to visualize WIP bloat and throughput trends, providing a continuous-improvement signal that timeboxed Scrum cannot easily offer.

3.1.3 Development Activities in the Framework

Development is organized around four continuous activities rather than fixed sprints. **Replenishment** occurs weekly, when the team and the adviser re-prioritize the Backlog and refill the Ready column. A short **daily stand-up** of approximately ten minutes identifies blocked cards and confirms compliance with WIP limits. **Delivery on demand** is practiced throughout — any card that clears Testing is merged to the main branch and shipped to the staging environment immediately, without waiting for a sprint boundary. Finally, a **retrospective** is held bi-weekly to inspect lead time, cycle time, and the cumulative flow diagram, and to adjust WIP limits or process steps where data indicates room for improvement.

These activities are explicitly tier-aware: cards involving freemium gating (entitlement checks, paywall, the Locator, and the Advanced Dashboard) are tagged with a "premium" label so the team can examine flow and defect rates for that vertical separately from the free experience, ensuring that the Premium upgrade path receives proportionate attention without crowding out the always-free assessment and offline-games experiences.

3.1.4 Artifacts of the Chosen Framework

The Kanban implementation produces a set of artifacts that are referenced from later chapters and from the deployment process. These include the **product backlog** maintained on Trello, **board snapshots** at the start, middle, and end of the development period (Figures 3.1 and 3.2), a **cumulative flow diagram** updated weekly, and a **lead-time and cycle-time chart**. A written **Definition of Done** governs every card and contains the following criteria: source reviewed, unit and widget tests green, acceptance criteria met, security and privacy items satisfied (notably, no persistence of GPS coordinates), and successful deployment to the staging environment.

3.2 SOFTWARE REQUIREMENTS

3.2.1 User Requirements

The system has three user roles. The Specialist or Doctor role from the previous design has been intentionally excluded so that the prototype scope remains focused on the AI-driven assessment and the freemium therapy locator. The Administrator role is web-based; the Parent and Child roles are mobile-only.

Table 3.1. User Roles
| Role | Description |
| Parent (Free) | Primary caregiver of a child aged two to six with early-stage Autism Spectrum Disorder. Can complete one full assessment cycle per child profile, play offline games freely, configure screen-time limits, view a Basic Dashboard, and browse the Therapy Directory at the city level. |
| Parent (Premium) | A Parent with an active monthly subscription processed through PayMongo. Receives continuous AI-driven personalization, the Interactive Therapy Locator with full center details and GPS-based ranking, and the Advanced Dashboard. |
| Administrator | Manages assessment items, learning modules, offline games, therapy-center records, and user accounts through a web portal. |

3.2.2 Functional Requirements

Table 3.2. Functional Requirements
| ID | Requirement | Tier |
| FR-01 | The system shall allow parents to register, sign in (email/password or social login), or continue as a guest. | Free |
| FR-02 | The system shall allow a parent to create and edit one or more child profiles capturing display name, birth date, sex, avatar (avatar_1 to avatar_8), and optional developmental notes. | Free |
| FR-03 | The system shall allow the parent to configure sensory preferences per child, including music and SFX volume, vibration, animation intensity, prompt speed, and reward preference (balloons, fireworks, bubbles, candy, or randomized). | Free |
| FR-04 | The system shall deliver one complete free assessment cycle per child: gamified Pre-Assessment using the four mini-games (Match It, Copy Me, Do What I Say, My Turn Your Turn), AI-recommended Learning Modules tailored to the cycle, and a Post-Assessment that compares pre and post results. | Free |
| FR-05 | The system shall classify the child's skill band (Emerging, Developing, Proficient) per domain — communication, social interaction, and play skills — using an XGBoost model trained on per-trial gameplay features. | Free (during trial) / Premium (continuous) |
| FR-06 | The system shall provide unrestricted access to the offline games library at all times, regardless of subscription tier or network availability. | Free |
| FR-07 | The system shall present a Basic Dashboard summarizing the most recent assessment cycle (overall band, modules completed, time on task, daily screen-time usage). | Free |
| FR-08 | The system shall enforce parent-defined daily screen-time limits and lock further play when the limit is reached. | Free |
| FR-09 | The system shall display a Therapy Directory listing each registered center's name and city only. | Free |
| FR-10 | The system shall offer a Premium Monthly subscription processed through **PayMongo**, supporting cards, GCash, GrabPay, and Maya. | All |
| FR-11 | The system shall continue generating personalized module recommendations after every completed assessment cycle, indefinitely while the Premium subscription is active. | Premium |
| FR-12 | The system shall present the Interactive Therapy Locator with full center details (address, contact number, services offered, operating hours, and last-updated timestamp). | Premium |
| FR-13 | The system shall, after the parent grants foreground location permission just-in-time, retrieve the device's GPS coordinates and rank therapy centers by ascending distance using the **Haversine formula**. | Premium |
| FR-14 | The system shall render an in-app Google Map (Google Maps SDK for Android) showing the parent's current location and ranked therapy-center markers. | Premium |
| FR-15 | The system shall provide a Get Directions action that hands off to the device's default maps application via an Android Intent (`google.navigation:` or `geo:` URI). The system itself does not compute or render routes. | Premium |
| FR-16 | The system shall present an Advanced Dashboard with skill-band trend lines, per-domain history across cycles, and a Strengths and Gaps panel. | Premium |
| FR-17 | The system shall verify subscription status against PayMongo webhooks routed through a Supabase Edge Function and a Supabase `subscription` record, and shall honor the cached `expires_at` while the device is offline. | All |
| FR-18 | The system shall allow administrators to manage modules, games, therapy centers, and users through a web portal. | Admin |
| FR-19 | The system shall persist all parent and child data locally in SQLite first and synchronize to Supabase when the device is online and the parent is authenticated. | All |

3.2.3 Non-Functional Requirements

Table 3.3. Non-Functional Requirements
| ID | Category | Requirement |
| NFR-01 | Usability (ASD-aligned) | All primary controls shall be at least 64 dp in size, use a soft palette, and avoid sudden motion or audio peaks. |
| NFR-02 | Performance | Pre-assessment and post-assessment screens shall render within two seconds on a mid-range Android device (4 GB RAM, Android 10 or later). |
| NFR-03 | Offline-first | The application shall remain fully usable for offline games, dashboard viewing, and screen-time enforcement without network connectivity. |
| NFR-04 | Privacy — Location | Location shall be requested just-in-time on the Locator screen using foreground-only permission. GPS coordinates shall not be persisted to local storage, transmitted to Supabase, or written to logs. |
| NFR-05 | Privacy — Child Data | Developmental notes are optional, parent-reported context, and shall not be represented or treated as a clinical diagnosis. |
| NFR-06 | Security | All Supabase tables shall enforce Row-Level Security; PayMongo webhooks shall be verified by signature before granting Premium entitlements. |
| NFR-07 | Reliability | Local writes shall never block the user interface; sync failures shall retry with exponential backoff and cap at a configurable ceiling. |
| NFR-08 | Cost Control | Map-tile and Places usage shall remain within Google Maps Platform's free monthly tier through aggressive caching of center coordinates and a per-session map-load cap. |
| NFR-09 | Accessibility | Color contrast shall meet WCAG 2.1 AA; all icons shall be paired with short text labels; the application shall be compatible with Android screen readers. |
| NFR-10 | Maintainability | The codebase shall follow the offline-first repository pattern (local SQLite first, Supabase sync second) for every data entity. |

3.3 SOFTWARE AND HARDWARE REQUIREMENTS

3.3.1 Software Requirements for Development

Table 3.4. Software Tools
| Category | Tool | Purpose |
| Integrated Development Environment | Android Studio, Visual Studio Code | Flutter and Dart development for the mobile application. |
| Mobile framework | Flutter (stable channel) | Cross-platform UI for the Android client. |
| Game engine | Flame Engine | 2D mini-game implementation for assessment items and learning modules. |
| Backend platform | Supabase (Auth, Postgres, Storage, Edge Functions, Row-Level Security) | Cloud database, authentication, and webhook receiver. |
| Local database | SQLite via the `sqflite` plugin | Offline-first local storage. |
| AI training | Python, XGBoost, scikit-learn, pandas | Skill-band classifier training. |
| AI inference | ONNX Runtime Mobile | On-device classifier inference. |
| Map and Location | Google Maps SDK for Android, Google Maps Platform Places (basic data) | Premium Therapy Locator. |
| Payment Gateway | **PayMongo** (cards, GCash, GrabPay, Maya) | Premium Monthly subscription processing. |
| API layer | FastAPI | Inference endpoints and administrative integrations. |
| Design | Figma | Wireframes and prototype screens. |
| Source control and CI | GitHub and GitHub Actions | Source code management and signed APK builds on tagged commits. |
| Project tracking | Trello | Kanban board, backlog, and flow metrics. |

3.3.2 Hardware Requirements for Development

Each proponent uses an Intel Core i5 (10th generation or later) or AMD Ryzen 5 (3000 series or later) class laptop with at least 8 GB of RAM, 256 GB of solid-state storage, and at least one Android test device running Android 8.0 (API 26) or higher. A reliable broadband connection is required for Supabase, PayMongo, and Google Maps Platform integration testing.

3.3.3 Hardware and Software Requirements for End Users

For the Parent and Child users, the application targets Android 8.0 (API 26) or higher, with a minimum of 2 GB of RAM (4 GB recommended), at least 200 MB of free storage, and a GPS-capable device (required only when the Premium Locator is used). An internet connection is optional except for sign-in, synchronization, subscription verification, and map-tile loading. The Administrator uses a modern desktop browser (Chrome, Edge, or Firefox, latest two versions) on a stable broadband connection. No iOS, desktop, or web build of the parent or child experience is delivered within the capstone timeframe.

3.4 FEASIBILITY ISSUES

3.4.1 Economic Feasibility

The project is economically feasible. One-time development costs are absorbed as academic work performed by the proponents, while recurring operating costs are limited to the Supabase free or Pro tier sized for prototype usage, Google Maps Platform usage capped within the free monthly tier through coordinate caching, the PayMongo merchant account (no monthly fee; per-transaction fees only), and the optional Google Play developer account fee for distribution. Premium monthly subscriptions provide a recurring revenue stream that, per the cost-benefit analysis in §3.6, recovers operating costs after a small validator-tester base converts. Free-tier users incur near-zero variable cost because they do not consume map tiles or AI inference beyond the trial cycle.

3.4.2 Technical Feasibility

All chosen technologies are mature, well-documented, and free for prototype-scale use. The XGBoost-based skill-band classifier is supported by published evidence of strong performance on small tabular data (Grinsztajn et al., 2022; Velarde et al., 2024; Hakkal & Ait Lahcen, 2024). The Locator uses the Google Maps SDK's standard map view together with the Haversine formula — a closed-form computation imposing no server load and executable on-device. Navigation is delegated to the user's installed maps application via Android Intent, which eliminates the need to build a routing engine. PayMongo provides a documented REST API and webhook contract that integrates cleanly with Supabase Edge Functions. By removing Jitsi-based video conferencing, calendar booking, and the specialist portal from the previous design, the project materially reduces integration risk and concentrates engineering effort on the AI assessment and the freemium directory.

3.4.3 Operational Feasibility

The proposed system is operationally feasible because it directly addresses the real-world needs identified through SPED teacher consultation: assessment of communication, social interaction, play skills, behavior or attention, and sensory response, integrated into simple game-based activities such as turn-taking, matching, imitation, and instruction-following. The four mini-games — Match It, Copy Me, Do What I Say, and My Turn, Your Turn — operationalize these skills in a child-friendly format, while the parent dashboard, sensory preferences, and screen-time controls support the home environment in which most use will occur.

The freemium structure is operationally suited to the Davao City context. Free access to one full assessment cycle and to the offline games library lowers the adoption barrier for families with limited disposable income, while the Premium tier (Interactive Therapy Locator and continuous personalization) is priced to match the value of the manual cost it displaces. The system is explicitly limited to a supplementary educational support tool and does not replace formal diagnosis, therapy, or professional assessment. Therapy-center records are administrator-curated, ensuring that directory accuracy does not depend on therapist participation, which simplifies operations significantly compared with the previous tele-health design.

3.4.4 Schedule Feasibility

The project is schedule-feasible. It follows a clearly defined development period from February to September 2026 covering planning, design, development, testing, evaluation, and documentation, and the Agile-Kanban methodology allows tasks to be broken into smaller increments that can be continuously monitored. The early months focus on requirements gathering and system design, the middle months on iterative system development and testing, and the final months on evaluation, validator review, deployment preparation, and documentation. Removing the tele-health components from the prior scope provides additional schedule slack, which is allocated to the new freemium components — PayMongo integration, the Locator, and the Advanced Dashboard.

Figure 3.3. Schedule Feasibility Gantt Chart

The Gantt chart shows that project activities are distributed within the planned academic period from February 2026 to September 2026. The early months focus on requirements gathering and system design, the middle months on system development and iterative testing, and the final months on evaluation, validation, deployment preparation, documentation, and final system maintenance.

3.5 WORK BREAKDOWN STRUCTURE

The Work Breakdown Structure (WBS) decomposes the project into manageable modules aligned with the Kanban workflow and the test plan in §3.8. The WBS is organized into six development modules and three testing modules.

Table 3.5. Work Breakdown Structure
| WBS ID | Module | Scope |
| 3.1 | Account Access and Child Profile | Registration, login, guest mode, child profile management, parent account binding, avatar selection. |
| 3.2 | Settings, Sensory Preferences, and Screen-Time | Sensory preference configuration (audio, vibration, animation intensity, prompt speed, reward preference), screen-time limits, and lock behaviors. |
| 3.3 | Gamified Assessment and Gameplay Indicators | The four mini-games (Match It, Copy Me, Do What I Say, My Turn Your Turn), per-trial gameplay-indicator capture (response time, accuracy, retries, hints, idle time, invalid touches), and the pre-assessment runner. |
| 3.4 | AI Assessment and Recommendation | XGBoost classifier (training and ONNX inference), the rule-based plus content-based recommender, and trial-cycle gating. |
| 3.5 | Learning Module and Post-Assessment | Module rendering, progress tracking, post-assessment, and pre-versus-post comparison. |
| 3.6 | Dashboard, Offline Support, and Freemium Gateway | Basic and Advanced Dashboards, offline-first sync, **PayMongo subscription integration**, entitlement caching, Therapy Directory (free) and Interactive Therapy Locator (Premium). |
| 4.1 | Functional and Integration Testing | Unit, integration, and functional testing per module. |
| 4.2 | User Acceptance Testing | UAT with parents, guardians, and SPED/SNeD teachers, and cross-platform testing. |
| 4.3 | Validator Review and Revision | Security review, technical evaluation, and revisions following adviser feedback. |

3.6 COST-BENEFIT ANALYSIS

The cost-benefit analysis (CBA) determines whether **Aumazing** should proceed to prototype deployment by comparing the recurring cost of the manual home-intervention status quo against the projected operating cost of the proposed system over a three-year horizon. The analysis is conservative: parental labor is disclosed but not counted toward savings, and PayMongo fees are deducted from operator revenue rather than passed to the parent.

**Decision rule.** The project shall proceed to prototype deployment if the payback period is less than or equal to three years and projected annual savings per Premium household are at least ₱3,000.

Table 3.6. Present Annual Cost of the Manual Process (per household)
| Line Item | Computation | Annual Cost |
| Printed worksheets and flashcards | 50 pages × ₱2 × 12 months | ₱1,200 |
| Photocopies of therapist handouts | ₱200 × 4 quarters | ₱800 |
| Reward stickers and tangible reinforcers | ₱150 × 12 months | ₱1,800 |
| Transportation for routine follow-ups | ₱500 × 8 trips | ₱4,000 |
| Cash subtotal | | ₱7,800 |
| Parent preparation time (disclosed, not counted) | 2 hours/day × 30 days × ₱10 × 12 months | ₱7,200 |

Table 3.7. Projected Annual Operating Cost of Aumazing (per household, conservative)
| Line Item | Computation | Annual Cost |
| Supabase usage (prototype share) | prorated | ₱600 |
| Google Maps Platform usage (within free tier with caching) | ₱0 expected; ₱600 buffer reserved | ₱600 |
| PayMongo platform fees | per-transaction; deducted from revenue | — |
| Google Play developer account (one-time US$25, amortized) | prorated | ₱150 |
| Operating subtotal (cost to operator per Premium household) | | ₱1,350 |

Table 3.8. Premium Subscription Pricing
| SKU | Price | PayMongo Fees (estimated) | Net to Operator (annual) |
| Premium Monthly | ₱149 / month | Cards: 3.5% + ₱15; e-wallets: 2.5% (typical) | ≈ ₱1,520 / year |

Table 3.9. Annual Savings per Converted Household
| Item | Computation | Amount |
| Avoided manual cash outlay | ₱7,800 | ₱7,800 |
| Less: Premium subscription | ₱149 × 12 | (₱1,788) |
| Less: residual incidental costs | estimated | (₱1,000) |
| Net savings per Premium household | | ₱5,012 / year |

For Free-tier households, the trial cycle plus offline games library still produces an estimated ₱3,200/year in avoided costs (less printing and fewer routine-practice trips), keeping the system materially valuable even for parents who never upgrade.

**Payback period.** One-time prototype infrastructure cost (domains, signing keys, developer account, design tools) is approximately ₱12,000.

> Payback (per Premium household) = ₱12,000 ÷ ₱5,012/year ≈ **2.4 years ≈ 2 years and 5 months**.

**Decision.** Both thresholds are satisfied (payback < 3 years; savings > ₱3,000). The study **recommends proceeding** with prototype deployment under the freemium model.

3.7 RISK MANAGEMENT

Table 3.10. Risk Register
| ID | Risk | Likelihood | Impact | Mitigation |
| R-01 | The XGBoost classifier underperforms on the small validator-collected dataset. | Medium | High | Use cross-validation; fall back to a rule-based recommender when model confidence is below threshold; periodically re-train as more validator data accumulates. |
| R-02 | Google Maps Platform monthly free quota is exceeded. | Low | Medium | Cache center coordinates locally; cap map loads per session; configure billing alerts at 50%, 80%, and 100% of the free tier. |
| R-03 | A parent denies the GPS permission. | Medium | Low | Provide a graceful fallback that ranks centers by parent-entered city only; show a clear in-context rationale before requesting permission. |
| R-04 | PayMongo webhook delivery fails or arrives late. | Low | Medium | Verify subscription state on app launch by polling PayMongo's REST API as a backup; cache the last verified `expires_at`; honor it offline; re-verify on next online launch. |
| R-05 | Therapy-center directory data becomes stale. | Medium | Medium | The Administrator Portal supports periodic updates and shows `last_updated` per center to maintain parental trust. |
| R-06 | Sync conflicts between local SQLite and Supabase. | Medium | Medium | Apply last-write-wins per row using `updated_at`; queue pending writes with retry and exponential backoff. |
| R-07 | Sensory-trigger content is inadvertently included in a module. | Low | High | Maintain a sensory-review checklist in the Definition of Done; require validator sign-off per module. |
| R-08 | Scope creep back into tele-health features. | Low | High | The v2 scope is contractually locked in this revision; any tele-health work is reserved for post-capstone study. |
| R-09 | Subscription chargebacks or fraudulent payments through PayMongo. | Low | Medium | Use PayMongo's signed webhooks; validate signatures in the Supabase Edge Function; revoke entitlement promptly when a `payment.refunded` or `subscription.cancelled` event is received. |

3.8 TESTING PLAN

Testing follows a layered strategy aligned with the freemium model and is organized to map directly to the test cases TC-AU-001 through TC-AU-030 already maintained in the project test repository.

Table 3.11. Testing Layers
| Layer | Scope | Tools | Pass Criteria |
| Unit | Repositories, Haversine ranking, entitlement gate, recommender rules, scoring functions. | Dart `test`, Python `pytest`. | At least 80% line coverage on the `core/` directory. |
| Widget and UI | Each ASD-aligned screen and game shell. | `flutter_test`. | All goldens match; no overflow; touch targets at least 64 dp. |
| Integration | Offline-first sync, **PayMongo subscription flow**, GPS permission flow, AI inference round-trip. | `integration_test`. | All happy paths green; airplane-mode path green; webhook simulation green. |
| Model | XGBoost classifier. | `pytest` plus held-out evaluation set. | Macro-F1 at least equal to the rule-based baseline. |
| User Acceptance | Validator scripts per user story. | Manual checklists (parent, SPED teacher, adviser). | One hundred percent of acceptance criteria met per cycle. |

In addition to the tests already documented for the assessment, recommendation, dashboard, and offline-first modules, the v2 scope adds the following premium-specific test cases:
- A Free user is correctly blocked from a second AI-personalized cycle and is shown an upgrade prompt, while the offline games library remains fully accessible.
- A Premium user receives a fresh recommendation set after every completed assessment cycle.
- The Interactive Therapy Locator is hidden for Free users.
- When the GPS permission is denied, the Locator falls back to a city-filtered list and shows a non-blocking banner.
- The Get Directions action launches the device's default maps application via an Android Intent.
- A successful PayMongo subscription event grants Premium entitlement and updates the local cache within five seconds.
- A `payment.refunded` or `subscription.cancelled` PayMongo event downgrades the account at next launch with no data loss.

Table 3.12. Module Testing Alignment
| WBS Module | Test Cases | Primary Tester |
| 3.1 Account Access and Child Profile Module | TC-AU-001 to TC-AU-003, TC-AU-019 to TC-AU-020, TC-AU-026 | Ruel Mendio |
| 3.2 Settings, Sensory Preferences, and Screen-Time Module | TC-AU-005, TC-AU-018, TC-AU-028 | Ruel Mendio, SPED Teacher |
| 3.3 Gamified Assessment and Gameplay Indicator Module | TC-AU-004, TC-AU-006 to TC-AU-012 | Ruel Mendio |
| 3.4 AI Assessment and Recommendation Module | TC-AU-015 to TC-AU-016 | Benedict Paul Samson |
| 3.5 Learning Module and Post-Assessment Module | TC-AU-023, TC-AU-028 | Parent / Guardian Testers |
| 3.6 Dashboard, Offline Support, and Freemium Gateway Module | TC-AU-013 to TC-AU-014, TC-AU-025, TC-AU-029 plus the premium-specific test cases listed above | Benedict Paul Samson, Adviser |

Table 3.13. Testing Phases
| Phase | WBS Reference | Description | Timeline | Testing Resource | Budget |
| Phase 4.1 | 4.1 Functional and Integration Testing | Unit, integration, and functional testing across all modules. | August 2026 | Ruel Mendio, Benedict Paul Samson | ₱400.00 |
| Phase 4.2 | 4.2 User Acceptance Testing | UAT with parents and guardians, plus cross-platform testing. | September 2026 | Parent / Guardian Testers, SPED Teacher | ₱400.00 |
| Phase 4.3 | 4.3 Validator Review and Revision | Security review, technical evaluation, and revisions. | September 2026 | Adviser / IT Evaluator | ₱400.00 |

3.9 DEPLOYMENT PLAN

The deployment plan defines the activities required to prepare and release the **Aumazing** prototype for testing, validation, and final capstone presentation. Because the system is an academic prototype, deployment focuses on controlled implementation using selected Android devices, configured backend services, and validator-guided testing rather than full public release. The deployment proceeds in six phases.

First, the **environment setup** phase provisions the development, staging, and demonstration environments. The team configures Gradle build flavors (`dev`, `staging`, `prod`), Android signing keys, and a GitHub Actions pipeline that produces a signed APK on tagged commits. Second, the **Supabase configuration** phase applies all SQL migrations, enables Row-Level Security on every table, configures email and Google authentication, seeds reference data (modules, games, and therapy-center records), and stores all service keys in the team's secret manager. Third, the **PayMongo integration** phase creates the PayMongo merchant account, registers the Premium Monthly product, configures webhook endpoints pointing at a Supabase Edge Function, validates webhook signatures with the merchant secret, and runs end-to-end test transactions for cards, GCash, GrabPay, and Maya in PayMongo's sandbox environment. Fourth, the **Maps configuration** phase enables Google Maps SDK for Android in Google Cloud, restricts the API key by package name and SHA-1 fingerprint, sets up billing alerts at 50%, 80%, and 100% of the free tier, and verifies the on-device caching of center coordinates. Fifth, the **validator distribution** phase distributes a signed internal-testing APK via the Google Play Console internal track or direct private link, accompanied by an installation guide, a consent form, and a fifteen-minute walkthrough video. Pre-provisioned sandbox accounts are issued to validators. Finally, the **validator training and support** phase runs a one-hour synchronous orientation on evaluation criteria and provides asynchronous support through a dedicated channel; issues raised by validators are triaged on the Kanban board and addressed in the next build.

Figure 3.5. Deployment Plan for Aumazing

Table 3.14. Development and Deployment Phases
| Phase | Development Phase | Timeline | Description |
| Phase 1 | Requirements Gathering and Project Planning | February to March 2026 | Identifying goals, consulting validators and SPED teachers, defining the v2 freemium scope, and gathering requirements for core features. |
| Phase 2 | System and Software Design | March to April 2026 | Designing architecture, database, UI/UX, game mechanics, recommendation flows, and the freemium gating model. |
| Phase 3 | System Development and Iterative Testing | April to August 2026 | Modular development of all six WBS modules followed by iterative testing and revisions, including the PayMongo integration and the Interactive Therapy Locator. |
| Phase 4 | Evaluation, Validation, and Final Testing | August to September 2026 | UAT, accessibility checking, security review, and technical evaluation with parents and qualified validators. |
| Phase 5 | Deployment Preparation and Documentation | September 2026 | Configuring backend services, finalizing documentation, performing final bug fixes, and preparing the capstone presentation. |
