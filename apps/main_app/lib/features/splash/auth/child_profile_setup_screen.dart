import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_audio/shared_audio.dart';

import 'package:shared_ui/shared_ui.dart';

import '../../../core/child_profile_policy.dart';
import '../../../model/child_profile.dart';
import '../../../providers/child_provider.dart';
import '../../../services/screen_time_service.dart';
import '../../home/home_screen.dart';
import '../../rewards/widgets/reward_preference_selector.dart';
import 'widgets/sound_preferences_step.dart';
import '../../stars/star_catalogue.dart';
import '../../stars/widgets/character_picker.dart';

/// Collects a child's profile, sound preferences and reward settings.
///
/// Serves two flows with the same fields and validation:
/// * onboarding — the parent's first child, ending on the dashboard;
/// * "Add Child" from Manage Children ([isAdditionalChild]), which returns
///   the new profile to the caller and leaves the active child alone.
class ChildProfileSetupScreen extends StatefulWidget {
  const ChildProfileSetupScreen({
    super.key,
    this.initialErrorMessage,
    this.isAdditionalChild = false,
  });

  /// Adds another child to an account that already has one: the screen can be
  /// dismissed, and saving pops with the created [ChildProfile] instead of
  /// replacing the navigation stack with the dashboard.
  const ChildProfileSetupScreen.addAnother({super.key})
      : initialErrorMessage = null,
        isAdditionalChild = true;

  final String? initialErrorMessage;
  final bool isAdditionalChild;

  @override
  State<ChildProfileSetupScreen> createState() =>
      _ChildProfileSetupScreenState();
}

class _ChildProfileSetupScreenState extends State<ChildProfileSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _nameFocusNode = FocusNode();
  final _scrollController = ScrollController();
  DateTime? _selectedBirthDate;
  int _selectedAvatarIndex = 0;
  ChildSex? _selectedSex;
  /// Null until the parent chooses. Never defaulted, because a
  /// preselected card is a recommendation whether or not it is labelled
  /// as one (STAR-A1).
  ChildCharacter? _selectedCharacter;
  bool _isLoading = false;

  // Setup step tracking
  int _currentStep = 0; // 0: basic info, 1: sound & voice, 2: rewards & limits
  static const _stepCount = 3;

  /// Language, voice, music and prompt choices made on step 1.
  SoundPreferences _sound = SoundPreferences.initial();

  // Reward preference state
  RewardPreference _selectedRewardPreference = RewardPreference.bubbles;
  bool _useRandomReward = false;

  // Daily screen-time limit (minutes); null = off. Pre-filled with the
  // age-based recommendation once the birth date is known.
  int? _screenTimeLimitMinutes;
  bool _screenTimeTouched = false;
  static const _screenTimeOptions = [15, 20, 30, 45, 60, 90];

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
    lockParentAdaptive();
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
    _scrollController.dispose();
    _nameFocusNode.dispose();
    _nameController.dispose();
    super.dispose();
  }

  /// The last step saves and leaves — to the dashboard during onboarding, or
  /// back to Manage Children when a sibling is being added.
  String get _finalStepLabel =>
      widget.isAdditionalChild ? 'Save Child Profile' : 'Continue to Dashboard';

  Future<void> _saveProfile() async {
    // Only validate form if we're still on step 0 (form is mounted)
    // On step 1, validation already happened in _goToNextStep()
    if (_currentStep == 0 && !(_formKey.currentState?.validate() ?? false)) return;
    
    // Checked in the order the fields are shown, so the error names the
    // first thing missing down the page rather than jumping past it.
    if (_selectedSex == null) {
      _showError("Please select your child's gender.");
      return;
    }
    final validation = validateBirthDate(_selectedBirthDate);
    if (validation == ChildBirthDateValidation.missing) {
      _showError('Please select your child\'s birth date.');
      return;
    }
    if (validation == ChildBirthDateValidation.futureDate) {
      _showError('Birth date cannot be in the future.');
      return;
    }
    // Ages outside 2–6 are allowed at initialization (no age-range limit).

    setState(() => _isLoading = true);

    try {
      final childProvider = context.read<ChildProvider>();
      final previousActiveChildId = childProvider.activeChildId;
      // Adding a second child never takes over the session — the parent
      // switches deliberately from Manage Children.
      final profile = await childProvider.addChild(
        makeActive: !widget.isAdditionalChild,
        displayName: _nameController.text.trim(),
        birthDate: _selectedBirthDate!,
        avatar: _avatars[_selectedAvatarIndex].emoji,
        sex: _selectedSex,
        // Skipping picks at random rather than defaulting: a fixed
        // fallback would quietly make one character 'the normal one'.
        characterId: (_selectedCharacter ??
                (ChildCharacter.values..shuffle()).first)
            .id,
        musicEnabled: _sound.musicEnabled,
        musicVolume: _sound.musicVolume,
        musicCategory: _sound.musicCategory,
        sfxVolume: _sound.sfxVolume,
        vibrationEnabled: _sound.vibrationEnabled,
        promptSpeed: _sound.promptSpeed,
        // The parent has just chosen music, effects, vibration and prompt
        // speed here, so the pre-assessment does not ask for them again.
        sensoryPreferencesSet: true,
        rewardPreference: _selectedRewardPreference,
        useRandomReward: _useRandomReward,
      );

      // Language and voice live in local prefs keyed by child id, so they can
      // only be written once the child record exists.
      await childProvider.applyInitialPreferences(
        childId: profile.id,
        language: _sound.language,
        voicePackId: _sound.voicePackId,
      );
      await childProvider.setShowTextPrompts(_sound.showTextPrompts);

      // Save the daily screen-time limit chosen during setup (can be
      // changed later in Settings → Screen Time).
      await ScreenTimeService.instance.load(profile.id);
      await ScreenTimeService.instance
          .setLimitMinutes(_screenTimeLimitMinutes);
      // The service holds one child at a time — hand it back to the child
      // still playing, so an added sibling's limit is not applied to them.
      if (widget.isAdditionalChild && previousActiveChildId != null) {
        await ScreenTimeService.instance.load(previousActiveChildId);
      }

      if (widget.isAdditionalChild) {
        if (mounted) Navigator.of(context).pop(profile);
        return;
      }

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
    final currentContext = context;
    FocusScope.of(currentContext).unfocus();
    await Future.delayed(const Duration(milliseconds: 100));

    final today = DateTime.now();
    final initialDate =
        _selectedBirthDate ?? DateTime(today.year - 4, today.month, today.day);
    // No age range is enforced at setup, so the picker only has to stay
    // within plausible human dates rather than a 2–6 year window.
    final firstDate = DateTime(today.year - 100, today.month, today.day);
    if (!mounted) return;
    final pickedDate = await showDatePicker(
      context: currentContext,
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

  /// Moves to [step] and returns the scroll view to the top so the new step's
  /// header is what the parent sees, not the middle of the previous page.
  void _setStep(int step) {
    _nameFocusNode.unfocus();
    setState(() => _currentStep = step);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.jumpTo(0);
    });
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
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    // During onboarding PopScope stops the system back gesture exiting the
    // app; when adding a sibling the parent may back out to Manage Children.
    return PopScope(
      canPop: widget.isAdditionalChild,
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        extendBodyBehindAppBar: true,
        appBar: widget.isAdditionalChild
            ? AppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                foregroundColor: AppColors.primaryPurple,
                title: Text(
                  'Add Child',
                  style: AppTextStyles.titleMedium.copyWith(
                    color: AppColors.primaryPurple,
                  ),
                ),
              )
            : null,
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
                    controller: _scrollController,
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
    if (_currentStep == 1) {
      // Sound & voice step in landscape
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildSoundStepHeader(),
                const SizedBox(height: AppSpacing.md),
                TextButton(
                  onPressed: () => _setStep(0),
                  child: const Text('Go Back'),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            flex: 6,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SoundPreferencesStep(
                  value: _sound,
                  onChanged: (value) => setState(() => _sound = value),
                ),
                const SizedBox(height: AppSpacing.lg),
                AppPrimaryButton(
                  label: 'Continue',
                  onPressed: _isLoading ? null : _goToRewardStep,
                  isLoading: _isLoading,
                  autofocus: false,
                ),
              ],
            ),
          ),
        ],
      );
    }

    if (_currentStep == 2) {
      // Reward step in landscape
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildRewardStepHeader(),
                const SizedBox(height: AppSpacing.md),
                TextButton(
                  onPressed: () => _setStep(1),
                  child: const Text('Go Back'),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            flex: 6,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                RewardPreferenceSelector(
                  selectedPreference: _selectedRewardPreference,
                  useRandomReward: _useRandomReward,
                  onPreferenceChanged: (preference) {
                    setState(() => _selectedRewardPreference = preference);
                  },
                  onRandomChanged: (useRandom) {
                    setState(() => _useRandomReward = useRandom);
                  },
                  showSkipOption: true,
                  onSkip: _skipRewardPreference,
                ),
                const SizedBox(height: AppSpacing.lg),
                _buildScreenTimeSelector(),
                const SizedBox(height: AppSpacing.lg),
                AppPrimaryButton(
                  label: _finalStepLabel,
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
              // Name → gender → birth date. Gender is a two-tap choice and
              // the date opens a modal picker, so asking the quick question
              // before the interrupting one keeps the run of fields moving.
              _buildGenderSelector(),
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
          const SizedBox(height: AppSpacing.lg),
          _buildCharacterPicker(),
              const SizedBox(height: AppSpacing.xl),
              AppPrimaryButton(
                label: 'Continue',
                onPressed: _isLoading ? null : _goToNextStep,
                isLoading: _isLoading,
                autofocus: false,
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _goToNextStep() {
    if (!_formKey.currentState!.validate()) return;
    // Same order as the fields on screen: name, gender, then birth date.
    if (_selectedSex == null) {
      _showError("Please select your child's gender.");
      return;
    }
    final validation = validateBirthDate(_selectedBirthDate);
    if (validation == ChildBirthDateValidation.missing) {
      _showError('Please select your child\'s birth date.');
      return;
    }
    if (validation == ChildBirthDateValidation.futureDate) {
      _showError('Birth date cannot be in the future.');
      return;
    }
    // Ages outside 2–6 are allowed at initialization (no age-range limit).

    // Default the screen-time limit to the age-based recommendation
    // (AAP/WHO guidance, ASD-adjusted) unless the parent already chose.
    if (!_screenTimeTouched) {
      _screenTimeLimitMinutes = ScreenTimeService.recommendedMinutesForAge(
        calculateAgeYears(_selectedBirthDate!),
      );
    }

    _setStep(1);
  }

  void _goToRewardStep() => _setStep(2);

  void _skipRewardPreference() {
    // Use default (bubbles) and save
    _saveProfile();
  }

  Widget _buildPortraitColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.md),
        if (_currentStep == 0) ...[
          _buildHeader(compact: false),
          const SizedBox(height: AppSpacing.xl),
          _buildForm(),
          const SizedBox(height: AppSpacing.xl),
          _buildGenderSelector(),
          const SizedBox(height: AppSpacing.xl),
          _buildBirthDateSelector(),
          const SizedBox(height: AppSpacing.xl),
          _buildAvatarPicker(),
          const SizedBox(height: AppSpacing.lg),
          _buildCharacterPicker(),
          const SizedBox(height: AppSpacing.xl),
          AppPrimaryButton(
            label: 'Continue',
            onPressed: _isLoading ? null : _goToNextStep,
            isLoading: _isLoading,
            autofocus: false,
          ),
        ] else if (_currentStep == 1) ...[
          _buildSoundStepHeader(),
          const SizedBox(height: AppSpacing.lg),
          SoundPreferencesStep(
            value: _sound,
            onChanged: (value) => setState(() => _sound = value),
          ),
          const SizedBox(height: AppSpacing.xl),
          AppPrimaryButton(
            label: 'Continue',
            onPressed: _isLoading ? null : _goToRewardStep,
            isLoading: _isLoading,
            autofocus: false,
          ),
          const SizedBox(height: AppSpacing.md),
          TextButton(
            onPressed: () => _setStep(0),
            child: const Text('Go Back'),
          ),
        ] else ...[
          _buildRewardStepHeader(),
          const SizedBox(height: AppSpacing.lg),
          RewardPreferenceSelector(
            selectedPreference: _selectedRewardPreference,
            useRandomReward: _useRandomReward,
            onPreferenceChanged: (preference) {
              setState(() => _selectedRewardPreference = preference);
            },
            onRandomChanged: (useRandom) {
              setState(() => _useRandomReward = useRandom);
            },
            showSkipOption: true,
            onSkip: _skipRewardPreference,
          ),
          const SizedBox(height: AppSpacing.xl),
          _buildScreenTimeSelector(),
          const SizedBox(height: AppSpacing.xl),
          AppPrimaryButton(
            label: _finalStepLabel,
            onPressed: _isLoading ? null : _saveProfile,
            isLoading: _isLoading,
            autofocus: false,
          ),
          const SizedBox(height: AppSpacing.md),
          TextButton(
            onPressed: () => _setStep(1),
            child: const Text('Go Back'),
          ),
        ],
        const SizedBox(height: AppSpacing.xxl),
      ],
    );
  }

  /// Compact daily screen-time selector for the setup flow. The age-based
  /// recommendation (AAP/WHO, ASD-adjusted) is pre-selected and starred.
  Widget _buildScreenTimeSelector() {
    final birthDate = _selectedBirthDate;
    final recommended = birthDate == null
        ? null
        : ScreenTimeService.recommendedMinutesForAge(
            calculateAgeYears(birthDate));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Daily Screen Time',
          style: AppTextStyles.titleMedium.copyWith(
            color: AppColors.foreground,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        if (recommended != null)
          Text(
            'Recommended for age ${calculateAgeYears(birthDate!)}: '
            '$recommended minutes per day (AAP/WHO guidance, adjusted '
            'for children with ASD).',
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.mutedForeground,
            ),
          ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: const Text('Off'),
              selected: _screenTimeLimitMinutes == null,
              selectedColor: AppColors.primaryPurple,
              labelStyle: AppTextStyles.bodySmall.copyWith(
                color: _screenTimeLimitMinutes == null
                    ? AppColors.white
                    : AppColors.textPrimary,
              ),
              onSelected: (_) => setState(() {
                _screenTimeLimitMinutes = null;
                _screenTimeTouched = true;
              }),
            ),
            for (final minutes in _screenTimeOptions)
              ChoiceChip(
                label: Text(
                    minutes == recommended ? '$minutes min ★' : '$minutes min'),
                selected: _screenTimeLimitMinutes == minutes,
                selectedColor: AppColors.primaryPurple,
                labelStyle: AppTextStyles.bodySmall.copyWith(
                  color: _screenTimeLimitMinutes == minutes
                      ? AppColors.white
                      : AppColors.textPrimary,
                ),
                onSelected: (_) => setState(() {
                  _screenTimeLimitMinutes = minutes;
                  _screenTimeTouched = true;
                }),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildSoundStepHeader() => _buildStepHeader(
        icon: Icons.hearing_rounded,
        title: 'How should it sound?',
        subtitle: 'Pick the language, voice and music your child is most '
            'comfortable with. Everything here can be changed later in '
            'Settings.',
        step: 2,
      );

  Widget _buildRewardStepHeader() => _buildStepHeader(
        icon: Icons.celebration_rounded,
        title: 'Almost Done!',
        subtitle: 'Choose how to celebrate when your child completes games',
        step: 3,
      );

  Widget _buildStepHeader({
    required IconData icon,
    required String title,
    required String subtitle,
    required int step,
  }) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            color: AppColors.lavenderLight,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 48, color: AppColors.primaryPurple),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Step $step of $_stepCount',
          textAlign: TextAlign.center,
          style: AppTextStyles.bodySmall.copyWith(
            color: AppColors.mutedForeground,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          title,
          textAlign: TextAlign.center,
          style: AppTextStyles.headlineLarge.copyWith(
            color: AppColors.primaryPurple,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.mutedForeground,
          ),
        ),
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
            'Step 1 of $_stepCount',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.mutedForeground,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
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
            // Advances rather than saving: the sound and reward steps still
            // have to be answered before there is a profile worth writing.
            onFieldSubmitted: (_) => _goToNextStep(),
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
            : selectedBirthDate != null
            ? '${selectedBirthDate.month}/${selectedBirthDate.day}/${selectedBirthDate.year}'
            : "Select your child's birth date.";

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
            color: validation == ChildBirthDateValidation.futureDate
                ? AppColors.destructiveRed
                : AppColors.mutedForeground,
          ),
        ),
      ],
    );
  }

  Widget _buildGenderSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Gender',
          style: AppTextStyles.titleMedium.copyWith(
            color: AppColors.foreground,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Sets the app background theme. "Prefer not to say" uses a neutral theme.',
          style: AppTextStyles.bodySmall.copyWith(
            color: AppColors.mutedForeground,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _GenderCell(
                  icon: Icons.male_rounded,
                  label: 'Boy',
                  accent: GamePalettes.boy.primary,
                  selected: _selectedSex == ChildSex.male,
                  onTap: _isLoading ? null : () => _selectSex(ChildSex.male),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _GenderCell(
                  icon: Icons.female_rounded,
                  label: 'Girl',
                  accent: GamePalettes.girl.primary,
                  selected: _selectedSex == ChildSex.female,
                  onTap: _isLoading ? null : () => _selectSex(ChildSex.female),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _GenderCell(
                  icon: Icons.emoji_emotions_outlined,
                  label: 'Prefer not to say',
                  accent: GamePalettes.neutral.primary,
                  selected: _selectedSex == ChildSex.preferNotToSay,
                  onTap: _isLoading
                      ? null
                      : () => _selectSex(ChildSex.preferNotToSay),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _selectSex(ChildSex sex) {
    _nameFocusNode.unfocus();
    setState(() => _selectedSex = sex);
  }

  /// `Who will play with <name>?` — the parent's choice of companion.
  ///
  /// Sits with the child's own details rather than in a later step: this is
  /// part of who the child is in the app, not a preference to tune afterwards.
  Widget _buildCharacterPicker() {
    final name = _nameController.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(
          title: name.isEmpty
              ? 'Who will play along?'
              : 'Who will play with $name?',
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Your child can change costumes later by earning stars.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: AppSpacing.md),
        CharacterPicker(
          selected: _selectedCharacter,
          onSelected: (c) => setState(() => _selectedCharacter = c),
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

/// A selectable gender option whose accent reflects the theme it applies.
class _GenderCell extends StatelessWidget {
  const _GenderCell({
    required this.icon,
    required this.label,
    required this.accent,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color accent;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? accent.withValues(alpha: 0.15) : AppColors.inputFill,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? accent : Colors.transparent,
              width: 2.5,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 30,
                  color: selected ? accent : AppColors.mutedForeground,
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: selected ? accent : AppColors.foreground,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
