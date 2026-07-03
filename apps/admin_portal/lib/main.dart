import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/admin_shell.dart';
import 'screens/login_screen.dart';

/// Aumazing System Administrator Portal (Flutter Web).
///
/// Runs against the same Supabase project as the mobile app. Authorization
/// is enforced by the database: the `admin_users` allowlist + RLS policies
/// mean this portal is only a UI — a non-admin login can render buttons but
/// every privileged query fails server-side.
///
/// Run: flutter run -d chrome --dart-define-from-file=../main_app/env/dev.json
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  assert(
    supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty,
    'Missing backend config. Run with '
    '--dart-define-from-file=../main_app/env/dev.json',
  );

  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);

  runApp(const AdminPortalApp());
}

class AdminPortalApp extends StatelessWidget {
  const AdminPortalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Aumazing Admin',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF7E57C2),
        scaffoldBackgroundColor: const Color(0xFFFAF9F6),
      ),
      home: const _AuthGate(),
    );
  }
}

/// Shows the login screen until a session exists, then the admin shell.
class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = Supabase.instance.client.auth.currentSession;
        if (session == null) return const LoginScreen();
        return const AdminShell();
      },
    );
  }
}
