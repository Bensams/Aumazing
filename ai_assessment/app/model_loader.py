"""
app/model_loader.py
Loads the trained XGBoost model, label encoder, and feature names from disk.

Provides a simple `predict()` function used by the FastAPI endpoint.
Model artifacts are saved by `training/train_model.py` into the `models/` directory.
"""

import json
import os
from pathlib import Path

import joblib
import numpy as np

# ──────────────────────────────────────────────────────────────────────
# Paths to model artifacts (relative to project root)
# ──────────────────────────────────────────────────────────────────────
BASE_DIR = Path(__file__).resolve().parent.parent  # project root
MODEL_PATH = BASE_DIR / "models" / "xgboost_preassessment.pkl"
ENCODER_PATH = BASE_DIR / "models" / "label_encoder.pkl"
FEATURES_PATH = BASE_DIR / "models" / "feature_names.json"

# ──────────────────────────────────────────────────────────────────────
# Module-level variables (loaded once at import time)
# ──────────────────────────────────────────────────────────────────────
_model = None
_label_encoder = None
_feature_names: list[str] = []
_is_loaded = False


def _load_artifacts() -> None:
    """
    Load model, label encoder, and feature names from disk.
    Sets module-level variables so artifacts are only loaded once.
    """
    global _model, _label_encoder, _feature_names, _is_loaded

    if _is_loaded:
        return

    # Check that all required files exist
    for path, name in [
        (MODEL_PATH, "XGBoost model"),
        (ENCODER_PATH, "Label encoder"),
        (FEATURES_PATH, "Feature names"),
    ]:
        if not path.exists():
            raise FileNotFoundError(
                f"{name} not found at {path}. "
                "Run `python training/train_model.py` first to generate model artifacts."
            )

    _model = joblib.load(MODEL_PATH)
    _label_encoder = joblib.load(ENCODER_PATH)

    with open(FEATURES_PATH, "r") as f:
        _feature_names = json.load(f)

    _is_loaded = True
    print(f"[model_loader] Loaded model with {len(_feature_names)} features.")


def predict(features: dict) -> tuple[str, float]:
    """
    Run a prediction using the loaded XGBoost model.

    Args:
        features: Dictionary of feature_name -> value. Keys must match
                  the feature names used during training.

    Returns:
        Tuple of (predicted_profile_label, confidence_score).
        - predicted_profile_label: e.g. "communication_support"
        - confidence_score: float between 0.0 and 1.0
    """
    # Ensure artifacts are loaded
    _load_artifacts()

    # Build feature vector in the correct column order
    feature_vector = []
    for fname in _feature_names:
        feature_vector.append(features.get(fname, 0.0))

    # Reshape to (1, n_features) for a single prediction
    X = np.array([feature_vector], dtype=np.float64)

    # Get predicted class index and probability distribution
    predicted_index = _model.predict(X)[0]
    probabilities = _model.predict_proba(X)[0]

    # Decode the label back to a human-readable string
    predicted_label = _label_encoder.inverse_transform([int(predicted_index)])[0]

    # Confidence is the probability of the predicted class
    confidence = float(probabilities[int(predicted_index)])

    return predicted_label, confidence
