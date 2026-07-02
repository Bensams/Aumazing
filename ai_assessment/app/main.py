"""
app/main.py
FastAPI application for the Aumazing AI Assessment API.

Endpoints:
    GET  /                        — Health check
    GET  /health                  — Health check
    POST /predict-preassessment   — Run XGBoost prediction from pre-computed features
    POST /predict-from-sessions   — Accept raw game sessions, compute features, predict
    POST /predict-from-supabase   — Fetch sessions from Supabase, compute features, predict

The API accepts game-session features, runs them through a trained XGBoost model,
and returns a developmental profile prediction with recommended learning modules.
Results can optionally be stored in Supabase tables: assessment_results & module_recommendations.
"""

import logging
from typing import List

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware

from app import __version__, __app_name__
from app.schemas import (
    GameSessionInput,
    GameSessionsInput,
    PreAssessmentInput,
    PreAssessmentResponse,
    SupabasePredictInput,
)
from app.model_loader import predict
from app.rules import get_recommendation
from app.feature_aggregator import aggregate_features

logger = logging.getLogger(__name__)

# ──────────────────────────────────────────────────────────────────────
# FastAPI app instance
# ──────────────────────────────────────────────────────────────────────
app = FastAPI(
    title=__app_name__,
    description=(
        "XGBoost-based prediction service for the Aumazing app. "
        "Predicts a child's developmental profile from game-session data "
        "and recommends appropriate learning modules."
    ),
    version=__version__,
)

# ──────────────────────────────────────────────────────────────────────
# CORS middleware — allow all origins for development
# In production, restrict `allow_origins` to your Flutter app's domain.
# ──────────────────────────────────────────────────────────────────────
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ──────────────────────────────────────────────────────────────────────
# Health-check endpoints
# ──────────────────────────────────────────────────────────────────────
@app.get("/")
def root():
    """Root health check."""
    return {
        "status": "ok",
        "service": __app_name__,
        "version": __version__,
    }


@app.get("/health")
def health():
    """Explicit health-check endpoint."""
    return {
        "status": "ok",
        "service": __app_name__,
        "version": __version__,
    }


# ──────────────────────────────────────────────────────────────────────
# 1. Original endpoint — pre-computed features (backward compatible)
# ──────────────────────────────────────────────────────────────────────
@app.post("/predict-preassessment", response_model=PreAssessmentResponse)
def predict_preassessment(input_data: PreAssessmentInput):
    """
    Accept pre-assessment features and return a developmental profile prediction.

    **Flow:**
    1. Extract feature values from the request body.
    2. Pass features to the XGBoost model for prediction.
    3. Apply rule-based logic to generate module recommendations.
    4. Return the full response (profile, confidence, summary, modules).

    The response can be used by the Flutter app to:
    - Store the profile in ``assessment_results``
    - Create entries in ``module_recommendations``
    """
    try:
        features = input_data.model_dump()
        area_levels = predict(features)
        recommendation = get_recommendation(area_levels, features)

        return PreAssessmentResponse(
            area_levels=recommendation["area_levels"],
            module_details=recommendation["module_details"],
            skill_areas=recommendation["skill_areas"],
            predicted_profile=recommendation["predicted_profile"],
            confidence=recommendation["confidence"],
            pre_assessment_result=recommendation["pre_assessment_result"],
            recommended_modules=recommendation["recommended_modules"],
            feature_values=features,
        )

    except FileNotFoundError as e:
        raise HTTPException(status_code=503, detail=str(e))
    except Exception as e:
        logger.exception("Prediction failed in /predict-preassessment")
        raise HTTPException(
            status_code=500,
            detail=f"Prediction failed: {str(e)}",
        )


# ──────────────────────────────────────────────────────────────────────
# 2. New endpoint — raw game sessions → features → prediction
# ──────────────────────────────────────────────────────────────────────
@app.post("/predict-from-sessions", response_model=PreAssessmentResponse)
def predict_from_sessions(input_data: GameSessionsInput):
    """
    Accept raw game session data, compute features, and predict.

    **Flow:**
    1. Aggregate raw ``GameSessionInput`` records into the 12 XGBoost features.
    2. Run the XGBoost model.
    3. Apply rule-based recommendations.
    4. Return the response with ``feature_values`` included for transparency.
    """
    try:
        features = aggregate_features(input_data.sessions)
        area_levels = predict(features)
        recommendation = get_recommendation(area_levels, features)

        return PreAssessmentResponse(
            area_levels=recommendation["area_levels"],
            module_details=recommendation["module_details"],
            skill_areas=recommendation["skill_areas"],
            predicted_profile=recommendation["predicted_profile"],
            confidence=recommendation["confidence"],
            pre_assessment_result=recommendation["pre_assessment_result"],
            recommended_modules=recommendation["recommended_modules"],
            feature_values=features,
        )

    except FileNotFoundError as e:
        raise HTTPException(status_code=503, detail=str(e))
    except Exception as e:
        logger.exception("Prediction failed in /predict-from-sessions")
        raise HTTPException(
            status_code=500,
            detail=f"Prediction failed: {str(e)}",
        )


# ──────────────────────────────────────────────────────────────────────
# 3. New endpoint — fetch from Supabase → features → prediction
# ──────────────────────────────────────────────────────────────────────
@app.post("/predict-from-supabase", response_model=PreAssessmentResponse)
def predict_from_supabase(input_data: SupabasePredictInput):
    """
    Fetch game sessions from Supabase, compute features, and predict.

    Optionally saves the assessment result and module recommendations
    back to Supabase when ``save_results`` is ``True``.

    **Flow:**
    1. Fetch game sessions from the ``game_sessions`` table.
    2. Convert rows to ``GameSessionInput`` objects.
    3. Aggregate into the 12 XGBoost features.
    4. Run the model and build recommendations.
    5. (Optional) Persist results to Supabase.
    6. Return the response.
    """
    try:
        # Lazy import to avoid requiring Supabase credentials for other endpoints
        from app.supabase_client import (
            fetch_game_sessions,
            save_assessment_result,
            save_module_recommendations,
        )

        # 1. Fetch raw session rows from Supabase
        raw_sessions = fetch_game_sessions(
            input_data.child_id,
            input_data.assessment_run_id,
        )

        if not raw_sessions:
            raise HTTPException(
                status_code=404,
                detail=(
                    f"No game sessions found for child_id={input_data.child_id}, "
                    f"assessment_run_id={input_data.assessment_run_id}"
                ),
            )

        # 2. Convert Supabase rows to GameSessionInput objects
        sessions: List[GameSessionInput] = []
        for row in raw_sessions:
            sessions.append(
                GameSessionInput(
                    game_id=row.get("game_id", ""),
                    score=row.get("score", 0),
                    total_items=row.get("total_items", 1),
                    error_count=row.get("error_count", 0),
                    total_response_time_ms=row.get("total_response_time_ms", 4000),
                    retry_count=row.get("retry_count", 0),
                    hint_count=row.get("hint_count", 0),
                    idle_time_seconds=row.get("idle_time_seconds", 0.0),
                    random_touch_count=row.get("random_touch_count", 0),
                )
            )

        # 3. Aggregate features
        features = aggregate_features(sessions)

        # 4. Predict and build recommendation
        area_levels = predict(features)
        recommendation = get_recommendation(area_levels, features)

        # 5. Optionally save results back to Supabase
        if input_data.save_results:
            try:
                save_assessment_result(
                    child_id=input_data.child_id,
                    assessment_run_id=input_data.assessment_run_id,
                    result={
                        "predicted_profile": recommendation["predicted_profile"],
                        "confidence": recommendation["confidence"],
                        "summary": recommendation["pre_assessment_result"]["summary"],
                        "support_level": recommendation["pre_assessment_result"]["support_level"],
                        "area_levels": recommendation["area_levels"],
                    },
                )
                save_module_recommendations(
                    child_id=input_data.child_id,
                    assessment_run_id=input_data.assessment_run_id,
                    recommendations=recommendation.get("module_details", []),
                )
                logger.info(
                    "Saved results to Supabase for child=%s, run=%s",
                    input_data.child_id,
                    input_data.assessment_run_id,
                )
            except Exception as save_err:
                # Log but don't fail the prediction if saving fails
                logger.error(
                    "Failed to save results to Supabase: %s", save_err
                )

        # 6. Return response
        return PreAssessmentResponse(
            area_levels=recommendation["area_levels"],
            module_details=recommendation["module_details"],
            skill_areas=recommendation["skill_areas"],
            predicted_profile=recommendation["predicted_profile"],
            confidence=recommendation["confidence"],
            pre_assessment_result=recommendation["pre_assessment_result"],
            recommended_modules=recommendation["recommended_modules"],
            feature_values=features,
        )

    except HTTPException:
        raise
    except FileNotFoundError as e:
        raise HTTPException(status_code=503, detail=str(e))
    except Exception as e:
        logger.exception("Prediction failed in /predict-from-supabase")
        raise HTTPException(
            status_code=500,
            detail=f"Prediction failed: {str(e)}",
        )
