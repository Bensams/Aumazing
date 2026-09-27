import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'parent_questionnaire.dart';

/// Fetches the active template rows for an assessment type. Injectable so a
/// test can stand in for the backend.
typedef TemplateFetcher =
    Future<List<Map<String, dynamic>>> Function(String questionnaireType);

/// Which parent questionnaire to show (AUM-344).
///
/// An approved practitioner authors templates and an admin activates one
/// (`questionnaire_templates`). This picks the active template for the
/// assessment, keeps the last one seen for offline use, and falls back to
/// the bundled draft whenever nothing usable is available — the
/// questionnaire must never fail to open because a network or a template
/// was bad.
class QuestionnaireTemplateRepository {
  QuestionnaireTemplateRepository({TemplateFetcher? fetcher, this.timeout})
    : _fetcher = fetcher;

  static final QuestionnaireTemplateRepository instance =
      QuestionnaireTemplateRepository();

  final TemplateFetcher? _fetcher;

  /// How long the parent waits for the backend before the cached or bundled
  /// template is used. The hand-off must not stall on a slow connection.
  final Duration? timeout;

  static const _defaultTimeout = Duration(seconds: 3);

  static String _cacheKey(String type) => 'questionnaire_template_$type';

  /// The template to show before (`pre`) or after (`post`) an assessment.
  Future<QuestionnaireTemplate> templateFor(String questionnaireType) async {
    try {
      final rows = await (_fetcher ?? _fetchRemote)(
        questionnaireType,
      ).timeout(timeout ?? _defaultTimeout);
      final row = pickActive(rows, questionnaireType);
      final parsed = row == null ? null : parse(row);
      if (parsed != null) {
        await _cache(questionnaireType, row!);
        return parsed;
      }
      if (row == null) {
        // Nothing active: the practitioner template was withdrawn, so the
        // bundled draft applies again rather than a stale cached copy.
        await _clearCache(questionnaireType);
        return kParentQuestionnaireDraft;
      }
    } catch (e) {
      debugPrint('[QuestionnaireTemplates] remote unavailable: $e');
      final cached = await _cached(questionnaireType);
      if (cached != null) return cached;
    }
    return kParentQuestionnaireDraft;
  }

  static Future<List<Map<String, dynamic>>> _fetchRemote(String type) async {
    final rows = await Supabase.instance.client
        .from('questionnaire_templates')
        .select(
          'template_key, version, questionnaire_type, title, intro, items, '
          'status',
        )
        .eq('is_active', true)
        .inFilter('questionnaire_type', [type, 'both']);
    return List<Map<String, dynamic>>.from(rows);
  }

  /// The active row for [type]: one made for that type wins over a `both`.
  @visibleForTesting
  static Map<String, dynamic>? pickActive(
    List<Map<String, dynamic>> rows,
    String type,
  ) {
    for (final row in rows) {
      if (row['questionnaire_type'] == type) return row;
    }
    for (final row in rows) {
      if (row['questionnaire_type'] == 'both') return row;
    }
    return null;
  }

  /// A template from a stored row, or null when it would not work: unknown
  /// domains, duplicate or missing ids, or a domain with no items (which
  /// would leave that domain without a score).
  @visibleForTesting
  static QuestionnaireTemplate? parse(Map<String, dynamic> row) {
    try {
      final rawItems = row['items'] is String
          ? jsonDecode(row['items'] as String)
          : row['items'];
      if (rawItems is! List) return null;
      final byKey = {for (final d in QuestionnaireDomain.values) d.key: d};
      final items = <QuestionnaireItem>[];
      final ids = <String>{};
      for (final raw in rawItems) {
        if (raw is! Map) return null;
        final id = raw['id'];
        final text = raw['text'];
        final domain = byKey[raw['domain']];
        if (id is! String || id.isEmpty || text is! String || text.isEmpty) {
          return null;
        }
        if (domain == null || !ids.add(id)) return null;
        items.add(QuestionnaireItem(id: id, domain: domain, text: text));
      }
      for (final domain in QuestionnaireDomain.values) {
        if (!items.any((i) => i.domain == domain)) return null;
      }
      final key = row['template_key'];
      final title = row['title'];
      if (key is! String || title is! String) return null;
      return QuestionnaireTemplate(
        id: key,
        version: (row['version'] as num?)?.toInt() ?? 1,
        status: row['status'] == 'validated' ? 'validated' : 'draft',
        title: title,
        intro: (row['intro'] as String?) ?? '',
        items: items,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _cache(String type, Map<String, dynamic> row) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey(type), jsonEncode(row));
    } catch (_) {}
  }

  Future<void> _clearCache(String type) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cacheKey(type));
    } catch (_) {}
  }

  Future<QuestionnaireTemplate?> _cached(String type) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey(type));
      if (raw == null) return null;
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? parse(decoded) : null;
    } catch (_) {
      return null;
    }
  }
}
