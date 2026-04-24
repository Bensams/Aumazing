"""
app/supabase_client.py
Supabase client initialisation and helper functions for the Aumazing AI Assessment API.

Provides convenience wrappers around the Supabase Python client for:
- Fetching game sessions for a child / assessment run
- Saving assessment results
- Saving module recommendations
"""

import logging
from typing import Optional

from supabase import create_client, Client

from app.config import SUPABASE_URL, SUPABASE_SERVICE_KEY

logger = logging.getLogger(__name__)

# ──────────────────────────────────────────────────────────────────────
# Supabase client singleton
# ──────────────────────────────────────────────────────────────────────
_client: Optional[Client] = None


def _get_client() -> Client:
    """Return (and lazily initialise) the Supabase client."""
    global _client
    if _client is None:
        if not SUPABASE_SERVICE_KEY:
            raise RuntimeError(
                "SUPABASE_SERVICE_KEY is not set. "
                "Add it to your .env file or environment variables."
            )
        _client = create_client(SUPABASE_URL, SUPABASE_SERVICE_KEY)
        logger.info("Supabase client initialised for %s", SUPABASE_URL)
    return _client


# ──────────────────────────────────────────────────────────────────────
# Helper functions
# ──────────────────────────────────────────────────────────────────────

def fetch_game_sessions(child_id: str, assessment_run_id: str) -> list[dict]:
    """
    Fetch game session rows from the ``game_sessions`` table for a given
    child and assessment run.

    Args:
        child_id: UUID of the child.
        assessment_run_id: UUID of the assessment run.

    Returns:
        List of game-session dictionaries as stored in Supabase.
    """
    client = _get_client()
    response = (
        client.table("game_sessions")
        .select("*")
        .eq("child_id", child_id)
        .eq("assessment_run_id", assessment_run_id)
        .execute()
    )
    logger.info(
        "Fetched %d game sessions for child=%s, run=%s",
        len(response.data),
        child_id,
        assessment_run_id,
    )
    return response.data


def save_assessment_result(
    child_id: str,
    assessment_run_id: str,
    result: dict,
) -> dict:
    """
    Upsert an assessment result into the ``assessment_results`` table.

    Args:
        child_id: UUID of the child.
        assessment_run_id: UUID of the assessment run.
        result: Dictionary containing prediction results (predicted_profile,
                confidence, summary, support_level, etc.).

    Returns:
        The inserted/updated row as a dictionary.
    """
    client = _get_client()
    row = {
        "child_id": child_id,
        "assessment_run_id": assessment_run_id,
        "predicted_profile": result.get("predicted_profile"),
        "confidence": result.get("confidence"),
        "support_level": result.get("support_level"),
        "notes": result.get("summary"),
    }
    response = client.table("assessment_results").upsert(row).execute()
    logger.info(
        "Saved assessment result for child=%s, run=%s",
        child_id,
        assessment_run_id,
    )
    return response.data[0] if response.data else row


def save_module_recommendations(
    child_id: str,
    assessment_run_id: str,
    recommendations: list[dict],
) -> list[dict]:
    """
    Insert module recommendation rows into the ``module_recommendations`` table.

    Args:
        child_id: UUID of the child.
        assessment_run_id: UUID of the assessment run.
        recommendations: List of recommendation dicts, each containing at
                         least ``game_id``, ``name``, and ``starting_level``.

    Returns:
        List of inserted rows.
    """
    client = _get_client()
    rows = [
        {
            "child_id": child_id,
            "assessment_run_id": assessment_run_id,
            "game_id": rec.get("game_id"),
            "module_name": rec.get("name"),
            "starting_level": rec.get("starting_level", 1),
        }
        for rec in recommendations
    ]
    response = client.table("module_recommendations").insert(rows).execute()
    logger.info(
        "Saved %d module recommendations for child=%s, run=%s",
        len(rows),
        child_id,
        assessment_run_id,
    )
    return response.data if response.data else rows
