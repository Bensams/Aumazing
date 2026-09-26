import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:game_core/game_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/services/local_db_service.dart';
import '../model/assessment_result.dart';
import '../model/gameplay_session.dart';
import 'parent_history_service.dart';
import 'rubric/rubric.dart';

/// Who wrote an overall gameplay summary.
enum GameplaySummarySource {
  /// Written by Gemini through the `summarize-gameplay` Edge Function.
  gemini,

  /// Written by Groq, which the Edge Function falls back to when Gemini is
  /// rate-limited or failing.
  groq,

  /// Written on this device by [OverallGameplaySummaryService.buildFallback]
  /// because neither Gemini nor Groq answered.
  onDevice,
}

/// One finished assessment sitting, in the order the child took them.
class SummaryAssessment {
  const SummaryAssessment({
    required this.type,
    required this.cycle,
    required this.completedAt,
    required this.accuracyPct,
    required this.areas,
  });

  /// 'pre' or 'post'.
  final String type;

  /// 1 for the first pre → post cycle, 2 for the next, and so on.
  final int cycle;
  final DateTime? completedAt;
  final int accuracyPct;

  /// Area → rubric label ('Communication' → 'Emerging', ...).
  final Map<String, String> areas;

  String get label =>
      '${type == 'post' ? 'Post-assessment' : 'Pre-assessment'} '
      '(cycle $cycle)';

  Map<String, dynamic> toPayload() => {
    'label': label,
    'type': type,
    'cycle': cycle,
    'accuracy_pct': accuracyPct,
    'areas': [
      for (final e in areas.entries) {'name': e.key, 'level': e.value},
    ],
  };
}

/// One game of the recommended learning path, as the child has played it.
class SummaryPathGame {
  const SummaryPathGame({
    required this.gameId,
    required this.name,
    required this.plays,
    required this.avgAccuracyPct,
    required this.reachedStrength,
    required this.tries,
    this.lastLabel,
  });

  final String gameId;
  final String name;

  /// Recommended-activity plays of this game (all cycles).
  final int plays;
  final int? avgAccuracyPct;
  final bool reachedStrength;

  /// Tries it took to reach Strength, or the tries so far while it has not.
  final int tries;
  final String? lastLabel;

  int get retries => tries > 0 ? tries - 1 : 0;

  Map<String, dynamic> toPayload() => {
    'name': name,
    'plays': plays,
    if (avgAccuracyPct != null) 'avg_accuracy_pct': avgAccuracyPct,
    'reached_strength': reachedStrength,
    'tries': tries,
    if (lastLabel != null && lastLabel!.isNotEmpty) 'last_level': lastLabel,
  };
}

/// Everything an overall summary is written from. Practice play is never in
/// here: only assessments (every cycle) and recommended activities.
class GameplaySummaryInput {
  const GameplaySummaryInput({
    required this.assessments,
    required this.pathGames,
    required this.recommendedPlays,
    required this.fingerprint,
  });

  /// Completed assessments, oldest first.
  final List<SummaryAssessment> assessments;
  final List<SummaryPathGame> pathGames;
  final int recommendedPlays;

  /// Changes whenever a record the summary depends on changes; an unchanged
  /// fingerprint means there is no new game record to summarize.
  final String fingerprint;

  bool get isEmpty => assessments.isEmpty && recommendedPlays == 0;

  Map<String, dynamic> toPayload() => {
    'assessments': [for (final a in assessments) a.toPayload()],
    'recommended_activities': [for (final g in pathGames) g.toPayload()],
    'recommended_plays': recommendedPlays,
  };
}

/// An overall summary of the child's gameplay, plus questions the parent can
/// bring to a therapist or practitioner.
class OverallGameplaySummary {
  const OverallGameplaySummary({
    required this.summary,
    required this.questions,
    required this.source,
    required this.generatedAt,
    this.fromCache = false,
  });

  final String summary;
  final List<String> questions;
  final GameplaySummarySource source;
  final DateTime generatedAt;

  /// True when this is the saved summary, reused because no new game record
  /// arrived since it was written.
  final bool fromCache;

  bool get isAi => source != GameplaySummarySource.onDevice;
}

/// Sends a request body to the summarizer and returns its JSON reply.
typedef GameplaySummaryRemote =
    Future<Object?> Function(Map<String, dynamic> body);

/// Writes the parent dashboard's overall gameplay summary.
///
/// Covers the pre-assessment, the recommended activities (My Path), the
/// post-assessment and any later assessment cycle — free practice is left
/// out. The `summarize-gameplay` Edge Function writes it with Gemini, or with
/// Groq when Gemini is at its limit (keys in Vault; only levels, counts and
/// game names are sent — never the child's name). When neither answers the
/// summary is written on the device instead, and the card says which of the
/// three the parent is reading.
///
/// An AI summary is saved per child with the fingerprint of the records it
/// was written from. While no new game record arrives the saved summary is
/// shown as-is — no request, works offline. An on-device summary is never
/// saved, so the next visit tries Gemini again.
class OverallGameplaySummaryService {
  OverallGameplaySummaryService({
    LocalDbService? localDb,
    GameplaySummaryRemote? remote,
  }) : _localDbOverride = localDb,
       _remote = remote;

  static final OverallGameplaySummaryService instance =
      OverallGameplaySummaryService();

  /// Covers the whole server-side chain: Gemini, then Groq (10 s each).
  static const _timeout = Duration(seconds: 25);

  /// Contexts that feed the summary. 'practice' is deliberately absent.
  static const includedContexts = {
    'pre_assessment',
    'post_assessment',
    'recommended_module',
  };

  final LocalDbService? _localDbOverride;
  final GameplaySummaryRemote? _remote;

  LocalDbService get _localDb => _localDbOverride ?? localDbService;

  // ── Input ──────────────────────────────────────────────────────────────

  /// Collects the summary input for [childId] from the local database.
  ///
  /// [pathGameIds] — the current learning path, in order, so every path game
  /// is listed even before it has been played. [pathAttempts] — the tries
  /// counted by the Strength gate, which win over the session-derived count.
  Future<GameplaySummaryInput> buildInput({
    required String childId,
    List<String> pathGameIds = const [],
    Map<String, PathAttemptRecord> pathAttempts = const {},
  }) async {
    final runs = await _localDb.getAssessmentRuns(childId: childId);
    final results = await _localDb.getAssessmentResults(childId: childId);
    final sessions = await _localDb.getGameSessions(childId: childId);
    return assemble(
      runs: [
        for (final r in runs)
          if (r.isCompleted)
            (id: r.id, type: r.type, completedAt: r.completedAt ?? r.startedAt),
      ],
      results: results,
      sessions: sessions,
      pathGameIds: pathGameIds,
      pathAttempts: pathAttempts,
    );
  }

  /// Pure assembly of the input — exposed for tests.
  @visibleForTesting
  static GameplaySummaryInput assemble({
    required List<({String id, String type, DateTime completedAt})> runs,
    required List<AssessmentResult> results,
    required List<GameplaySession> sessions,
    List<String> pathGameIds = const [],
    Map<String, PathAttemptRecord> pathAttempts = const {},
  }) {
    final included = [
      for (final s in sessions)
        if (includedContexts.contains(s.context)) s,
    ]..sort((a, b) => a.startedAt.compareTo(b.startedAt));

    // Assessments, oldest first; every pre opens a new cycle.
    final ordered = [...runs]
      ..sort((a, b) => a.completedAt.compareTo(b.completedAt));
    final assessments = <SummaryAssessment>[];
    var cycle = 0;
    for (final run in ordered) {
      if (run.type != 'post' || cycle == 0) cycle++;
      final runResults = [
        for (final r in results)
          if (r.assessmentRunId == run.id) r,
      ];
      final runSessions = [
        for (final s in included)
          if (s.assessmentRunId == run.id) s,
      ];
      assessments.add(
        SummaryAssessment(
          type: run.type,
          cycle: cycle,
          completedAt: run.completedAt,
          accuracyPct: _meanAccuracyPct(runSessions) ?? 0,
          areas: {
            for (final e in ParentHistoryService.aggregateSkills(runResults))
              e.area: e.label,
          },
        ),
      );
    }

    // Recommended activities, grouped per game.
    final recommended = [
      for (final s in included)
        if (s.context == 'recommended_module') s,
    ];
    final byGame = <String, List<GameplaySession>>{};
    for (final s in recommended) {
      byGame.putIfAbsent(s.gameId, () => []).add(s);
    }
    final gameIds = <String>[
      ...pathGameIds,
      for (final id in byGame.keys)
        if (!pathGameIds.contains(id)) id,
    ];
    const mastery = PathMastery();
    final pathGames = <SummaryPathGame>[];
    for (final id in gameIds) {
      final plays = byGame[id] ?? const <GameplaySession>[];
      final record = pathAttempts[id];
      int tries;
      bool reached;
      String? lastLabel;
      if (record != null) {
        tries = record.attemptsToStrength ?? record.attempts;
        reached = record.reachedStrength;
        lastLabel = record.lastLabel;
      } else {
        final firstStrength = plays.indexWhere(mastery.isStrength);
        reached = firstStrength >= 0;
        tries = reached ? firstStrength + 1 : plays.length;
        lastLabel =
            plays.isEmpty ? null : mastery.labelFor(plays.last).displayName;
      }
      pathGames.add(
        SummaryPathGame(
          gameId: id,
          name: GameRegistry.find(id)?.name ?? id.replaceAll('_', ' '),
          plays: plays.length,
          avgAccuracyPct: _meanAccuracyPct(plays),
          reachedStrength: reached,
          tries: tries,
          lastLabel: lastLabel,
        ),
      );
    }

    return GameplaySummaryInput(
      assessments: assessments,
      pathGames: pathGames,
      recommendedPlays: recommended.length,
      fingerprint: _fingerprint(included, assessments, pathGames),
    );
  }

  static int? _meanAccuracyPct(List<GameplaySession> sessions) {
    final scored = [
      for (final s in sessions)
        if (s.totalItems > 0) (s.score / s.totalItems).clamp(0.0, 1.0),
    ];
    if (scored.isEmpty) return null;
    return (scored.reduce((a, b) => a + b) / scored.length * 100).round();
  }

  static String _fingerprint(
    List<GameplaySession> included,
    List<SummaryAssessment> assessments,
    List<SummaryPathGame> pathGames,
  ) {
    final buffer = StringBuffer();
    for (final s in included) {
      buffer.write('${s.id}|');
    }
    for (final a in assessments) {
      buffer.write('${a.label}:${a.areas}|');
    }
    for (final g in pathGames) {
      buffer.write('${g.gameId}:${g.tries}:${g.reachedStrength}|');
    }
    return sha1.convert(utf8.encode(buffer.toString())).toString();
  }

  // ── Summary ────────────────────────────────────────────────────────────

  /// The overall summary for [input]: the saved Gemini summary while nothing
  /// changed, a fresh Gemini summary otherwise, or the on-device summary when
  /// Gemini cannot be reached. Returns null when there is nothing to
  /// summarize yet.
  ///
  /// [forceRefresh] skips the saved summary (the parent asked to retry).
  Future<OverallGameplaySummary?> summarize({
    required String childId,
    required GameplaySummaryInput input,
    String languageCode = 'en',
    bool forceRefresh = false,
  }) async {
    if (input.isEmpty) return null;

    if (!forceRefresh) {
      final cached = await _readCache(childId);
      if (cached != null &&
          cached['fingerprint'] == input.fingerprint &&
          cached['language'] == languageCode) {
        final saved = _fromJson(cached, fromCache: true);
        if (saved != null) return saved;
      }
    }

    try {
      final body = {...input.toPayload(), 'language': languageCode};
      final data = await (_remote ?? _invokeEdgeFunction)(body).timeout(
        _timeout,
      );
      final parsed = _parseReply(data);
      if (parsed != null) {
        final summary = OverallGameplaySummary(
          summary: parsed.$1,
          questions:
              parsed.$2.isEmpty ? buildFallback(input).questions : parsed.$2,
          source: parsed.$3,
          generatedAt: DateTime.now(),
        );
        await _writeCache(childId, {
          'fingerprint': input.fingerprint,
          'language': languageCode,
          'provider': summary.source.name,
          'summary': summary.summary,
          'questions': summary.questions,
          'generated_at': summary.generatedAt.toIso8601String(),
        });
        return summary;
      }
    } catch (e) {
      // Offline, timeout, both providers limited — all handled the same way.
      debugPrint('[OverallGameplaySummary] AI unavailable: $e');
    }
    return buildFallback(input);
  }

  static Future<Object?> _invokeEdgeFunction(Map<String, dynamic> body) async {
    final response = await Supabase.instance.client.functions.invoke(
      'summarize-gameplay',
      body: body,
    );
    return response.data;
  }

  static (String, List<String>, GameplaySummarySource)? _parseReply(
    Object? data,
  ) {
    if (data is! Map) return null;
    final summary = (data['summary'] as String?)?.trim();
    if (summary == null || summary.isEmpty) return null;
    final questions = <String>[
      if (data['questions'] is List)
        for (final q in data['questions'] as List)
          if (q is String && q.trim().isNotEmpty) q.trim(),
    ];
    return (summary, questions.take(5).toList(), _aiSource(data['provider']));
  }

  /// The AI provider named in a reply or cache entry; Gemini when absent
  /// (replies from before the Groq fallback existed).
  static GameplaySummarySource _aiSource(Object? provider) =>
      provider == GameplaySummarySource.groq.name
          ? GameplaySummarySource.groq
          : GameplaySummarySource.gemini;

  // ── On-device summarizer ───────────────────────────────────────────────

  static const _levelRank = {
    'Strength': 2,
    'Sustained Attention': 2,
    'Emerging': 1,
    'Variable Attention': 1,
    'Needs Support': 0,
    'Needs Attention Support': 0,
  };

  /// Writes the summary and questions on the device, from the same input
  /// Gemini would receive. Plain rules over the recorded levels and tries —
  /// it never invents anything the records do not say.
  static OverallGameplaySummary buildFallback(GameplaySummaryInput input) {
    final sentences = <String>[];
    final questions = <String>[];

    final latest = input.assessments.isEmpty ? null : input.assessments.last;
    SummaryAssessment? earlier;
    if (latest != null) {
      for (final a in input.assessments.reversed.skip(1)) {
        if (a.areas.isNotEmpty) {
          earlier = a;
          break;
        }
      }
    }

    final count = input.assessments.length;
    final opening = StringBuffer(
      'Your child has completed $count assessment${count == 1 ? '' : 's'}',
    );
    if (input.recommendedPlays > 0) {
      opening.write(
        ' and played ${input.recommendedPlays} recommended '
        'activit${input.recommendedPlays == 1 ? 'y' : 'ies'}',
      );
    }
    sentences.add('$opening.');

    final strengths = <String>[];
    final growing = <String>[];
    if (latest != null) {
      for (final e in latest.areas.entries) {
        final rank = _levelRank[e.value];
        if (rank == null) continue; // sensory preference is not a level
        (rank == 2 ? strengths : growing).add(e.key);
      }
      final which = latest.type == 'post' ? 'latest' : 'first';
      if (strengths.isNotEmpty) {
        sentences.add(
          'In the $which assessment, ${_join(strengths)} stood out as '
          '${strengths.length == 1 ? 'a strength' : 'strengths'}.',
        );
      }
      if (growing.isNotEmpty) {
        sentences.add(
          '${_capitalize(_join(growing))} ${growing.length == 1 ? 'is' : 'are'} '
          'still growing and will benefit from more playful practice.',
        );
      }
    }

    final improved = <String>[];
    if (latest != null && earlier != null) {
      for (final e in latest.areas.entries) {
        final now = _levelRank[e.value];
        final before = _levelRank[earlier.areas[e.key]];
        if (now != null && before != null && now > before) improved.add(e.key);
      }
      sentences.add(
        improved.isEmpty
            ? 'Compared with the earlier assessment, the skill levels have '
                'stayed steady.'
            : 'Since the earlier assessment, ${_join(improved)} moved up a '
                'level.',
      );
    }

    final played = [
      for (final g in input.pathGames)
        if (g.tries > 0) g,
    ];
    if (input.pathGames.isNotEmpty) {
      final reached = input.pathGames.where((g) => g.reachedStrength).length;
      sentences.add(
        'On My Path, your child reached Strength in $reached of '
        '${input.pathGames.length} recommended game'
        '${input.pathGames.length == 1 ? '' : 's'}.',
      );
    }
    SummaryPathGame? hardest;
    for (final g in played) {
      if (hardest == null || g.tries > hardest.tries) hardest = g;
    }
    if (hardest != null && hardest.tries >= 3) {
      sentences.add(
        hardest.reachedStrength
            ? '${hardest.name} took ${hardest.tries} tries before reaching '
                'Strength — steady effort paid off.'
            : '${hardest.name} is still being practised '
                '(${hardest.tries} tries so far).',
      );
    }

    // Questions for the therapist or practitioner.
    for (final area in growing.take(2)) {
      questions.add(
        'What simple everyday activities can we do at home to support '
        '${area.toLowerCase()}?',
      );
    }
    if (hardest != null && hardest.tries >= 3) {
      questions.add(
        '${hardest.name} took ${hardest.tries} tries'
        '${hardest.reachedStrength ? ' to reach Strength' : ' so far'} — is '
        'that expected, and how can we make that kind of task easier at home?',
      );
    }
    if (improved.isNotEmpty) {
      questions.add(
        'How can we keep building on the progress we have seen in '
        '${improved.first.toLowerCase()}?',
      );
    }
    questions.add(
      'Which one or two goals should we focus on over the next few weeks?',
    );
    if (questions.length < 5) {
      questions.add(
        'What signs should we watch for that would tell us our child needs a '
        'different kind of support?',
      );
    }

    return OverallGameplaySummary(
      summary: sentences.join(' '),
      questions: questions.take(5).toList(),
      source: GameplaySummarySource.onDevice,
      generatedAt: DateTime.now(),
    );
  }

  static String _join(List<String> items) {
    final lower = [for (final i in items) i.toLowerCase()];
    if (lower.length <= 1) return lower.join();
    return '${lower.sublist(0, lower.length - 1).join(', ')} and ${lower.last}';
  }

  static String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  // ── Cache ──────────────────────────────────────────────────────────────

  static String _cacheKey(String childId) =>
      'overall_gameplay_summary_$childId';

  static OverallGameplaySummary? _fromJson(
    Map<String, dynamic> json, {
    required bool fromCache,
  }) {
    final summary = json['summary'] as String?;
    if (summary == null || summary.isEmpty) return null;
    return OverallGameplaySummary(
      summary: summary,
      questions: [
        for (final q in (json['questions'] as List? ?? const []))
          if (q is String) q,
      ],
      source: _aiSource(json['provider']),
      generatedAt:
          DateTime.tryParse(json['generated_at'] as String? ?? '') ??
          DateTime.now(),
      fromCache: fromCache,
    );
  }

  Future<Map<String, dynamic>?> _readCache(String childId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey(childId));
      if (raw == null) return null;
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCache(String childId, Map<String, dynamic> value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey(childId), jsonEncode(value));
    } catch (e) {
      debugPrint('[OverallGameplaySummary] cache write failed: $e');
    }
  }
}
