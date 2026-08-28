"""
training/generate_training_data.py
Generates synthetic pre-assessment training data for the Aumazing
multi-output ordinal classifier (Path B per-area design).

Each row represents aggregated game-session metrics for one child,
labelled with FOUR ordinal targets (one per developmental skill area):

    - communication_level   (0=Needs Support, 1=Emerging, 2=Strength)
    - social_level          (0=Needs Support, 1=Emerging, 2=Strength)
    - play_level            (0=Needs Support, 1=Emerging, 2=Strength)
    - attention_level       (0=Needs Support, 1=Emerging, 2=Strength)

Labels are *derived* from the 12 input features by applying the
validator labeling rubric (see training/LABELING_RUBRIC.md). The
dataset, the rubric, and the training labels are all produced from
the same single source of truth — a defensible methodology choice
for capstone validation.

Sampling strategy:
  - Each per-game accuracy is drawn uniformly from [0.05, 0.95] to
    give broad coverage of all three ordinal levels.
  - Attention markers (idle time, invalid touches, response time,
    prompt dependency) are sampled from realistic ranges spanning
    both elevated and non-elevated values, INDEPENDENTLY of accuracy
    so the attention label is not a tautology of the others.
  - Aggregate features (retry/hint counts, task completion) are
    loosely correlated with accuracy + noise to remain realistic.
  - Labels are then derived deterministically by `derive_labels()`.

Usage (from ai_assessment/ directory):
    python training/generate_training_data.py
    python training/generate_training_data.py --samples 800 --output training/custom_data.csv
"""

import argparse
import csv
import random
from pathlib import Path

# ──────────────────────────────────────────────────────────────────────
# Labeling rubric constants — MUST match training/LABELING_RUBRIC.md
# and the validator-facing rubric in the manuscript Appendix.
# ──────────────────────────────────────────────────────────────────────

# Accuracy thresholds (apply to communication, social, play areas)
ACC_STRENGTH_MIN = 0.70   # >= -> Strength
ACC_EMERGING_MIN = 0.40   # >= -> Emerging, < -> Needs Support

# Attention "elevated marker" thresholds
ATTN_IDLE_THRESHOLD = 15.0           # idle_seconds > 15 is elevated
ATTN_INVALID_TOUCH_THRESHOLD = 6     # invalid_touch_count > 6 is elevated
ATTN_RESPONSE_TIME_THRESHOLD = 5.0   # avg_response_time > 5.0 sec is elevated
ATTN_PROMPT_DEP_THRESHOLD = 0.50     # prompt_dependency > 0.50 is elevated

# Attention level by number of elevated markers (out of 4):
#   0-1 elevated -> Strength
#   2 elevated   -> Emerging
#   3-4 elevated -> Needs Support
ATTN_NEEDS_SUPPORT_MIN_MARKERS = 3
ATTN_EMERGING_MIN_MARKERS = 2

# Ordinal level integer encoding
LEVEL_NEEDS_SUPPORT = 0
LEVEL_EMERGING = 1
LEVEL_STRENGTH = 2

# ──────────────────────────────────────────────────────────────────────
# Feature & target columns
# ──────────────────────────────────────────────────────────────────────

FEATURE_COLUMNS = [
    "overall_accuracy",
    "overall_avg_response_time",
    "overall_task_completion_rate",
    "overall_retry_count",
    "overall_hint_count",
    "overall_prompt_dependency_score",
    "overall_idle_time_seconds",
    "overall_invalid_touch_count",
    "copy_me_accuracy",
    "match_it_accuracy",
    "my_turn_your_turn_accuracy",
    "do_what_i_say_accuracy",
]

TARGET_COLUMNS = [
    "communication_level",
    "social_level",
    "play_level",
    "attention_level",
]

INTEGER_FEATURES = {
    "overall_retry_count",
    "overall_hint_count",
    "overall_idle_time_seconds",
    "overall_invalid_touch_count",
}


# ──────────────────────────────────────────────────────────────────────
# Helpers
# ──────────────────────────────────────────────────────────────────────

def _clamp(value: float, lo: float, hi: float) -> float:
    """Clamp a value between lo and hi."""
    return max(lo, min(hi, value))


def _accuracy_to_level(accuracy: float) -> int:
    """Map a single accuracy value to an ordinal level using rubric thresholds."""
    if accuracy >= ACC_STRENGTH_MIN:
        return LEVEL_STRENGTH
    if accuracy >= ACC_EMERGING_MIN:
        return LEVEL_EMERGING
    return LEVEL_NEEDS_SUPPORT


def derive_labels(row: dict) -> dict:
    """
    Apply the validator rubric to derive the 4 ordinal labels from features.

    THIS IS THE SINGLE SOURCE OF TRUTH for labeling. The same logic
    (with the same thresholds) is documented in LABELING_RUBRIC.md and
    given to validator SMEs to label held-out rows for content validation.

    Mutates ``row`` in place and returns it.
    """
    # Communication: mean of copy_me + do_what_i_say
    comm_mean = (row["copy_me_accuracy"] + row["do_what_i_say_accuracy"]) / 2.0
    row["communication_level"] = _accuracy_to_level(comm_mean)

    # Social: my_turn_your_turn accuracy directly
    row["social_level"] = _accuracy_to_level(row["my_turn_your_turn_accuracy"])

    # Play: match_it accuracy directly
    row["play_level"] = _accuracy_to_level(row["match_it_accuracy"])

    # Attention: count elevated markers
    elevated = (
        (row["overall_idle_time_seconds"] > ATTN_IDLE_THRESHOLD)
        + (row["overall_invalid_touch_count"] > ATTN_INVALID_TOUCH_THRESHOLD)
        + (row["overall_avg_response_time"] > ATTN_RESPONSE_TIME_THRESHOLD)
        + (row["overall_prompt_dependency_score"] > ATTN_PROMPT_DEP_THRESHOLD)
    )
    if elevated >= ATTN_NEEDS_SUPPORT_MIN_MARKERS:
        row["attention_level"] = LEVEL_NEEDS_SUPPORT
    elif elevated >= ATTN_EMERGING_MIN_MARKERS:
        row["attention_level"] = LEVEL_EMERGING
    else:
        row["attention_level"] = LEVEL_STRENGTH

    return row


# ──────────────────────────────────────────────────────────────────────
# Feature sampling
# ──────────────────────────────────────────────────────────────────────

def generate_features(rng: random.Random) -> dict:
    """
    Sample a single row of input features from realistic ranges.

    Game accuracies are independent uniform draws so all 81 possible
    (comm × social × play × attention) level combinations are reachable.
    Aggregate features are loosely correlated with accuracy to remain
    realistic without leaking the labels deterministically.
    """
    # Per-game accuracies (independent uniform across full range)
    copy_me = round(rng.uniform(0.05, 0.95), 4)
    match_it = round(rng.uniform(0.05, 0.95), 4)
    mttytt = round(rng.uniform(0.05, 0.95), 4)
    dwis = round(rng.uniform(0.05, 0.95), 4)

    # Overall accuracy ≈ mean of the 4 games + small jitter (clamped)
    avg_acc = (copy_me + match_it + mttytt + dwis) / 4.0
    overall_acc = round(_clamp(avg_acc + rng.uniform(-0.05, 0.05), 0.0, 1.0), 4)

    # Task completion correlates with accuracy
    task_compl = round(_clamp(avg_acc + rng.uniform(-0.10, 0.15), 0.0, 1.0), 4)

    # Attention markers — sampled INDEPENDENTLY of accuracy so that the
    # attention label is not just a re-statement of the accuracy labels.
    idle = int(round(rng.uniform(0.0, 50.0)))
    invalid_touch = int(round(rng.uniform(0.0, 20.0)))
    response_time = round(rng.uniform(1.5, 12.0), 4)
    prompt_dep = round(rng.uniform(0.0, 0.95), 4)

    # Retry/hint counts loosely correlate with low accuracy
    difficulty = 1.0 - avg_acc  # 0 (easy) → 1 (hard)
    retry = int(round(rng.uniform(0.0, 8.0) * (0.4 + 0.6 * difficulty)))
    hint = int(round(rng.uniform(0.0, 14.0) * (0.4 + 0.6 * difficulty)))

    return {
        "overall_accuracy": overall_acc,
        "overall_avg_response_time": response_time,
        "overall_task_completion_rate": task_compl,
        "overall_retry_count": retry,
        "overall_hint_count": hint,
        "overall_prompt_dependency_score": prompt_dep,
        "overall_idle_time_seconds": idle,
        "overall_invalid_touch_count": invalid_touch,
        "copy_me_accuracy": copy_me,
        "match_it_accuracy": match_it,
        "my_turn_your_turn_accuracy": mttytt,
        "do_what_i_say_accuracy": dwis,
    }


# ──────────────────────────────────────────────────────────────────────
# Dataset assembly
# ──────────────────────────────────────────────────────────────────────

def generate_dataset(n_samples: int, seed: int = 42) -> list[dict]:
    """Generate ``n_samples`` rows of features + derived labels."""
    rng = random.Random(seed)
    rows = []
    for _ in range(n_samples):
        row = generate_features(rng)
        derive_labels(row)
        rows.append(row)
    return rows


def write_csv(rows: list[dict], output_path: Path) -> None:
    """Write features + 4 ordinal targets to a CSV file."""
    columns = FEATURE_COLUMNS + TARGET_COLUMNS
    with open(output_path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=columns)
        writer.writeheader()
        writer.writerows(rows)


def print_summary(rows: list[dict]) -> None:
    """Print per-area level distributions and joint coverage stats."""
    level_names = {0: "Needs Support", 1: "Emerging", 2: "Strength"}

    print("\n" + "=" * 60)
    print("Dataset Generation Summary (Path B — per-area ordinal labels)")
    print("=" * 60)
    print(f"Total samples: {len(rows)}")
    print(f"Features:      {len(FEATURE_COLUMNS)}")
    print(f"Targets:       {len(TARGET_COLUMNS)}")

    print("\nPer-area level distribution:")
    for area in TARGET_COLUMNS:
        counts = {0: 0, 1: 0, 2: 0}
        for row in rows:
            counts[row[area]] += 1
        print(f"\n  {area}:")
        for level_int, name in level_names.items():
            count = counts[level_int]
            pct = count / len(rows) * 100
            print(f"    {level_int} {name:<15s} {count:>5d}  ({pct:5.1f}%)")

    # Joint coverage: distinct (comm, social, play, attn) tuples
    unique_combos = {
        (
            r["communication_level"],
            r["social_level"],
            r["play_level"],
            r["attention_level"],
        )
        for r in rows
    }
    print(f"\nUnique level combinations covered: {len(unique_combos)} / 81")

    # Co-occurring weakness coverage
    multi_ns = sum(
        1 for r in rows
        if sum(r[a] == 0 for a in TARGET_COLUMNS) >= 2
    )
    print(
        f"Rows with >= 2 areas at Needs Support: {multi_ns} "
        f"({multi_ns / len(rows) * 100:.1f}%)"
    )
    print("=" * 60)


# ──────────────────────────────────────────────────────────────────────
# CLI
# ──────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description=(
            "Generate synthetic pre-assessment training data for the "
            "Aumazing per-area ordinal classifier."
        )
    )
    parser.add_argument(
        "--samples",
        type=int,
        default=800,
        help="Total number of samples to generate (default: 800)",
    )
    parser.add_argument(
        "--output",
        type=str,
        default=None,
        help=(
            "Output CSV path "
            "(default: sample_preassessment_data.csv next to this script)"
        ),
    )
    parser.add_argument(
        "--seed",
        type=int,
        default=42,
        help="Random seed for reproducibility (default: 42)",
    )
    args = parser.parse_args()

    if args.output is None:
        output_path = Path(__file__).resolve().parent / "sample_preassessment_data.csv"
    else:
        output_path = Path(args.output)
        if not output_path.is_absolute():
            output_path = Path.cwd() / output_path

    rows = generate_dataset(args.samples, seed=args.seed)
    write_csv(rows, output_path)
    print(f"Dataset written to: {output_path}")
    print_summary(rows)


if __name__ == "__main__":
    main()
