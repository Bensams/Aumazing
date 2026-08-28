import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/admin_auth.dart';

/// Email/password and Google OAuth login for administrators.
///
/// Any Supabase account can sign in, but only accounts on the
/// `admin_users` allowlist can read or change anything — the shell checks
/// membership and signs non-admins straight back out. Google does not
/// bypass that allowlist.
class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    this.auth,
    this.oauthRedirectTo,
    this.currentUri,
  });

  /// Test seam. Production uses [SupabaseAdminAuth].
  final AdminAuth? auth;

  /// Override for tests. Production uses [adminPortalOAuthRedirectTo].
  final String? oauthRedirectTo;

  /// Override for tests. Production uses [Uri.base].
  final Uri? currentUri;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

enum _Busy { none, password, google }

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  _Busy _busy = _Busy.none;
  String? _error;

  AdminAuth get _auth => widget.auth ?? SupabaseAdminAuth();

  Uri get _currentUri => widget.currentUri ?? Uri.base;

  bool get _loading => _busy != _Busy.none;

  @override
  void initState() {
    super.initState();
    _error = oauthErrorFromUri(_currentUri);
  }

  Future<void> _signIn() async {
    setState(() {
      _busy = _Busy.password;
      _error = null;
    });
    try {
      await _auth.signInWithPassword(
        email: _email.text.trim(),
        password: _password.text,
      );
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Sign-in failed. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = _Busy.none);
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _busy = _Busy.google;
      _error = null;
    });
    try {
      final redirectTo =
          widget.oauthRedirectTo ?? adminPortalOAuthRedirectTo(_currentUri);
      final launched = await _auth.signInWithGoogle(redirectTo: redirectTo);
      if (!launched && mounted) {
        setState(
          () => _error = 'Could not open Google sign-in. Please try again.',
        );
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Google sign-in failed. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = _Busy.none);
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Card(
            margin: const EdgeInsets.all(24),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.admin_panel_settings_rounded,
                    size: 48,
                    color: Color(0xFF7E57C2),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Aumazing Admin',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _email,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.username],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      border: OutlineInputBorder(),
                    ),
                    obscureText: true,
                    autofillHints: const [AutofillHints.password],
                    onSubmitted: (_) => _signIn(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      key: const Key('admin-login-error'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    key: const Key('admin-email-sign-in'),
                    onPressed: _loading ? null : _signIn,
                    child: _busy == _Busy.password
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Sign In'),
                  ),
                  const SizedBox(height: 16),
                  const Row(
                    children: [
                      Expanded(child: Divider()),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Text('or'),
                      ),
                      Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    key: const Key('admin-google-sign-in'),
                    onPressed: _loading ? null : _signInWithGoogle,
                    child: _busy == _Busy.google
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Continue with Google'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
