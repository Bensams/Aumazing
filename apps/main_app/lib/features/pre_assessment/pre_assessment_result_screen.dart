import 'package:flutter/material.dart';

import 'package:shared_ui/shared_ui.dart';

import '../../model/ai_assessment_response.dart';
import '../../model/assessment_result.dart';
import '../../model/support_profile.dart';
import '../../services/active_games_service.dart';
import '../../services/recommendation_filter.dart';

/// Displays the pre-assessment results with a developmental profile
/// and recommended settings.
///
/// This is a thin wrapper that maps main_app domain models to the shared
/// [AssessmentResultLayout] widget from `shared_ui`.
class PreAssessmentResultScreen extends StatefulWidget {
  const PreAssessmentResultScreen({
    super.key,
    required this.profile,
    required this.results,
    this.aiResponse,
  });

  final SupportProfile profile;
  final List<AssessmentResult> results;

  /// AI prediction data, or null if AI was unavailable (rule-based fallback).
  final AiAssessmentResponse? aiResponse;

  @override
  State<PreAssessmentResultScreen> createState() =>
      _PreAssessmentResultScreenState();
}

class _PreAssessmentResultScreenState extends State<PreAssessmentResultScreen> {
  /// Filtered recommendations after removing inactive games.
  /// `null` means "still loading"; non-null means "ready to display".
  FilteredRecommendations? _filtered;

  @override
  void initState() {
    super.initState();
    debugPrint('[PreAssessmentResult] AI data received: '
        '${widget.aiResponse != null ? widget.aiResponse.toString() : "null (rule-based)"}');

    // Load active game IDs and filter recommendations.
    if (widget.aiResponse != null) {
      _loadFilteredRecommendations(widget.aiResponse!);
    }
  }

  /// Fetches the active game set (cached after first call) and applies
  /// the pure filter to the AI response's module recommendations.
  Future<void> _loadFilteredRecommendations(AiAssessmentResponse ai) async {
    final activeIds = await ActiveGamesService.instance.activeGameIds;
    final filtered = RecommendationFilter.filter(ai, activeIds);
    if (mounted) {
      setState(() => _filtered = filtered);
    }
  }

  SupportProfile get profile => widget.profile;
  List<AssessmentResult> get results => widget.results;
  AiAssessmentResponse? get aiResponse => widget.aiResponse;

  @override
  Widget build(BuildContext context) {
    return AssessmentResultLayout(
      profileRows: _buildProfileRows(),
      recommendations: _buildRecommendations(),
      gameScores: _buildGameScores(),
      aiData: _buildAiData(),
      onContinue: () {
        Navigator.of(context).popUntil((route) => route.isFirst);
      },
    );
  }

  // ── Data mapping ─────────────────────────────────────────────────────

  List<ResultProfileRow> _buildProfileRows() {
    return [
      ResultProfileRow(area: 'Communication', level: profile.communication),
      ResultProfileRow(
          area: 'Social Interaction', level: profile.socialInteraction),
      ResultProfileRow(area: 'Play Skills', level: profile.playSkills),
      ResultProfileRow(area: 'Attention', level: profile.attention),
      if (profile.sensoryNotes.isNotEmpty)
        ResultProfileRow(
            area: 'Sensory', level: profile.sensoryNotes.join(', ')),
    ];
  }

  List<ResultRecommendation> _buildRecommendations() {
    return [
      ResultRecommendation(
        icon: Icons.speed_rounded,
        label: 'Difficulty',
        value: profile.recommendedDifficulty,
      ),
      ResultRecommendation(
        icon: Icons.record_voice_over_rounded,
        label: 'Prompt Style',
        value: profile.recommendedPromptStyle,
      ),
      ResultRecommendation(
        icon: Icons.timer_rounded,
        label: 'Session Length',
        value: '${profile.recommendedSessionMinutes} min',
      ),
      ResultRecommendation(
        icon: Icons.repeat_rounded,
        label: 'Prompt Repetition',
        value: '${profile.promptRepetition}x',
      ),
      if (profile.lowStimulationMode)
        const ResultRecommendation(
          icon: Icons.visibility_off_rounded,
          label: 'Mode',
          value: 'Low-stimulation',
        ),
      if (profile.turnTakingPractice)
        const ResultRecommendation(
          icon: Icons.people_rounded,
          label: 'Practice',
          value: 'Extra turn-taking',
        ),
    ];
  }

  List<ResultGameScore> _buildGameScores() {
    return results
        .map((r) => ResultGameScore(
              gameId: r.gameId,
              name: _gameName(r.gameId),
              emoji: _gameEmoji(r.gameId),
              accuracy: r.adjustedAccuracy,
            ))
        .toList();
  }

  ResultAiData? _buildAiData() {
    final ai = aiResponse;
    if (ai == null) return null;

    // Map area levels
    const orderedAreas = <String, String>{
      'communication': 'Communication',
      'social': 'Social Interaction',
      'play': 'Play Skills',
      'attention': 'Attention',
    };

    final areaLevels = <ResultAreaLevel>[];
    for (final entry in orderedAreas.entries) {
      final areaLevel = ai.areaLevels[entry.key];
      if (areaLevel != null) {
        areaLevels.add(ResultAreaLevel(
          label: entry.value,
          levelName: areaLevel.levelName,
          levelInt: areaLevel.levelInt,
          confidence: areaLevel.confidence,
        ));
      }
    }

    // Map filtered modules
    final modules = <ResultModule>[];
    final moduleNames = <String>[];
    bool allFilteredOut = false;

    if (_filtered != null) {
      if (_filtered!.isEmpty) {
        allFilteredOut = true;
      } else if (_filtered!.moduleDetails.isNotEmpty) {
        for (final mod in _filtered!.moduleDetails) {
          modules.add(ResultModule(
            name: mod.name,
            startingLevel: mod.startingLevel,
          ));
        }
      } else if (_filtered!.recommendedModules.isNotEmpty) {
        moduleNames.addAll(_filtered!.recommendedModules);
      }
    }

    return ResultAiData(
      areaLevels: areaLevels,
      confidence: ai.confidence,
      summary: ai.summary,
      modules: modules,
      profileDisplayName: ai.profileDisplayName,
      supportLevel: ai.supportLevel,
      hasAreaLevels: ai.hasAreaLevels,
      recommendedModuleNames: moduleNames,
      allFilteredOut: allFilteredOut,
    );
  }

  // ── Game display helpers ─────────────────────────────────────────────

  String _gameName(String gameId) {
    switch (gameId) {
      case 'copy_me':
        return 'Copy Me';
      case 'do_what_i_say':
        return 'Do What I Say';
      case 'my_turn_your_turn':
        return 'My Turn, Your Turn';
      case 'match_it':
        return 'Match It';
      default:
        return gameId;
    }
  }

  String _gameEmoji(String gameId) {
    switch (gameId) {
      case 'copy_me':
        return '🪞';
      case 'do_what_i_say':
        return '🗣️';
      case 'my_turn_your_turn':
        return '🔄';
      case 'match_it':
        return '🧩';
      default:
        return '🎮';
    }
  }
}
