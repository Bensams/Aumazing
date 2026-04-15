import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:shared_ui/shared_ui.dart';

import '../../../core/services/auth_service.dart';
import '../../home/home_screen.dart';

class ChildProfileSetupScreen extends StatefulWidget {
  const ChildProfileSetupScreen({super.key});

  @override
  State<ChildProfileSetupScreen> createState() =>
      _ChildProfileSetupScreenState();
}

class _ChildProfileSetupScreenState extends State<ChildProfileSetupScreen> {
  final _authService = AuthService();
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _nameFocusNode = FocusNode();

  int? _selectedAge;
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
    if (_selectedAge == null) {
      _showError('Please select your child\'s age.');
      return;
    }

    setState(() => _isLoading = true);

    try {
      await _authService.saveChildProfile(
        name: _nameController.text.trim(),
        age: _selectedAge!,
        avatar: _avatars[_selectedAvatarIndex].emoji,
      );

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
          (_) => false,
        );
      }
    } catch (e) {
      _showError('Failed to save profile. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
              _buildAgeSelector(),
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
        _buildAgeSelector(),
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

  Widget _buildAgeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Age',
          style: AppTextStyles.titleMedium.copyWith(
            color: AppColors.foreground,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: List.generate(5, (index) {
            final age = index + 2;
            final isSelected = _selectedAge == age;

            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: index < 4 ? 8 : 0),
                child: Material(
                  color: isSelected
                      ? AppColors.primaryPurple
                      : AppColors.inputFill,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: _isLoading
                        ? null
                        : () {
                            _nameFocusNode.unfocus();
                            setState(() => _selectedAge = age);
                          },
                    child: Container(
                      height: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected
                              ? AppColors.primaryPurple
                              : AppColors.border,
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Text(
                        '$age',
                        style: AppTextStyles.titleLarge.copyWith(
                          color: isSelected
                              ? AppColors.white
                              : AppColors.foreground,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
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
