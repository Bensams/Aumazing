import 'package:flutter/material.dart';

import '../data/questionnaire_api.dart';

/// What a signed-in account that is neither an administrator nor an approved
/// practitioner sees (AUM-352): the application form, or where their
/// application stands.
class PractitionerAccessScreen extends StatefulWidget {
  const PractitionerAccessScreen({
    super.key,
    required this.api,
    required this.application,
    required this.onApplied,
    required this.onSignOut,
  });

  final QuestionnaireApi api;

  /// Their `practitioners` row, or null if they have not applied.
  final Map<String, dynamic>? application;

  /// Called after a successful application, to re-check access.
  final VoidCallback onApplied;
  final VoidCallback onSignOut;

  @override
  State<PractitionerAccessScreen> createState() =>
      _PractitionerAccessScreenState();
}

class _PractitionerAccessScreenState extends State<PractitionerAccessScreen> {
  final _name = TextEditingController();
  final _profession = TextEditingController();
  final _license = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _profession.dispose();
    _license.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    if (_name.text.trim().isEmpty || _profession.text.trim().isEmpty) {
      setState(() => _error = 'Enter your full name and profession.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.api.apply(
        fullName: _name.text.trim(),
        profession: _profession.text.trim(),
        licenseNumber: _license.text.trim(),
      );
      widget.onApplied();
    } catch (e) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = 'Could not send your application: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.application?['status'];
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    switch (status) {
                      'pending' => 'Your application is being reviewed',
                      'revoked' => 'Practitioner access is not available',
                      _ => 'Apply as a practitioner',
                    },
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  if (status == 'pending')
                    const Text(
                      'An administrator will check your details and licence. '
                      'Sign in again once you have been approved to write '
                      'questionnaires.',
                      key: Key('access.pending'),
                    )
                  else if (status == 'revoked')
                    const Text(
                      'This account cannot write questionnaires. Contact the '
                      'Aumazing team if you think this is a mistake.',
                      key: Key('access.revoked'),
                    )
                  else ...[
                    const Text(
                      'Therapists and SPED teachers can write the questions '
                      'parents and teachers answer before and after a child\'s '
                      'assessment. An administrator reviews every application.',
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      key: const Key('access.name'),
                      controller: _name,
                      decoration: const InputDecoration(
                        labelText: 'Full name',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('access.profession'),
                      controller: _profession,
                      decoration: const InputDecoration(
                        labelText: 'Profession (e.g. SPED teacher, OT, SLP)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('access.license'),
                      controller: _license,
                      decoration: const InputDecoration(
                        labelText: 'PRC licence number (if any)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    FilledButton(
                      key: const Key('access.apply'),
                      onPressed: _sending ? null : _apply,
                      child: Text(_sending ? 'Sending…' : 'Send application'),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: widget.onSignOut,
                    child: const Text('Sign out'),
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
