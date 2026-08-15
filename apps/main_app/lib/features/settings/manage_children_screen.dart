import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_audio/shared_audio.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../core/child_profile_policy.dart';
import '../../model/child_profile.dart';
import '../../providers/assessment_provider.dart';
import '../../providers/child_provider.dart';
import '../../providers/progress_provider.dart';
import '../../services/child_switch_service.dart';
import '../splash/auth/child_profile_setup_screen.dart';
import 'child_profile_edit_screen.dart';
import 'widgets/settings_scaffold.dart';

/// Parent-facing list of every child on the account.
///
/// Lives inside the protected parent area (Settings), and is where a parent
/// adds a sibling, switches who is playing, edits a profile or removes one.
/// Deleting additionally asks for parent verification and an explicit
/// confirmation, because it takes the child's progress with it.
class ManageChildrenScreen extends StatefulWidget {
  const ManageChildrenScreen({super.key});

  @override
  State<ManageChildrenScreen> createState() => _ManageChildrenScreenState();
}

class _ManageChildrenScreenState extends State<ManageChildrenScreen> {
  /// The child currently being switched to, so its row can show a spinner
  /// and the list cannot be double-tapped mid-switch.
  String? _busyChildId;

  @override
  Widget build(BuildContext context) {
    final childProv = context.watch<ChildProvider>();
    final children = childProv.children;

    return SettingsScaffold(
      title: 'Manage Children',
      icon: Icons.family_restroom_rounded,
      palette: childProv.activePalette,
      children: [
        if (children.isEmpty)
          const SettingsCard(
            children: [
              Text('No child profiles yet. Add your first child below.'),
            ],
          )
        else
          for (final child in children)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: _ChildRow(
                child: child,
                isActive: childProv.isActive(child.id),
                isBusy: _busyChildId == child.id,
                onSelect: () => _select(child),
                onEdit: () => _edit(child),
                onDelete: () => _confirmDelete(child),
              ),
            ),
        const SizedBox(height: AppSpacing.sm),
        AppPrimaryButton(
          key: const Key('add-child-button'),
          label: 'Add Child',
          onPressed: _busyChildId != null ? null : _addChild,
          autofocus: false,
        ),
        const SizedBox(height: AppSpacing.sm),
        const SettingsHintText(
          'Each child keeps their own assessment results, learning path, '
          'gameplay records, screen time and preferences.',
        ),
      ],
    );
  }

  // ── Actions ───────────────────────────────────────────────────────────

  Future<void> _select(ChildProfile child) async {
    final childProv = context.read<ChildProvider>();
    if (childProv.isActive(child.id) || _busyChildId != null) return;

    setState(() => _busyChildId = child.id);
    final switched = await switchActiveChild(
      childId: child.id,
      childProvider: childProv,
      assessmentProvider: context.read<AssessmentProvider>(),
      progressProvider: context.read<ProgressProvider>(),
      audioService: context.read<AudioService>(),
    );
    if (!mounted) return;
    setState(() => _busyChildId = null);
    if (switched) {
      _showMessage('${child.displayName} is now the active profile.');
    }
  }

  Future<void> _edit(ChildProfile child) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ChildProfileEditScreen(child: child)),
    );
  }

  Future<void> _addChild() async {
    final created = await Navigator.of(context).push<ChildProfile>(
      MaterialPageRoute(
        builder: (_) => const ChildProfileSetupScreen.addAnother(),
      ),
    );
    if (created == null || !mounted) return;
    _showMessage(
      '${created.displayName} was added. Tap their card to switch.',
    );
  }

  /// Parent verification, then a spelled-out confirmation, then the delete.
  Future<void> _confirmDelete(ChildProfile child) async {
    final verified = await ParentVerificationDialog.show(context);
    if (!verified || !mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete ${child.displayName}?'),
        content: Text(
          "This removes ${child.displayName}'s profile and all of their "
          'progress — assessment results, recommendations, learning path and '
          'gameplay records. This cannot be undone.',
          style: AppTextStyles.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('confirm-delete-child'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.destructiveRed,
            ),
            child: const Text('Delete Profile'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await _delete(child);
  }

  Future<void> _delete(ChildProfile child) async {
    final childProv = context.read<ChildProvider>();
    final assessmentProv = context.read<AssessmentProvider>();
    final progressProv = context.read<ProgressProvider>();
    final audioService = context.read<AudioService>();
    final navigator = Navigator.of(context);

    setState(() => _busyChildId = child.id);
    final outcome = await childProv.deleteChild(child.id);
    if (!mounted) return;
    setState(() => _busyChildId = null);

    switch (outcome) {
      case ChildDeletionOutcome.otherChildDeleted:
        _showMessage('${child.displayName} was deleted.');
      case ChildDeletionOutcome.switchedToAnotherChild:
        // The active child was deleted — rebuild everything around whichever
        // sibling took over, so no data of the removed child lingers.
        final replacement = childProv.profile!;
        assessmentProv.clear();
        progressProv.clear();
        await reloadChildScopedState(
          childId: replacement.id,
          childProvider: childProv,
          assessmentProvider: assessmentProv,
          progressProvider: progressProv,
          audioService: audioService,
        );
        if (!mounted) return;
        _showMessage(
          '${child.displayName} was deleted. '
          '${replacement.displayName} is now active.',
        );
      case ChildDeletionOutcome.noChildrenLeft:
        // Nothing left to show a dashboard for — back to setup.
        assessmentProv.clear();
        progressProv.clear();
        navigator.pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => const ChildProfileSetupScreen(),
          ),
          (_) => false,
        );
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

/// One child's card: avatar, name, birth date / age and what can be done
/// with the profile.
class _ChildRow extends StatelessWidget {
  const _ChildRow({
    required this.child,
    required this.isActive,
    required this.isBusy,
    required this.onSelect,
    required this.onEdit,
    required this.onDelete,
  });

  final ChildProfile child;
  final bool isActive;
  final bool isBusy;
  final VoidCallback onSelect;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final birthDate = child.birthDate;
    final subtitle = birthDate == null
        ? 'Birth date not set'
        : '${birthDate.month}/${birthDate.day}/${birthDate.year} · '
            'Age ${calculateAgeYears(birthDate)}';

    return Material(
      color: AppColors.white.withAlpha(240),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: isActive || isBusy ? null : onSelect,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isActive ? AppColors.primaryPurple : Colors.transparent,
              width: 2.5,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.lavenderLight,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  child.avatarEmoji,
                  style: const TextStyle(fontSize: 26),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            child.displayName,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.titleMedium.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        if (isActive) ...[
                          const SizedBox(width: AppSpacing.sm),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.primaryPurple,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              'Active',
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    if (!isActive)
                      Text(
                        'Tap to make active',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.primaryPurple,
                        ),
                      ),
                  ],
                ),
              ),
              if (isBusy)
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else ...[
                IconButton(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_rounded),
                  color: AppColors.primaryPurple,
                  tooltip: 'Edit ${child.displayName}',
                ),
                IconButton(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline_rounded),
                  color: AppColors.destructiveRed,
                  tooltip: 'Delete ${child.displayName}',
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
