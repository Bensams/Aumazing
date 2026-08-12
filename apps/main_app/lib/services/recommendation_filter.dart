import 'package:flutter/foundation.dart';

import '../model/ai_assessment_response.dart';
import '../model/module_recommendation.dart';

/// Result of filtering AI recommendations against the active-games set.
class FilteredRecommendations {
  /// Module details with inactive games removed.
  final List<ModuleRecommendation> moduleDetails;

  /// Recommended module name strings with inactive games removed.
  final List<String> recommendedModules;

  const FilteredRecommendations({
    required this.moduleDetails,
    required this.recommendedModules,
  });

  /// True when every recommendation was filtered out (all games disabled).
  bool get isEmpty => moduleDetails.isEmpty && recommendedModules.isEmpty;
}

/// Pure filter utility — no side effects, no state.
///
/// Takes an [AiAssessmentResponse] and a [Set<String>] of active game IDs
/// and returns only the recommendations whose `gameId` is in the active set.
///
/// ```dart
/// final filtered = RecommendationFilter.filter(aiResponse, activeIds);
/// ```
class RecommendationFilter {
  const RecommendationFilter._();

  /// Known mapping from human-readable module names to game IDs.
  ///
  /// Used to filter [AiAssessmentResponse.recommendedModules] which contains
  /// display names like `'Copy Me'` rather than IDs like `'copy_me'`.
  static const Map<String, String> _nameToGameId = {
    'Copy Me': 'copy_me',
    'Do What I Say': 'do_what_i_say',
    'My Turn, Your Turn': 'my_turn_your_turn',
    'Match It': 'match_it',
    'Sari-Sari Store Sorting': 'sari_sari_sort',
    'Trace It': 'trace_it',
    'Hintay!': 'hintay',
    "Ano'ng Susunod?": 'anong_susunod',
    'Sabay Tayo!': 'sabay_tayo',
  };

  /// Filter [response]'s module recommendations, keeping only those whose
  /// game ID is present in [activeGameIds].
  ///
  /// Emits [debugPrint] messages for every removed module so developers can
  /// trace filtering in the console.
  static FilteredRecommendations filter(
    AiAssessmentResponse response,
    Set<String> activeGameIds,
  ) {
    // ── Filter moduleDetails (structured) ──────────────────────────────
    final filteredDetails = <ModuleRecommendation>[];
    for (final mod in response.moduleDetails) {
      if (activeGameIds.contains(mod.gameId)) {
        filteredDetails.add(mod);
      } else {
        debugPrint('[RecommendationFilter] Removed moduleDetail '
            '"${mod.name}" (gameId=${mod.gameId}) — game not active');
      }
    }

    // ── Filter recommendedModules (string names) ───────────────────────
    final filteredModules = <String>[];
    for (final name in response.recommendedModules) {
      final gameId = _nameToGameId[name] ??
          name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
      if (activeGameIds.contains(gameId)) {
        filteredModules.add(name);
      } else {
        debugPrint('[RecommendationFilter] Removed recommendedModule '
            '"$name" (resolved gameId=$gameId) — game not active');
      }
    }

    return FilteredRecommendations(
      moduleDetails: filteredDetails,
      recommendedModules: filteredModules,
    );
  }
}
