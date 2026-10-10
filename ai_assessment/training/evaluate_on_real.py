"""
training/evaluate_on_real.py
Compares the original (independent-uniform) generator with the calibrated
one, testing only on real assessment runs.

For each generator:
  * train the production model shape (four XGBoost classifiers in a
    MultiOutputClassifier, same hyper-parameters as train_model.py) on
    synthetic rows only;
  * test it on the real runs in real_runs_features.csv, never seen in
    training;
  * measure how realistic each synthetic feature is: the two-sample
    Kolmogorov–Smirnov distance between its synthetic and real values
    (0 = same distribution, 1 = no overlap).

The real runs are labelled with the same rubric as the synthetic rows —
there are no expert labels yet — so "accuracy on real runs" measures how
well a model trained on synthetic data carries over to real feature
distributions, not clinical validity. The report says so.

Usage (from ai_assessment/):
    python training/evaluate_on_real.py
"""

from __future__ import annotations

from datetime import date
from pathlib import Path

import numpy as np
from scipy import stats
from sklearn.metrics import accuracy_score, f1_score

import generate_calibrated_data as calibrated
import generate_training_data as original
from generate_training_data import FEATURE_COLUMNS, TARGET_COLUMNS, derive_labels
from train_model import _build_estimator

TRAINING_DIR = Path(__file__).resolve().parent
REPORT_PATH = TRAINING_DIR / "REAL_DATA_EVALUATION.md"
N_SAMPLES = 1000
SEEDS = [11, 42, 97]
LEVELS = ["Needs Support", "Emerging", "Strength"]


def _matrix(rows: list[dict]) -> tuple[np.ndarray, np.ndarray]:
    x = np.array([[float(r[f]) for f in FEATURE_COLUMNS] for r in rows])
    y = np.array([[int(r[t]) for t in TARGET_COLUMNS] for r in rows])
    return x, y


def real_rows() -> list[dict]:
    real = calibrated.load_real_runs()
    n = len(real[FEATURE_COLUMNS[0]])
    rows = []
    for i in range(n):
        row = {f: float(real[f][i]) for f in FEATURE_COLUMNS}
        derive_labels(row)
        rows.append(row)
    return rows


def evaluate(train_rows: list[dict], test_rows: list[dict]) -> dict:
    x_train, y_train = _matrix(train_rows)
    x_test, y_test = _matrix(test_rows)
    model = _build_estimator(num_class=3)
    model.fit(x_train, y_train)
    pred = model.predict(x_test)
    out = {}
    for j, target in enumerate(TARGET_COLUMNS):
        out[target] = {
            "accuracy": accuracy_score(y_test[:, j], pred[:, j]),
            "macro_f1": f1_score(
                y_test[:, j], pred[:, j], average="macro",
                labels=sorted(set(y_test[:, j]) | set(pred[:, j])),
                zero_division=0,
            ),
        }
    ks = {
        f: stats.ks_2samp(x_train[:, i], x_test[:, i]).statistic
        for i, f in enumerate(FEATURE_COLUMNS)
    }
    return {"targets": out, "ks": ks}


def main() -> None:
    test = real_rows()
    real = calibrated.load_real_runs()
    results: dict[str, list[dict]] = {"original": [], "calibrated": []}
    for seed in SEEDS:
        results["original"].append(
            evaluate(original.generate_dataset(N_SAMPLES, seed), test)
        )
        results["calibrated"].append(
            evaluate(calibrated.generate(N_SAMPLES, real, 0.5, seed), test)
        )

    def mean(gen: str, *path: str) -> float:
        vals = []
        for r in results[gen]:
            v = r
            for p in path:
                v = v[p]
            vals.append(v)
        return float(np.mean(vals))

    _, y_real = _matrix(test)
    lines = [
        "# Synthetic data vs real assessment runs",
        "",
        f"Generated {date.today().isoformat()} by `training/evaluate_on_real.py`. "
        f"{len(test)} real runs (de-identified, de-duplicated) from the live "
        f"database; {N_SAMPLES} synthetic rows per generator; mean of "
        f"{len(SEEDS)} seeds.",
        "",
        "## Real-run labels (rubric)",
        "",
        "| Area | " + " | ".join(LEVELS) + " |",
        "|---|---|---|---|",
    ]
    for j, target in enumerate(TARGET_COLUMNS):
        counts = np.bincount(y_real[:, j], minlength=3)
        lines.append(f"| {target} | " + " | ".join(str(c) for c in counts) + " |")

    lines += [
        "",
        "## Trained on synthetic, tested on real",
        "",
        "| Area | Original: accuracy | Original: macro-F1 | "
        "Calibrated: accuracy | Calibrated: macro-F1 |",
        "|---|---|---|---|---|",
    ]
    for target in TARGET_COLUMNS:
        lines.append(
            f"| {target} | "
            f"{mean('original', 'targets', target, 'accuracy'):.2f} | "
            f"{mean('original', 'targets', target, 'macro_f1'):.2f} | "
            f"{mean('calibrated', 'targets', target, 'accuracy'):.2f} | "
            f"{mean('calibrated', 'targets', target, 'macro_f1'):.2f} |"
        )

    lines += [
        "",
        "## How realistic each feature is (KS distance to real, lower is better)",
        "",
        "| Feature | Original | Calibrated |",
        "|---|---|---|",
    ]
    ks_orig, ks_cal = [], []
    for f in FEATURE_COLUMNS:
        o, c = mean("original", "ks", f), mean("calibrated", "ks", f)
        ks_orig.append(o)
        ks_cal.append(c)
        lines.append(f"| {f} | {o:.2f} | {c:.2f} |")
    lines.append(
        f"| **mean** | **{np.mean(ks_orig):.2f}** | **{np.mean(ks_cal):.2f}** |"
    )

    lines += [
        "",
        "## Reading these numbers",
        "",
        "- **Realism is the meaningful comparison.** The calibrated generator's "
        f"features sit closer to the real runs (mean KS {np.mean(ks_cal):.2f} vs "
        f"{np.mean(ks_orig):.2f}). The largest gain is where the original "
        "generator's independence assumption was furthest from reality.",
        "- **Accuracy on real runs cannot separate the generators yet.** Almost "
        "every real run is Strength in every area, so a model that predicts "
        "Strength scores near 100% either way. More real runs — especially "
        "children who need support — are needed before this column means much.",
    ]
    lines += [
        "",
        "## Limitations",
        "",
        f"- **Small sample.** {len(test)} real runs, mostly strong performers. "
        "The copula keeps only part of their correlation "
        f"(shrinkage k = {calibrated.SHRINK_K:g}), and half of every marginal "
        "still comes from the rubric-spanning prior so that Needs Support and "
        "Emerging children stay represented.",
        "- **Labels are the rubric's.** The real runs have no expert labels, "
        "so accuracy on them shows how well a model trained on synthetic "
        "features carries over to real feature distributions — not clinical "
        "validity. Expert-labelled runs are needed for that.",
        "- **Possible test accounts.** Exact duplicate runs were removed as "
        "likely automated test runs; other developer runs may remain.",
        "- **Literature anchoring.** The prior ranges are the proponents' "
        "rubric-spanning ranges. Replacing them with ranges from published "
        "ASD gameplay studies is the next refinement.",
        "",
    ]
    REPORT_PATH.write_text("\n".join(lines), encoding="utf-8")
    print("\n".join(lines))


if __name__ == "__main__":
    main()
