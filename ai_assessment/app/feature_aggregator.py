"""
app/feature_aggregator.py
Transforms raw game session data into the 12 XGBoost features.

This module bridges the gap between the Flutter app's raw GameplaySession
records and the pre-computed feature vector expected by the XGBoost model.
"""

import logging
from typing import List

from app.schemas import GameSessionInput

logger = logging.getLogger(__name__)

# Valid game IDs recognised by the Aumazing app
VALID_GAME_IDS = {"copy_me", "match_it", "my_turn_your_turn", "do_what_i_say"}

# Default feature values used when no session data is available
DEFAULT_FEATURES: dict[str, float] = {
    "overall_accuracy": 0.5,
    "overall_avg_response_time": 4.0,
    "overall_task_completion_rate": 0.5,
    "overall_retry_count": 3.0,
    "overall_hint_count": 5.0,
    "overall_prompt_dependency_score": 0.3,
    "overall_idle_time_seconds": 15.0,
    "overall_invalid_touch_count": 5.0,
    "copy_me_accuracy": 0.5,
    "match_it_accuracy": 0.5,
    "my_turn_your_turn_accuracy": 0.5,
    "do_what_i_say_accuracy": 0.5,
}


def _safe_mean(values: list[float]) -> float:
    """Return the arithmetic mean, or 0.0 for an empty list."""
    if not values:
        return 0.0
    return sum(values) / len(values)


def _session_accuracy(session: GameSessionInput) -> float:
    """Compute accuracy for a single session (score / total_items)."""
    if session.total_items <= 0:
        return 0.0
    return session.score / session.total_items


def _per_game_accuracy(
    sessions: List[GameSessionInput],
    game_id: str,
    default: float = 0.5,
) -> float:
    """
    Compute mean accuracy for sessions matching *game_id*.

    Returns *default* if no sessions match.
    """
    accuracies = [
        _session_accuracy(s)
        for s in sessions
        if s.game_id == game_id
    ]
    if not accuracies:
        return default
    return _safe_mean(accuracies)


def aggregate_features(sessions: List[GameSessionInput]) -> dict[str, float]:
    """
    Transform raw game sessions into the 12 features expected by the XGBoost model.

    Mapping
    -------
    - ``overall_accuracy``              — mean(score / total_items) across all sessions
    - ``overall_avg_response_time``     — mean(total_response_time_ms / 1000 / total_items) in seconds
    - ``overall_task_completion_rate``   — count(sessions where score > 0) / total sessions
    - ``overall_retry_count``           — mean(retry_count) across sessions
    - ``overall_hint_count``            — mean(hint_count) across sessions
    - ``overall_prompt_dependency_score``— mean(hint_count / max(total_items, 1)) across sessions
    - ``overall_idle_time_seconds``     — mean(idle_time_seconds) across sessions
    - ``overall_invalid_touch_count``   — mean(random_touch_count) across sessions
    - ``copy_me_accuracy``              — mean accuracy for game_id == 'copy_me'  (default 0.5)
    - ``match_it_accuracy``             — mean accuracy for game_id == 'match_it' (default 0.5)
    - ``my_turn_your_turn_accuracy``    — mean accuracy for game_id == 'my_turn_your_turn' (default 0.5)
    - ``do_what_i_say_accuracy``        — mean accuracy for game_id == 'do_what_i_say' (default 0.5)

    Edge cases
    ----------
    - Empty sessions list → returns ``DEFAULT_FEATURES``.
    - Division by zero (total_items == 0) → treated as 0.0 accuracy / response time.
    - Missing games → per-game accuracy defaults to 0.5.
    """
    if not sessions:
        logger.warning("No sessions provided — returning default features.")
        return dict(DEFAULT_FEATURES)

    n = len(sessions)

    # Overall accuracy
    accuracies = [_session_accuracy(s) for s in sessions]
    overall_accuracy = _safe_mean(accuracies)

    # Overall average response time (seconds per item)
    response_times: list[float] = []
    for s in sessions:
        if s.total_items > 0:
            response_times.append(
                (s.total_response_time_ms / 1000.0) / s.total_items
            )
    overall_avg_response_time = _safe_mean(response_times) if response_times else 4.0

    # Task completion rate
    completed = sum(1 for s in sessions if s.score > 0)
    overall_task_completion_rate = completed / n

    # Retry count (mean)
    overall_retry_count = _safe_mean([float(s.retry_count) for s in sessions])

    # Hint count (mean)
    overall_hint_count = _safe_mean([float(s.hint_count) for s in sessions])

    # Prompt dependency score
    prompt_scores = [
        s.hint_count / max(s.total_items, 1)
        for s in sessions
    ]
    overall_prompt_dependency_score = _safe_mean(prompt_scores)

    # Idle time (mean)
    overall_idle_time_seconds = _safe_mean([s.idle_time_seconds for s in sessions])

    # Invalid touch count (mean)
    overall_invalid_touch_count = _safe_mean(
        [float(s.random_touch_count) for s in sessions]
    )

    # Per-game accuracies
    copy_me_accuracy = _per_game_accuracy(sessions, "copy_me")
    match_it_accuracy = _per_game_accuracy(sessions, "match_it")
    my_turn_your_turn_accuracy = _per_game_accuracy(sessions, "my_turn_your_turn")
    do_what_i_say_accuracy = _per_game_accuracy(sessions, "do_what_i_say")

    features = {
        "overall_accuracy": round(overall_accuracy, 6),
        "overall_avg_response_time": round(overall_avg_response_time, 6),
        "overall_task_completion_rate": round(overall_task_completion_rate, 6),
        "overall_retry_count": round(overall_retry_count, 6),
        "overall_hint_count": round(overall_hint_count, 6),
        "overall_prompt_dependency_score": round(overall_prompt_dependency_score, 6),
        "overall_idle_time_seconds": round(overall_idle_time_seconds, 6),
        "overall_invalid_touch_count": round(overall_invalid_touch_count, 6),
        "copy_me_accuracy": round(copy_me_accuracy, 6),
        "match_it_accuracy": round(match_it_accuracy, 6),
        "my_turn_your_turn_accuracy": round(my_turn_your_turn_accuracy, 6),
        "do_what_i_say_accuracy": round(do_what_i_say_accuracy, 6),
    }

    logger.info("Aggregated features from %d sessions: %s", n, features)
    return features
