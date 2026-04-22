import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_audio/shared_audio.dart';

import 'package:shared_ui/shared_ui.dart';

import '../../../core/child_profile_policy.dart';
import '../../../core/repositories/child_repository.dart';
import '../../home/home_screen.dart';

class ChildProfileSetupScreen extends StatefulWidget {
  const ChildProfileSetupScreen({
    super.key,
    this.initialErrorMessage,
    ChildRepository? childRepository,
  }) : _childRepository = childRepository;

  final String? initialErrorMessage;
  final ChildRepository? _childRepository;

  @override
  State<ChildProfileSetupScreen> createState() =>
      _ChildProfileSetupScreenState();
}

class _ChildProfileSetupScreenState extends State<ChildProfileSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _nameFocusNode = FocusNode();
  DateTime? _selectedBirthDate;
  int _selectedAvatarIndex = 0;
  bool _isLoading = false;

  static const _avatars = [
    _AvatarOption('🐻', 'Bear', Color(0xFFE8DEFA)),
    _AvatarOption('🐼', 'Panda', Color(0xFFD4F4E8)),
    _AvatarOption('🦊', 'Fox', Color(0xFFFFE8DD)),
    _AvatarOption('🐨', 'Koala', Color(0xFFD4E8FA)),
    _AvatarOption('🐸', 'Frog', Color(0xFFD4F4E8)),
    _AvatarOption('🦄', 'Unicorn', Color(0xFFE8DEFA)),
    _AvatarOption('🐙', 'Octopus', Color(0xFFFFE8DD)),
    _AvatarOption('🐰', 'Bunny', Color(0xFFFFF9DD)),
  ];

  @override
  void initState() {
    super.initState();
    lockParentLandscape();
    // Restore normal system overlays — the splash screen leaves the app
    // in edgeToEdge / immersiveSticky mode which causes Android's gesture
    // navigation to overlap app content and produce phantom touch events.
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final message = widget.initialErrorMessage;
      if (message != null && message.isNotEmpty) {
        _showError(message);
      }
    });
  }

  @override
  void dispose() {
    unlockParentOrientation();
    _nameFocusNode.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    final validation = validateBirthDate(_selectedBirthDate);
    if (validation == ChildBirthDateValidation.missing) {
      _showError('Please select your child\'s birth date.');
      return;
    }
    if (validation == ChildBirthDateValidation.futureDate) {
      _showError('Birth date cannot be in the future.');
      return;
    }
    if (validation != ChildBirthDateValidation.valid) {
      _showError('Aumazing currently supports children ages 2 to 6.');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final repository = widget._childRepository ?? childRepository;
      await repository.createChild(
        displayName: _nameController.text.trim(),
        birthDate: _selectedBirthDate!,
        avatar: _avatars[_selectedAvatarIndex].emoji,
      );

      if (mounted) {
        // Log audio state before navigation
        final audioService = context.read<AudioService>();
        debugPrint('[ChildProfileSetupScreen] Before navigation: isMusicPlaying=${audioService.isMusicPlaying}');

        // Use PageRouteBuilder for smoother transition that won't interrupt audio
        Navigator.of(context).pushAndRemoveUntil(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const HomeScreen(),
            transitionsBuilder: (_, animation, __, child) {
              return FadeTransition(opacity: animation, child: child);
            },
            transitionDuration: const Duration(milliseconds: 400),
          ),
          (_) => false,
        );
      }
    } catch (e) {
      _showError('Failed to save profile. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickBirthDate() async {
    // Hide keyboard to prevent overflow issues
    FocusScope.of(context).unfocus();
    await Future.delayed(const Duration(milliseconds: 100));

    final today = DateTime.now();
    final initialDate =
        _selectedBirthDate ?? DateTime(today.year - 4, today.month, today.day);
    final firstDate = DateTime(today.year - 10, today.month, today.day);
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDate.isAfter(today) ? today : initialDate,
      firstDate: firstDate,
      lastDate: today,
      helpText: 'Select birth date',
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: MediaQuery.of(context).padding.copyWith(bottom: 0),
          ),
          child: child!,
        );
      },
    );

    if (pickedDate != null && mounted) {
      setState(() => _selectedBirthDate = pickedDate);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.destructiveSoftRed,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    // PopScope prevents the system back gesture from exiting the app.
    return PopScope(
      canPop: false,
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        body: GestureDetector(
          // Dismiss the keyboard when tapping empty space.
          onTap: () => _nameFocusNode.unfocus(),
          behavior: HitTestBehavior.translucent,
          child: Container(
            decoration:
                const BoxDecoration(gradient: AppGradients.parentSkyButter),
            child: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final useSideBySide =
                      constraints.maxWidth >= constraints.maxHeight;

                  return SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: AppSpacing.horizontalLg.copyWith(
                      bottom:
                          bottomInset > 0 ? bottomInset + 16 : AppSpacing.lg,
                    ),
                    child: useSideBySide
                        ? _buildLandscapeTwoColumn()
                        : _buildPortraitColumn(),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Side-by-side in landscape: name + age on the left, avatars + CTA on the
  /// right so taps are not stacked in a short vertical band.
  Widget _buildLandscapeTwoColumn() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 5,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(compact: true),
              const SizedBox(height: AppSpacing.lg),
              _buildForm(),
              const SizedBox(height: AppSpacing.xl),
              _buildBirthDateSelector(),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.lg),
        Expanded(
          flex: 5,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: AppSpacing.sm),
              _buildAvatarPicker(),
              const SizedBox(height: AppSpacing.xl),
              AppPrimaryButton(
                label: 'Continue to Dashboard',
                onPressed: _isLoading ? null : _saveProfile,
                isLoading: _isLoading,
                autofocus: false,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPortraitColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.md),
        _buildHeader(compact: false),
        const SizedBox(height: AppSpacing.xl),
        _buildForm(),
        const SizedBox(height: AppSpacing.xl),
        _buildBirthDateSelector(),
        const SizedBox(height: AppSpacing.xl),
        _buildAvatarPicker(),
        const SizedBox(height: AppSpacing.xl),
        AppPrimaryButton(
          label: 'Continue to Dashboard',
          onPressed: _isLoading ? null : _saveProfile,
          isLoading: _isLoading,
          autofocus: false,
        ),
        const SizedBox(height: AppSpacing.xxl),
      ],
    );
  }

  Widget _buildHeader({required bool compact}) {
    return Center(
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.all(compact ? 12 : 16),
            decoration: const BoxDecoration(
              color: AppColors.lavenderLight,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.child_care_rounded,
              size: compact ? 40 : 48,
              color: AppColors.primaryPurple,
            ),
          ),
          SizedBox(height: compact ? AppSpacing.sm : AppSpacing.md),
          Text(
            'Tell us about your child',
            textAlign: TextAlign.center,
            style: AppTextStyles.headlineLarge.copyWith(
              color: AppColors.primaryPurple,
              fontSize: compact ? 20 : null,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            "We'll use this to personalize their learning experience",
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.mutedForeground,
              fontSize: compact ? 13 : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Child's Name",
            style: AppTextStyles.titleMedium.copyWith(
              color: AppColors.foreground,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          TextFormField(
            controller: _nameController,
            focusNode: _nameFocusNode,
            enabled: !_isLoading,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _saveProfile(),
            style: AppTextStyles.bodyMedium,
            scrollPadding: const EdgeInsets.only(bottom: 120),
            decoration: InputDecoration(
              hintText: 'Enter name',
              hintStyle: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.mutedForeground,
              ),
              prefixIcon: const Icon(
                Icons.person_outline_rounded,
                size: 20,
                color: AppColors.mutedForeground,
              ),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 16,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: AppColors.primaryPurple,
                  width: 1.5,
                ),
              ),
              filled: true,
              fillColor: AppColors.inputFill,
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please enter your child\'s name';
              }
              return null;
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBirthDateSelector() {
    final selectedBirthDate = _selectedBirthDate;
    final validation = validateBirthDate(selectedBirthDate);
    final ageLabel =
        selectedBirthDate == null
            ? 'Select birth date'
            : 'Age ${calculateAgeYears(selectedBirthDate)}';
    final helperText =
        validation == ChildBirthDateValidation.futureDate
            ? 'Birth date cannot be in the future.'
            : validation == ChildBirthDateValidation.tooYoung ||
                validation == ChildBirthDateValidation.tooOld
            ? 'Aumazing currently supports children ages 2 to 6.'
            : selectedBirthDate != null
            ? '${selectedBirthDate.month}/${selectedBirthDate.day}/${selectedBirthDate.year}'
            : 'Choose a date between ages 2 and 6.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Birth Date',
          style: AppTextStyles.titleMedium.copyWith(
            color: AppColors.foreground,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Material(
          color: AppColors.inputFill,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            key: const Key('birth-date-button'),
            borderRadius: BorderRadius.circular(12),
            onTap: _isLoading ? null : _pickBirthDate,
            child: Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.calendar_month_rounded,
                    color: AppColors.mutedForeground,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      ageLabel,
                      style: AppTextStyles.titleMedium.copyWith(
                        color:
                            selectedBirthDate == null
                                ? AppColors.mutedForeground
                                : AppColors.foreground,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.mutedForeground,
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          helperText,
          style: AppTextStyles.bodySmall.copyWith(
            color:
                validation == ChildBirthDateValidation.valid ||
                        validation == ChildBirthDateValidation.missing
                    ? AppColors.mutedForeground
                    : AppColors.destructiveSoftRed,
          ),
        ),
      ],
    );
  }

  Widget _buildAvatarPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Choose an Avatar',
          style: AppTextStyles.titleMedium.copyWith(
            color: AppColors.foreground,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        LayoutBuilder(
          builder: (context, constraints) {
            const spacing = 10.0;
            const columns = 4;
            final maxW = constraints.maxWidth;
            final cellW = (maxW - spacing * (columns - 1)) / columns;
            final cellH = cellW / 1.3;

            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: List.generate(_avatars.length, (index) {
                final avatar = _avatars[index];
                final isSelected = _selectedAvatarIndex == index;

                return SizedBox(
                  width: cellW,
                  height: cellH,
                  child: _AvatarCell(
                    key: ValueKey<int>(index),
                    avatar: avatar,
                    selected: isSelected,
                    onTap: _isLoading
                        ? null
                        : () {
                            _nameFocusNode.unfocus();
                            setState(() => _selectedAvatarIndex = index);
                          },
                  ),
                );
              }),
            );
          },
        ),
      ],
    );
  }
}

class _AvatarCell extends StatelessWidget {
  const _AvatarCell({
    super.key,
    required this.avatar,
    required this.selected,
    required this.onTap,
  });

  final _AvatarOption avatar;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? avatar.bgColor.withValues(alpha: 0.7)
          : AppColors.inputFill,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? AppColors.primaryPurple.withValues(alpha: 0.5)
                  : Colors.transparent,
              width: 2.5,
            ),
          ),
          child: Center(
            child: Text(
              avatar.emoji,
              style: TextStyle(
                fontSize: selected ? 30 : 28,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AvatarOption {
  final String emoji;
  final String label;
  final Color bgColor;

  const _AvatarOption(this.emoji, this.label, this.bgColor);
}
