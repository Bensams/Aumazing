import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../pages/audit_page.dart';
import '../pages/centers_page.dart';
import '../pages/dashboard_page.dart';
import '../pages/modules_page.dart';

/// Main admin layout: verifies allowlist membership, then shows a
/// navigation rail with the portal's sections.
class AdminShell extends StatefulWidget {
  const AdminShell({super.key});

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int _index = 0;
  bool? _isAdmin; // null while checking

  static const _pages = [
    DashboardPage(),
    ModulesPage(),
    CentersPage(),
    AuditPage(),
  ];

  @override
  void initState() {
    super.initState();
    _checkAdmin();
  }

  /// Membership check against the allowlist. RLS is the real enforcement —
  /// this just avoids showing a UI where every action would fail.
  Future<void> _checkAdmin() async {
    try {
      final isAdmin =
          await Supabase.instance.client.rpc('is_admin') as bool? ?? false;
      if (mounted) setState(() => _isAdmin = isAdmin);
    } catch (_) {
      if (mounted) setState(() => _isAdmin = false);
    }
  }

  Future<void> _signOut() => Supabase.instance.client.auth.signOut();

  @override
  Widget build(BuildContext context) {
    if (_isAdmin == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_isAdmin == false) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.block_rounded, size: 48, color: Colors.grey),
              const SizedBox(height: 12),
              const Text('This account is not an administrator.'),
              const SizedBox(height: 12),
              TextButton(onPressed: _signOut, child: const Text('Sign out')),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            labelType: NavigationRailLabelType.all,
            leading: const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Icon(Icons.admin_panel_settings_rounded,
                  color: Color(0xFF7E57C2), size: 32),
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
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.dashboard_rounded),
                label: Text('Dashboard'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.extension_rounded),
                label: Text('Games'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.local_hospital_rounded),
                label: Text('Centers'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.receipt_long_rounded),
                label: Text('Audit Log'),
              ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: _pages[_index]),
        ],
      ),
    );
  }
}
