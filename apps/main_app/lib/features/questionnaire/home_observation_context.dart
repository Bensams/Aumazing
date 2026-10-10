import 'dart:convert';

import '../../core/services/local_db_service.dart';
import 'parent_questionnaire.dart';

typedef HomeAssessmentLink = ({String id, String type, DateTime completedAt});
typedef HomeObservationLoader =
    Future<HomeObservationContext> Function(
      String childId,
      String runId,
      String assessmentType,
    );

/// A parent report kept separate from the game's measured performance.
class HomeObservation {
  const HomeObservation({
    required this.runId,
    required this.type,
    required this.completedAt,
    required this.templateId,
    required this.version,
    required this.status,
    required this.scores,
    this.schemaSignature,
    this.cycle,
  });

  final String runId;
  final String type;
  final DateTime completedAt;
  final String templateId;
  final int version;
  final String status;
  final String? schemaSignature;
  final int? cycle;
  final Map<String, double> scores;

  String get comparisonKey => schemaSignature ?? '$templateId:$version';

  bool comparableTo(HomeObservation other) =>
      schemaSignature != null && other.schemaSignature != null
          ? schemaSignature == other.schemaSignature
          : templateId == other.templateId && version == other.version;

  static HomeObservation? fromRow(Map<String, dynamic> row, {int? cycle}) {
    try {
      final type = row['questionnaire_type'];
      if (type != 'pre' && type != 'post') return null;
      final raw = row['responses'];
      final data = raw is String ? jsonDecode(raw) : raw;
      if (data is! Map || data['domain_scores'] is! Map) return null;
      final scores = <String, double>{};
      for (final domain in QuestionnaireDomain.values) {
        final value = (data['domain_scores'] as Map)[domain.key];
        if (value is num && value.isFinite && value >= 0 && value <= 100) {
          scores[domain.key] = value.toDouble();
        }
      }
      final date = DateTime.tryParse('${row['completed_at'] ?? ''}');
      final version = data['template_version'];
      final templateId = data['template_id'];
      if (scores.isEmpty ||
          date == null ||
          version is! int ||
          version < 1 ||
          templateId is! String ||
          templateId.isEmpty) {
        return null;
      }
      return HomeObservation(
        runId: '${row['assessment_run_id'] ?? ''}',
        type: type as String,
        completedAt: date,
        templateId: templateId,
        version: version,
        status: data['template_status'] == 'validated' ? 'validated' : 'draft',
        scores: scores,
        cycle: cycle,
        schemaSignature:
            data['schema_signature'] is String &&
                    (data['schema_signature'] as String).isNotEmpty
                ? data['schema_signature'] as String
                : null,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Only reports attached to the completed assessments being summarized.
/// Child/run identifiers and question wording never enter the provider payload.
class HomeObservationContext {
  const HomeObservationContext([this.observations = const []]);
  final List<HomeObservation> observations;
  bool get isEmpty => observations.isEmpty;

  static HomeObservationContext fromRows({
    required List<Map<String, dynamic>> rows,
    required List<HomeAssessmentLink> runs,
    String? childId,
    String? currentRunId,
  }) {
    final ordered = [...runs]
      ..sort((a, b) => a.completedAt.compareTo(b.completedAt));
    final links = <String, (String, int)>{};
    var cycle = 0;
    for (final run in ordered) {
      if (run.type != 'pre' && run.type != 'post') continue;
      if (run.type == 'pre' || cycle == 0) cycle++;
      links[run.id] = (run.type, cycle);
    }
    final current = currentRunId == null ? null : links[currentRunId];
    final chosen = <String, HomeObservation>{};
    for (final row in rows) {
      if (childId != null && row['child_id'] != childId) continue;
      final runId = '${row['assessment_run_id'] ?? ''}';
      final link = links[runId];
      if (link == null) continue;
      if (currentRunId != null &&
          (current == null ||
              (runId != currentRunId &&
                  !(current.$1 == 'post' &&
                      link.$1 == 'pre' &&
                      link.$2 == current.$2)))) {
        continue;
      }
      final observation = HomeObservation.fromRow(row, cycle: link.$2);
      if (observation == null || observation.type != link.$1) continue;
      if (chosen[runId] == null ||
          observation.completedAt.isAfter(chosen[runId]!.completedAt)) {
        chosen[runId] = observation;
      }
    }
    final records =
        chosen.values.toList()
          ..sort((a, b) => a.completedAt.compareTo(b.completedAt));
    // A skipped current questionnaire must not borrow a report from a prior run.
    if (currentRunId != null && !chosen.containsKey(currentRunId)) {
      return const HomeObservationContext();
    }
    return HomeObservationContext(records);
  }

  Map<String, dynamic> toPayload() {
    final groups = <String, String>{};
    final rows = <Map<String, dynamic>>[];
    for (final report in observations) {
      final group = groups.putIfAbsent(
        report.comparisonKey,
        () => 'set_${groups.length + 1}',
      );
      final earlier = observations.where(
        (other) =>
            other.type == 'pre' &&
            other.cycle == report.cycle &&
            other.completedAt.isBefore(report.completedAt),
      );
      final pre = earlier.isEmpty ? null : earlier.last;
      rows.add({
        'assessment_type': report.type,
        if (report.cycle != null) 'cycle': report.cycle,
        'completed_on': report.completedAt.toIso8601String().split('T').first,
        'question_set': group,
        'questionnaire_revision': report.version,
        'questionnaire_status': report.status,
        'comparable_to_pre':
            report.type == 'post' && pre != null && report.comparableTo(pre),
        'domain_frequencies': [
          for (final domain in QuestionnaireDomain.values)
            if (report.scores.containsKey(domain.key))
              {
                'name': domain.label,
                'frequency_pct': report.scores[domain.key],
              },
        ],
      });
    }
    return {
      'source': 'parent_reported_home_observations',
      'observations': rows,
    };
  }

  String get fallbackText {
    if (isEmpty) return '';
    final latest = observations.last;
    final areas = [
      for (final domain in QuestionnaireDomain.values)
        if (latest.scores.containsKey(domain.key))
          '${domain.label.toLowerCase()} ${latest.scores[domain.key]!.round()}/100',
    ];
    final date = latest.completedAt.toIso8601String().split('T').first;
    return 'In your home questionnaire on $date, you reported how often you '
        'observed these skills: ${areas.join(', ')}. These are parent-reported '
        'frequency ratings, separate from game scores.';
  }
}

class HomeObservationService {
  static final instance = HomeObservationService();

  Future<HomeObservationContext> forAssessment(
    String childId,
    String runId,
    String assessmentType,
  ) async {
    try {
      final rows = await localDbService.getCaregiverQuestionnaires(childId);
      final records = await localDbService.getAssessmentRuns(childId: childId);
      final runs = [
        for (final r in records)
          if (r.isCompleted)
            (id: r.id, type: r.type, completedAt: r.completedAt ?? r.startedAt),
      ];
      if (!runs.any((r) => r.id == runId && r.type == assessmentType)) {
        return const HomeObservationContext();
      }
      return HomeObservationContext.fromRows(
        rows: rows,
        runs: runs,
        childId: childId,
        currentRunId: runId,
      );
    } catch (_) {
      // Optional context cannot prevent a gameplay summary from appearing.
      return const HomeObservationContext();
    }
  }
}
