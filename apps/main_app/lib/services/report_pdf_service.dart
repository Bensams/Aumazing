import 'dart:io';
import 'dart:typed_data';

import 'package:game_core/game_core.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:shared_ui/shared_ui.dart';

import '../features/history/history_models.dart';

typedef ReportDirectoryProvider = Future<Directory> Function();
typedef ReportShareCallback =
    Future<ShareResult> Function(
      List<XFile> files, {
      String? subject,
      String? text,
    });

/// The generated, local-only report artifact.
///
/// [plainText] and [sectionTitles] come from the same immutable definition as
/// [bytes]. They make content, ordering, and privacy assertions possible
/// without coupling tests to PDF stream encoding.
class ReportPdfData {
  const ReportPdfData({
    required this.filename,
    required this.bytes,
    required this.plainText,
    required this.sectionTitles,
  });

  final String filename;
  final Uint8List bytes;
  final String plainText;
  final List<String> sectionTitles;
}

/// Contract used by parent-facing screens, allowing share behavior to be
/// tested without filesystem or platform-channel effects.
abstract interface class ReportPdfSharer {
  Future<void> shareAssessmentReport({
    required AssessmentResultViewModel model,
    required String childDisplayName,
  });

  Future<void> shareHistoryReport({
    required HistorySummary summary,
    required String childDisplayName,
  });
}

/// Builds structured A4 parent reports and shares a temporary local PDF.
///
/// Document generation is pure with respect to app data: callers hand in the
/// already-rendered assessment model or already-loaded history snapshot. Only
/// the `share*` methods touch the filesystem/platform share sheet.
class ReportPdfService implements ReportPdfSharer {
  ReportPdfService({
    ReportDirectoryProvider? temporaryDirectoryProvider,
    ReportShareCallback? shareCallback,
    DateTime Function()? now,
  }) : _temporaryDirectoryProvider =
           temporaryDirectoryProvider ?? getTemporaryDirectory,
       _shareCallback = shareCallback ?? Share.shareXFiles,
       _now = now ?? DateTime.now;

  static const disclaimer = AssessmentLabels.disclaimer;

  final ReportDirectoryProvider _temporaryDirectoryProvider;
  final ReportShareCallback _shareCallback;
  final DateTime Function() _now;

  Future<ReportPdfData> buildAssessmentReport({
    required AssessmentResultViewModel model,
    required String childDisplayName,
    DateTime? generatedAt,
  }) async {
    final generated = generatedAt ?? _now();
    final isPost = model.assessmentType == 'post';
    final title = isPost ? 'Post-Assessment Report' : 'Pre-Assessment Report';
    final completed = model.completedAt;
    final sections = <_ReportSection>[
      _ReportSection(
        title: AssessmentLabels.overallPerformance,
        lines: [
          'Adjusted accuracy: ${model.overallPercent}%',
          'Performance: ${_performanceLabel(model.overallPercent)}',
          'Correct: ${model.correctCount}',
          'Errors: ${model.errorCount}',
          'Total items: ${model.totalItems}',
          if (model.confidencePercent != null)
            'Confidence: ${model.confidencePercent}%',
          if (model.summary.trim().isNotEmpty) model.summary.trim(),
        ],
      ),
      if (model.overallProgress != null)
        _ReportSection(
          title: AssessmentLabels.overallProgress,
          lines: _overallProgressLines(model.overallProgress!),
        ),
      if (model.hasProgress)
        _ReportSection(
          title: AssessmentLabels.progressSinceFirst,
          lines: [model.progress!.headline],
          headers: const ['Skill area', 'Before', 'After', 'Change'],
          rows: [
            for (final area in model.progress!.areas)
              [
                area.label,
                area.beforeLevelName,
                area.afterLevelName,
                area.improved
                    ? 'Moved up'
                    : area.steady
                    ? 'Held steady'
                    : 'More practice here',
              ],
          ],
        ),
      if (model.hasAreas || model.sensoryObservations.isNotEmpty)
        _ReportSection(
          title: AssessmentLabels.developmentalProfile,
          lines: [
            if (model.profileDisplayName?.isNotEmpty == true)
              'Profile: ${model.profileDisplayName}',
          ],
          headers: const ['Area', 'Finalized observation'],
          rows: [
            for (final row in model.profileRows) [row.area, row.level],
          ],
        ),
      if (model.games.isNotEmpty)
        _ReportSection(
          title: AssessmentLabels.gameResults,
          headers: const [
            'Game',
            'Adjusted accuracy',
            'Correct',
            'Errors',
            'Off-target',
            'Total items',
          ],
          rows: [
            for (final game in model.games)
              [
                game.name,
                '${AssessmentScoring.percent(game.accuracy)}%',
                '${game.correctCount}',
                '${game.errorCount}',
                '${game.offTargetCount}',
                '${game.totalItems}',
              ],
          ],
        ),
      if (model.recommendations.isNotEmpty)
        _ReportSection(
          title: AssessmentLabels.recommendedSettings,
          headers: const ['Setting', 'Recommendation'],
          rows: [
            for (final recommendation in model.recommendations)
              [recommendation.label, recommendation.value],
          ],
        ),
      if (model.hasLearningPath ||
          model.learningPathUnavailable ||
          model.premiumRequired)
        _ReportSection(
          title: AssessmentLabels.recommendedActivities,
          lines: [
            if (model.premiumRequired)
              'Premium is required to generate the next personalized module. '
                  'Upgrade to keep building a learning path tailored to your child.'
            else if (model.learningPathUnavailable)
              'No activities available right now - please contact your administrator.',
          ],
          headers:
              model.hasLearningPath &&
                      !model.premiumRequired &&
                      !model.learningPathUnavailable
                  ? const ['Activity', 'Starting level', 'Why it comes next']
                  : const [],
          rows: [
            for (final module in model.learningPath)
              if (!model.premiumRequired && !model.learningPathUnavailable)
                [
                  module.name,
                  'Level ${module.startingLevel}',
                  module.reason ?? '',
                ],
          ],
        ),
      const _ReportSection(title: 'Important information', lines: [disclaimer]),
    ];

    return _build(
      title: title,
      childDisplayName: childDisplayName,
      reportDateLabel: 'Completion date',
      reportDate: completed,
      generatedAt: generated,
      metadata: ['Analysis source: ${model.source.label}'],
      filenameType: isPost ? 'post-assessment' : 'pre-assessment',
      sections: sections,
    );
  }

  Future<ReportPdfData> buildHistoryReport({
    required HistorySummary summary,
    required String childDisplayName,
    DateTime? generatedAt,
  }) async {
    final generated = generatedAt ?? _now();
    final assessmentSections = <_ReportSection>[
      if (summary.runs.isEmpty)
        const _ReportSection(
          title: 'Assessment History',
          lines: [
            'No assessments yet. Complete a pre-assessment to see results here.',
          ],
        )
      else ...[
        const _ReportSection(title: 'Assessment History'),
        for (final run in summary.runs) _historyRunSection(run),
      ],
    ];
    final comparison = summary.comparison;
    final sections = <_ReportSection>[
      ...assessmentSections,
      if (comparison != null)
        _ReportSection(
          title: 'Progress Comparison',
          lines: [
            '${_signed(comparison.overallDeltaPoints.round())} points overall',
          ],
          headers: const ['Skill area', 'Before', 'After'],
          rows: [
            for (final area in comparison.areas)
              [area.area, area.before ?? '-', area.after ?? '-'],
          ],
        ),
      _ReportSection(
        title: 'Completed My Path & Modules',
        lines:
            summary.completedModules.isEmpty
                ? const ['No completed modules yet.']
                : const [],
        headers:
            summary.completedModules.isEmpty
                ? const []
                : const ['Module', 'Status', 'Completed', 'Progress'],
        rows: [
          for (final module in summary.completedModules)
            [
              module.moduleName,
              _statusLabel(module.status),
              module.completedAt == null
                  ? '-'
                  : _formatDate(module.completedAt!),
              if (module.level > 0)
                'Level ${module.level} of ${module.maxLevel}'
              else if (module.source == 'my_path' && module.gameCount > 0)
                '${module.gameCount} ${module.gameCount == 1 ? 'game' : 'games'} on the path'
              else
                '-',
            ],
        ],
      ),
      _ReportSection(
        title: 'Practice History',
        lines:
            summary.practiceSessions.isEmpty
                ? const ['No practice sessions yet.']
                : [
                  if (summary.practiceSessions.length == 20)
                    'Showing the latest 20 sessions.',
                ],
        headers:
            summary.practiceSessions.isEmpty
                ? const []
                : const ['Game', 'Score', 'Date'],
        rows: [
          for (final session in summary.practiceSessions)
            [
              _gameName(session.gameId),
              '${session.score}',
              _formatDate(session.endedAt),
            ],
        ],
      ),
      const _ReportSection(title: 'Important information', lines: [disclaimer]),
    ];

    return _build(
      title: 'History & Progress Report',
      childDisplayName: childDisplayName,
      reportDateLabel: 'Report date',
      reportDate: generated,
      generatedAt: generated,
      metadata: const [],
      filenameType: 'history-progress',
      sections: sections,
    );
  }

  @override
  Future<void> shareAssessmentReport({
    required AssessmentResultViewModel model,
    required String childDisplayName,
  }) async {
    final report = await buildAssessmentReport(
      model: model,
      childDisplayName: childDisplayName,
    );
    await _writeAndShare(report);
  }

  @override
  Future<void> shareHistoryReport({
    required HistorySummary summary,
    required String childDisplayName,
  }) async {
    final report = await buildHistoryReport(
      summary: summary,
      childDisplayName: childDisplayName,
    );
    await _writeAndShare(report);
  }

  Future<void> _writeAndShare(ReportPdfData report) async {
    final directory = await _temporaryDirectoryProvider();
    final file = File(
      '${directory.path}${Platform.pathSeparator}${report.filename}',
    );
    await file.writeAsBytes(report.bytes, flush: true);
    await _shareCallback(
      [XFile(file.path, mimeType: 'application/pdf')],
      subject: 'Aumazing parent report',
      text: 'Aumazing parent report for ${_subjectName(report.plainText)}.',
    );
  }

  Future<ReportPdfData> _build({
    required String title,
    required String childDisplayName,
    required String reportDateLabel,
    required DateTime? reportDate,
    required DateTime generatedAt,
    required List<String> metadata,
    required String filenameType,
    required List<_ReportSection> sections,
  }) async {
    final header = [
      title,
      'Child: $childDisplayName',
      '$reportDateLabel: ${reportDate == null ? 'Not recorded' : _formatDate(reportDate)}',
      'Generated: ${_formatDateTime(generatedAt)}',
      ...metadata,
    ];
    final definition = _ReportDefinition(header: header, sections: sections);
    final document = pw.Document();
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 40, 36, 40),
        footer:
            (context) => pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Aumazing', style: const pw.TextStyle(fontSize: 8)),
                pw.Text(
                  'Page ${context.pageNumber} of ${context.pagesCount}',
                  style: const pw.TextStyle(fontSize: 8),
                ),
              ],
            ),
        build:
            (_) => [
              pw.Text(
                _pdfSafe(title),
                style: pw.TextStyle(
                  fontSize: 24,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 8),
              for (final line in header.skip(1)) pw.Text(_pdfSafe(line)),
              pw.SizedBox(height: 14),
              for (final section in sections) ..._sectionWidgets(section),
            ],
      ),
    );
    final bytes = await document.save();
    return ReportPdfData(
      filename: safeFilename(
        reportType: filenameType,
        childDisplayName: childDisplayName,
        date: reportDate ?? generatedAt,
      ),
      bytes: bytes,
      plainText: definition.plainText,
      sectionTitles: [for (final section in sections) section.title],
    );
  }

  static List<pw.Widget> _sectionWidgets(_ReportSection section) {
    final hasTable = section.headers.isNotEmpty && section.rows.isNotEmpty;
    final keepWholeTable = hasTable && section.rows.length <= 10;
    final lead = <pw.Widget>[
      pw.Header(level: 1, text: _pdfSafe(section.title)),
      for (final line in section.lines) ...[
        pw.Text(_pdfSafe(line)),
        pw.SizedBox(height: 4),
      ],
      if (keepWholeTable)
        _table(section.headers, section.rows)
      else if (hasTable)
        _table(section.headers, [section.rows.first]),
    ];
    return [
      // Keep the heading with actual content. Remaining rows stay spanning so
      // a long assessment/history table can still cross page boundaries.
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: lead,
      ),
      if (hasTable && !keepWholeTable && section.rows.length > 1)
        _table(section.headers, section.rows.skip(1).toList()),
    ];
  }

  static pw.Widget _table(List<String> headers, List<List<String>> rows) =>
      pw.TableHelper.fromTextArray(
        headers: headers.map(_pdfSafe).toList(),
        data: [for (final row in rows) row.map(_pdfSafe).toList()],
        headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
        cellStyle: const pw.TextStyle(fontSize: 8),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey100),
        cellAlignment: pw.Alignment.centerLeft,
        cellPadding: const pw.EdgeInsets.all(5),
      );

  static _ReportSection _historyRunSection(AssessmentRunHistory history) {
    final run = history.run;
    final date = run.completedAt ?? run.startedAt;
    return _ReportSection(
      title:
          '${run.type == 'pre' ? 'Pre-assessment' : 'Post-assessment'} - ${_formatDate(date)}',
      lines: [
        'Status: ${_statusLabel(run.status)}',
        if (history.skills.isNotEmpty)
          'Skills: ${history.skills.map((skill) => '${skill.area}: ${skill.label}').join('; ')}',
        if (history.recommendedModule != null)
          'Recommended: ${history.recommendedModule}',
        if (history.overallSummary != null) history.overallSummary!,
      ],
      headers:
          history.games.isEmpty
              ? const []
              : const ['Game', 'Score', 'Total', 'Adjusted accuracy', 'Errors'],
      rows: [
        for (final game in history.games)
          [
            game.gameName,
            '${game.score}',
            game.totalItems > 0 ? '${game.totalItems}' : '-',
            game.totalItems > 0 ? '${(game.accuracy * 100).round()}%' : '-',
            game.totalItems > 0 ? '${game.errorCount}' : '-',
          ],
      ],
    );
  }

  static List<String> _overallProgressLines(ResultOverallProgress progress) {
    final accuracy = (progress.accuracyDelta * 100).round();
    final lines = <String>[
      if (accuracy > 0)
        'Accuracy improved by $accuracy percentage points since the pre-assessment.'
      else if (accuracy == 0)
        'Accuracy held steady since the pre-assessment.'
      else
        'Accuracy changed by $accuracy percentage points - every child progresses at their own pace.',
    ];
    if (progress.responseTimeDeltaMs.abs() >= 100) {
      lines.add(
        progress.responseTimeDeltaMs > 0
            ? 'Responses are ${(progress.responseTimeDeltaMs / 1000).toStringAsFixed(1)}s faster on average.'
            : 'Responses take a little longer - often a sign of more careful choices.',
      );
    }
    return lines;
  }

  static String safeFilename({
    required String reportType,
    required String childDisplayName,
    required DateTime date,
  }) {
    String slug(String value, String fallback) {
      final safe = value
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
          .replaceAll(RegExp(r'^-+|-+$'), '');
      if (safe.isEmpty) return fallback;
      return safe.length <= 48 ? safe : safe.substring(0, 48);
    }

    return 'aumazing_${slug(reportType, 'report')}_${slug(childDisplayName, 'child')}_${_dateStamp(date)}.pdf';
  }

  static String _performanceLabel(int percent) {
    if (percent >= 80) return 'Strong';
    if (percent >= 50) return 'Steady';
    return 'Needs practice';
  }

  static String _statusLabel(String status) {
    switch (status) {
      case 'completed':
        return 'Completed';
      case 'in_progress':
        return 'In progress';
      default:
        return 'Incomplete';
    }
  }

  static String _gameName(String gameId) {
    final entry = GameRegistry.find(gameId);
    if (entry != null) return entry.name;
    final words = gameId.replaceAll('_', ' ').trim();
    if (words.isEmpty) return 'Practice game';
    return words[0].toUpperCase() + words.substring(1);
  }

  static String _signed(int value) => value > 0 ? '+$value' : '$value';

  /// The package's built-in offline font is WinAnsi. Normalize the common
  /// punctuation emitted by app copy so local generation never needs a font
  /// download. Latin display names (including Filipino diacritics) remain
  /// intact; unsupported scripts are replaced visibly instead of disappearing.
  static String _pdfSafe(String value) => value
      .replaceAll('\u2018', "'")
      .replaceAll('\u2019', "'")
      .replaceAll('\u201c', '"')
      .replaceAll('\u201d', '"')
      .replaceAll('\u2013', '-')
      .replaceAll('\u2014', '-')
      .replaceAll('\u2192', '->')
      .replaceAll(RegExp(r'[^\x09\x0A\x0D\x20-\x7E\xA0-\xFF]'), '?');

  static String _subjectName(String plainText) {
    for (final line in plainText.split('\n')) {
      if (line.startsWith('Child: ')) return line.substring('Child: '.length);
    }
    return 'your child';
  }

  static String _dateStamp(DateTime date) {
    final local = date.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }

  static String _formatDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final local = date.toLocal();
    return '${months[local.month - 1]} ${local.day}, ${local.year}';
  }

  static String _formatDateTime(DateTime date) {
    final local = date.toLocal();
    final hour =
        local.hour == 0 ? 12 : (local.hour > 12 ? local.hour - 12 : local.hour);
    final minute = local.minute.toString().padLeft(2, '0');
    final period = local.hour >= 12 ? 'PM' : 'AM';
    return '${_formatDate(local)}, $hour:$minute $period';
  }
}

class _ReportDefinition {
  const _ReportDefinition({required this.header, required this.sections});

  final List<String> header;
  final List<_ReportSection> sections;

  String get plainText => [
    ...header,
    for (final section in sections) ...[
      section.title,
      ...section.lines,
      if (section.headers.isNotEmpty) section.headers.join(' | '),
      for (final row in section.rows) row.join(' | '),
    ],
  ].join('\n');
}

class _ReportSection {
  const _ReportSection({
    required this.title,
    this.lines = const [],
    this.headers = const [],
    this.rows = const [],
  });

  final String title;
  final List<String> lines;
  final List<String> headers;
  final List<List<String>> rows;
}
