"""
training/generate_calibrated_data.py
Synthetic training data calibrated on real pre-/post-assessment runs.

Why this exists (pre-final defense note): the original generator,
``generate_training_data.py``, draws every feature independently from a
fixed uniform range. Real children do not produce data like that — a child
who needs more hints also tends to answer more slowly and idle longer — and
the panel asked that synthetic data be based on the existing assessment
results instead.

Method — a Gaussian copula with blended marginals:

1. **Real runs.** ``real_runs_features.csv`` holds the 12 model features for
   every real assessment run in the live database, computed exactly as the
   app computes them (``on_device_feature_aggregator.dart``), de-identified
   and de-duplicated.

2. **Dependence (copula).** The rank correlation between features is
   estimated from the real runs, then shrunk toward independence because the
   sample is small (``lambda = n / (n + SHRINK_K)``). Features with no
   variation in the real runs contribute no correlation.

3. **Marginals.** Each feature's distribution is a blend of
   (a) the real runs, smoothed with a Gaussian kernel, and
   (b) the rubric-spanning prior range the original generator used.
   The real runs are mostly strong performers, so (b) is what keeps
   "Needs Support" and "Emerging" children in the data at all. The blend
   weight is ``--real-weight`` (default 0.5).

4. **Definitional features are derived, not sampled.** ``overall_accuracy``
   is the mean of the four per-game accuracies (one session per game), and
   ``overall_task_completion_rate`` is the share of games not abandoned, as
   in the app.

5. **Labels** come from the same rubric as before (``derive_labels``). There
   are no expert labels for the real runs, so this calibrates the *features*
   to reality; it does not make the *labels* clinical. That limitation is
   stated in ``REAL_DATA_EVALUATION.md``.

Usage (from ai_assessment/):
    python training/generate_calibrated_data.py
    python training/generate_calibrated_data.py --samples 1200 --real-weight 0.6
"""

from __future__ import annotations

import argparse
import csv
from pathlib import Path

import numpy as np
from scipy import stats

from generate_training_data import (
    FEATURE_COLUMNS,
    TARGET_COLUMNS,
    derive_labels,
)

TRAINING_DIR = Path(__file__).resolve().parent
REAL_RUNS_PATH = TRAINING_DIR / "real_runs_features.csv"
DEFAULT_OUTPUT = TRAINING_DIR / "calibrated_preassessment_data.csv"

# Prior range per sampled feature: the range the original generator spanned,
# widened where a real run fell outside it (response time up to 13.7 s,
# idle time up to 40 s), so the prior never excludes an observed child.
PRIOR_RANGE: dict[str, tuple[float, float]] = {
    "copy_me_accuracy": (0.05, 1.0),
    "match_it_accuracy": (0.05, 1.0),
    "my_turn_your_turn_accuracy": (0.05, 1.0),
    "do_what_i_say_accuracy": (0.05, 1.0),
    "overall_avg_response_time": (1.5, 15.0),
    "overall_retry_count": (0.0, 8.0),
    "overall_hint_count": (0.0, 14.0),
    "overall_prompt_dependency_score": (0.0, 0.95),
    "overall_idle_time_seconds": (0.0, 50.0),
    "overall_invalid_touch_count": (0.0, 20.0),
}

SAMPLED_FEATURES = list(PRIOR_RANGE)
GAME_ACCURACIES = [
    "copy_me_accuracy",
    "match_it_accuracy",
    "my_turn_your_turn_accuracy",
    "do_what_i_say_accuracy",
]

# Shrinkage strength: with n real runs the correlation estimate keeps
# n / (n + SHRINK_K) of its value. 10 keeps a bit over half at n = 13.
SHRINK_K = 10.0

# A game counts as abandoned below this accuracy when deriving completion.
ABANDON_ACCURACY = 0.15


def load_real_runs(path: Path = REAL_RUNS_PATH) -> dict[str, np.ndarray]:
    """Feature columns of the real runs as float arrays."""
    with open(path, newline="", encoding="utf-8") as fh:
        rows = list(csv.DictReader(fh))
    if not rows:
        raise ValueError(f"no real runs in {path}")
    return {f: np.array([float(r[f]) for r in rows]) for f in FEATURE_COLUMNS}


def _normal_scores(values: np.ndarray) -> np.ndarray:
    """Rank-based normal scores (van der Waerden)."""
    ranks = stats.rankdata(values)
    return stats.norm.ppf((ranks - 0.5) / len(values))


def estimate_correlation(real: dict[str, np.ndarray]) -> np.ndarray:
    """Shrunk normal-scores correlation between the sampled features."""
    n = len(next(iter(real.values())))
    k = len(SAMPLED_FEATURES)
    scores = np.zeros((n, k))
    varying = np.zeros(k, dtype=bool)
    for j, feature in enumerate(SAMPLED_FEATURES):
        column = real[feature]
        if np.ptp(column) > 0:
            scores[:, j] = _normal_scores(column)
            varying[j] = True

    corr = np.eye(k)
    idx = np.flatnonzero(varying)
    if len(idx) >= 2:
        sub = np.corrcoef(scores[:, idx], rowvar=False)
        corr[np.ix_(idx, idx)] = np.nan_to_num(sub)
        np.fill_diagonal(corr, 1.0)

    lam = n / (n + SHRINK_K)
    shrunk = lam * corr + (1.0 - lam) * np.eye(k)
    # Guard against a numerically indefinite matrix from a tiny sample.
    eigval, eigvec = np.linalg.eigh(shrunk)
    eigval = np.clip(eigval, 1e-6, None)
    fixed = eigvec @ np.diag(eigval) @ eigvec.T
    d = np.sqrt(np.diag(fixed))
    return fixed / np.outer(d, d)


def marginal_reference(
    feature: str,
    real_values: np.ndarray,
    real_weight: float,
    rng: np.random.Generator,
    size: int = 20000,
) -> np.ndarray:
    """A large sorted sample of the blended marginal, used for quantiles."""
    lo, hi = PRIOR_RANGE[feature]
    n_real = int(round(size * real_weight))
    # Kernel-smoothed real component. Silverman bandwidth, floored at 3% of
    # the prior range so identical real values still spread a little.
    sd = np.std(real_values)
    bw = max(1.06 * sd * len(real_values) ** (-1 / 5), 0.03 * (hi - lo))
    real_part = rng.choice(real_values, n_real) + rng.normal(0, bw, n_real)
    prior_part = rng.uniform(lo, hi, size - n_real)
    return np.sort(np.clip(np.concatenate([real_part, prior_part]), lo, hi))


def generate(
    n_samples: int,
    real: dict[str, np.ndarray],
    real_weight: float = 0.5,
    seed: int = 42,
) -> list[dict]:
    """Rows of the 12 features plus the 4 rubric labels."""
    rng = np.random.default_rng(seed)
    corr = estimate_correlation(real)
    references = {
        f: marginal_reference(f, real[f], real_weight, rng)
        for f in SAMPLED_FEATURES
    }

    z = rng.multivariate_normal(np.zeros(len(SAMPLED_FEATURES)), corr, n_samples)
    u = stats.norm.cdf(z)

    rows = []
    for i in range(n_samples):
        row: dict = {}
        for j, feature in enumerate(SAMPLED_FEATURES):
            ref = references[feature]
            row[feature] = float(ref[min(int(u[i, j] * len(ref)), len(ref) - 1)])

        games = [row[g] for g in GAME_ACCURACIES]
        row["overall_accuracy"] = float(np.mean(games))
        abandoned = sum(1 for g in games if g < ABANDON_ACCURACY)
        row["overall_task_completion_rate"] = 1.0 - abandoned / len(games)

        for feature in FEATURE_COLUMNS:
            row[feature] = round(row[feature], 4)
        derive_labels(row)
        rows.append(row)
    return rows


def write_csv(rows: list[dict], path: Path) -> None:
    columns = FEATURE_COLUMNS + TARGET_COLUMNS
    with open(path, "w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(fh, fieldnames=columns)
        writer.writeheader()
        for row in rows:
            writer.writerow({c: row[c] for c in columns})


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--samples", type=int, default=1000)
    ap.add_argument("--real-weight", type=float, default=0.5,
                    help="share of each marginal drawn from the real runs")
    ap.add_argument("--seed", type=int, default=42)
    ap.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = ap.parse_args()

    real = load_real_runs()
    rows = generate(args.samples, real, args.real_weight, args.seed)
    write_csv(rows, args.output)

    n_real = len(real[FEATURE_COLUMNS[0]])
    print(f"Calibrated on {n_real} real runs; wrote {len(rows)} rows to "
          f"{args.output}")
    for target in TARGET_COLUMNS:
        counts = np.bincount([r[target] for r in rows], minlength=3)
        print(f"  {target:<22} NS={counts[0]:4d}  EM={counts[1]:4d}  "
              f"ST={counts[2]:4d}")


if __name__ == "__main__":
    main()
