/// Plain data classes for the [AssessmentResultLayout] widget.
///
/// These are framework-agnostic value objects that both main_app and game_lab
/// can construct from their own domain models (or from hardcoded mock data).
library;

import 'package:flutter/material.dart';

/// A single developmental area with its predicted level.
class ResultAreaLevel {
  const ResultAreaLevel({
    required this.label,
    required this.levelName,
    required this.levelInt,
    this.confidence = 0.0,
  });

  /// Display name, e.g. "Communication", "Social Interaction".
  final String label;

  /// Human-readable level, e.g. "Needs Support", "Emerging", "Strength".
  final String levelName;

  /// Ordinal: 0 = Needs Support, 1 = Emerging, 2 = Strength.
  final int levelInt;

  /// Model confidence for this area (0.0–1.0). Not displayed but kept
  /// for potential future use.
  final double confidence;
}

/// A single game's score for the Game Scores card.
class ResultGameScore {
  const ResultGameScore({
    required this.gameId,
    required this.name,
    required this.emoji,
    required this.accuracy,
  });

  final String gameId;
  final String name;
  final String emoji;

  /// 0.0–1.0 accuracy.
  final double accuracy;
}

/// A recommended learning module with its starting level.
class ResultModule {
  const ResultModule({
    required this.name,
    required this.startingLevel,
  });

  final String name;
  final int startingLevel;
}

/// A single row in the Recommendations card.
class ResultRecommendation {
  const ResultRecommendation({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;
}

/// A single row in the Developmental Profile card.
class ResultProfileRow {
  const ResultProfileRow({
    required this.area,
    required this.level,
  });

  final String area;
  final String level;
}

/// All data needed to render the AI Insights card.
///
/// When `null` is passed to [AssessmentResultLayout.aiData], the layout
/// falls back to the rule-based view (no AI Insights card).
class ResultAiData {
  const ResultAiData({
    required this.areaLevels,
    required this.confidence,
    required this.summary,
    required this.modules,
    this.profileDisplayName,
    this.supportLevel,
    this.hasAreaLevels = true,
    this.recommendedModuleNames = const [],
    this.allFilteredOut = false,
  });

  /// Per-area ordinal predictions.
  final List<ResultAreaLevel> areaLevels;

  /// Overall model confidence (0.0–1.0).
  final double confidence;

  /// Human-readable summary text.
  final String summary;

  /// Structured module recommendations with starting levels.
  final List<ResultModule> modules;

  /// Legacy single-profile display name (used when [hasAreaLevels] is false).
  final String? profileDisplayName;

  /// Legacy support level string (used when [hasAreaLevels] is false).
  final String? supportLevel;

  /// Whether the API returned per-area level predictions.
  final bool hasAreaLevels;

  /// Fallback: plain module name strings (used when [modules] is empty).
  final List<String> recommendedModuleNames;

  /// True when all recommendations were filtered out (no active games).
  final bool allFilteredOut;
}
