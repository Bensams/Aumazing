import 'package:aumazing/model/ai_assessment_response.dart';
import 'package:aumazing/model/area_level.dart';
import 'package:aumazing/model/assessment_result.dart';
import 'package:aumazing/model/module_recommendation.dart';
import 'package:aumazing/model/support_profile.dart';
import 'package:aumazing/services/assessment_result_mapper.dart';
import 'package:aumazing/services/scoring_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';

AssessmentResult _result(
  String gameId, {
  int score = 6,
  int totalItems = 10,
  int errorCount = 4,
  String? modelSource = 'xgboost_onnx',
  DateTime? completedAt,
}) => AssessmentResult(
  id: 'r-$gameId',
  childId: 'child-1',
  assessmentRunId: 'run-1',
  type: 'pre',
  gameId: gameId,
  score: score,
  totalItems: totalItems,
  errorCount: errorCount,
  avgResponseTimeMs: 1800,
  completedAt: completedAt ?? DateTime(2026, 5, 12),
  modelSource: modelSource,
);

const _profile = SupportProfile(
  communication: 'good',
  socialInteraction: 'emerging',
  playSkills: 'strong',
  attention: 'moderate',
  sensoryNotes: ['Prefers Quiet Play'],
  recommendedDifficulty: 'intermediate',
  recommendedPromptStyle: 'combined',
  recommendedSessionMinutes: 5,
  lowStimulationMode: true,
  turnTakingPractice: true,
  promptRepetition: 2,
);

AreaLevel _area(int levelInt) => AreaLevel(
  level: const ['needs_support', 'emerging', 'strength'][levelInt],
  levelInt: levelInt,
  levelName: const ['Needs Support', 'Emerging', 'Strength'][levelInt],
  confidence: 0.7,
);

AiAssessmentResponse _ai({bool onDevice = true}) => AiAssessmentResponse(
  predictedProfile: 'social_support',
  confidence: 0.82,
  summary: 'Attention is a strength; social interaction needs support.',
  supportLevel: 'moderate',
  recommendedModules: const ['Copy Me', 'Match It'],
  moduleDetails: const [
    ModuleRecommendation(gameId: 'copy_me', name: 'Copy Me', startingLevel: 1),
    ModuleRecommendation(
      gameId: 'match_it',
      name: 'Match It',
      startingLevel: 2,
    ),
  ],
  skillAreas: const ['communication', 'social', 'play', 'attention'],
  areaLevels: {
    'communication': _area(1),
    'social': _area(0),
    'play': _area(1),
    'attention': _area(2),
  },
  onDevice: onDevice,
);

final _results = [
  _result('copy_me', score: 5, totalItems: 10, errorCount: 5),
  _result('match_it', score: 8, totalItems: 10, errorCount: 2),
];

void main() {
  group('canonical model', () {
    test('completion and review build identical models from one run', () {
      // Completion mode maps the run right after it finishes; review mode
      // maps the very same stored run later. Same inputs → same values.
      final completion = AssessmentResultMapper.build(
        results: _results,
        profile: _profile,
        aiResponse: _ai(),
        activeGameIds: const {'copy_me', 'match_it'},
      );
      final review = AssessmentResultMapper.build(
        results: _results,
        profile: _profile,
        aiResponse: _ai(),
        activeGameIds: const {'copy_me', 'match_it'},
      );

      expect(review.assessmentRunId, completion.assessmentRunId);
      expect(review.completedAt, completion.completedAt);
      expect(review.correctCount, completion.correctCount);
      expect(review.errorCount, completion.errorCount);
      expect(review.totalItems, completion.totalItems);
      expect(
        review.overallAdjustedAccuracy,
        completion.overallAdjustedAccuracy,
      );
      expect(review.source, completion.source);
      expect(review.confidence, completion.confidence);
      expect(review.summary, completion.summary);
      expect(
        review.areas.map((a) => '${a.label}:${a.levelName}'),
        completion.areas.map((a) => '${a.label}:${a.levelName}'),
      );
      expect(
        review.recommendations.map((r) => '${r.label}=${r.value}'),
        completion.recommendations.map((r) => '${r.label}=${r.value}'),
      );
      expect(
        review.learningPath.map((m) => '${m.name}@${m.startingLevel}'),
        completion.learningPath.map((m) => '${m.name}@${m.startingLevel}'),
      );
      expect(review.sensoryObservations, completion.sensoryObservations);
    });

    test('run id and completion date come from the results', () {
      final model = AssessmentResultMapper.build(
        results: [
          _result('copy_me', completedAt: DateTime(2026, 5, 10)),
          _result('match_it', completedAt: DateTime(2026, 5, 12)),
        ],
        profile: _profile,
      );
      expect(model.assessmentRunId, 'run-1');
      expect(model.completedAt, DateTime(2026, 5, 12));
    });
  });

  group('scoring policy', () {
    test('overall accuracy is item-weighted adjusted accuracy', () {
      final model = AssessmentResultMapper.build(
        results: [
          // adjusted 5/10 = 0.5 over 10 items
          _result('copy_me', score: 5, totalItems: 10, errorCount: 5),
          // adjusted 9/10 = 0.9 over 30 items
          _result('match_it', score: 9, totalItems: 30, errorCount: 1),
        ],
        profile: _profile,
      );
      // (0.5 * 10 + 0.9 * 30) / 40 = 0.8
      expect(model.overallAdjustedAccuracy, closeTo(0.8, 1e-9));
      expect(model.overallPercent, 80);
    });

    test('overall accuracy is not the raw score/totalItems ratio', () {
      final model = AssessmentResultMapper.build(
        results: [
          // Retry-until-correct game: raw accuracy is 10/10 = 100%, but
          // eight errors along the way make the adjusted accuracy 10/18.
          _result('copy_me', score: 10, totalItems: 10, errorCount: 8),
        ],
        profile: _profile,
      );
      expect(model.correctCount, 10);
      expect(model.totalItems, 10);
      expect(model.overallPercent, 56);
      expect(model.games.single.accuracy, closeTo(10 / 18, 1e-9));
    });

    test('raw counts stay raw', () {
      final model = AssessmentResultMapper.build(
        results: _results,
        profile: _profile,
      );
      expect(model.correctCount, 13);
      expect(model.errorCount, 7);
      expect(model.totalItems, 20);
    });

    test('an empty run is safe', () {
      final model = AssessmentResultMapper.build(
        results: const [],
        profile: _profile,
      );
      expect(model.overallAdjustedAccuracy, 0.0);
      expect(model.totalItems, 0);
      expect(model.games, isEmpty);
    });
  });

  group('analysis source and confidence', () {
    test('on-device results are labelled On-Device AI', () {
      final model = AssessmentResultMapper.build(
        results: _results,
        profile: _profile,
        aiResponse: _ai(),
      );
      expect(model.source, AssessmentAnalysisSource.onDeviceAi);
      expect(model.source.label, 'On-Device AI');
      expect(model.confidencePercent, 82);
    });

    test('cloud results are labelled AI Analysis', () {
      final model = AssessmentResultMapper.build(
        results: [_result('copy_me', modelSource: 'xgboost')],
        profile: _profile,
        aiResponse: _ai(onDevice: false),
      );
      expect(model.source, AssessmentAnalysisSource.cloudAi);
      expect(model.source.label, 'AI Analysis');
    });

    test('a rubric-synthesized prediction is Rule-Based, not AI', () {
      // The offline fallback is delivered as an AiAssessmentResponse with
      // onDevice: true — the stored model source is what decides.
      final model = AssessmentResultMapper.build(
        results: [_result('copy_me', modelSource: 'rubric_based')],
        profile: _profile,
        aiResponse: _ai(),
      );
      expect(model.source, AssessmentAnalysisSource.ruleBased);
      expect(model.source.label, 'Rule-Based');
    });

    test('no prediction at all falls back to Rule-Based', () {
      final model = AssessmentResultMapper.build(
        results: [_result('copy_me', modelSource: null)],
        profile: _profile,
      );
      expect(model.source, AssessmentAnalysisSource.ruleBased);
      expect(model.confidence, isNull);
      expect(model.summary, isNotEmpty);
    });
  });

  group('profile and recommendations', () {
    test('AI area levels drive the developmental profile when present', () {
      final model = AssessmentResultMapper.build(
        results: _results,
        profile: _profile,
        aiResponse: _ai(),
      );
      expect(model.areas.map((a) => a.label), [
        'Communication',
        'Social Interaction',
        'Play Skills',
        'Attention',
      ]);
      expect(model.areas.map((a) => a.levelInt), [1, 0, 1, 2]);
    });

    test('the rubric profile drives it when the AI emitted no areas', () {
      final model = AssessmentResultMapper.build(
        results: _results,
        profile: _profile,
      );
      expect(model.areas.map((a) => a.levelName), [
        'Emerging',
        'Needs Support',
        'Strength',
        'Emerging',
      ]);
    });

    test('recommended settings use the fixed labels and order', () {
      final model = AssessmentResultMapper.build(
        results: _results,
        profile: _profile,
      );
      expect(model.recommendations.map((r) => r.label), [
        AssessmentLabels.difficulty,
        AssessmentLabels.promptStyle,
        AssessmentLabels.sessionLength,
        AssessmentLabels.promptRepetition,
        AssessmentLabels.lowStimulationMode,
        AssessmentLabels.turnTakingPractice,
      ]);
      expect(model.recommendations.map((r) => r.value).take(4), [
        'Intermediate',
        'Combined',
        '5 min',
        '2x',
      ]);
    });

    test('sensory observations come from the finalized profile, so later '
        'settings changes cannot rewrite them', () {
      // The finalized profile — what the provider persisted with the run.
      final finalized = AssessmentResultMapper.build(
        results: _results,
        profile: _profile,
      );

      // The parent then turns music off and drops the animation intensity.
      // Recomputing from those *current* settings would invent new notes;
      // the stored profile must not move.
      final recomputed = const ScoringService().generateProfile(
        results: _results,
        sensorySettings: const {
          'music_enabled': false,
          'vibration_enabled': false,
          'animation_intensity': 0.2,
        },
      );
      expect(recomputed.sensoryNotes, isNot(_profile.sensoryNotes));

      final reviewed = AssessmentResultMapper.build(
        results: _results,
        profile: _profile,
      );
      expect(reviewed.sensoryObservations, finalized.sensoryObservations);
      expect(reviewed.sensoryObservations, ['Prefers Quiet Play']);
    });
  });

  group('learning path', () {
    test('activities keep the My Path order and difficulty', () {
      final model = AssessmentResultMapper.build(
        results: _results,
        profile: _profile,
        aiResponse: _ai(),
        activeGameIds: const {'copy_me', 'match_it'},
      );
      expect(model.learningPath.map((m) => '${m.name}@${m.startingLevel}'), [
        'Copy Me@1',
        'Match It@2',
      ]);
      expect(model.learningPathUnavailable, isFalse);
    });

    test('inactive games are filtered out', () {
      final model = AssessmentResultMapper.build(
        results: _results,
        profile: _profile,
        aiResponse: _ai(),
        activeGameIds: const {'match_it'},
      );
      expect(model.learningPath.map((m) => m.name), ['Match It']);
    });

    test('an all-filtered path is flagged rather than shown empty', () {
      final model = AssessmentResultMapper.build(
        results: _results,
        profile: _profile,
        aiResponse: _ai(),
        activeGameIds: const {},
      );
      expect(model.learningPath, isEmpty);
      expect(model.learningPathUnavailable, isTrue);
    });
  });

  group('game display', () {
    test('game names and emoji come from one central mapping', () {
      final model = AssessmentResultMapper.build(
        results: _results,
        profile: _profile,
      );
      expect(model.games.map((g) => g.name), ['Copy Me', 'Match It']);
      expect(model.games.map((g) => g.emoji), ['🪞', '🧩']);
    });
  });
}
