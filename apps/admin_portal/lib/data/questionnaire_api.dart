import 'package:supabase_flutter/supabase_flutter.dart';

/// What the portal reads and writes for practitioners and questionnaire
/// templates (AUM-352). An interface so pages can be tested without a
/// backend.
///
/// The database is the real gate: row-level security lets an approved
/// practitioner write only their own templates, and a trigger stops anyone
/// but an admin activating or validating one — and takes a template out of
/// use when a practitioner rewords it.
abstract class QuestionnaireApi {
  /// The signed-in user's id.
  String? get userId;

  Future<bool> isAdmin();

  /// The signed-in user's practitioner row, or null if they never applied.
  Future<Map<String, dynamic>?> myPractitioner();

  Future<void> apply({
    required String fullName,
    required String profession,
    String? licenseNumber,
  });

  /// Every practitioner (admins only).
  Future<List<Map<String, dynamic>>> practitioners();

  Future<void> setPractitionerStatus(String userId, String status);

  /// The templates the caller may see: all for an admin, their own (and the
  /// active ones) for a practitioner.
  Future<List<Map<String, dynamic>>> templates();

  Future<void> insertTemplate(Map<String, dynamic> row);

  Future<void> updateTemplate(String id, Map<String, dynamic> fields);

  /// Admins only. Activating takes the template that was active for the
  /// same question set and assessment type out of use first.
  Future<void> setActive(Map<String, dynamic> template, bool active);

  /// Admins only: `draft` or `validated`.
  Future<void> setStatus(String id, String status);
}

class SupabaseQuestionnaireApi implements QuestionnaireApi {
  SupabaseQuestionnaireApi([SupabaseClient? client]) : _client = client;

  final SupabaseClient? _client;

  SupabaseClient get _db => _client ?? Supabase.instance.client;

  static const _templateColumns =
      'id, template_key, version, kind, questionnaire_type, title, intro, '
      'items, status, is_active, authored_by, activated_at, updated_at';

  @override
  String? get userId => _db.auth.currentUser?.id;

  @override
  Future<bool> isAdmin() async => await _db.rpc('is_admin') as bool? ?? false;

  @override
  Future<Map<String, dynamic>?> myPractitioner() async {
    final id = userId;
    if (id == null) return null;
    return _db.from('practitioners').select().eq('user_id', id).maybeSingle();
  }

  @override
  Future<void> apply({
    required String fullName,
    required String profession,
    String? licenseNumber,
  }) => _db.from('practitioners').insert({
    'user_id': userId,
    'full_name': fullName,
    'profession': profession,
    if (licenseNumber != null && licenseNumber.isNotEmpty)
      'license_number': licenseNumber,
  });

  @override
  Future<List<Map<String, dynamic>>> practitioners() async =>
      List<Map<String, dynamic>>.from(
        await _db
            .from('practitioners')
            .select()
            .order('created_at', ascending: false),
      );

  @override
  Future<void> setPractitionerStatus(String userId, String status) =>
      _db
          .from('practitioners')
          .update({
            'status': status,
            'approved_by': status == 'approved' ? this.userId : null,
            'approved_at':
                status == 'approved'
                    ? DateTime.now().toUtc().toIso8601String()
                    : null,
          })
          .eq('user_id', userId);

  @override
  Future<List<Map<String, dynamic>>> templates() async =>
      List<Map<String, dynamic>>.from(
        await _db
            .from('questionnaire_templates')
            .select(_templateColumns)
            .order('kind')
            .order('template_key')
            .order('version', ascending: false),
      );

  @override
  Future<void> insertTemplate(Map<String, dynamic> row) =>
      _db.from('questionnaire_templates').insert({
        ...row,
        'authored_by': userId,
      });

  @override
  Future<void> updateTemplate(String id, Map<String, dynamic> fields) =>
      _db.from('questionnaire_templates').update(fields).eq('id', id);

  @override
  Future<void> setActive(Map<String, dynamic> template, bool active) async {
    if (active) {
      await _db
          .from('questionnaire_templates')
          .update({'is_active': false})
          .eq('kind', template['kind'] ?? 'home')
          .eq('questionnaire_type', template['questionnaire_type'])
          .eq('is_active', true);
    }
    await _db
        .from('questionnaire_templates')
        .update({'is_active': active})
        .eq('id', template['id']);
  }

  @override
  Future<void> setStatus(String id, String status) => _db
      .from('questionnaire_templates')
      .update({'status': status})
      .eq('id', id);
}
