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
  Object? startupError;
  if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
    startupError = const FormatException(
      'Missing SUPABASE_URL or SUPABASE_ANON_KEY dart-define.',
    );
  } else {
    try {
      await Supabase.initialize(
        url: supabaseUrl,
        anonKey: supabaseAnonKey,
        authOptions: const FlutterAuthClientOptions(
          // Render the app before handling an OAuth callback so a failed
          // PKCE exchange cannot leave the browser on a blank page.
          detectSessionInUri: false,
        ),
      );
    } catch (error) {
      startupError = error;
    }
  }

  runApp(AdminPortalApp(startupError: startupError));
}

class AdminPortalApp extends StatelessWidget {
  const AdminPortalApp({super.key, this.startupError});

  final Object? startupError;

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
      home: startupError == null
          ? const _OAuthCallbackGate()
          : StartupErrorScreen(error: startupError!),
    );
  }
}

class _OAuthCallbackGate extends StatefulWidget {
  const _OAuthCallbackGate();

  @override
  State<_OAuthCallbackGate> createState() => _OAuthCallbackGateState();
}

class _OAuthCallbackGateState extends State<_OAuthCallbackGate> {
  Object? _callbackError;
  bool _handlingCallback = false;

  @override
  void initState() {
    super.initState();
    final code = Uri.base.queryParameters['code'];
    if (code != null && code.isNotEmpty) {
      _exchangeCode(code);
    }
  }

  Future<void> _exchangeCode(String code) async {
    setState(() => _handlingCallback = true);
    try {
      await Supabase.instance.client.auth
          .exchangeCodeForSession(code)
          .timeout(const Duration(seconds: 15));
    } catch (error) {
      if (mounted) setState(() => _callbackError = error);
    } finally {
      if (mounted) setState(() => _handlingCallback = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_handlingCallback) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_callbackError != null) {
      return StartupErrorScreen(error: _callbackError!);
    }
    return const _AuthGate();
  }
}

class StartupErrorScreen extends StatelessWidget {
  const StartupErrorScreen({required this.error, super.key});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.warning_amber_rounded, size: 42),
                    const SizedBox(height: 16),
                    Text(
                      'Admin portal could not start',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Check the Supabase URL/key dart-defines and the browser console, then reload.',
                    ),
                    const SizedBox(height: 16),
                    SelectableText(error.toString()),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
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
