import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../../core/services/local_db_service.dart';
import '../../model/gameplay_session.dart';

/// Creates a portable, de-identified copy of the active child's gameplay.
///
/// CSV is intended for teacher/panel review. JSON preserves the schema and
/// metadata needed by the training pipeline. Neither format contains the
/// child's name or database identifier. PDF is a human-readable summary only;
/// CSV and JSON remain the machine-learning source files.
class GameplayExportService {
  GameplayExportService({LocalDbService? localDb})
      : _localDb = localDb ?? LocalDbService();

  final LocalDbService _localDb;

  static const schemaVersion = '1.0';

  Future<List<File>> exportAndShare({required String childId}) async {
    final sessions = await _localDb.getGameSessions(childId: childId);
    final directory = await getTemporaryDirectory();
    final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');
    final participantId = _participantId(childId);
    final base = 'aumazing_gameplay_${participantId}_$stamp';

    final csvFile = File('${directory.path}/$base.csv');
    final jsonFile = File('${directory.path}/$base.json');
    final pdfFile = File('${directory.path}/$base.pdf');
    await csvFile.writeAsString(_csv(participantId, sessions));
    await jsonFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'schema_version': schemaVersion,
        'exported_at_utc': 'EXPORT_TIME',
        'participant_id': 'PARTICIPANT_ID',
        'sessions': 'SESSIONS',
      }).replaceFirst('"EXPORT_TIME"',
          '"${DateTime.now().toUtc().toIso8601String()}"')
          .replaceFirst('"PARTICIPANT_ID"', '"$participantId"')
          .replaceFirst('"SESSIONS"',
              jsonEncode(sessions.map((s) => _sessionMap(participantId, s)).toList())),
    );
    await pdfFile.writeAsBytes(await _pdf(participantId, sessions));

    await Share.shareXFiles(
      [
        XFile(csvFile.path, mimeType: 'text/csv'),
        XFile(jsonFile.path, mimeType: 'application/json'),
        XFile(pdfFile.path, mimeType: 'application/pdf'),
      ],
      subject: 'Aumazing gameplay export and summary',
      text: 'Aumazing export. The PDF is a human-readable summary; CSV and JSON are the data files.',
    );
    return [csvFile, jsonFile, pdfFile];
  }

  Future<List<int>> _pdf(String participantId, List<GameplaySession> sessions) async {
    final document = pw.Document();
    final totalScore = sessions.fold<int>(0, (sum, session) => sum + session.score);
    final totalItems = sessions.fold<int>(0, (sum, session) => sum + session.totalItems);
    final accuracy = totalItems == 0 ? 0.0 : totalScore / totalItems * 100;
    final byGame = <String, List<GameplaySession>>{};
    for (final session in sessions) {
      byGame.putIfAbsent(session.gameId, () => []).add(session);
    }

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text('Aumazing | Page ${context.pageNumber}', style: const pw.TextStyle(fontSize: 8)),
        ),
        build: (context) => [
          pw.Header(level: 0, child: pw.Text('Aumazing Gameplay Summary')),
          pw.Text('Participant code: $participantId'),
          pw.Text('Generated: ${DateTime.now().toUtc().toIso8601String()}'),
          pw.SizedBox(height: 16),
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.blueGrey)),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('Summary', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.Text('Completed game sessions: ${sessions.length}'),
              pw.Text('Total items: $totalItems'),
              pw.Text('Total score: $totalScore'),
              pw.Text('Overall item accuracy: ${accuracy.toStringAsFixed(1)}%'),
            ]),
          ),
          pw.SizedBox(height: 18),
          pw.Text('Results by game', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          if (byGame.isEmpty)
            pw.Text('No completed gameplay sessions were found.')
          else
            pw.TableHelper.fromTextArray(
              headers: const ['Game', 'Sessions', 'Items', 'Score', 'Accuracy'],
              data: byGame.entries.map((entry) {
                final items = entry.value.fold<int>(0, (sum, session) => sum + session.totalItems);
                final score = entry.value.fold<int>(0, (sum, session) => sum + session.score);
                final percent = items == 0 ? 0.0 : score / items * 100;
                return [entry.key, '${entry.value.length}', '$items', '$score', '${percent.toStringAsFixed(1)}%'];
              }).toList(),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              cellStyle: const pw.TextStyle(fontSize: 9),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey100),
            ),
          pw.SizedBox(height: 20),
          pw.Text('Important information', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.Bullet(text: 'This document is a gameplay summary for parents or educators.'),
          pw.Bullet(text: 'It is not a clinical assessment and does not diagnose autism or any other condition.'),
          pw.Bullet(text: 'CSV and JSON files contain the de-identified records intended for approved analysis.'),
          pw.Bullet(text: 'Interpret results with a qualified SPED teacher or other appropriate professional.'),
        ],
      ),
    );
    return document.save();
  }

  String _participantId(String childId) =>
      'AUM-${sha256.convert(utf8.encode(childId)).toString().substring(0, 10).toUpperCase()}';

  Map<String, dynamic> _sessionMap(String participantId, GameplaySession s) {
    final map = s.toMap();
    map.remove('child_id');
    map['participant_id'] = participantId;
    final assessmentRunId = map['assessment_run_id'] as String?;
    if (assessmentRunId != null && assessmentRunId.isNotEmpty) {
      map['assessment_run_id'] =
          'R-${sha256.convert(utf8.encode(assessmentRunId)).toString().substring(0, 12).toUpperCase()}';
    }
    map['session_id'] = 'S-${sha256.convert(utf8.encode(s.id)).toString().substring(0, 12).toUpperCase()}';
    map.remove('id');
    map['started_at'] = _relativeTimestamp(s.startedAt, s.startedAt);
    map['ended_at'] = _relativeTimestamp(s.endedAt, s.startedAt);
    return map;
  }

  String _relativeTimestamp(DateTime value, DateTime start) =>
      value.difference(start).inMilliseconds.toString();

  String _csv(String participantId, List<GameplaySession> sessions) {
    const columns = [
      'participant_id', 'session_id', 'assessment_run_id', 'game_id', 'context',
      'score', 'total_items', 'error_count', 'total_response_time_ms',
      'retry_count', 'hint_count', 'prompt_count', 'idle_time_seconds',
      'random_touch_count', 'avg_response_time', 'avg_valid_response_time',
      'off_task_action_count', 'improvement_score', 'consistency_score',
      'task_completion_rate', 'prompt_dependency_score',
      'turn_taking_success_rate', 'interruption_count',
      'waiting_tolerance_seconds', 'time_to_first_touch',
      'time_to_first_valid_action', 'time_to_completion', 'sensory_condition',
      'started_at_relative_ms', 'ended_at_relative_ms',
    ];
    final rows = <String>[columns.join(',')];
    for (final session in sessions) {
      final map = _sessionMap(participantId, session);
      map['started_at_relative_ms'] = '0';
      map['ended_at_relative_ms'] = session.endedAt.difference(session.startedAt).inMilliseconds;
      rows.add(columns.map((column) => _csvCell(map[column])).join(','));
    }
    return '${rows.join('\n')}\n';
  }

  String _csvCell(Object? value) {
    final text = value?.toString() ?? '';
    return '"${text.replaceAll('"', '""')}"';
  }
}
