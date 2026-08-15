import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../core/child_profile_policy.dart';
import '../../model/child_profile.dart';
import '../../providers/child_provider.dart';
import '../rewards/widgets/reward_preference_selector.dart';
import 'widgets/settings_scaffold.dart';

/// Edits one child's profile — name, gender, birth date, avatar and reward
/// celebration.
///
/// Writes through [ChildProvider.editChild], which updates only this child's
/// record; siblings and the active-child selection are untouched. Birth dates
/// are validated exactly as in setup: anything plausible and not in the
/// future is accepted, with no 2–6 age restriction.
class ChildProfileEditScreen extends StatefulWidget {
  const ChildProfileEditScreen({super.key, required this.child});

  final ChildProfile child;

  @override
  State<ChildProfileEditScreen> createState() => _ChildProfileEditScreenState();
}

class _ChildProfileEditScreenState extends State<ChildProfileEditScreen> {
  static const avatars = ['🐻', '🐼', '🦊', '🐨', '🐸', '🦄', '🐙', '🐰'];

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController =
      TextEditingController(text: widget.child.displayName);

  late DateTime? _birthDate = widget.child.birthDate;
  late ChildSex? _sex = widget.child.sex;
  late String _avatar = widget.child.avatarEmoji;
  late RewardPreference _rewardPreference = widget.child.rewardPreference;
  late bool _useRandomReward = widget.child.useRandomReward;
  bool _isSaving = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickBirthDate() async {
    final today = DateTime.now();
    final initial = _birthDate ?? DateTime(today.year - 4, today.month, today.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isAfter(today) ? today : initial,
      // Plausible human dates only — the picker, not an age range, is the
      // limit (same rule as child setup).
      firstDate: DateTime(today.year - 100, today.month, today.day),
      lastDate: today,
      helpText: 'Select birth date',
    );
    if (picked != null && mounted) setState(() => _birthDate = picked);
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_sex == null) {
      _showError("Please select your child's gender.");
      return;
    }
    final validation = validateBirthDate(_birthDate);
    if (validation == ChildBirthDateValidation.missing) {
      _showError("Please select your child's birth date.");
      return;
    }
    if (validation == ChildBirthDateValidation.futureDate) {
      _showError('Birth date cannot be in the future.');
      return;
    }

    setState(() => _isSaving = true);
    try {
      await context.read<ChildProvider>().editChild(
            widget.child.id,
            displayName: _nameController.text.trim(),
            birthDate: _birthDate,
            avatar: _avatar,
            sex: _sex,
            rewardPreference: _rewardPreference,
            useRandomReward: _useRandomReward,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      _showError('Could not save the changes. Please try again.');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.destructiveRed,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.watch<ChildProvider>().activePalette;
    final birthDate = _birthDate;

    return SettingsScaffold(
      title: 'Edit ${widget.child.displayName}',
      icon: Icons.edit_rounded,
      palette: palette,
      children: [
        SettingsCard(
          children: [
            Form(
              key: _formKey,
              child: TextFormField(
                controller: _nameController,
                enabled: !_isSaving,
                textCapitalization: TextCapitalization.words,
                style: AppTextStyles.bodyMedium,
                decoration: const InputDecoration(
                  labelText: "Child's name",
                  prefixIcon: Icon(Icons.person_outline_rounded),
                ),
                validator: (value) =>
                    (value == null || value.trim().isEmpty)
                        ? "Please enter your child's name"
                        : null,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Birth Date',
              style: AppTextStyles.titleMedium
                  .copyWith(color: AppColors.foreground),
            ),
            const SizedBox(height: AppSpacing.xs),
            OutlinedButton.icon(
              key: const Key('edit-birth-date-button'),
              onPressed: _isSaving ? null : _pickBirthDate,
              icon: const Icon(Icons.calendar_month_rounded),
              label: Text(
                birthDate == null
                    ? 'Select birth date'
                    : '${birthDate.month}/${birthDate.day}/${birthDate.year} '
                        '· Age ${calculateAgeYears(birthDate)}',
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Gender',
              style: AppTextStyles.titleMedium
                  .copyWith(color: AppColors.foreground),
            ),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: 8,
              children: [
                for (final option in const [
                  (ChildSex.male, 'Boy'),
                  (ChildSex.female, 'Girl'),
                  (ChildSex.preferNotToSay, 'Prefer not to say'),
                ])
                  ChoiceChip(
                    label: Text(option.$2),
                    selected: _sex == option.$1,
                    selectedColor: AppColors.primaryPurple,
                    labelStyle: AppTextStyles.bodySmall.copyWith(
                      color: _sex == option.$1
                          ? AppColors.white
                          : AppColors.textPrimary,
                    ),
                    onSelected:
                        _isSaving ? null : (_) => setState(() => _sex = option.$1),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Avatar',
              style: AppTextStyles.titleMedium
                  .copyWith(color: AppColors.foreground),
            ),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final emoji in avatars)
                  GestureDetector(
                    onTap: _isSaving ? null : () => setState(() => _avatar = emoji),
                    child: Container(
                      width: 52,
                      height: 52,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.inputFill,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _avatar == emoji
                              ? AppColors.primaryPurple
                              : Colors.transparent,
                          width: 2.5,
                        ),
                      ),
                      child: Text(emoji, style: const TextStyle(fontSize: 26)),
                    ),
                  ),
              ],
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        SettingsCard(
          children: [
            RewardPreferenceSelector(
              selectedPreference: _rewardPreference,
              useRandomReward: _useRandomReward,
              onPreferenceChanged: (preference) =>
                  setState(() => _rewardPreference = preference),
              onRandomChanged: (useRandom) =>
                  setState(() => _useRandomReward = useRandom),
            ),
            const SizedBox(height: AppSpacing.sm),
            const SettingsHintText(
              'Theme, language, voice, difficulty and screen time follow '
              'whichever child is active — switch to this child to change '
              'them in Settings.',
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        AppPrimaryButton(
          label: 'Save Changes',
          onPressed: _isSaving ? null : _save,
          isLoading: _isSaving,
          autofocus: false,
        ),
      ],
    );
  }
}
