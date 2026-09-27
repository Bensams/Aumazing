# Synthetic data vs real assessment runs

Generated 2026-09-27 by `training/evaluate_on_real.py`. 13 real runs (de-identified, de-duplicated) from the live database; 1000 synthetic rows per generator; mean of 3 seeds.

## Real-run labels (rubric)

| Area | Needs Support | Emerging | Strength |
|---|---|---|---|
| communication_level | 0 | 1 | 12 |
| social_level | 0 | 2 | 11 |
| play_level | 0 | 1 | 12 |
| attention_level | 1 | 1 | 11 |

## Trained on synthetic, tested on real

| Area | Original: accuracy | Original: macro-F1 | Calibrated: accuracy | Calibrated: macro-F1 |
|---|---|---|---|---|
| communication_level | 0.97 | 0.94 | 1.00 | 1.00 |
| social_level | 1.00 | 1.00 | 1.00 | 1.00 |
| play_level | 1.00 | 1.00 | 1.00 | 1.00 |
| attention_level | 1.00 | 1.00 | 1.00 | 1.00 |

## How realistic each feature is (KS distance to real, lower is better)

| Feature | Original | Calibrated |
|---|---|---|
| overall_accuracy | 0.92 | 0.61 |
| overall_avg_response_time | 0.53 | 0.40 |
| overall_task_completion_rate | 1.00 | 0.17 |
| overall_retry_count | 0.83 | 0.47 |
| overall_hint_count | 0.74 | 0.49 |
| overall_prompt_dependency_score | 0.69 | 0.48 |
| overall_idle_time_seconds | 0.60 | 0.41 |
| overall_invalid_touch_count | 0.79 | 0.46 |
| copy_me_accuracy | 0.50 | 0.28 |
| match_it_accuracy | 0.86 | 0.52 |
| my_turn_your_turn_accuracy | 0.64 | 0.35 |
| do_what_i_say_accuracy | 0.81 | 0.57 |
| **mean** | **0.74** | **0.43** |

## Reading these numbers

- **Realism is the meaningful comparison.** The calibrated generator's features sit closer to the real runs (mean KS 0.43 vs 0.74). The largest gain is where the original generator's independence assumption was furthest from reality.
- **Accuracy on real runs cannot separate the generators yet.** Almost every real run is Strength in every area, so a model that predicts Strength scores near 100% either way. More real runs — especially children who need support — are needed before this column means much.

## Limitations

- **Small sample.** 13 real runs, mostly strong performers. The copula keeps only part of their correlation (shrinkage k = 10), and half of every marginal still comes from the rubric-spanning prior so that Needs Support and Emerging children stay represented.
- **Labels are the rubric's.** The real runs have no expert labels, so accuracy on them shows how well a model trained on synthetic features carries over to real feature distributions — not clinical validity. Expert-labelled runs are needed for that.
- **Possible test accounts.** Exact duplicate runs were removed as likely automated test runs; other developer runs may remain.
- **Literature anchoring.** The prior ranges are the proponents' rubric-spanning ranges. Replacing them with ranges from published ASD gameplay studies is the next refinement.
