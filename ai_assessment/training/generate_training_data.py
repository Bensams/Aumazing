"""
training/generate_training_data.py
Generates synthetic pre-assessment training data for the Aumazing XGBoost model.

Each row represents aggregated game-session metrics for one child, labelled
with one of five developmental profiles.

Usage (from ai_assessment/ directory):
    python training/generate_training_data.py
    python training/generate_training_data.py --samples-per-class 60 --output training/custom_data.csv
"""

import argparse
import csv
import os
import random
import sys
from pathlib import Path

# ──────────────────────────────────────────────────────────────────────
# Profile definitions — {feature: (low, high)}
# ──────────────────────────────────────────────────────────────────────
PROFILES = {
    "communication_support": {
        "overall_accuracy": (0.25, 0.55),
        "overall_avg_response_time": (3.0, 8.0),
        "overall_task_completion_rate": (0.3, 0.6),
        "overall_retry_count": (3, 8),
        "overall_hint_count": (5, 12),
        "overall_prompt_dependency_score": (0.4, 0.8),
        "overall_idle_time_seconds": (5, 25),
        "overall_invalid_touch_count": (2, 10),
        "copy_me_accuracy": (0.1, 0.4),
        "match_it_accuracy": (0.4, 0.8),
        "my_turn_your_turn_accuracy": (0.4, 0.7),
        "do_what_i_say_accuracy": (0.1, 0.4),
    },
    "social_support": {
        "overall_accuracy": (0.3, 0.6),
        "overall_avg_response_time": (2.0, 6.0),
        "overall_task_completion_rate": (0.4, 0.7),
        "overall_retry_count": (2, 6),
        "overall_hint_count": (3, 10),
        "overall_prompt_dependency_score": (0.3, 0.6),
        "overall_idle_time_seconds": (10, 35),
        "overall_invalid_touch_count": (3, 12),
        "copy_me_accuracy": (0.5, 0.8),
        "match_it_accuracy": (0.5, 0.8),
        "my_turn_your_turn_accuracy": (0.1, 0.35),
        "do_what_i_say_accuracy": (0.5, 0.8),
    },
    "play_support": {
        "overall_accuracy": (0.3, 0.55),
        "overall_avg_response_time": (3.0, 7.0),
        "overall_task_completion_rate": (0.35, 0.65),
        "overall_retry_count": (3, 7),
        "overall_hint_count": (4, 10),
        "overall_prompt_dependency_score": (0.3, 0.7),
        "overall_idle_time_seconds": (5, 20),
        "overall_invalid_touch_count": (2, 8),
        "copy_me_accuracy": (0.3, 0.6),
        "match_it_accuracy": (0.1, 0.35),
        "my_turn_your_turn_accuracy": (0.5, 0.8),
        "do_what_i_say_accuracy": (0.4, 0.7),
    },
    "attention_support": {
        "overall_accuracy": (0.2, 0.5),
        "overall_avg_response_time": (5.0, 12.0),
        "overall_task_completion_rate": (0.2, 0.5),
        "overall_retry_count": (4, 10),
        "overall_hint_count": (6, 15),
        "overall_prompt_dependency_score": (0.5, 0.9),
        "overall_idle_time_seconds": (20, 55),
        "overall_invalid_touch_count": (8, 20),
        "copy_me_accuracy": (0.2, 0.5),
        "match_it_accuracy": (0.2, 0.5),
        "my_turn_your_turn_accuracy": (0.3, 0.6),
        "do_what_i_say_accuracy": (0.15, 0.45),
    },
    "balanced_profile": {
        "overall_accuracy": (0.6, 0.9),
        "overall_avg_response_time": (1.5, 4.0),
        "overall_task_completion_rate": (0.7, 1.0),
        "overall_retry_count": (0, 3),
        "overall_hint_count": (0, 4),
        "overall_prompt_dependency_score": (0.0, 0.25),
        "overall_idle_time_seconds": (0, 10),
        "overall_invalid_touch_count": (0, 4),
        "copy_me_accuracy": (0.6, 0.9),
        "match_it_accuracy": (0.6, 0.9),
        "my_turn_your_turn_accuracy": (0.6, 0.9),
        "do_what_i_say_accuracy": (0.6, 0.9),
    },
}

# Features that should be integers
INTEGER_FEATURES = {
    "overall_retry_count",
    "overall_hint_count",
    "overall_idle_time_seconds",
    "overall_invalid_touch_count",
}

# Canonical feature order (must match model expectations)
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

TARGET_COLUMN = "developmental_profile"

# Noise factor: 10% of samples get values slightly outside their range
NOISE_FRACTION = 0.10
NOISE_SCALE = 0.15  # how far outside the range noisy values can drift


def _clamp(value: float, lo: float, hi: float) -> float:
    """Clamp a value between lo and hi."""
    return max(lo, min(hi, value))


def generate_sample(
    profile_name: str,
    rng: random.Random,
    add_noise: bool = False,
) -> dict:
    """Generate a single sample row for the given profile."""
    ranges = PROFILES[profile_name]
    row = {}

    for feature in FEATURE_COLUMNS:
        lo, hi = ranges[feature]

        if add_noise:
            # Expand the range by NOISE_SCALE in both directions
            span = hi - lo
            lo_noisy = lo - span * NOISE_SCALE
            hi_noisy = hi + span * NOISE_SCALE
            value = rng.uniform(lo_noisy, hi_noisy)
        else:
            value = rng.uniform(lo, hi)

        # Clamp probabilities/rates to [0, 1]
        if feature in (
            "overall_accuracy",
            "overall_task_completion_rate",
            "overall_prompt_dependency_score",
            "copy_me_accuracy",
            "match_it_accuracy",
            "my_turn_your_turn_accuracy",
            "do_what_i_say_accuracy",
        ):
            value = _clamp(value, 0.0, 1.0)

        # Clamp counts/times to >= 0
        if feature in INTEGER_FEATURES or feature == "overall_avg_response_time":
            value = max(0.0, value)

        # Round integers
        if feature in INTEGER_FEATURES:
            value = int(round(value))
        else:
            value = round(value, 4)

        row[feature] = value

    row[TARGET_COLUMN] = profile_name
    return row


def generate_dataset(samples_per_class: int, seed: int = 42) -> list[dict]:
    """Generate the full dataset with all profiles."""
    rng = random.Random(seed)
    rows = []

    for profile_name in PROFILES:
        n_noisy = int(samples_per_class * NOISE_FRACTION)
        n_clean = samples_per_class - n_noisy

        # Generate clean samples
        for _ in range(n_clean):
            rows.append(generate_sample(profile_name, rng, add_noise=False))

        # Generate noisy samples (slight overlap with other classes)
        for _ in range(n_noisy):
            rows.append(generate_sample(profile_name, rng, add_noise=True))

    # Shuffle the dataset (deterministically)
    rng.shuffle(rows)
    return rows


def write_csv(rows: list[dict], output_path: str) -> None:
    """Write the dataset to a CSV file."""
    columns = FEATURE_COLUMNS + [TARGET_COLUMN]
    with open(output_path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=columns)
        writer.writeheader()
        writer.writerows(rows)


def print_summary(rows: list[dict]) -> None:
    """Print class distribution summary."""
    counts: dict[str, int] = {}
    for row in rows:
        label = row[TARGET_COLUMN]
        counts[label] = counts.get(label, 0) + 1

    print("\n" + "=" * 50)
    print("Dataset Generation Summary")
    print("=" * 50)
    print(f"Total samples: {len(rows)}")
    print(f"Features:      {len(FEATURE_COLUMNS)}")
    print(f"\nClass distribution:")
    for label in PROFILES:
        count = counts.get(label, 0)
        pct = count / len(rows) * 100
        print(f"  {label:<30s} {count:>4d}  ({pct:.1f}%)")
    print("=" * 50)


def main():
    parser = argparse.ArgumentParser(
        description="Generate synthetic pre-assessment training data for Aumazing."
    )
    parser.add_argument(
        "--samples-per-class",
        type=int,
        default=40,
        help="Number of samples per developmental profile (default: 40)",
    )
    parser.add_argument(
        "--output",
        type=str,
        default=None,
        help="Output CSV path (default: sample_preassessment_data.csv in same directory)",
    )
    parser.add_argument(
        "--seed",
        type=int,
        default=42,
        help="Random seed for reproducibility (default: 42)",
    )
    args = parser.parse_args()

    # Resolve output path
    if args.output is None:
        output_path = Path(__file__).resolve().parent / "sample_preassessment_data.csv"
    else:
        output_path = Path(args.output)
        if not output_path.is_absolute():
            output_path = Path.cwd() / output_path

    # Generate
    rows = generate_dataset(args.samples_per_class, seed=args.seed)

    # Write
    write_csv(rows, str(output_path))
    print(f"Dataset written to: {output_path}")

    # Summary
    print_summary(rows)


if __name__ == "__main__":
    main()
