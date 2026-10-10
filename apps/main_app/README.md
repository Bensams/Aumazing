# aumazing

A new Flutter project.

## Parent-reported home context in summaries

The assessment summary and Overall Gameplay Summary include optional home
questionnaire frequencies alongside game results. Reports are matched to the
child's completed assessment runs and their pre/post cycle. Child names, run
identifiers, questionnaire identifiers and question wording are not sent to the
summary providers.

Skipping the home questionnaire keeps the game-based summary available. Missing
answers remain unknown, never zero. Home frequency ratings do not change game
scores, difficulty, recommendations, support settings or learning-path unlocks.
The summaries identify them as parent reports, keep them separate from measured
game performance, and do not treat draft questionnaires as validated measures.

Home comparisons require the same item-set signature; legacy reports without a
signature require the same template and revision. A changed report refreshes the
summary cache. Gemini remains the primary provider and Groq the fallback; when
both are unavailable, the app uses its existing on-device summary.

## Optional parent forms

Before a fresh assessment, collect child background once. Later assessments
offer **Use previous answers** or **Update answers**. The adult identifies who
is watching today; questions marked `current_session` by a practitioner always
start blank. Resuming an unfinished assessment skips this form, as before.

Intake responses keep separate `background_answers` and `session_answers`, plus
`background_mode`, `reused_question_ids`, and the original `answer_sources`.
The existing `answers` and readable `summary` remain available to older readers.
An untouched prefilled answer retains its original source even in Update mode.
Results label reused background as earlier information, not a new observation.
Reuse requires the same template identity and matching question wording, type,
timing and option labels. Legacy responses without question signatures require
the same template identity and version; changed versions ask for fresh answers.

After play, the bundled version 2 check-in asks about help, mood and the day.
Game questions appear only for games the adult selects for extra explanation;
deselecting a game discards its unsaved details. Practitioner session questions
and required answers within selected game details remain supported. A session-only
observation template is also valid. Historical observation records retain their
saved wording, summaries and flags.

The home questionnaire stays at assessment milestones: the initial pre-assessment,
the post-assessment offered after completing the recommended learning path, and
later assessment cycles. It is never prompted by ordinary game sessions. A report
already saved for a run is not collected again, even if the active version changes;
the next assessment uses the active version and fresh home observations.

All three forms explain their purpose and allow skipping. Intake and after-play
observations do not enter AI summaries. The existing attributed home-report context
in assessment and overall summaries remains unchanged and never changes game scores.
This change uses existing template items and response JSON; it needs no database
migration or summary-function redeployment. Rebuild and reinstall the mobile app
to use the new flow.
