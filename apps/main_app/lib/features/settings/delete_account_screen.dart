import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../core/services/auth_service.dart';
import '../../core/services/local_db_service.dart';
import '../../core/utils/network_errors.dart';
import '../../providers/child_provider.dart';
import '../splash/auth/login_screen.dart';
import 'widgets/settings_scaffold.dart';

/// Delete this account and everything stored with it (AUM-147).
///
/// Deliberately a full screen rather than a dialog. Deletion is the one
/// action in the app that cannot be undone, so the parent gets room to read
/// what actually goes, and the confirmation is a deliberate act — parent
/// verification, then typing DELETE — rather than a button that could be
/// hit by a child handed the device, or by a mis-tap on the way to Sign Out.
class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({
    super.key,
    required this.palette,
    required this.authService,
    this.localDb,
    this.signedOutBuilder,
  });

  final GamePalette palette;
  final AuthService authService;

  /// Injectable so a test can prove local data is wiped without a database.
  final LocalDbService? localDb;

  /// Where the parent lands once the account is gone. Defaults to the login
  /// screen; injectable because that screen needs a live Supabase instance,
  /// which a widget test has no business standing up just to prove the
  /// deletion guards work.
  final WidgetBuilder? signedOutBuilder;

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  final _confirmController = TextEditingController();

  /// The word the parent types to confirm. Not localised on purpose: it is a
  /// literal match, and a translated variant would be a second thing to keep
  /// in step with the check below.
  static const _confirmWord = 'DELETE';

  bool _isDeleting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _confirmController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _confirmController.dispose();
    super.dispose();
  }

  bool get _confirmed =>
      _confirmController.text.trim().toUpperCase() == _confirmWord;

  Future<void> _delete() async {
    // Parent verification first: the child may be holding the device, and
    // this screen is reachable from settings like any other.
    final verified = await ParentVerificationDialog.show(context);
    if (!verified || !mounted) return;

    setState(() {
      _isDeleting = true;
      _errorMessage = null;
    });

    try {
      await widget.authService.deleteAccount();

      // The server-side account is gone; the device must not keep this
      // family's children, sessions or results behind for whoever signs in
      // next. Failing here is not a reason to claim deletion failed — the
      // account really is deleted — so it is logged and reported separately.
      var localWipeFailed = false;
      try {
        await (widget.localDb ?? localDbService).clearAll();
      } catch (e) {
        localWipeFailed = true;
        debugPrint('[DeleteAccount] local wipe failed: $e');
      }

      if (!mounted) return;
      _goToLogin(localWipeFailed: localWipeFailed);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isDeleting = false;
        _errorMessage = friendly(
          e,
          fallback:
              'We could not delete the account. Nothing has been '
              'removed — please try again.',
        );
      });
    }
  }

  void _goToLogin({required bool localWipeFailed}) {
    context.read<ChildProvider>().clear();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: widget.signedOutBuilder ?? (_) => const LoginScreen(),
      ),
      (_) => false,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          localWipeFailed
              ? 'Your account was deleted. Some data may remain on this '
                  'device until it is reinstalled.'
              : 'Your account and its data have been deleted.',
        ),
        backgroundColor: AppColors.mint,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SettingsScaffold(
      title: 'Delete Account',
      icon: Icons.delete_forever_rounded,
      palette: widget.palette,
      children: [
        SettingsCard(
          children: [
            Text(
              'This removes your account and everything saved with it.',
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            // Named plainly. A parent deciding this deserves to know what
            // goes, not a euphemism.
            ...const [
              'Every child profile on this account',
              'All assessment results and recommendations',
              'All gameplay history and progress',
              'Your settings and preferences',
            ].map(
              (line) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 3, right: 8),
                      child: Icon(
                        Icons.remove_circle_outline_rounded,
                        size: 16,
                        color: AppColors.statusDangerDark,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        line,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'This cannot be undone, and the data cannot be recovered '
              'afterwards.',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.statusDangerDark,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        SettingsCard(
          children: [
            Text(
              'Type $_confirmWord to confirm',
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              key: const Key('deleteAccount.confirmField'),
              controller: _confirmController,
              enabled: !_isDeleting,
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                hintText: _confirmWord,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                _errorMessage!,
                key: const Key('deleteAccount.error'),
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.statusDangerDark,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                key: const Key('deleteAccount.submit'),
                // Disabled until the word matches, so the destructive action
                // is never one stray tap away.
                onPressed: (_confirmed && !_isDeleting) ? _delete : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.statusDangerDark,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child:
                    _isDeleting
                        ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                        : const Text('Delete my account'),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed:
                    _isDeleting ? null : () => Navigator.of(context).pop(),
                child: const Text('Keep my account'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
