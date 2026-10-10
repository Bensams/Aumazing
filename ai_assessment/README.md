# Aumazing AI Assessment — model training

Offline training pipeline for the XGBoost developmental-profile model. The
trained model is exported to ONNX and bundled with the Flutter app, which runs
it **on-device** through ONNX Runtime (`apps/main_app/lib/services/on_device_ai_assessment_service_native.dart`).
There is no hosted prediction server — when the on-device model is
unavailable (for example on the web build), the app falls back to its local
rubric scoring.

## Layout

```
ai_assessment/
├── models/
│   ├── xgboost_multi_output.pkl   # Trained per-area classifier (export input)
│   ├── feature_names.json         # Canonical feature order
│   ├── target_names.json          # Developmental areas
│   └── level_names.json           # 0=Needs Support, 1=Emerging, 2=Strength
├── training/
│   ├── generate_training_data.py  # Original generator + the labeling rubric
│   ├── generate_calibrated_data.py # Generator calibrated on real runs
│   ├── real_runs_features.csv     # Real runs' features (de-identified)
│   ├── evaluate_on_real.py        # Synthetic-trained model vs real runs
│   ├── REAL_DATA_EVALUATION.md    # Latest evaluation report
│   ├── sample_preassessment_data.csv
│   ├── LABELING_RUBRIC.md
│   ├── train_model.py             # Training with 5-fold CV
│   └── export_onnx.py             # Exports per-area ONNX models into the app
└── requirements.txt
```

## Workflow

```bash
cd ai_assessment
pip install -r requirements.txt

# 1. (optional) regenerate training data — calibrated on the real runs
python training/generate_calibrated_data.py
#    or the original independent-uniform generator:
python training/generate_training_data.py

#    compare both against the real runs (writes REAL_DATA_EVALUATION.md)
python training/evaluate_on_real.py

# 2. train
python training/train_model.py --data training/sample_preassessment_data.csv

# 3. export to the Flutter app's assets
python training/export_onnx.py
```

Step 3 writes `communication.onnx`, `social.onnx`, `play.onnx`,
`attention.onnx`, `feature_names.json` and `level_names.json` into
`apps/main_app/assets/models/`. The feature order in `feature_names.json` must
match `OnDeviceFeatureAggregator` in the app.

## Calibrated synthetic data

`generate_calibrated_data.py` answers the pre-final defense note that synthetic
data should be based on real assessment results. It fits a Gaussian copula to
the real runs in `real_runs_features.csv` (feature correlations, shrunk toward
independence because the sample is small) and draws each feature from a blend of
the smoothed real distribution and the original rubric-spanning range, so that
Needs Support and Emerging children stay represented. Labels still come from
the rubric in `generate_training_data.py`: the real runs have no expert labels.

To refresh `real_runs_features.csv`, compute the 12 features per assessment run
from `public.game_sessions` exactly as `OnDeviceFeatureAggregator` does,
drop run ids, and remove exact duplicate runs (automated test runs).
`REAL_DATA_EVALUATION.md` reports what the calibration changes and its limits.

