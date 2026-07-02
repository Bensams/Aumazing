"""
app/schemas.py
Pydantic models for the Aumazing AI Assessment API.

These schemas define the request/response structure for all prediction endpoints.
Fields map to features derived from Supabase tables: game_sessions, game_rounds, session_events.
"""

from typing import Dict, List, Optional
from pydantic import BaseModel, Field


# ──────────────────────────────────────────────────────────────────────
# Existing pre-assessment input (12 XGBoost features)
# ──────────────────────────────────────────────────────────────────────

class PreAssessmentInput(BaseModel):
    """
    Input features for pre-assessment prediction.

    All fields are optional with sensible defaults so the API can handle
    partial data (e.g. if a child hasn't played all games yet).

    Per-child aggregated features (derived from game_sessions / game_rounds / session_events):
    """

    # --- Overall aggregated features ---
    overall_accuracy: float = Field(
        default=0.5,
        ge=0.0, le=1.0,
        description="Overall accuracy across all games (0.0-1.0)"
    )
    overall_avg_response_time: float = Field(
        default=4.0,
        ge=0.0,
        description="Average response time in seconds across all rounds"
    )
    overall_task_completion_rate: float = Field(
        default=0.5,
        ge=0.0, le=1.0,
        description="Fraction of tasks completed (0.0-1.0)"
    )
    overall_retry_count: float = Field(
        default=3.0,
        ge=0.0,
        description="Total number of retries across sessions"
    )
    overall_hint_count: float = Field(
        default=5.0,
        ge=0.0,
        description="Total number of hints used across sessions"
    )
    overall_prompt_dependency_score: float = Field(
        default=0.3,
        ge=0.0, le=1.0,
        description="How dependent the child is on prompts (0.0-1.0)"
    )
    overall_idle_time_seconds: float = Field(
        default=15.0,
        ge=0.0,
        description="Total idle/inactive time in seconds"
    )
    overall_invalid_touch_count: float = Field(
        default=5.0,
        ge=0.0,
        description="Number of invalid/random touches during sessions"
    )

    # --- Per-game accuracy features ---
    copy_me_accuracy: float = Field(
        default=0.5,
        ge=0.0, le=1.0,
        description="Accuracy in the 'Copy Me' game (0.0-1.0)"
    )
    match_it_accuracy: float = Field(
        default=0.5,
        ge=0.0, le=1.0,
        description="Accuracy in the 'Match It' game (0.0-1.0)"
    )
    my_turn_your_turn_accuracy: float = Field(
        default=0.5,
        ge=0.0, le=1.0,
        description="Accuracy in the 'My Turn, Your Turn' game (0.0-1.0)"
    )
    do_what_i_say_accuracy: float = Field(
        default=0.5,
        ge=0.0, le=1.0,
        description="Accuracy in the 'Do What I Say' game (0.0-1.0)"
    )

    class Config:
        json_schema_extra = {
            "example": {
                "overall_accuracy": 0.65,
                "overall_avg_response_time": 3.2,
                "overall_task_completion_rate": 0.7,
                "overall_retry_count": 4,
                "overall_hint_count": 6,
                "overall_prompt_dependency_score": 0.35,
                "overall_idle_time_seconds": 12.0,
                "overall_invalid_touch_count": 3,
                "copy_me_accuracy": 0.7,
                "match_it_accuracy": 0.6,
                "my_turn_your_turn_accuracy": 0.55,
                "do_what_i_say_accuracy": 0.65,
            }
        }


# ──────────────────────────────────────────────────────────────────────
# Game session input — matches Flutter GameplaySession.toSupabase()
# ──────────────────────────────────────────────────────────────────────

class GameSessionInput(BaseModel):
    """Matches the Flutter app's GameplaySession.toSupabase() format."""

    game_id: str = Field(
        description="Game identifier: copy_me, match_it, my_turn_your_turn, do_what_i_say"
    )
    score: int = Field(description="Number of correct responses in the session")
    total_items: int = Field(description="Total number of items/rounds in the session")
    error_count: int = Field(default=0, description="Number of errors in the session")
    total_response_time_ms: int = Field(
        default=4000,
        description="Total response time in milliseconds across all items",
    )
    # Sensory round metrics (optional)
    retry_count: int = Field(default=0, description="Number of retries in the session")
    hint_count: int = Field(default=0, description="Number of hints used in the session")
    prompt_count: int = Field(default=0, description="Number of prompts given in the session")
    idle_time_seconds: float = Field(
        default=0.0,
        description="Total idle/inactive time in seconds",
    )
    random_touch_count: int = Field(
        default=0,
        description="Number of random/invalid touches during the session",
    )
    # Extended analytics fields
    avg_response_time: float = Field(
        default=0.0,
        description="Average response time in seconds",
    )
    avg_valid_response_time: float = Field(
        default=0.0,
        description="Average valid response time in seconds",
    )
    off_task_action_count: int = Field(
        default=0,
        description="Number of off-task actions",
    )
    improvement_score: float = Field(
        default=0.0,
        description="Performance improvement score (-1.0 to 1.0)",
    )
    consistency_score: float = Field(
        default=0.0,
        description="Performance consistency score (0.0 to 1.0)",
    )
    # Sensory preference fields
    bg_music_enabled: bool = Field(
        default=True,
        description="Whether background music was enabled during this session",
    )
    haptic_feedback_enabled: bool = Field(
        default=True,
        description="Whether haptic feedback was enabled during this session",
    )


class GameSessionsInput(BaseModel):
    """Input for the /predict-from-sessions endpoint."""

    child_id: str = Field(description="UUID of the child")
    assessment_run_id: Optional[str] = Field(
        default=None,
        description="UUID of the assessment run (optional)",
    )
    sessions: List[GameSessionInput] = Field(
        description="List of raw game session data from the Flutter app",
    )


class SupabasePredictInput(BaseModel):
    """Input for the /predict-from-supabase endpoint."""

    child_id: str = Field(description="UUID of the child")
    assessment_run_id: str = Field(description="UUID of the assessment run")
    save_results: bool = Field(
        default=True,
        description="Whether to save prediction results back to Supabase",
    )


# ──────────────────────────────────────────────────────────────────────
# Response models
# ──────────────────────────────────────────────────────────────────────

class PreAssessmentResult(BaseModel):
    """Human-readable summary and support level for the assessment."""
    summary: str = Field(description="Human-readable summary of the assessment")
    support_level: str = Field(description="Support level: 'high', 'moderate', or 'low'")


class AreaLevel(BaseModel):
    """
    Per-area ordinal prediction for a single developmental skill area.

    Path B — each child receives one of these for each of the four areas
    (communication, social, play, attention).
    """
    level: str = Field(
        description="Snake-case label: 'needs_support', 'emerging', or 'strength'",
    )
    level_int: int = Field(
        description="Ordinal integer encoding: 0=Needs Support, 1=Emerging, 2=Strength",
        ge=0, le=2,
    )
    level_name: str = Field(
        description="Title-case label for display: 'Needs Support', 'Emerging', or 'Strength'",
    )
    confidence: float = Field(
        description="Model confidence for this area's prediction (0.0-1.0)",
        ge=0.0, le=1.0,
    )


class ModuleDetail(BaseModel):
    """A single recommended learning module with its driving context."""
    game_id: str = Field(description="Game identifier (e.g. 'copy_me')")
    name: str = Field(description="Display name (e.g. 'Copy Me')")
    starting_level: int = Field(
        description="Suggested starting difficulty (1=easiest, 3=hardest)",
        ge=1, le=3,
    )
    driver_areas: List[str] = Field(
        description="Skill areas that triggered this recommendation",
    )


class PreAssessmentResponse(BaseModel):
    """
    Full response from the pre-assessment prediction endpoint.

    Dual-response shape (Path B):
      * ``area_levels`` (NEW) is the canonical per-area output produced by
        the multi-output classifier.
      * ``module_details`` (NEW) lists each recommended module with its
        driving area and starting level.
      * ``predicted_profile`` / ``confidence`` / ``recommended_modules``
        are derived legacy fields preserved for backwards compatibility
        with old Flutter clients. New clients should prefer ``area_levels``.
    """

    # ---- New per-area fields (preferred) ----
    area_levels: Dict[str, AreaLevel] = Field(
        description=(
            "Per-area predictions keyed by short area name "
            "('communication', 'social', 'play', 'attention')."
        ),
    )
    module_details: List[ModuleDetail] = Field(
        default_factory=list,
        description="Detailed module recommendations with driver areas and starting levels",
    )
    skill_areas: List[str] = Field(
        default_factory=list,
        description="Skill areas implicated by the recommendation",
    )

    # ---- Legacy fields (derived, kept for backwards compatibility) ----
    predicted_profile: str = Field(
        description=(
            "Legacy single-profile string derived via tie-break rule from "
            "area_levels. Prefer area_levels for new clients."
        ),
    )
    confidence: float = Field(
        description="Confidence of the dominant area's prediction (legacy)",
        ge=0.0, le=1.0,
    )
    pre_assessment_result: PreAssessmentResult = Field(
        description="Assessment summary and support level",
    )
    recommended_modules: List[str] = Field(
        description="Flat list of recommended module names (legacy)",
    )

    # ---- Diagnostic ----
    feature_values: Optional[Dict[str, float]] = Field(
        default=None,
        description="Computed feature values used for prediction (transparency/debug)",
    )

    class Config:
        json_schema_extra = {
            "example": {
                "area_levels": {
                    "communication": {
                        "level": "needs_support",
                        "level_int": 0,
                        "level_name": "Needs Support",
                        "confidence": 0.84,
                    },
                    "social": {
                        "level": "emerging",
                        "level_int": 1,
                        "level_name": "Emerging",
                        "confidence": 0.72,
                    },
                    "play": {
                        "level": "strength",
                        "level_int": 2,
                        "level_name": "Strength",
                        "confidence": 0.91,
                    },
                    "attention": {
                        "level": "emerging",
                        "level_int": 1,
                        "level_name": "Emerging",
                        "confidence": 0.65,
                    },
                },
                "module_details": [
                    {
                        "game_id": "copy_me",
                        "name": "Copy Me",
                        "starting_level": 1,
                        "driver_areas": ["communication"],
                    },
                    {
                        "game_id": "do_what_i_say",
                        "name": "Do What I Say",
                        "starting_level": 1,
                        "driver_areas": ["communication", "attention"],
                    },
                    {
                        "game_id": "my_turn_your_turn",
                        "name": "My Turn, Your Turn",
                        "starting_level": 2,
                        "driver_areas": ["social"],
                    },
                ],
                "skill_areas": ["communication", "social", "attention"],
                "predicted_profile": "communication_support",
                "confidence": 0.84,
                "pre_assessment_result": {
                    "summary": (
                        "Your child may benefit from activities that build "
                        "imitation and verbal instruction skills, turn-taking "
                        "and social interaction, and focus and sustained attention."
                    ),
                    "support_level": "high",
                },
                "recommended_modules": [
                    "Copy Me", "Do What I Say", "My Turn, Your Turn",
                ],
                "feature_values": {
                    "overall_accuracy": 0.55,
                    "copy_me_accuracy": 0.30,
                },
            }
        }
