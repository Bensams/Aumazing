"""
training/train_model.py
Training pipeline for the Aumazing Pre-Assessment multi-output ordinal
classifier (Path B per-area design).

Trains FOUR XGBoost classifiers — one per developmental skill area —
wrapped in a sklearn MultiOutputClassifier. Each classifier predicts
an ordinal level in {0=Needs Support, 1=Emerging, 2=Strength}.

This script:
    1. Loads the dataset (12 features + 4 ordinal targets)
    2. Performs 5-fold cross-validation
    3. Reports per-area accuracy, macro-F1, and confusion matrices
    4. Reports overall exact-match accuracy (all 4 areas correct)
    5. Trains a final MultiOutputClassifier on the full dataset
    6. Saves the bundled model + feature names + level/target name maps

Usage (from ai_assessment/ directory):
    python training/train_model.py
    python training/train_model.py --data training/custom_data.csv
"""

import argparse
import json
import sys
from pathlib import Path

import joblib
import numpy as np
import pandas as pd
from sklearn.metrics import (
    accuracy_score,
    classification_report,
    confusion_matrix,
    f1_score,
)
from sklearn.model_selection import KFold
from sklearn.multioutput import MultiOutputClassifier
from xgboost import XGBClassifier

# ──────────────────────────────────────────────────────────────────────
# Paths (relative to project root = ai_assessment/)
# ──────────────────────────────────────────────────────────────────────
PROJECT_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_DATA_PATH = PROJECT_ROOT / "training" / "sample_preassessment_data.csv"
MODELS_DIR = PROJECT_ROOT / "models"
MODEL_OUTPUT = MODELS_DIR / "xgboost_multi_output.pkl"
FEATURES_OUTPUT = MODELS_DIR / "feature_names.json"
LEVEL_NAMES_OUTPUT = MODELS_DIR / "level_names.json"
TARGET_NAMES_OUTPUT = MODELS_DIR / "target_names.json"

TARGET_COLUMNS = [
    "communication_level",
    "social_level",
    "play_level",
    "attention_level",
]

LEVEL_NAMES = {0: "Needs Support", 1: "Emerging", 2: "Strength"}


def parse_args():
    parser = argparse.ArgumentParser(
        description=(
            "Train the Aumazing Pre-Assessment multi-output ordinal classifier."
        )
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


def _build_estimator(num_class: int) -> MultiOutputClassifier:
    """Construct a fresh MultiOutputClassifier wrapping XGBClassifier."""
    base = XGBClassifier(
        n_estimators=200,
        max_depth=4,
        learning_rate=0.1,
        objective="multi:softprob",
        num_class=num_class,
        random_state=42,
        eval_metric="mlogloss",
    )
    return MultiOutputClassifier(base)


def _print_confusion_matrix(cm: np.ndarray, area_name: str) -> None:
    print(f"\n  Confusion matrix — {area_name} (rows=true, cols=pred):")
    header = f"    {'':>15s}"
    for i in range(cm.shape[1]):
        header += f"{LEVEL_NAMES[i][:13]:>15s}"
    print(header)
    for i, row in enumerate(cm):
        line = f"    {LEVEL_NAMES[i][:13]:>15s}"
        for val in row:
            line += f"{val:>15d}"
        print(line)


def main():
    args = parse_args()

    if args.data is not None:
        data_path = Path(args.data)
        if not data_path.is_absolute():
            data_path = Path.cwd() / data_path
    else:
        data_path = DEFAULT_DATA_PATH

    MODELS_DIR.mkdir(parents=True, exist_ok=True)

    # ── 1. Load dataset ────────────────────────────────────────
    print("=" * 60)
    print("Aumazing Pre-Assessment — Multi-Output Ordinal Training")
    print("=" * 60)

    if not data_path.exists():
        print(f"ERROR: Dataset not found at {data_path}")
        sys.exit(1)

    df = pd.read_csv(data_path)
    print(f"\nLoaded dataset: {df.shape[0]} rows, {df.shape[1]} columns")
    print(f"Source: {data_path}")

    # Validate target columns exist
    missing = [c for c in TARGET_COLUMNS if c not in df.columns]
    if missing:
        print(
            f"ERROR: Target columns missing from dataset: {missing}. "
            "Regenerate with `python training/generate_training_data.py`."
        )
        sys.exit(1)

    feature_cols = [c for c in df.columns if c not in TARGET_COLUMNS]
    X = df[feature_cols].values
    Y = df[TARGET_COLUMNS].values  # shape: (n_samples, 4)
    num_class = 3  # ordinal levels: 0, 1, 2

    print(f"\nFeature columns ({len(feature_cols)}):")
    for col in feature_cols:
        print(f"  - {col}")

    print(f"\nTarget columns ({len(TARGET_COLUMNS)}):")
    for col in TARGET_COLUMNS:
        print(f"  - {col}")
    print()

    # ── 2. 5-fold cross-validation ───────────────────────────────
    print("-" * 60)
    print("5-Fold Cross-Validation")
    print("-" * 60)

    kf = KFold(n_splits=5, shuffle=True, random_state=42)

    # Per-area, per-fold metrics
    fold_accs = {area: [] for area in TARGET_COLUMNS}
    fold_f1s = {area: [] for area in TARGET_COLUMNS}
    fold_exact_match = []

    # Collect predictions across folds for full reports
    Y_cv_pred = np.zeros_like(Y)

    for fold_idx, (train_idx, val_idx) in enumerate(kf.split(X), start=1):
        X_train, X_val = X[train_idx], X[val_idx]
        Y_train, Y_val = Y[train_idx], Y[val_idx]

        model = _build_estimator(num_class)
        model.fit(X_train, Y_train)
        Y_val_pred = model.predict(X_val)
        Y_cv_pred[val_idx] = Y_val_pred

        # Per-area metrics for this fold
        per_area_acc = []
        for ai, area in enumerate(TARGET_COLUMNS):
            acc = accuracy_score(Y_val[:, ai], Y_val_pred[:, ai])
            f1 = f1_score(
                Y_val[:, ai], Y_val_pred[:, ai],
                average="macro", zero_division=0,
            )
            fold_accs[area].append(acc)
            fold_f1s[area].append(f1)
            per_area_acc.append(f"{area.split('_')[0]}={acc:.3f}")

        # Exact-match: all 4 areas predicted correctly
        exact_match = np.mean(np.all(Y_val == Y_val_pred, axis=1))
        fold_exact_match.append(exact_match)

        print(
            f"  Fold {fold_idx}: exact-match={exact_match:.4f}  "
            f"({', '.join(per_area_acc)})  "
            f"(train={len(train_idx)}, val={len(val_idx)})"
        )

    # ── 3. Aggregate CV metrics ─────────────────────────────────
    print("\n" + "-" * 60)
    print("Cross-Validation Summary (5 folds)")
    print("-" * 60)

    print(
        f"\n  Exact-match accuracy (all 4 areas correct): "
        f"{np.mean(fold_exact_match):.4f} (+/- {np.std(fold_exact_match):.4f})"
    )

    print("\n  Per-area metrics (mean over folds):")
    print(f"    {'Area':<22s} {'Accuracy':>14s} {'Macro-F1':>14s}")
    for area in TARGET_COLUMNS:
        ma = np.mean(fold_accs[area])
        sa = np.std(fold_accs[area])
        mf = np.mean(fold_f1s[area])
        sf = np.std(fold_f1s[area])
        print(
            f"    {area:<22s} {ma:.4f} \u00b1 {sa:.3f}  "
            f"{mf:.4f} \u00b1 {sf:.3f}"
        )

    # ── 4. Per-area classification reports + confusion matrices ────────
    print("\n" + "-" * 60)
    print("Per-Area Classification Reports (cross-validated)")
    print("-" * 60)

    target_names = [LEVEL_NAMES[i] for i in (0, 1, 2)]
    for ai, area in enumerate(TARGET_COLUMNS):
        print(f"\n[{area}]")
        print(
            classification_report(
                Y[:, ai], Y_cv_pred[:, ai],
                labels=[0, 1, 2],
                target_names=target_names,
                zero_division=0,
            )
        )
        cm = confusion_matrix(Y[:, ai], Y_cv_pred[:, ai], labels=[0, 1, 2])
        _print_confusion_matrix(cm, area)

    # ── 5. Train final model on full dataset ───────────────────────
    print("\n" + "-" * 60)
    print("Training final MultiOutputClassifier on full dataset...")
    print("-" * 60)

    final_model = _build_estimator(num_class)
    final_model.fit(X, Y)
    print("Training complete.")

    # ── 6. Feature importance per area ────────────────────────────
    print("\nTop feature importances per area:")
    for ai, area in enumerate(TARGET_COLUMNS):
        sub_estimator = final_model.estimators_[ai]
        importances = sub_estimator.feature_importances_
        ranked = sorted(
            zip(feature_cols, importances),
            key=lambda x: x[1],
            reverse=True,
        )
        print(f"\n  [{area}]")
        for fname, imp in ranked[:5]:
            bar = "#" * int(imp * 50)
            print(f"    {fname:<40s} {imp:.4f}  {bar}")

    # ── 7. Save artifacts ─────────────────────────────────────
    joblib.dump(final_model, MODEL_OUTPUT)
    print(f"\nModel saved to:          {MODEL_OUTPUT}")

    with open(FEATURES_OUTPUT, "w") as f:
        json.dump(feature_cols, f, indent=2)
    print(f"Feature names saved to:  {FEATURES_OUTPUT}")

    with open(LEVEL_NAMES_OUTPUT, "w") as f:
        # JSON keys must be strings
        json.dump({str(k): v for k, v in LEVEL_NAMES.items()}, f, indent=2)
    print(f"Level names saved to:    {LEVEL_NAMES_OUTPUT}")

    with open(TARGET_NAMES_OUTPUT, "w") as f:
        json.dump(TARGET_COLUMNS, f, indent=2)
    print(f"Target names saved to:   {TARGET_NAMES_OUTPUT}")

    print("\n" + "=" * 60)
    print("Training pipeline complete. Next: update model_loader / API.")
    print("=" * 60)


if __name__ == "__main__":
    main()
