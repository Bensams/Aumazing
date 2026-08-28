"""
app/rules.py
Per-area recommendation logic for the Aumazing Pre-Assessment system
(Path B — per-area ordinal design).

Given the model's per-area level predictions, this module:
  * Selects modules to recommend for any skill area not labelled Strength.
  * Deduplicates modules driven by multiple areas, keeping the lowest
    starting level when an area requires more support.
  * Derives a legacy single ``predicted_profile`` string for backwards
    compatibility with old Flutter clients (dual-response strategy).

Game-ID ↔ Skill-area mapping:
    copy_me            → Communication
    do_what_i_say      → Communication, Attention
    match_it           → Play, Attention
    my_turn_your_turn  → Social
    hintay             → Attention (go/no-go; the only direct measure)
    anong_susunod      → Play, Communication (routine sequencing / visual schedule)
    kumusta            → Social, Communication (responding to a greeting bid)
"""

from typing import Any

# ──────────────────────────────────────────────────────────────────────
# Per-area module map — modules to suggest when a given skill area is
# anything other than Strength. Mirrors PROFILE_MODULE_MAP from the
# legacy single-profile design.
# ──────────────────────────────────────────────────────────────────────
AREA_MODULE_MAP: dict[str, list[dict[str, Any]]] = {
    "communication": [
        {"game_id": "copy_me", "name": "Copy Me"},
        {"game_id": "do_what_i_say", "name": "Do What I Say"},
        {"game_id": "sari_sari_sort", "name": "Sari-Sari Store Sorting"},
        {"game_id": "anong_susunod", "name": "Ano'ng Susunod?"},
        {"game_id": "kumusta", "name": "Kumusta!"},
        {"game_id": "anong_nararamdaman", "name": "Ano'ng Nararamdaman?"},
        {"game_id": "tulong_kaibigan", "name": "Tulong, Kaibigan!"},
    ],
    "social": [
        # Ordered developmentally, easiest prerequisite first, because the
        # child works down this list: joint attention comes before responding
        # to a social bid, which comes before sustaining a turn-taking
        # exchange. A child who cannot yet share attention with a partner
        # cannot meaningfully greet one or take turns with one, so offering
        # turn-taking first would be asking for a skill built on a foundation
        # that is not there yet.
        {"game_id": "sabay_tayo", "name": "Sabay Tayo!"},
        {"game_id": "kumusta", "name": "Kumusta!"},
        {"game_id": "my_turn_your_turn", "name": "My Turn, Your Turn"},
        # Last, and not because it matters least: reading what another person
        # feels asks the child to infer an inner state from a face, which comes
        # later than joining, greeting or alternating with them.
        {"game_id": "anong_nararamdaman", "name": "Ano'ng Nararamdaman?"},
        {"game_id": "tulong_kaibigan", "name": "Tulong, Kaibigan!"},
    ],
    "play": [
        {"game_id": "match_it", "name": "Match It"},
        {"game_id": "sabay_tayo", "name": "Sabay Tayo!"},
        {"game_id": "sari_sari_sort", "name": "Sari-Sari Store Sorting"},
        {"game_id": "trace_it", "name": "Trace It"},
        {"game_id": "anong_susunod", "name": "Ano'ng Susunod?"},
    ],
    "attention": [
        # Listed first: the only module built to train attention directly
        # rather than measuring it as a by-product of another task.
        {"game_id": "hintay", "name": "Hintay!"},
        {"game_id": "do_what_i_say", "name": "Do What I Say"},
        {"game_id": "match_it", "name": "Match It"},
    ],
}

# Per-area human-readable summary fragments used to build the response summary.
AREA_SUMMARY: dict[str, str] = {
    "communication": "imitation and verbal instruction skills",
    "social": "turn-taking and social interaction",
    "play": "matching and creative play",
    "attention": "focus and sustained attention",
}

# Map a level int (0/1/2) to a default starting difficulty.
# Needs Support → start easy; Emerging → mid; Strength → advanced.
LEVEL_TO_STARTING_LEVEL: dict[int, int] = {0: 1, 1: 2, 2: 3}

# Game-ID → accuracy feature name (used for fallback starting-level lookup).
_GAME_ACCURACY_KEY: dict[str, str] = {
    "copy_me": "copy_me_accuracy",
    "match_it": "match_it_accuracy",
    "my_turn_your_turn": "my_turn_your_turn_accuracy",
    "do_what_i_say": "do_what_i_say_accuracy",
}

# Tie-break priority for deriving the legacy ``predicted_profile`` string.
# Attention wins ties because broad attention concerns affect performance
# in every other area; this is clinically the most important to flag first.
_LEGACY_PRIORITY: list[str] = ["attention", "communication", "social", "play"]

# Map an area key to the legacy 5-class profile string.
_AREA_TO_LEGACY_PROFILE: dict[str, str] = {
    "communication": "communication_support",
    "social": "social_support",
    "play": "play_support",
    "attention": "attention_support",
}

# Areas that consume the ``recommended_modules`` field. Order is preserved
# in the dual-response so old clients see a stable ordering.
_AREA_ORDER: list[str] = ["communication", "social", "play", "attention"]


# ──────────────────────────────────────────────────────────────────────
# Helpers
# ──────────────────────────────────────────────────────────────────────

def get_support_level(confidence: float) -> str:
    """Map a confidence score to a ``high``/``moderate``/``low`` label."""
    if confidence >= 0.8:
        return "high"
    if confidence >= 0.5:
        return "moderate"
    return "low"


def determine_starting_level(accuracy: float) -> int:
    """Fallback per-game starting level based on raw accuracy."""
    if accuracy >= 0.8:
        return 3
    if accuracy >= 0.5:
        return 2
    return 1


def _derive_legacy_profile(area_levels: dict[str, dict]) -> tuple[str, float]:
    """
    Derive a legacy 5-class profile string from the per-area predictions.

    Rules (dual-response backwards compatibility):
      1. If all four areas are at Strength (level_int == 2) → ``"balanced_profile"``.
      2. Otherwise, find the lowest level_int across areas. Among areas tied
         at that lowest level, pick by ``_LEGACY_PRIORITY``
         (attention > communication > social > play).
      3. Map that winning area to its legacy profile string.
      4. The legacy ``confidence`` is the confidence of the winning area.
    """
    if all(area_levels[a]["level_int"] == 2 for a in _AREA_ORDER if a in area_levels):
        # Confidence = mean across areas (any single area's confidence is fine)
        confidences = [area_levels[a]["confidence"] for a in area_levels]
        avg_conf = sum(confidences) / len(confidences) if confidences else 0.0
        return "balanced_profile", round(avg_conf, 4)

    # Find the lowest level_int present across known areas
    present = [a for a in _AREA_ORDER if a in area_levels]
    lowest_level = min(area_levels[a]["level_int"] for a in present)

    # Among ties at lowest_level, pick by priority
    for area in _LEGACY_PRIORITY:
        if area in area_levels and area_levels[area]["level_int"] == lowest_level:
            return (
                _AREA_TO_LEGACY_PROFILE[area],
                round(area_levels[area]["confidence"], 4),
            )

    # Defensive fallback (should not reach here for known areas)
    return "balanced_profile", 0.0


def _build_summary(area_levels: dict[str, dict]) -> str:
    """Build a human-readable summary listing each non-Strength area."""
    needs = [
        AREA_SUMMARY[a]
        for a in _AREA_ORDER
        if a in area_levels and area_levels[a]["level_int"] != 2
    ]
    if not needs:
        return (
            "Your child shows balanced skills across all areas. "
            "A mixed starter module is recommended."
        )
    if len(needs) == 1:
        return f"Your child may benefit from activities that build {needs[0]}."
    if len(needs) == 2:
        return (
            f"Your child may benefit from activities that build "
            f"{needs[0]} and {needs[1]}."
        )
    return (
        "Your child may benefit from activities that build "
        + ", ".join(needs[:-1])
        + f", and {needs[-1]}."
    )


# ──────────────────────────────────────────────────────────────────────
# Main recommendation builder
# ──────────────────────────────────────────────────────────────────────

def get_recommendation(
    area_levels: dict[str, dict],
    feature_values: dict[str, float] | None = None,
) -> dict:
    """
    Build a full recommendation payload from per-area predictions.

    Args:
        area_levels: Per-area predictions, keyed by short area name
            ("communication", "social", "play", "attention"). Each value
            must contain at least ``level_int`` (0/1/2) and ``confidence``.
            This is the exact structure returned by
            ``app.model_loader.predict``.
        feature_values: Optional dict of computed features used as a
            fallback to refine each module's ``starting_level``.

    Returns:
        Dictionary populating the ``PreAssessmentResponse`` schema, including
        the legacy ``predicted_profile`` and ``confidence`` fields for
        backwards compatibility.
    """
    # 1. Collect modules driven by any non-Strength area, deduplicating by
    #    game_id and keeping the lowest starting level (i.e. the area that
    #    needs the most support drives difficulty).
    modules_by_game: dict[str, dict[str, Any]] = {}
    for area, prediction in area_levels.items():
        level_int = prediction.get("level_int", 2)
        if level_int == 2:  # Strength — no module needed for this area
            continue
        if area not in AREA_MODULE_MAP:
            continue

        new_starting = LEVEL_TO_STARTING_LEVEL.get(level_int, 1)
        for mod in AREA_MODULE_MAP[area]:
            game_id = mod["game_id"]
            existing = modules_by_game.get(game_id)
            if existing is None:
                modules_by_game[game_id] = {
                    "game_id": game_id,
                    "name": mod["name"],
                    "starting_level": new_starting,
                    "driver_areas": [area],
                }
            else:
                # Lower starting level wins (more support)
                if new_starting < existing["starting_level"]:
                    existing["starting_level"] = new_starting
                if area not in existing["driver_areas"]:
                    existing["driver_areas"].append(area)

    # 2. If every area is Strength, recommend a balanced starter set so the
    #    child still has something to play.
    if not modules_by_game:
        for area in ("communication", "social", "play", "attention"):
            for mod in AREA_MODULE_MAP[area]:
                modules_by_game.setdefault(
                    mod["game_id"],
                    {
                        "game_id": mod["game_id"],
                        "name": mod["name"],
                        "starting_level": 3,
                        "driver_areas": ["balanced"],
                    },
                )

    # 3. Optional refinement: if we have raw feature accuracies, allow them
    #    to *raise* the starting level when the child performed strongly on
    #    that game even though some other area triggered the recommendation.
    if feature_values:
        for game_id, mod in modules_by_game.items():
            acc_key = _GAME_ACCURACY_KEY.get(game_id)
            if not acc_key or acc_key not in feature_values:
                continue
            acc_based = determine_starting_level(feature_values[acc_key])
            mod["starting_level"] = max(mod["starting_level"], acc_based)

    modules = list(modules_by_game.values())
    module_names = [m["name"] for m in modules]

    # 4. Derive the legacy single-profile fields for dual-response compat.
    legacy_profile, legacy_confidence = _derive_legacy_profile(area_levels)
    support_level = get_support_level(legacy_confidence)
    summary = _build_summary(area_levels)

    # 5. List the skill areas implicated by this recommendation.
    skill_areas = [
        a for a in _AREA_ORDER
        if a in area_levels and area_levels[a].get("level_int", 2) != 2
    ]
    if not skill_areas:
        skill_areas = list(_AREA_ORDER)

    return {
        "area_levels": area_levels,
        "predicted_profile": legacy_profile,
        "confidence": round(legacy_confidence, 4),
        "pre_assessment_result": {
            "summary": summary,
            "support_level": support_level,
        },
        "recommended_modules": module_names,
        "skill_areas": skill_areas,
        "module_details": modules,
    }
