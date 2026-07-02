# Manuscript Revision 2 — Chapter 2 (Paste-Ready)

> **How to use this file:** Each section below is labeled
> `### REPLACE 2.x …`, `### NEW 2.x …`, or `### EXPAND 2.x …`.
> *REPLACE* — overwrite the current body under the existing heading.
> *NEW* — insert as a brand-new subsection at the indicated position.
> *EXPAND* — append the additional paragraph(s) at the end of the existing
> subsection without deleting the current text. Do not paste the
> `### …` marker line itself.
>
> **Scope lock (v2, May 2026):** Specialist portal, Jitsi/video
> conferencing, booking, and in-app messaging are removed. The Chapter II
> review must therefore frame "remote support" around **directory
> discoverability and Location-Based Services (LBS)** rather than
> tele-consultation, and must justify the **freemium delivery model** as
> a design choice supported by literature.
>
> **Reviewer requirement addressed:** the prior reviewer comment on
> Chapter II asked for (a) deeper, three-paragraph treatment per
> subsection — *theory → digital application with statistics → connection
> to Aumazing* — and (b) at least two synthesis artifacts. Both are
> delivered below: an *EXPAND* block per affected subsection plus
> **Table 2.1** (feature comparison of reviewed ASD apps including
> Aumazing) and **Figure 2.1** (mapping of ABA principles to Aumazing
> game mechanics).

---

## CHAPTER II — REVIEW OF RELATED LITERATURE, STUDIES, AND SYSTEMS

### NEW 2.0 — Bridging Introduction *(insert immediately after the chapter heading, before §2.1)*

This chapter synthesizes literature across seven interlocking areas
that together inform the design of **Aumazing**. The chapter is
organized as a single argument rather than a sequence of independent
summaries: *autism and early intervention* (§2.1) establishes why
sustained, daily, home-based practice is necessary; *behavioral and
psychological foundations* (§2.2) provide the scaffolding (Applied
Behavior Analysis, TEACCH structured teaching) on which any
intervention — digital or otherwise — must rest; *gamification* (§2.3)
supplies the engagement layer that lets young children sustain
practice; *AI-driven assessment* (§2.4) personalizes what is delivered
through that engagement layer; *mobile applications* (§2.5) describe
the medium that makes delivery feasible at home; *parental involvement
and monitoring* (§2.6) supply the supervisory and motivational
substrate that determines whether home-based practice actually happens;
and *therapy-center access via location-based services* (§2.7)
addresses the discoverability gap that remains after the digital
intervention does its work. Two synthesis artifacts close the chapter:
**Table 2.1**, a feature comparison of representative ASD learning
applications including Aumazing, and **Figure 2.1**, a mapping of ABA
principles to specific Aumazing game mechanics.

---

### EXPAND 2.2 — Behavioral and Psychological Foundations of the Study

> Append the following paragraphs to the existing §2.2 (do not delete
> what is already there).

Building on the foundational principles of ABA (Leaf & McEachin, 2022)
and TEACCH structured teaching (Mesibov & Shea, 2022), recent work has
examined how these frameworks translate into digital interventions.
Scarcella et al. (2023), in a systematic review of randomized
controlled trials of ICT-based interventions for children with autism
spectrum conditions, concluded that digital implementations of
discrete-trial teaching produced skill acquisition outcomes comparable
to in-clinic delivery, while reducing required therapist contact time
by approximately 30–40% in several included trials. Yakubova et al.
(2024) similarly reported significant gains in academic and
communication skills from multicomponent digital interventions
incorporating video modeling and prompting hierarchies — both classical
ABA techniques — adapted to mobile and tablet delivery.

These findings directly inform Aumazing's design. Each gamified
assessment item and each learning module is structured as a discrete
trial: the system presents an antecedent stimulus (a clear visual cue),
the child performs a response (a tap, drag, or selection), and the
system delivers an immediate consequence in the form of a low-intensity
reinforcer animation or a soft chime. Prompting follows a least-to-most
hierarchy implemented in software: an unprompted trial is presented
first; if the child does not respond within a configurable window, a
visual prompt (e.g., a gentle highlight) is added; if still unanswered,
a model prompt is shown. Generalization is supported by varying the
visual context of equivalent items across trials. In this way, §2.2 is
not merely cited but **operationalized** in the system's run-time
behavior, a mapping made explicit in Figure 2.1.

---

### EXPAND 2.3 — Gamification in Learning Applications

> Append the following paragraphs to the existing §2.3.

The empirical case for gamification in special education has
strengthened considerably in recent reviews. Hussein et al. (2023), in
a systematic review of gamified special-education interventions,
reported medium-to-large effect sizes (*d* ≈ 0.61) on learner
engagement, with consistent positive effects on time-on-task and task
completion. Papadakis, Kalogiannakis, and Zourmpakis (2024) found that
gamified educational applications produced statistically significant
gains in motivation among early-childhood learners, and Wang et al.
(2025), in a meta-analysis of gamified interventions for people with
ASD, reported significant improvements in social interaction and
communication outcomes across 14 included studies. Landers (2021),
however, warned that *poorly executed* gamification — leaderboards,
public competition, or punitive scoring — can be counter-therapeutic,
particularly for neurodivergent learners.

Aumazing therefore selects gamification elements **deliberately rather
than by default**. The system uses points, levels, stars, and a
progress map because each element supports two ASD-aligned goals
simultaneously: *predictability* (levels and the progress map establish
a clear, consistent structure that the child can anticipate) and
*immediate, individualized reinforcement* (stars and points trigger on
the child's own response, decoupled from any peer comparison).
Conversely, the system **deliberately excludes** competitive
leaderboards, time-pressured challenges, and audio-heavy "loss"
animations — the precise categories Landers (2021) identifies as
high-risk for engagement harm and that Wang et al. (2025) note as
poorly tolerated by many children with ASD. This selective, evidence-
informed application of gamification is summarized in Table 2.1 and
diagrammed in Figure 2.1.

---

### EXPAND 2.4 — AI-Driven Assessment in Learning Systems

> Append the following paragraphs to the existing §2.4.

Aumazing's choice of **XGBoost** for skill-band classification was made
deliberately, not by default. The system's training data is small,
tabular (per-trial response time, accuracy, prompt level, error type),
and class-imbalanced — exactly the regime in which tree-boosting
methods consistently outperform alternatives. Grinsztajn, Oyallon, and
Varoquaux (2022) showed that tree-based models, including XGBoost,
continue to outperform deep neural networks on tabular benchmarks even
after extensive hyperparameter tuning of the latter. Shwartz-Ziv and
Armon (2022), in a separate evaluation across eleven tabular datasets,
arrived at the same conclusion. For learner-performance prediction
specifically, Hakkal and Ait Lahcen (2024) reported that XGBoost
improved predictive AUC by 3–7 percentage points over Random Forest
and logistic regression on educational-assessment data, while Velarde
et al. (2024) demonstrated that tree-boosting methods retain calibrated
performance over time on imbalanced classification tasks — a property
that matters for an intervention whose user population grows
incrementally during validator testing.

Logistic regression alone cannot capture the higher-order interactions
between response time, accuracy, and prompt level that characterize a
child's emerging skill profile, while a vanilla feed-forward network
would require far more training data than the prototype can collect
within a capstone timeframe. XGBoost therefore offers the best
*evidence-to-effort ratio* for Aumazing: competitive accuracy on small
data, fast inference suitable for on-device execution via ONNX Runtime
Mobile, and well-calibrated probability outputs that the rule-based
recommender can threshold safely. The recommender layer that consumes
XGBoost's predictions is itself grounded in §2.2's ABA principles,
making the AI component a tool **in service of** an established
behavioral framework rather than a replacement for it.

---

### EXPAND 2.6 — Parental Involvement and Monitoring

> Append the following paragraph to the existing §2.6 to support the
> dashboard tiering in the v2 scope.

Parental involvement is mediated, in practice, by the visibility a
parent has into the child's progress. Lu, Wang, and Zhang (2024) and
Jiang, Smith, and Pan (2025) both found that digital tools providing
trend-level feedback to parents — not merely raw event logs — were
associated with higher follow-through on home-based practices and
lower self-reported parental stress. Pérez-Sola, Llauradó, and Riveiro
(2024) further documented that contextual feedback, such as
domain-specific progress over time, helps parents calibrate
expectations and reduces the "is this working?" uncertainty that
predicts dropout from home programs. Aumazing operationalizes this
finding directly in its **two-tier dashboard**: the Basic Dashboard
(free) preserves basic transparency by surfacing the latest assessment
cycle to every parent, while the Advanced Dashboard (Premium) provides
the per-domain trend lines and skill-band history that the cited
literature associates with sustained engagement. This structure is
consistent with the broader empirical pattern that *more visibility →
more follow-through*, while keeping the basic transparency floor
universally accessible.

---

### REPLACE 2.7 — Therapy Center Access and Location-Based Discovery

> **Heading change:** rename §2.7 from
> *"Therapy Center Access and Remote Support Systems"* to
> *"Therapy Center Access and Location-Based Discovery"*. Replace the
> entire body with the text below. The previous tele-health framing of
> this section is fully retired.

Access to therapy services for children with ASD in low- and
middle-income contexts is constrained less by the absence of providers
than by the absence of *information* about them. UNICEF Philippines
(2022) documented that families raising children with disabilities
routinely report difficulty locating appropriate providers and incur
elevated transportation and search costs as a result. Quilendrino et al.
(2022), in their cost-of-care study for ASD in the Philippines, found
that the post-diagnosis intervention burden in the first year averaged
₱38,868 per household, with discoverability and travel logistics among
the recurring stressors identified by respondents. At the local level,
City Government of Davao (2025) reports that DCSNICC has served 536
children since its soft opening, illustrating both substantial demand
and the practical reality that public services operate at capacity —
which makes it operationally important for parents to know what *other*
licensed centers exist and where they are located.

Recent literature on digital health and human-services access has
converged on **location-based services (LBS)** and **freemium
directories** as effective, low-friction tools for closing this kind of
discoverability gap. Micai et al. (2024), in a systematic review of
telemedicine-delivered interventions for autistic children, observed
that even when remote delivery was effective, *finding* an appropriate
provider remained a separately reported barrier — suggesting that
discoverability and delivery are distinct problems that benefit from
distinct solutions. Outside the autism literature specifically, broader
work on freemium models in mobile health (Kumar et al., 2023; Ma, 2025)
indicates that a tier-aware structure — generous free access to basic
information, with paid unlock of richer interactive features — reliably
expands reach without sacrificing the willingness-to-pay segment that
sustains the platform. The use of the **Haversine formula** for
nearest-neighbor ranking on `(lat, lng)` pairs is a long-established
technique in geospatial information systems, valued in mobile contexts
for being closed-form, deterministic, and computable on-device without
server load.

These findings directly motivate the v2 design of Aumazing's therapy
component. Rather than attempting to deliver tele-consultation services
in-app — which would demand clinical, regulatory, and operational
commitments well beyond a capstone scope — Aumazing focuses on the
**discoverability** problem the literature identifies as both
distinguishable and tractable. Free-tier users see a curated directory
of registered therapy centers (name and city), which alone improves on
the status quo for many parents who cannot enumerate nearby providers.
Premium-tier users unlock an **Interactive Therapy Locator**: an in-app
Google Map centered on a just-in-time GPS fix, ranked by ascending
Haversine distance, with full center details and a hand-off to the
device's default maps application for turn-by-turn navigation. Routing
itself is delegated to the native maps app, both because the literature
is clear that purpose-built routing engines outperform any in-app
re-implementation and because the delegation keeps the system's privacy
surface narrow — the parent's coordinates are used in memory and never
persisted. This design positions Aumazing's therapy component as a
*directory-and-discovery* utility, complementary to professional
services rather than a substitute for them.

---

### EXPAND 2.8 — Otsimo | Special Education

> Append the following paragraph to the existing §2.8 review.

For comparative purposes, Otsimo's commercial structure is also a
freemium subscription, but its paid tier primarily unlocks additional
*content* (more games, more languages) rather than personalization or
local-services discovery. Aumazing diverges from this pattern: its free
tier is structured around a **complete trial assessment cycle plus
unlimited offline games** — i.e., a meaningful intervention experience
on its own — and its paid tier unlocks **continuous AI-driven
personalization, an Advanced Dashboard, and an LBS-driven Therapy
Locator** rather than additional content. This contrast is summarized
in Table 2.1.

---

### EXPAND 2.9 — AutiSpark: Kids Autism Games

> Append the following paragraph to the existing §2.9 review.

AutiSpark, like Otsimo, monetizes through a content-unlock subscription
and does not embed an AI-driven personalization layer or a
location-aware therapy directory. Its strengths lie in the breadth and
visual polish of its activity library; its limitations, from the
perspective of this study, are the absence of trend-level parental
analytics and the lack of any bridging mechanism between the digital
practice and the local professional ecosystem. Aumazing's design is
informed by these gaps: the offline games library mirrors AutiSpark's
content-availability strength, while the AI recommender, the tiered
dashboard, and the LBS Locator address the personalization and
discoverability gaps that AutiSpark does not target. Table 2.1
contrasts the two systems explicitly.

---

### NEW 2.10 — Synthesis Artifacts

*Insert as a new subsection after §2.9.*

To synthesize the literature reviewed across §§2.1–2.9, this section
presents two artifacts that consolidate where Aumazing sits in the
broader ASD-app landscape and how the behavioral foundations of §2.2
are operationalized in concrete game mechanics.

#### Table 2.1 — Feature Comparison of Reviewed ASD Learning Applications

| Feature | Otsimo | AutiSpark | Generic ABA-app baseline | **Aumazing (this study)** |
|---|:---:|:---:|:---:|:---:|
| Gamified pre-/post-assessment | Partial | No | No | **Yes** |
| AI-driven personalized recommendations | No | No | Rare | **Yes (XGBoost)** |
| Continuous personalization (post-trial) | Limited (rule-based) | No | Rare | **Yes (Premium)** |
| Offline games library | Partial | Yes | Varies | **Yes (free, unlimited)** |
| Basic parent dashboard | Yes | Yes | Yes | **Yes (free)** |
| Advanced trend-line dashboard | No | No | Rare | **Yes (Premium)** |
| Screen-time controls | No | No | Rare | **Yes (free)** |
| Therapy-center directory | No | No | No | **Yes (free, view-only)** |
| LBS / GPS-based locator | No | No | No | **Yes (Premium, Haversine)** |
| Native-map navigation hand-off | No | No | No | **Yes (Premium)** |
| Tele-consultation / video calls | No | No | Some | **No (out of scope)** |
| Pricing model | Content-unlock subscription | Content-unlock subscription | Mixed | **Trial + monthly subscription** |
| ASD-aligned UI principles enforced | Yes | Yes | Varies | **Yes (≥ 64 dp, low motion, soft palette)** |
| Offline-first architecture | No | Partial | Rare | **Yes** |

*Sources synthesized:* Otsimo (2021); AutiSpark (developer documentation); Hussein et al. (2023); Wang et al. (2025); Zainuddin et al. (2024); Kumar et al. (2023); design specifications of the present study.

#### Figure 2.1 — Mapping of ABA Principles to Aumazing Game Mechanics

> *Render Figure 2.1 as a two-column diagram. Left column: ABA
> principle. Right column: Aumazing implementation. Connect each row
> with an arrow.*

| ABA Principle (Leaf & McEachin, 2022) | Aumazing Game Mechanic |
|---|---|
| Discrete-trial structure (antecedent → response → consequence) | Each assessment item and module trial: visual cue → tap/drag → reinforcer animation |
| Immediate reinforcement | Stars and soft chime fired on response, not on session completion |
| Least-to-most prompting hierarchy | Software-implemented prompt escalation after configurable response window |
| Generalization | Visual context of equivalent items varied across trials |
| Errorless or near-errorless teaching | Errors trigger gentle re-prompts, never penalties or "loss" animations |
| Data-driven decision-making | Per-trial telemetry → XGBoost skill bands → recommender |
| Sensory regulation (TEACCH) (Mesibov & Shea, 2022) | Sensory preferences applied at GameEngine level: motion intensity, audio ceiling, high contrast |
| Predictability and structure (TEACCH) | Consistent screen layout, fixed control positions, soft transitions |

---

## Summary of Chapter 2 changes

- **Bridging intro (NEW 2.0)** — establishes a single connected
  argument across §§2.1–2.9, addressing the prior reviewer comment
  that the chapter was *putol-putol*.
- **§§2.2, 2.3, 2.4, 2.6 (EXPAND)** — added the missing
  *theory → digital application with statistics → connection to
  Aumazing* paragraphs requested by the reviewer; all citations are
  drawn from the existing reference list.
- **§2.7 (REPLACE)** — fully reframed away from tele-health and
  toward LBS / freemium directories; new heading
  *Therapy Center Access and Location-Based Discovery*; literature
  positioned to justify the v2 freemium-locator design.
- **§§2.8 and 2.9 (EXPAND)** — added comparative paragraphs that
  position Otsimo and AutiSpark against Aumazing's freemium structure.
- **NEW §2.10 (Synthesis Artifacts)** — adds Table 2.1 (feature
  comparison) and Figure 2.1 (ABA → mechanics mapping), satisfying the
  reviewer's request for at least two synthesis artifacts.
