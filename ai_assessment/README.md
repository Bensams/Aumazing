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
│   ├── generate_training_data.py  # Synthetic data generator
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

# 1. (optional) regenerate training data
python training/generate_training_data.py

# 2. train
python training/train_model.py --data training/sample_preassessment_data.csv

# 3. export to the Flutter app's assets
python training/export_onnx.py
```

Step 3 writes `communication.onnx`, `social.onnx`, `play.onnx`,
`attention.onnx`, `feature_names.json` and `level_names.json` into
`apps/main_app/assets/models/`. The feature order in `feature_names.json` must
match `OnDeviceFeatureAggregator` in the app.
