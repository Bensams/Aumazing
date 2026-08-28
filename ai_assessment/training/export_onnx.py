"""
training/export_onnx.py
Export the trained MultiOutputClassifier (XGBoost) to per-area ONNX models for
on-device inference (ONNX Runtime Mobile) in the Flutter app.

Run from the ai_assessment/ directory:

    pip install onnx onnxmltools skl2onnx
    python training/export_onnx.py

Inputs (produced by training/train_model.py):
    models/xgboost_multi_output.pkl
    models/feature_names.json
    models/target_names.json
    models/level_names.json

Outputs (written into the Flutter app's assets so the app can bundle them):
    apps/main_app/assets/models/communication.onnx
    apps/main_app/assets/models/social.onnx
    apps/main_app/assets/models/play.onnx
    apps/main_app/assets/models/attention.onnx
    apps/main_app/assets/models/feature_names.json   (copied)
    apps/main_app/assets/models/level_names.json     (copied)

Each model is exported with zipmap=False so its probabilities output is a plain
[1, num_classes] float tensor (what on_device_ai_assessment_service.dart reads).
"""

import json
import shutil
from pathlib import Path

import joblib
from skl2onnx import convert_sklearn, update_registered_converter
from skl2onnx.common.data_types import FloatTensorType
from skl2onnx.common.shape_calculator import (
    calculate_linear_classifier_output_shapes,
)
from onnxmltools.convert.xgboost.operator_converters.XGBoost import convert_xgboost
from xgboost import XGBClassifier

BASE_DIR = Path(__file__).resolve().parent.parent  # ai_assessment/
MODELS_DIR = BASE_DIR / "models"
MODEL_PATH = MODELS_DIR / "xgboost_multi_output.pkl"
FEATURES_PATH = MODELS_DIR / "feature_names.json"
TARGETS_PATH = MODELS_DIR / "target_names.json"
LEVELS_PATH = MODELS_DIR / "level_names.json"

# Flutter app assets directory (adjust if your repo layout differs).
ASSETS_DIR = BASE_DIR.parent / "apps" / "main_app" / "assets" / "models"


def _register_xgboost() -> None:
    """Teach skl2onnx how to convert an XGBClassifier."""
    update_registered_converter(
        XGBClassifier,
        "XGBoostXGBClassifier",
        calculate_linear_classifier_output_shapes,
        convert_xgboost,
        options={"nocl": [True, False], "zipmap": [True, False, "columns"]},
    )


def main() -> None:
    if not MODEL_PATH.exists():
        raise FileNotFoundError(
            f"{MODEL_PATH} not found. Run `python training/train_model.py` first."
        )

    _register_xgboost()

    model = joblib.load(MODEL_PATH)
    feature_names = json.loads(FEATURES_PATH.read_text())
    target_names = json.loads(TARGETS_PATH.read_text())
    n_features = len(feature_names)

    ASSETS_DIR.mkdir(parents=True, exist_ok=True)
    initial_types = [("input", FloatTensorType([None, n_features]))]

    for idx, target in enumerate(target_names):
        estimator = model.estimators_[idx]
        onx = convert_sklearn(
            estimator,
            initial_types=initial_types,
            options={id(estimator): {"zipmap": False}},
            # Pin the ai.onnx.ml domain to v3 — the XGBoost converter defaults
            # to v5, which skl2onnx does not yet support. Main ONNX opset 12 is
            # widely compatible with ONNX Runtime Mobile.
            target_opset={"": 12, "ai.onnx.ml": 3},
        )
        area = target.replace("_level", "")
        out_path = ASSETS_DIR / f"{area}.onnx"
        out_path.write_bytes(onx.SerializeToString())
        print(f"[export_onnx] Wrote {out_path} ({out_path.stat().st_size} bytes)")

    # The app needs the feature order and level labels alongside the models.
    shutil.copy(FEATURES_PATH, ASSETS_DIR / "feature_names.json")
    if LEVELS_PATH.exists():
        shutil.copy(LEVELS_PATH, ASSETS_DIR / "level_names.json")

    print(
        f"[export_onnx] Done — {len(target_names)} ONNX models + metadata "
        f"written to {ASSETS_DIR}"
    )


if __name__ == "__main__":
    main()
