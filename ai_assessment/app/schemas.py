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
    idle_time_seconds: float = Field(
        default=0.0,
        description="Total idle/inactive time in seconds",
    )
    random_touch_count: int = Field(
        default=0,
        description="Number of random/invalid touches during the session",
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
    """
    Nested result containing a human-readable summary and support level.
    Maps to the `assessment_results` table (sensory_score / notes fields).
    """
    summary: str = Field(description="Human-readable summary of the assessment")
    support_level: str = Field(description="Support level: 'high', 'moderate', or 'low'")


class PreAssessmentResponse(BaseModel):
    """
    Full response from the pre-assessment prediction endpoint.

    - predicted_profile maps to assessment_results.notes
    - recommended_modules maps to module_recommendations entries
    """
    predicted_profile: str = Field(description="Predicted developmental profile category")
    confidence: float = Field(description="Model confidence score (0.0-1.0)")
    pre_assessment_result: PreAssessmentResult = Field(
        description="Assessment summary and support level",
    )
    recommended_modules: List[str] = Field(
        description="List of recommended learning module titles",
    )
    feature_values: Optional[Dict[str, float]] = Field(
        default=None,
        description="Computed feature values used for prediction (for transparency/debugging)",
    )

    class Config:
        json_schema_extra = {
            "example": {
                "predicted_profile": "communication_support",
                "confidence": 0.82,
                "pre_assessment_result": {
                    "summary": "Your child may benefit from activities that build imitation and verbal instruction skills.",
                    "support_level": "high",
                },
                "recommended_modules": ["Copy Me", "Do What I Say"],
                "feature_values": {
                    "overall_accuracy": 0.65,
                    "copy_me_accuracy": 0.7,
                    "match_it_accuracy": 0.6,
                },
            }
        }
