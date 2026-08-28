"""
app/model_loader.py
Loads the trained multi-output ordinal classifier and supporting metadata.

Provides a `predict()` function that returns per-area developmental level
predictions (Path B per-area design). Model artifacts are produced by
`training/train_model.py` into the `models/` directory.
"""

import json
from pathlib import Path

import joblib
import numpy as np

# ──────────────────────────────────────────────────────────────────────
# Paths to model artifacts (relative to project root = ai_assessment/)
# ──────────────────────────────────────────────────────────────────────
BASE_DIR = Path(__file__).resolve().parent.parent
MODEL_PATH = BASE_DIR / "models" / "xgboost_multi_output.pkl"
FEATURES_PATH = BASE_DIR / "models" / "feature_names.json"
LEVEL_NAMES_PATH = BASE_DIR / "models" / "level_names.json"
TARGET_NAMES_PATH = BASE_DIR / "models" / "target_names.json"

# Default fallbacks if the JSON files are absent (kept in sync with train_model)
DEFAULT_LEVEL_NAMES = {0: "Needs Support", 1: "Emerging", 2: "Strength"}
DEFAULT_TARGET_NAMES = [
    "communication_level",
    "social_level",
    "play_level",
    "attention_level",
]

# Mapping from a target column name to a short area key used in the API response
TARGET_TO_AREA = {
    "communication_level": "communication",
    "social_level": "social",
    "play_level": "play",
    "attention_level": "attention",
}

# Mapping from level int to the API-facing snake_case label
LEVEL_INT_TO_API = {0: "needs_support", 1: "emerging", 2: "strength"}


# ──────────────────────────────────────────────────────────────────────
# Module-level state (loaded once at import time)
# ──────────────────────────────────────────────────────────────────────
_model = None
_feature_names: list[str] = []
_target_names: list[str] = []
_level_names: dict[int, str] = {}
_is_loaded = False


def _load_artifacts() -> None:
    """Load model + metadata once and cache module-level."""
    global _model, _feature_names, _target_names, _level_names, _is_loaded

    if _is_loaded:
        return

    if not MODEL_PATH.exists():
        raise FileNotFoundError(
            f"Multi-output model not found at {MODEL_PATH}. "
            "Run `python training/train_model.py` first to generate model artifacts."
        )
    if not FEATURES_PATH.exists():
        raise FileNotFoundError(
            f"Feature names file not found at {FEATURES_PATH}. "
            "Run `python training/train_model.py` first."
        )

    _model = joblib.load(MODEL_PATH)

    with open(FEATURES_PATH, "r") as f:
        _feature_names = json.load(f)

    if TARGET_NAMES_PATH.exists():
        with open(TARGET_NAMES_PATH, "r") as f:
            _target_names = json.load(f)
    else:
        _target_names = list(DEFAULT_TARGET_NAMES)

    if LEVEL_NAMES_PATH.exists():
        with open(LEVEL_NAMES_PATH, "r") as f:
            raw = json.load(f)
            _level_names = {int(k): v for k, v in raw.items()}
    else:
        _level_names = dict(DEFAULT_LEVEL_NAMES)

    _is_loaded = True
    print(
        f"[model_loader] Loaded multi-output model with "
        f"{len(_feature_names)} features and {len(_target_names)} target areas."
    )


def predict(features: dict) -> dict:
    """
    Run a per-area prediction.

    Args:
        features: Dict of feature_name -> value. Keys must match training names.

    Returns:
        Dict keyed by short area name ("communication", "social", "play",
        "attention"). Each value is a sub-dict:
            {
                "level":         "needs_support" | "emerging" | "strength",
                "level_int":     0 | 1 | 2,
                "level_name":    "Needs Support" | "Emerging" | "Strength",
                "confidence":    float in [0.0, 1.0],
            }
    """
    _load_artifacts()

    # Build feature vector in canonical training order
    x = np.array(
        [[features.get(fname, 0.0) for fname in _feature_names]],
        dtype=np.float64,
    )

    # MultiOutputClassifier exposes one underlying estimator per target.
    # We call each one to get both the predicted class and its probability.
    result: dict[str, dict] = {}
    for target_idx, target_name in enumerate(_target_names):
        estimator = _model.estimators_[target_idx]
        probabilities = estimator.predict_proba(x)[0]
        predicted_int = int(np.argmax(probabilities))
        confidence = float(probabilities[predicted_int])

        area_key = TARGET_TO_AREA.get(target_name, target_name)
        result[area_key] = {
            "level": LEVEL_INT_TO_API.get(predicted_int, str(predicted_int)),
            "level_int": predicted_int,
            "level_name": _level_names.get(predicted_int, str(predicted_int)),
            "confidence": round(confidence, 4),
        }

    return result
