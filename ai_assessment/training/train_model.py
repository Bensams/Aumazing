"""
training/train_model.py
Training script for the Aumazing Pre-Assessment XGBoost model.

This script:
    1. Loads the sample CSV dataset
    2. Encodes the target labels
    3. Performs stratified 5-fold cross-validation
    4. Trains a final XGBClassifier on the full dataset
    5. Prints per-class precision/recall/F1, accuracy, and confusion matrix
    6. Saves the model, label encoder, and feature names to the models/ directory

Usage (from ai_assessment/ directory):
    python training/train_model.py
    python training/train_model.py --data training/custom_data.csv
"""

import argparse
import json
import os
import sys
from pathlib import Path

import joblib
import numpy as np
import pandas as pd
from sklearn.metrics import (
    accuracy_score,
    classification_report,
    confusion_matrix,
)
from sklearn.model_selection import StratifiedKFold, cross_val_predict
from sklearn.preprocessing import LabelEncoder
from xgboost import XGBClassifier

# ──────────────────────────────────────────────────────────────────────
# Paths (relative to project root = ai_assessment/)
# ──────────────────────────────────────────────────────────────────────
PROJECT_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_DATA_PATH = PROJECT_ROOT / "training" / "sample_preassessment_data.csv"
MODELS_DIR = PROJECT_ROOT / "models"
MODEL_OUTPUT = MODELS_DIR / "xgboost_preassessment.pkl"
ENCODER_OUTPUT = MODELS_DIR / "label_encoder.pkl"
FEATURES_OUTPUT = MODELS_DIR / "feature_names.json"


def parse_args():
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(
        description="Train the Aumazing Pre-Assessment XGBoost model."
    )
    parser.add_argument(
        "--data",
        type=str,
        default=None,
        help=(
            "Path to the training CSV file "
            "(default: training/sample_preassessment_data.csv)"
        ),
    )
    return parser.parse_args()


def main():
    """Main training pipeline."""
    args = parse_args()

    # Resolve data path
    if args.data is not None:
        data_path = Path(args.data)
        if not data_path.is_absolute():
            data_path = Path.cwd() / data_path
    else:
        data_path = DEFAULT_DATA_PATH

    # Ensure the models directory exists
    MODELS_DIR.mkdir(parents=True, exist_ok=True)

    # ── 1. Load the dataset ──────────────────────────────────────────
    print("=" * 60)
    print("Aumazing Pre-Assessment — XGBoost Training Pipeline")
    print("=" * 60)

    if not data_path.exists():
        print(f"ERROR: Dataset not found at {data_path}")
        sys.exit(1)

    df = pd.read_csv(data_path)
    print(f"\nLoaded dataset: {df.shape[0]} rows, {df.shape[1]} columns")
    print(f"Source: {data_path}")
    print(f"\nTarget distribution:\n{df['developmental_profile'].value_counts()}\n")

    # ── 2. Separate features (X) and target (y) ─────────────────────
    TARGET_COL = "developmental_profile"
    feature_cols = [col for col in df.columns if col != TARGET_COL]

    X = df[feature_cols].values
    y_raw = df[TARGET_COL].values

    print(f"Feature columns ({len(feature_cols)}):")
    for col in feature_cols:
        print(f"  - {col}")
    print()

    # ── 3. Encode target labels ──────────────────────────────────────
    label_encoder = LabelEncoder()
    y = label_encoder.fit_transform(y_raw)

    print("Label encoding:")
    for i, label in enumerate(label_encoder.classes_):
        print(f"  {i} -> {label}")
    print()

    # ── 4. Stratified 5-fold cross-validation ────────────────────────
    print("-" * 60)
    print("Stratified 5-Fold Cross-Validation")
    print("-" * 60)

    skf = StratifiedKFold(n_splits=5, shuffle=True, random_state=42)

    # XGBoost hyperparameters
    xgb_params = dict(
        n_estimators=200,
        max_depth=4,
        learning_rate=0.1,
        objective="multi:softprob",
        num_class=len(label_encoder.classes_),
        random_state=42,
        eval_metric="mlogloss",
    )

    # Per-fold accuracy tracking
    fold_accuracies = []

    for fold_idx, (train_idx, val_idx) in enumerate(skf.split(X, y), start=1):
        X_train, X_val = X[train_idx], X[val_idx]
        y_train, y_val = y[train_idx], y[val_idx]

        fold_model = XGBClassifier(**xgb_params)
        fold_model.fit(X_train, y_train)

        y_val_pred = fold_model.predict(X_val)
        fold_acc = accuracy_score(y_val, y_val_pred)
        fold_accuracies.append(fold_acc)
        print(f"  Fold {fold_idx}: accuracy = {fold_acc:.4f}  "
              f"(train={len(train_idx)}, val={len(val_idx)})")

    mean_acc = np.mean(fold_accuracies)
    std_acc = np.std(fold_accuracies)
    print(f"\n  Mean CV Accuracy: {mean_acc:.4f} (+/- {std_acc:.4f})")

    # Cross-val predictions for full classification report
    cv_model = XGBClassifier(**xgb_params)
    y_cv_pred = cross_val_predict(cv_model, X, y, cv=skf)

    target_names = list(label_encoder.classes_)

    print(f"\nOverall CV Accuracy: {accuracy_score(y, y_cv_pred):.4f}\n")

    print("Classification Report (cross-validated):")
    print(classification_report(y, y_cv_pred, target_names=target_names))

    # Confusion matrix from CV predictions
    print("Confusion Matrix (cross-validated):")
    cm = confusion_matrix(y, y_cv_pred)
    # Print with labels for readability
    print(f"{'':>25s}", end="")
    for name in target_names:
        print(f"{name[:12]:>14s}", end="")
    print()
    for i, row in enumerate(cm):
        print(f"{target_names[i]:>25s}", end="")
        for val in row:
            print(f"{val:>14d}", end="")
        print()
    print()

    # ── 5. Train final model on full dataset ─────────────────────────
    print("-" * 60)
    print("Training final model on full dataset...")
    print("-" * 60)

    final_model = XGBClassifier(**xgb_params)
    final_model.fit(X, y)
    print("Training complete.\n")

    # ── 6. Feature importance ────────────────────────────────────────
    importances = final_model.feature_importances_
    importance_pairs = sorted(
        zip(feature_cols, importances),
        key=lambda x: x[1],
        reverse=True,
    )

    print("Feature Importance (sorted):")
    for fname, imp in importance_pairs:
        bar = "#" * int(imp * 50)
        print(f"  {fname:<40s} {imp:.4f}  {bar}")
    print()

    # ── 7. Save artifacts ────────────────────────────────────────────
    # Save the trained model
    joblib.dump(final_model, MODEL_OUTPUT)
    print(f"Model saved to:          {MODEL_OUTPUT}")

    # Save the label encoder
    joblib.dump(label_encoder, ENCODER_OUTPUT)
    print(f"Label encoder saved to:  {ENCODER_OUTPUT}")

    # Save feature names as JSON
    with open(FEATURES_OUTPUT, "w") as f:
        json.dump(feature_cols, f, indent=2)
    print(f"Feature names saved to:  {FEATURES_OUTPUT}")

    print("\n" + "=" * 60)
    print("Training pipeline complete! You can now start the API server:")
    print("  uvicorn app.main:app --reload")
    print("=" * 60)


if __name__ == "__main__":
    main()
