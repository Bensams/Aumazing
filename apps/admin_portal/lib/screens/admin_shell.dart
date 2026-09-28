import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/questionnaire_api.dart';
import '../pages/audit_page.dart';
import '../pages/beta_page.dart';
import '../pages/centers_page.dart';
import '../pages/dashboard_page.dart';
import '../pages/modules_page.dart';
import '../pages/payments_page.dart';
import '../pages/practitioners_page.dart';
import '../pages/questionnaires_page.dart';
import '../pages/rubric_page.dart';
import '../pages/users_page.dart';
import 'practitioner_access_screen.dart';

/// Main portal layout. Works out who is signed in, then shows:
/// - an **administrator** every section, including practitioners and
///   questionnaires;
/// - an **approved practitioner** the questionnaires they write (AUM-352);
/// - anyone else the practitioner application, or its status.
///
/// These checks only decide what is shown. The database's row-level
/// security and `is_admin()` are the real enforcement.
class AdminShell extends StatefulWidget {
  const AdminShell({super.key, this.api, this.onSignOut});

  /// Injectable for tests; the app talks to Supabase.
  final QuestionnaireApi? api;
  final Future<void> Function()? onSignOut;

  @override
  State<AdminShell> createState() => _AdminShellState();
}

enum _Access { checking, admin, practitioner, other }

class _Section {
  const _Section(this.icon, this.label, this.page);

  final IconData icon;
  final String label;
  final Widget page;
}

class _AdminShellState extends State<AdminShell> {
  late final QuestionnaireApi _api = widget.api ?? SupabaseQuestionnaireApi();
  int _index = 0;
  _Access _access = _Access.checking;
  Map<String, dynamic>? _application;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    setState(() => _access = _Access.checking);
    var access = _Access.other;
    Map<String, dynamic>? application;
    try {
      if (await _api.isAdmin()) {
        access = _Access.admin;
      } else {
        application = await _api.myPractitioner();
        if (application?['status'] == 'approved') {
          access = _Access.practitioner;
        }
      }
    } catch (_) {
      access = _Access.other;
    }
    if (!mounted) return;
    setState(() {
      _access = access;
      _application = application;
      _index = 0;
    });
  }

  Future<void> _signOut() =>
      (widget.onSignOut ?? Supabase.instance.client.auth.signOut)();

  List<_Section> get _sections => switch (_access) {
    _Access.admin => [
      const _Section(Icons.dashboard_rounded, 'Dashboard', DashboardPage()),
      const _Section(Icons.science_rounded, 'Beta Review', BetaPage()),
      const _Section(Icons.people_rounded, 'Accounts', UsersPage()),
      const _Section(Icons.extension_rounded, 'Games', ModulesPage()),
      const _Section(Icons.local_hospital_rounded, 'Centers', CentersPage()),
      const _Section(Icons.tune_rounded, 'Rubric', RubricPage()),
      _Section(
        Icons.quiz_rounded,
        'Questionnaires',
        QuestionnairesPage(api: _api, isAdmin: true),
      ),
      _Section(
        Icons.badge_rounded,
        'Practitioners',
        PractitionersPage(api: _api),
      ),
      const _Section(Icons.receipt_long_rounded, 'Audit Log', AuditPage()),
      const _Section(Icons.payments_rounded, 'Payments', PaymentsPage()),
    ],
    _Access.practitioner => [
      _Section(
        Icons.quiz_rounded,
        'Questionnaires',
        QuestionnairesPage(api: _api, isAdmin: false),
      ),
    ],
    _ => const [],
  };

  @override
  Widget build(BuildContext context) {
    if (_access == _Access.checking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_access == _Access.other) {
      return PractitionerAccessScreen(
        api: _api,
        application: _application,
        onApplied: _check,
        onSignOut: _signOut,
      );
    }

    final sections = _sections;
    final practitioner = _access == _Access.practitioner;
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            labelType: NavigationRailLabelType.all,
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Tooltip(
                message: practitioner ? 'Practitioner' : 'Administrator',
                child: Icon(
                  practitioner
                      ? Icons.medical_services_rounded
                      : Icons.admin_panel_settings_rounded,
                  color: const Color(0xFF7E57C2),
                  size: 32,
                ),
              ),
            ),
            trailing: Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: IconButton(
                    onPressed: _signOut,
                    icon: const Icon(Icons.logout_rounded),
                    tooltip: 'Sign out',
                  ),
                ),
              ),
            ),
            destinations: [
              for (final s in sections)
                NavigationRailDestination(
                  icon: Icon(s.icon),
                  label: Text(s.label),
                ),
              // A rail needs at least two destinations; a practitioner's
              // second one is their application details.
              if (sections.length < 2)
                const NavigationRailDestination(
                  icon: Icon(Icons.badge_rounded),
                  label: Text('My details'),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: _index < sections.length
                ? sections[_index].page
                : _MyDetails(application: _application),
          ),
        ],
      ),
    );
  }
}

class _MyDetails extends StatelessWidget {
  const _MyDetails({required this.application});

  final Map<String, dynamic>? application;

  @override
  Widget build(BuildContext context) {
    final a = application ?? const {};
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('My details', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          Text('${a['full_name'] ?? ''}'),
          Text('${a['profession'] ?? ''}'),
          Text('Licence: ${a['license_number'] ?? 'not given'}'),
          const SizedBox(height: 8),
          const Text('Approved practitioner'),
          const SizedBox(height: 16),
          const Text(
            'To change these details, contact an Aumazing administrator.',
          ),
        ],
      ),
    );
  }
}
