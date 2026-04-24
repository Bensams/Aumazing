"""
app/rules.py
Rule-based module recommendation mapping for the Aumazing Pre-Assessment system.

Maps predicted developmental profiles to recommended learning modules
and human-readable summaries. These recommendations align with the
`module_recommendations` and `learning_modules` tables in Supabase.

Game-ID ↔ Skill-category mapping (from the Flutter app):
    copy_me            → Communication, Play Skills
    match_it           → Play Skills
    do_what_i_say      → Communication
    my_turn_your_turn  → Social Interaction
"""

from typing import Any

# ──────────────────────────────────────────────────────────────────────
# Enriched module recommendations per developmental profile
# ──────────────────────────────────────────────────────────────────────
PROFILE_MODULE_MAP: dict[str, dict[str, Any]] = {
    "communication_support": {
        "modules": [
            {"game_id": "copy_me", "name": "Copy Me", "starting_level": 1},
            {"game_id": "do_what_i_say", "name": "Do What I Say", "starting_level": 1},
        ],
        "summary": (
            "Your child may benefit from activities that build imitation "
            "and verbal instruction skills."
        ),
        "skill_areas": ["communication"],
    },
    "social_support": {
        "modules": [
            {"game_id": "my_turn_your_turn", "name": "My Turn, Your Turn", "starting_level": 1},
        ],
        "summary": (
            "Your child may benefit from activities that encourage "
            "turn-taking and social interaction."
        ),
        "skill_areas": ["social_interaction"],
    },
    "play_support": {
        "modules": [
            {"game_id": "match_it", "name": "Match It", "starting_level": 1},
            {"game_id": "copy_me", "name": "Copy Me", "starting_level": 1},
        ],
        "summary": (
            "Your child may benefit from activities that develop matching "
            "and creative play skills."
        ),
        "skill_areas": ["play_skills"],
    },
    "attention_support": {
        "modules": [
            {"game_id": "do_what_i_say", "name": "Do What I Say", "starting_level": 1},
            {"game_id": "match_it", "name": "Match It", "starting_level": 1},
        ],
        "summary": (
            "Your child may benefit from activities that build focus "
            "and sustained attention."
        ),
        "skill_areas": ["attention"],
    },
    "balanced_profile": {
        "modules": [
            {"game_id": "copy_me", "name": "Copy Me", "starting_level": 1},
            {"game_id": "match_it", "name": "Match It", "starting_level": 1},
            {"game_id": "my_turn_your_turn", "name": "My Turn, Your Turn", "starting_level": 1},
            {"game_id": "do_what_i_say", "name": "Do What I Say", "starting_level": 1},
        ],
        "summary": (
            "Your child shows balanced skills across all areas. "
            "A mixed starter module is recommended."
        ),
        "skill_areas": ["communication", "social_interaction", "play_skills", "attention"],
    },
}

# Game-ID → accuracy feature name (used for starting-level lookup)
_GAME_ACCURACY_KEY: dict[str, str] = {
    "copy_me": "copy_me_accuracy",
    "match_it": "match_it_accuracy",
    "my_turn_your_turn": "my_turn_your_turn_accuracy",
    "do_what_i_say": "do_what_i_say_accuracy",
}


# ──────────────────────────────────────────────────────────────────────
# Support-level helpers
# ──────────────────────────────────────────────────────────────────────

def get_support_level(confidence: float) -> str:
    """
    Determine the support level label based on model confidence.

    Args:
        confidence: Model prediction confidence (0.0 – 1.0).

    Returns:
        ``"high"`` if confidence ≥ 0.8,
        ``"moderate"`` if confidence ≥ 0.5,
        ``"low"`` otherwise.
    """
    if confidence >= 0.8:
        return "high"
    elif confidence >= 0.5:
        return "moderate"
    else:
        return "low"


def determine_starting_level(accuracy: float) -> int:
    """
    Choose a starting difficulty level based on per-game accuracy.

    Args:
        accuracy: Accuracy value (0.0 – 1.0).

    Returns:
        3 if accuracy ≥ 0.8,
        2 if accuracy ≥ 0.5,
        1 otherwise.
    """
    if accuracy >= 0.8:
        return 3
    elif accuracy >= 0.5:
        return 2
    else:
        return 1


# ──────────────────────────────────────────────────────────────────────
# Main recommendation builder
# ──────────────────────────────────────────────────────────────────────

def get_recommendation(
    profile: str,
    confidence: float,
    feature_values: dict[str, float] | None = None,
) -> dict:
    """
    Build a full recommendation payload for a given profile and confidence.

    When *feature_values* are provided (i.e. when called from the
    session-based endpoints), the ``starting_level`` of each module is
    dynamically set based on the child's per-game accuracy.

    Args:
        profile: Predicted developmental profile string
                 (e.g. ``"communication_support"``).
        confidence: Model prediction confidence (0.0 – 1.0).
        feature_values: Optional dict of computed features. Used to
                        determine per-module starting levels.

    Returns:
        Dictionary matching the ``PreAssessmentResponse`` schema.
    """
    profile_data = PROFILE_MODULE_MAP.get(profile)

    if profile_data is None:
        # Fallback for unrecognised profiles
        profile_data = PROFILE_MODULE_MAP["balanced_profile"]

    support_level = get_support_level(confidence)

    # Deep-copy modules so we don't mutate the constant
    modules = [dict(m) for m in profile_data["modules"]]

    # Adjust starting levels when feature values are available
    if feature_values:
        for mod in modules:
            acc_key = _GAME_ACCURACY_KEY.get(mod["game_id"])
            if acc_key and acc_key in feature_values:
                mod["starting_level"] = determine_starting_level(
                    feature_values[acc_key]
                )

    # Build the flat module-name list for backward compatibility
    module_names = [m["name"] for m in modules]

    return {
        "predicted_profile": profile,
        "confidence": round(confidence, 4),
        "pre_assessment_result": {
            "summary": profile_data["summary"],
            "support_level": support_level,
        },
        "recommended_modules": module_names,
        "skill_areas": profile_data["skill_areas"],
        "module_details": modules,
    }
