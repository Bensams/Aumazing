import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_audio/shared_audio.dart';
import 'package:shared_haptic/shared_haptic.dart';

import 'package:shared_ui/shared_ui.dart';

import '../../core/services/auth_service.dart';
import '../../providers/child_provider.dart';
import '../../services/parent_pin_service.dart';
import '../../services/screen_time_service.dart';
import '../parent_lock/parent_pin_setup_dialog.dart';
import '../rewards/widgets/reward_preference_selector.dart';
import 'bind_account_modal.dart';
import 'manage_children_screen.dart';
import 'widgets/background_picker.dart';
import 'widgets/settings_scaffold.dart';
import 'widgets/object_style_picker.dart';

/// Full-screen Settings hub (the "main settings" page).
///
/// Categories:
/// - Video — graphics quality, animation intensity
/// - Audio — music, volumes, vibration, prompt speed
/// - Child Preferences — avatar, background theme, game difficulty,
///   language, reward celebration
/// - Bind Account — shown only while in guest mode
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.authService});

  final AuthService authService;

  @override
  Widget build(BuildContext context) {
    final palette = context.watch<ChildProvider>().activePalette;
    final isGuest = authService.isGuestMode;

    return SettingsScaffold(
      title: 'Settings',
      icon: Icons.settings_rounded,
      palette: palette,
      children: [
        _CategoryTile(
          icon: Icons.monitor_rounded,
          color: const Color(0xFF5E94B5),
          title: 'Video',
          subtitle: 'Graphics quality, animation intensity',
          onTap: () => _push(context, _VideoSettingsScreen(palette: palette)),
        ),
        _CategoryTile(
          icon: Icons.volume_up_rounded,
          color: const Color(0xFF6FAE97),
          title: 'Audio',
          subtitle: 'Music, sound effects, vibration, prompt speed',
          onTap: () => _push(context, _AudioSettingsScreen(palette: palette)),
        ),
        _CategoryTile(
          icon: Icons.family_restroom_rounded,
          color: const Color(0xFF7E9BD4),
          title: 'Manage Children',
          subtitle: 'Add, switch, edit or remove a child profile',
          onTap: () => _push(context, const ManageChildrenScreen()),
        ),
        _CategoryTile(
          icon: Icons.child_care_rounded,
          color: AppColors.primaryPurple,
          title: 'Child Preferences',
          subtitle: 'Avatar, theme, game difficulty, language, rewards',
          onTap: () =>
              _push(context, _ChildPreferencesScreen(palette: palette)),
        ),
        _CategoryTile(
          icon: Icons.timer_rounded,
          color: const Color(0xFFDD9B4A),
          title: 'Screen Time',
          subtitle: 'Daily play limit, age-based recommendation',
          onTap: () =>
              _push(context, _ScreenTimeSettingsScreen(palette: palette)),
        ),
        _CategoryTile(
          icon: Icons.lock_outline_rounded,
          color: const Color(0xFF8A7BC8),
          title: 'Parent Lock',
          subtitle: 'How the app checks a grown-up is present',
          onTap: () => _push(
            context,
            _ParentLockSettingsScreen(
              palette: palette,
              authService: authService,
            ),
          ),
        ),
        if (isGuest)
          _CategoryTile(
            icon: Icons.link_rounded,
            color: AppColors.statusWarningDark,
            title: 'Bind Account',
            subtitle: 'Save your progress permanently',
            onTap: () => showDialog(
              context: context,
              builder: (_) => BindAccountModal(authService: authService),
            ),
          ),
      ],
    );
  }

  void _push(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Video
// ─────────────────────────────────────────────────────────────────────────

class _VideoSettingsScreen extends StatelessWidget {
  const _VideoSettingsScreen({required this.palette});

  final GamePalette palette;

  @override
  Widget build(BuildContext context) {
    return SettingsScaffold(
      title: 'Video',
      icon: Icons.monitor_rounded,
      palette: palette,
      children: [
        Consumer<ChildProvider>(
          builder: (context, childProv, _) {
            return SettingsCard(
              children: [
                const _SectionLabel('Graphics Quality'),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: 8,
                  children: GraphicsQuality.values.map((q) {
                    final selected = childProv.graphicsQuality == q;
                    return ChoiceChip(
                      label: Text(q.label),
                      selected: selected,
                      selectedColor: AppColors.primaryPurple,
                      labelStyle: AppTextStyles.bodySmall.copyWith(
                        color: selected
                            ? AppColors.white
                            : AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                      onSelected: (_) => childProv.setGraphicsQuality(q),
                    );
                  }).toList(),
                ),
                const SizedBox(height: AppSpacing.xs),
                const SettingsHintText(
                  'Lower quality = static background and fewer effects '
                  '(cooler device, calmer visuals).',
                ),
                const SizedBox(height: AppSpacing.md),
                const Divider(height: 1),
                const SizedBox(height: AppSpacing.md),
                const _SectionLabel('Animation Intensity'),
                _SettingSlider(
                  label: 'Intensity',
                  value: childProv.animationIntensity,
                  onChanged: (val) => childProv.updateComfortSettings(
                    animationIntensity: val,
                  ),
                ),
                const SettingsHintText(
                  'Reduce visual stimulation for children sensitive to '
                  'movement.',
                ),
                const SizedBox(height: AppSpacing.md),
                const Divider(height: 1),
                const SizedBox(height: AppSpacing.md),
                const _SectionLabel('On-screen Text'),
                _SettingToggle(
                  icon: Icons.chat_bubble_outline_rounded,
                  label: 'Show instruction text',
                  value: childProv.showTextPrompts,
                  onChanged: (val) => childProv.setShowTextPrompts(val),
                ),
                const SettingsHintText(
                  'Hide the written prompt during games for pre-readers or '
                  'children who find text busy. The spoken instruction still '
                  'plays either way.',
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Audio
// ─────────────────────────────────────────────────────────────────────────

class _AudioSettingsScreen extends StatelessWidget {
  const _AudioSettingsScreen({required this.palette});

  final GamePalette palette;

  @override
  Widget build(BuildContext context) {
    return SettingsScaffold(
      title: 'Audio',
      icon: Icons.volume_up_rounded,
      palette: palette,
      children: [
        Consumer<ChildProvider>(
          builder: (context, childProv, _) {
            return SettingsCard(
              children: [
                _SettingToggle(
                  icon: Icons.music_note_rounded,
                  label: 'Music',
                  value: childProv.musicEnabled,
                  onChanged: (val) {
                    childProv.updateComfortSettings(musicEnabled: val);
                    final audioService = context.read<AudioService>();
                    // Sync AudioConfig so lifecycle callbacks respect it.
                    audioService.updateConfig(
                      audioService.config.copyWith(musicEnabled: val),
                    );
                    if (val) {
                      audioService.playCategoryMusic(childProv.musicCategory);
                    } else {
                      audioService.stopMusic();
                    }
                  },
                ),
                if (childProv.musicEnabled) ...[
                  _SettingSlider(
                    label: 'Music Volume',
                    value: childProv.musicVolume,
                    onChanged: (val) {
                      childProv.updateComfortSettings(musicVolume: val);
                      final audioService = context.read<AudioService>();
                      audioService.updateConfig(
                        audioService.config.copyWith(musicVolume: val),
                      );
                    },
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _MusicCategoryPicker(childProv: childProv),
                ],
                _SettingSlider(
                  label: 'Sound Effects',
                  value: childProv.sfxVolume,
                  onChanged: (val) {
                    childProv.updateComfortSettings(sfxVolume: val);
                    final audioService = context.read<AudioService>();
                    audioService.updateConfig(
                      audioService.config.copyWith(sfxVolume: val),
                    );
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                const Divider(height: 1),
                const SizedBox(height: AppSpacing.md),
                _SettingToggle(
                  icon: Icons.vibration_rounded,
                  label: 'Vibration',
                  value: childProv.vibrationEnabled,
                  onChanged: (val) {
                    childProv.updateComfortSettings(vibrationEnabled: val);
                    final hapticService = context.read<HapticService>();
                    hapticService.updateConfig(
                      hapticService.config.copyWith(enabled: val),
                    );
                  },
                ),
                _PromptSpeedSlider(childProv: childProv),
                const SettingsHintText(
                  'How quickly voice prompts and instructions play. Release '
                  'the slider to hear the new pace.',
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Child Preferences
// ─────────────────────────────────────────────────────────────────────────

class _ChildPreferencesScreen extends StatelessWidget {
  const _ChildPreferencesScreen({required this.palette});

  final GamePalette palette;

  static const _avatars = ['🐻', '🐼', '🦊', '🐨', '🐸', '🦄', '🐙', '🐰'];

  @override
  Widget build(BuildContext context) {
    return SettingsScaffold(
      title: 'Child Preferences',
      icon: Icons.child_care_rounded,
      palette: palette,
      children: [
        Consumer<ChildProvider>(
          builder: (context, childProv, _) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Avatar ────────────────────────────────────────────
                SettingsCard(
                  children: [
                    const _SectionLabel('Avatar'),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: _avatars.map((emoji) {
                        final selected =
                            childProv.profile?.avatarEmoji == emoji;
                        return GestureDetector(
                          onTap: () =>
                              childProv.updateProfile(avatar: emoji),
                          child: Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: selected
                                  ? AppColors.lavenderLight
                                  : AppColors.inputFill,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: selected
                                    ? AppColors.primaryPurple
                                    : Colors.transparent,
                                width: 2.5,
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Text(emoji,
                                style: const TextStyle(fontSize: 28)),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),

                // ── Background theme ──────────────────────────────────
                SettingsCard(
                  children: [
                    const _SectionLabel('Background Theme'),
                    const SizedBox(height: 2),
                    const SettingsHintText(
                      'Some children are sensitive to colors. Pick a calmer '
                      'theme if the current one is overstimulating.',
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        for (final theme in GameTheme.values)
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4),
                              child: _ThemeOption(
                                theme: theme,
                                childProv: childProv,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (childProv.isThemeOverridden)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () => childProv.clearThemeOverride(),
                          icon: const Icon(Icons.restart_alt_rounded,
                              size: 16),
                          label: const Text('Auto from gender'),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    if (childProv.hasCustomBackground)
                      const SettingsHintText(
                        'A custom background is in use, so the theme above '
                        'only sets the button and card colours.',
                      ),
                    const SizedBox(height: AppSpacing.sm),
                    const Divider(height: 1),
                    // The detailed controls live on their own page: the
                    // wheel, swatches and two previews are far too tall to
                    // sit inline in a list of one-line settings.
                    _CustomiseTile(
                      childProv: childProv,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              _AppearanceSettingsScreen(palette: palette),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),

                // ── My Path scene ─────────────────────────────────────
                SettingsCard(
                  children: [
                    const _SectionLabel('My Path Scene'),
                    const SizedBox(height: 2),
                    const SettingsHintText(
                      'Sets the world your child\'s learning path travels '
                      'through. The games themselves are unchanged. Pick one '
                      'your child likes — and keep it, since a path that '
                      'looks different each visit is harder to follow.',
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        for (final world in WorldTheme.values)
                          Expanded(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 4),
                              child: _WorldOption(
                                world: world,
                                childProv: childProv,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),

                // ── Game difficulty ───────────────────────────────────
                SettingsCard(
                  children: [
                    const _SectionLabel('Game Difficulty'),
                    const SizedBox(height: 2),
                    SettingsHintText(
                      childProv.isDifficultyOverridden
                          ? 'Manually set — applies to all practice games.'
                          : 'Following the assessment (per skill area).',
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: 8,
                      children: const [(1, 'Easy'), (2, 'Medium'), (3, 'Hard')]
                          .map((tier) {
                        final selected =
                            childProv.difficultyOverride == tier.$1;
                        return ChoiceChip(
                          label: Text(tier.$2),
                          selected: selected,
                          selectedColor: AppColors.primaryPurple,
                          labelStyle: AppTextStyles.bodySmall.copyWith(
                            color: selected
                                ? AppColors.white
                                : AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                          onSelected: (_) =>
                              childProv.setDifficultyOverride(tier.$1),
                        );
                      }).toList(),
                    ),
                    if (childProv.isDifficultyOverridden)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () =>
                              childProv.clearDifficultyOverride(),
                          icon: const Icon(Icons.restart_alt_rounded,
                              size: 16),
                          label: const Text('Auto from assessment'),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.textSecondary,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),

                // ── Language ──────────────────────────────────────────
                SettingsCard(
                  children: [
                    _SectionLabel(childProv.strings.languageLabel),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: 8,
                      children: GameLanguage.values.map((lang) {
                        final selected = childProv.language == lang;
                        return ChoiceChip(
                          label: Text(lang.label),
                          selected: selected,
                          selectedColor: AppColors.primaryPurple,
                          labelStyle: AppTextStyles.bodySmall.copyWith(
                            color: selected
                                ? AppColors.white
                                : AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                          onSelected: (_) => childProv.setLanguage(lang),
                        );
                      }).toList(),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),

                // ── Voice ─────────────────────────────────────────────
                // Shown for every language so a parent can always hear a
                // sample, even where there is only one recorded voice.
                SettingsCard(
                  children: [
                    const _SectionLabel('Voice'),
                    const SizedBox(height: 2),
                    const SettingsHintText(
                      'Who reads the prompts aloud. Tap the speaker to hear '
                      'a sample.',
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _VoicePackPicker(childProv: childProv),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),

                // ── Reward celebration ────────────────────────────────
                SettingsCard(
                  children: [
                    const _SectionLabel('Reward Celebration'),
                    const SizedBox(height: AppSpacing.sm),
                    RewardPreferenceDropdown(
                      selectedPreference: childProv.rewardPreference,
                      useRandomReward: childProv.useRandomReward,
                      onPreferenceChanged: (preference) {
                        childProv.updateRewardPreferences(
                          rewardPreference: preference,
                          useRandomReward: false,
                        );
                      },
                      onRandomChanged: (useRandom) {
                        childProv.updateRewardPreferences(
                          useRandomReward: useRandom,
                        );
                      },
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _SettingToggle(
                      icon: Icons.shuffle_rounded,
                      label: 'Use Random Rewards',
                      value: childProv.useRandomReward,
                      onChanged: (val) => childProv.updateRewardPreferences(
                        useRandomReward: val,
                      ),
                    ),
                    const SettingsHintText('A different celebration every time!'),
                  ],
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Appearance (custom background + game objects)
// ─────────────────────────────────────────────────────────────────────────

/// Row inside the Background Theme card that opens the appearance page.
///
/// Summarises what is currently set so the parent can see the state without
/// opening it — the point of moving the controls out was to shorten this
/// list, which is lost if they then have to go in to check.
class _CustomiseTile extends StatelessWidget {
  const _CustomiseTile({required this.childProv, required this.onTap});

  final ChildProvider childProv;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final background = childProv.customBackground;
    final style = childProv.objectStyle;

    final backgroundText = background == null
        ? 'Theme background'
        : background.kind == ChildBackgroundKind.solid
            ? 'Custom colour'
            : 'Custom blend';
    final outlineText = style.hasOutline
        ? '${style.outline.label.toLowerCase()} outline'
        : 'no outline';
    final summary = '$backgroundText · $outlineText';

    return Semantics(
      button: true,
      label: 'Customise background and objects. Currently $summary',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          constraints:
              const BoxConstraints(minHeight: kMinInteractiveDimension),
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Row(
            children: [
              Icon(Icons.tune_rounded,
                  size: 20, color: AppColors.primaryPurple),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Customise background and objects',
                      style: AppTextStyles.labelLarge
                          .copyWith(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      summary,
                      style: AppTextStyles.bodySmall
                          .copyWith(color: AppColors.mutedForeground),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: AppColors.mutedForeground),
            ],
          ),
        ),
      ),
    );
  }
}

/// The custom background and game-object editors, on two tabs.
///
/// These live on their own page rather than inline in Child Preferences:
/// each carries a colour wheel and a live game preview, and stacked inline
/// they buried the shorter settings underneath them. Two tabs rather than
/// one long scroll because the two things are independent — a parent
/// adjusting the outline is not also adjusting the background.
class _AppearanceSettingsScreen extends StatelessWidget {
  const _AppearanceSettingsScreen({required this.palette});

  final GamePalette palette;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        body: Container(
          decoration: BoxDecoration(gradient: palette.parentBackground),
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.lg,
                      AppSpacing.md, AppSpacing.lg, AppSpacing.sm),
                  child: Row(
                    children: [
                      Material(
                        color: AppColors.white.withAlpha(220),
                        shape: const CircleBorder(),
                        child: IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: Icon(Icons.arrow_back_rounded,
                              color: palette.primary),
                          tooltip: 'Back',
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppColors.white.withAlpha(235),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.palette_rounded,
                            color: palette.primary),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Flexible(
                        child: Text(
                          'Appearance',
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.headlineSmall.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.white.withAlpha(200),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TabBar(
                      labelColor: palette.primary,
                      unselectedLabelColor: AppColors.textSecondary,
                      indicatorColor: palette.primary,
                      // Full-width targets rather than text-width ones.
                      indicatorSize: TabBarIndicatorSize.tab,
                      tabs: const [
                        Tab(text: 'Background', height: kMinInteractiveDimension),
                        Tab(
                            text: 'Game objects',
                            height: kMinInteractiveDimension),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: Consumer<ChildProvider>(
                    builder: (context, childProv, _) => TabBarView(
                      children: [
                        _AppearanceTab(
                          hint: 'Pick your own colour for your child\'s game '
                              'screens, or blend two. This replaces the theme '
                              'background and is used for every game, so the '
                              'screens stay predictable.',
                          child: BackgroundPicker(childProv: childProv),
                        ),
                        _AppearanceTab(
                          hint: 'Sets the card behind each shape, picture and '
                              'item, and the outline around it. A plain card '
                              'colour with an outline makes objects easier to '
                              'tell apart — helpful if your child struggles to '
                              'pick out a shape.',
                          child: ObjectStylePicker(childProv: childProv),
                        ),
                      ],
                    ),
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

/// One tab's scrollable body, matching the settings pages' card look.
class _AppearanceTab extends StatelessWidget {
  const _AppearanceTab({required this.hint, required this.child});

  final String hint;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xl),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: SettingsCard(
            children: [
              SettingsHintText(hint),
              const SizedBox(height: AppSpacing.sm),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Shared scaffold + widgets
// ─────────────────────────────────────────────────────────────────────────

/// Full-screen settings page: themed gradient, header with back button,
/// scrollable centered content column.
/// One category row on the main settings hub.
class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Material(
        color: AppColors.white.withAlpha(240),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(icon, color: color, size: 28),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: AppTextStyles.titleMedium.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 16,
                  color: AppColors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Chips for choosing which recorded voice speaks the voice-over cues, each
/// with a speaker button that auditions the voice before it is applied.
class _VoicePackPicker extends StatefulWidget {
  const _VoicePackPicker({required this.childProv});

  final ChildProvider childProv;

  @override
  State<_VoicePackPicker> createState() => _VoicePackPickerState();
}

class _VoicePackPickerState extends State<_VoicePackPicker> {
  /// Throwaway player used only for auditioning; the games build their own.
  VoiceOverService? _preview;
  String? _previewFolder;

  @override
  void dispose() {
    _preview?.dispose();
    super.dispose();
  }

  Future<void> _playPreview(VoicePack pack) async {
    // Rebuild the throwaway player whenever the audition target changes.
    if (_previewFolder != pack.assetFolder) {
      final previous = _preview;
      _preview = VoiceOverService(languageCode: pack.assetFolder);
      _previewFolder = pack.assetFolder;
      await previous?.dispose();
    }
    // Audition at the child's own prompt speed — the same voice sounds quite
    // different stretched to 0.6x, and that is what the child will hear.
    _preview?.setSpeed(widget.childProv.voicePlaybackRate);
    await _preview?.play(VoiceOverCue.greatJob);
  }

  /// Heading for an age tier. Null is the untiered human-recorded Cebuano
  /// pack, which is listed last without a heading.
  static const Map<String, String> _tierHeadings = {
    'adult': 'Grown-up voices',
    'young': 'Teen voices',
    'child': 'Child voices',
  };

  @override
  Widget build(BuildContext context) {
    final selectedId = widget.childProv.voicePack.id;
    final languageSlug = widget.childProv.language.slug;
    final tiers = voiceTiersForLanguage(languageSlug);

    // Each language offers six or seven voices, so a single flat Wrap would
    // be a wall of chips. Grouping by age gives the parent a way to narrow
    // down before auditioning.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final tier in tiers) ...[
          if (tier != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              _tierHeadings[tier] ?? tier,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
          ],
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              for (final pack in voicePacksForTier(languageSlug, tier))
                _buildChip(
                  pack,
                  pack.id == selectedId,
                  tier == null ? null : _tierHeadings[tier],
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildChip(VoicePack pack, bool selected, String? tierHeading) {
    // Every tier offers a "Girl" and a "Boy", so the visible label alone is
    // ambiguous once the heading is out of view — Accessibility Scanner
    // reported four pairs of identical descriptions here. Screen readers get
    // the heading folded in; sighted parents still read the short label.
    final spokenName =
        tierHeading == null ? pack.label : '$tierHeading: ${pack.label}';

    // The preview button sits outside the chip: nesting it in the chip's
    // label lets the chip's own InkWell swallow the tap.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ChoiceChip(
          selected: selected,
          selectedColor: AppColors.primaryPurple,
          label: Text(pack.label, semanticsLabel: spokenName),
          labelStyle: AppTextStyles.bodySmall.copyWith(
            color: selected ? AppColors.white : AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
          // Selecting also plays a sample, so the parent always hears
          // the voice they just chose.
          onSelected: (_) async {
            await widget.childProv.setVoicePack(pack.id);
            await _playPreview(pack);
          },
        ),
        const SizedBox(width: 2),
        IconButton(
          onPressed: () => _playPreview(pack),
          icon: const Icon(Icons.volume_up_rounded, size: 22),
          color: AppColors.primaryPurple,
          tooltip: 'Hear $spokenName',
          // VisualDensity.compact used to shave 8dp off each axis, quietly
          // defeating the 48dp constraints below and landing these at
          // 40x40dp in Accessibility Scanner.
          constraints: const BoxConstraints(
            minWidth: kMinInteractiveDimension,
            minHeight: kMinInteractiveDimension,
          ),
        ),
      ],
    );
  }
}

/// White rounded content card wrapping one settings section.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppTextStyles.labelLarge.copyWith(
        color: AppColors.textSecondary,
      ),
    );
  }
}

class _SettingToggle extends StatelessWidget {
  const _SettingToggle({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.textSecondary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              label,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeTrackColor: AppColors.primaryPurple,
          ),
        ],
      ),
    );
  }
}

class _SettingSlider extends StatelessWidget {
  const _SettingSlider({
    required this.label,
    required this.value,
    required this.onChanged,
    this.onChangeEnd,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Slider(
              value: value,
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
              activeColor: AppColors.primaryPurple,
              inactiveColor: AppColors.lavenderLight,
            ),
          ),
          SizedBox(
            width: 36,
            child: Text(
              '${(value * 100).round()}%',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Prompt-speed slider that speaks a sample at the new pace when released.
///
/// Prompt speed is the one comfort setting with no visible effect, so without
/// a sample a parent is guessing at a percentage. Dragging is silent; the
/// sample plays on release so a drag does not stutter out ten half-cues.
class _PromptSpeedSlider extends StatefulWidget {
  const _PromptSpeedSlider({required this.childProv});

  final ChildProvider childProv;

  @override
  State<_PromptSpeedSlider> createState() => _PromptSpeedSliderState();
}

class _PromptSpeedSliderState extends State<_PromptSpeedSlider> {
  VoiceOverService? _preview;

  @override
  void dispose() {
    _preview?.dispose();
    super.dispose();
  }

  Future<void> _playSample() async {
    final childProv = widget.childProv;
    _preview ??= VoiceOverService(languageCode: childProv.voiceAssetFolder);
    await _preview?.setLanguage(childProv.voiceAssetFolder);
    _preview?.setSpeed(childProv.voicePlaybackRate);
    await _preview?.play(VoiceOverCue.greatJob);
  }

  @override
  Widget build(BuildContext context) {
    return _SettingSlider(
      label: 'Prompt Speed',
      value: widget.childProv.promptSpeed,
      onChanged: (val) =>
          widget.childProv.updateComfortSettings(promptSpeed: val),
      onChangeEnd: (_) => _playSample(),
    );
  }
}

/// Lets the parent choose which kind of background music the child hears.
///
/// One track from the chosen category is picked when a session starts and
/// loops until it ends — the music never changes underneath the child. Picking
/// here is the deliberate exception: the parent is listening on purpose, so the
/// new category starts playing immediately as a preview.
class _MusicCategoryPicker extends StatefulWidget {
  const _MusicCategoryPicker({required this.childProv});

  final ChildProvider childProv;

  @override
  State<_MusicCategoryPicker> createState() => _MusicCategoryPickerState();
}

class _MusicCategoryPickerState extends State<_MusicCategoryPicker> {
  /// Which category is expanded to show its individual tracks. Defaults to
  /// none, so the list opens as six calm choices rather than thirty.
  String? _expandedKey;

  /// Path of the track being auditioned, so the row can show it is playing.
  String? _previewPath;

  Future<void> _selectCategory(BgmCategory category) async {
    await widget.childProv.updateComfortSettings(musicCategory: category.key);
    if (!mounted) return;
    // restart: true so the parent hears the new style straight away rather
    // than only on the next session.
    await context
        .read<AudioService>()
        .playCategoryMusic(category.key, restart: true);
    if (!mounted) return;
    setState(() => _previewPath = context.read<AudioService>().currentTrack);
  }

  Future<void> _previewTrack(BgmCategory category, BgmTrack track) async {
    await context.read<AudioService>().playCategoryTrack(category, track);
    if (!mounted) return;
    setState(() => _previewPath = category.trackPath(track));
  }

  @override
  Widget build(BuildContext context) {
    final selectedKey = widget.childProv.musicCategory;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Music Style',
          style: AppTextStyles.bodySmall.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'One track from the chosen style plays each session, on repeat. '
          'Tap a style to choose it, or ▸ to hear each track.',
          style: AppTextStyles.bodySmall.copyWith(
            color: AppColors.textSecondary,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        for (final category in kBgmCategories) ...[
          _MusicCategoryOption(
            category: category,
            selected: category.key == selectedKey,
            expanded: _expandedKey == category.key,
            onTap: () => _selectCategory(category),
            onToggleExpand: () => setState(
              () => _expandedKey =
                  _expandedKey == category.key ? null : category.key,
            ),
          ),
          if (_expandedKey == category.key)
            Padding(
              padding: const EdgeInsets.only(
                left: AppSpacing.md,
                bottom: AppSpacing.xs,
              ),
              child: Column(
                children: [
                  for (final track in category.tracks)
                    _MusicTrackRow(
                      title: track.title,
                      playing: _previewPath == category.trackPath(track),
                      onTap: () => _previewTrack(category, track),
                    ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

/// One track inside an expanded style, with a preview control.
///
/// Previewing does not change which style is selected — a parent can listen
/// through everything before committing to one.
class _MusicTrackRow extends StatelessWidget {
  const _MusicTrackRow({
    required this.title,
    required this.playing,
    required this.onTap,
  });

  final String title;
  final bool playing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Preview $title',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 8),
          child: Row(
            children: [
              Icon(
                playing ? Icons.volume_up_rounded : Icons.play_circle_outline,
                size: 18,
                color: playing
                    ? AppColors.primaryPurple
                    : AppColors.textSecondary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  title,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: playing
                        ? AppColors.primaryPurple
                        : AppColors.textPrimary,
                    fontWeight:
                        playing ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One row in [_MusicCategoryPicker]: the category name, its guidance text,
/// and a check when it is the active choice.
class _MusicCategoryOption extends StatelessWidget {
  const _MusicCategoryOption({
    required this.category,
    required this.selected,
    required this.expanded,
    required this.onTap,
    required this.onToggleExpand,
  });

  final BgmCategory category;
  final bool selected;
  final bool expanded;
  final VoidCallback onTap;
  final VoidCallback onToggleExpand;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      inMutuallyExclusiveGroup: true,
      selected: selected,
      button: true,
      label: category.label,
      hint: category.description,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: selected ? AppColors.lavenderLight : AppColors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? AppColors.primaryPurple
                  : AppColors.lavenderLight,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category.label,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      category.description,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                const Icon(
                  Icons.check_circle_rounded,
                  size: 20,
                  color: AppColors.primaryPurple,
                ),
              // Separate hit target: expanding to audition the tracks must not
              // change which style the child gets.
              IconButton(
                key: ValueKey('bgm-expand-${category.key}'),
                onPressed: onToggleExpand,
                visualDensity: VisualDensity.compact,
                iconSize: 20,
                tooltip: expanded
                    ? 'Hide ${category.label} tracks'
                    : 'Hear ${category.label} tracks',
                icon: Icon(
                  expanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A tappable swatch for one background theme, showing its dashboard
/// gradient and primary color. Highlights when it is the active theme.
class _ThemeOption extends StatelessWidget {
  const _ThemeOption({required this.theme, required this.childProv});

  final GameTheme theme;
  final ChildProvider childProv;

  @override
  Widget build(BuildContext context) {
    final palette = GamePalettes.of(theme);
    final selected = childProv.activeTheme == theme;
    return GestureDetector(
      onTap: () => childProv.setThemeOverride(theme),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? palette.primary : AppColors.border,
            width: selected ? 2.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Container(
              height: 40,
              decoration: BoxDecoration(
                gradient: palette.parentBackground,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: palette.primary.withAlpha(60)),
              ),
              alignment: Alignment.center,
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: palette.primary,
                  shape: BoxShape.circle,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              theme.label,
              style: AppTextStyles.labelSmall.copyWith(
                color: selected ? palette.primary : AppColors.textSecondary,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A tappable swatch for one "My Path" scene, previewing the real backdrop
/// with a sample of its trail across the middle.
///
/// Choosing [WorldTheme.classic] clears the override rather than storing one,
/// so it doubles as the reset control and no separate button is needed.
class _WorldOption extends StatelessWidget {
  const _WorldOption({required this.world, required this.childProv});

  final WorldTheme world;
  final ChildProvider childProv;

  @override
  Widget build(BuildContext context) {
    final style = WorldStyles.of(world);
    final selected = childProv.activeWorld == world;
    return GestureDetector(
      onTap: () => world == WorldTheme.classic
          ? childProv.clearWorldOverride()
          : childProv.setWorldOverride(world),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.primaryPurple : AppColors.border,
            width: selected ? 2.5 : 1,
          ),
        ),
        child: Column(
          children: [
            SizedBox(
              height: 40,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (style.hasBackdrop)
                    WorldBackdrop(style: style, borderRadius: 8)
                  else
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.muted,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.border),
                      ),
                    ),
                  // A sample of the trail, so the swatch shows the thing that
                  // actually changes rather than just a background.
                  Center(
                    child: Container(
                      width: 26,
                      height: 3,
                      decoration: BoxDecoration(
                        color: style.trailTravelled,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              world.label,
              style: AppTextStyles.labelSmall.copyWith(
                color: selected
                    ? AppColors.primaryPurple
                    : AppColors.textSecondary,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Screen Time
// ─────────────────────────────────────────────────────────────────────────

/// Parent controls for the daily screen-time limit (FR: set daily limits;
/// gameplay pauses when exceeded).
///
/// The recommendation follows AAP/WHO guidance (≤1 hour/day of quality
/// content for ages 2–5, less is better at age 2) adjusted conservatively
/// for ASD learners — see [ScreenTimeService.recommendedMinutesForAge].
class _ScreenTimeSettingsScreen extends StatefulWidget {
  const _ScreenTimeSettingsScreen({required this.palette});

  final GamePalette palette;

  @override
  State<_ScreenTimeSettingsScreen> createState() =>
      _ScreenTimeSettingsScreenState();
}

class _ScreenTimeSettingsScreenState extends State<_ScreenTimeSettingsScreen> {
  static const _options = [15, 20, 30, 45, 60, 90];

  @override
  void initState() {
    super.initState();
    final childId = context.read<ChildProvider>().profile?.id;
    if (childId != null) ScreenTimeService.instance.load(childId);
  }

  int? _childAgeYears() {
    final birthDate = context.read<ChildProvider>().profile?.birthDate;
    if (birthDate == null) return null;
    final now = DateTime.now();
    var age = now.year - birthDate.year;
    if (now.month < birthDate.month ||
        (now.month == birthDate.month && now.day < birthDate.day)) {
      age--;
    }
    return age;
  }

  @override
  Widget build(BuildContext context) {
    final age = _childAgeYears();
    final recommended =
        age == null ? null : ScreenTimeService.recommendedMinutesForAge(age);

    return SettingsScaffold(
      title: 'Screen Time',
      icon: Icons.timer_rounded,
      palette: widget.palette,
      children: [
        ListenableBuilder(
          listenable: ScreenTimeService.instance,
          builder: (context, _) {
            final screenTime = ScreenTimeService.instance;
            final usedMin = (screenTime.usedTodaySeconds / 60).ceil();
            final limit = screenTime.limitMinutes;

            return SettingsCard(
              children: [
                const _SectionLabel('Today'),
                const SizedBox(height: AppSpacing.xs),
                Row(
                  children: [
                    const Icon(Icons.hourglass_bottom_rounded,
                        size: 18, color: AppColors.primaryPurple),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        limit == null
                            ? '$usedMin min played today (no limit set)'
                            : '$usedMin of $limit min played today',
                        style: AppTextStyles.bodyMedium
                            .copyWith(color: AppColors.textPrimary),
                      ),
                    ),
                    TextButton(
                      onPressed: () => screenTime.resetToday(),
                      child: const Text('Reset'),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                const _SectionLabel('Daily Limit'),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('Off'),
                      selected: limit == null,
                      selectedColor: AppColors.primaryPurple,
                      labelStyle: AppTextStyles.bodySmall.copyWith(
                        color: limit == null
                            ? AppColors.white
                            : AppColors.textPrimary,
                      ),
                      onSelected: (_) => screenTime.setLimitMinutes(null),
                    ),
                    for (final minutes in _options)
                      ChoiceChip(
                        label: Text(minutes == recommended
                            ? '$minutes min ★'
                            : '$minutes min'),
                        selected: limit == minutes,
                        selectedColor: AppColors.primaryPurple,
                        labelStyle: AppTextStyles.bodySmall.copyWith(
                          color: limit == minutes
                              ? AppColors.white
                              : AppColors.textPrimary,
                        ),
                        onSelected: (_) =>
                            screenTime.setLimitMinutes(minutes),
                      ),
                  ],
                ),
                if (recommended != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.star_rounded,
                          size: 16, color: Color(0xFFDD9B4A)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Recommended for age $age: $recommended minutes '
                          'per day. Based on AAP/WHO guidance (at most 1 '
                          'hour of quality screen time for ages 2–5), set '
                          'conservatively for children with ASD. Short, '
                          'purposeful sessions work best.',
                          style: AppTextStyles.bodySmall
                              .copyWith(color: AppColors.mutedForeground),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'When the limit is reached, the screen fades to a plain '
                  'rest screen with no messages or buttons for your child. '
                  'Only the parent lock in the top-right corner unlocks it '
                  '(add 15 minutes or exit child mode).',
                  style: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.mutedForeground),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Parent Lock
// ─────────────────────────────────────────────────────────────────────────

/// Chooses how the app verifies a grown-up before leaving child mode.
///
/// The default word code needs nothing memorised, but it is beaten by any
/// child who can read the number words on screen — which is why we
/// recommend a custom PIN from age [ParentPinService.recommendedPinAge].
/// It is a recommendation, not a rule: reading ability varies widely among
/// ASD learners and the parent knows their child.
///
/// Custom PINs require a confirmed email on the account. A forgotten PIN is
/// reset via a one-time code sent to that address — with no address there is
/// no way back in, so we do not let a parent set a PIN they could be
/// permanently locked out by.
class _ParentLockSettingsScreen extends StatefulWidget {
  const _ParentLockSettingsScreen({
    required this.palette,
    required this.authService,
  });

  final GamePalette palette;
  final AuthService authService;

  @override
  State<_ParentLockSettingsScreen> createState() =>
      _ParentLockSettingsScreenState();
}

class _ParentLockSettingsScreenState extends State<_ParentLockSettingsScreen> {
  int? _childAgeYears() {
    final birthDate = context.read<ChildProvider>().profile?.birthDate;
    if (birthDate == null) return null;
    final now = DateTime.now();
    var age = now.year - birthDate.year;
    if (now.month < birthDate.month ||
        (now.month == birthDate.month && now.day < birthDate.day)) {
      age--;
    }
    return age;
  }

  Future<void> _setPin({required bool isChange}) async {
    final saved = await ParentPinSetupDialog.show(context, isChange: isChange);
    if (!mounted || !saved) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Parent PIN saved.'),
        backgroundColor: AppColors.mint,
      ),
    );
  }

  Future<void> _switchToWordCode() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Remove your PIN?',
          style:
              AppTextStyles.titleLarge.copyWith(color: AppColors.textPrimary),
        ),
        content: Text(
          'The lock will go back to showing a code on screen for you to type '
          'back. A child who can read those words will be able to get past '
          'it.',
          style: AppTextStyles.bodyMedium
              .copyWith(color: AppColors.mutedForeground),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep PIN'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ParentPinService.instance.clearPin();
  }

  @override
  Widget build(BuildContext context) {
    final age = _childAgeYears();
    final recommendsPin =
        age != null && ParentPinService.recommendsCustomPin(age);
    final email = widget.authService.verifiedEmail;

    return SettingsScaffold(
      title: 'Parent Lock',
      icon: Icons.lock_outline_rounded,
      palette: widget.palette,
      children: [
        ListenableBuilder(
          listenable: ParentPinService.instance,
          builder: (context, _) {
            final pinService = ParentPinService.instance;
            final usesPin = pinService.hasPin;

            return SettingsCard(
              children: [
                const _SectionLabel('Unlock Method'),
                const SizedBox(height: AppSpacing.sm),
                _LockModeOption(
                  icon: Icons.abc_rounded,
                  title: 'Word Code',
                  subtitle: 'We show four numbers as words — type them back. '
                      'Nothing to remember.',
                  selected: !usesPin,
                  onTap: usesPin ? _switchToWordCode : null,
                ),
                const SizedBox(height: AppSpacing.sm),
                _LockModeOption(
                  icon: Icons.pin_rounded,
                  title: 'My Own PIN',
                  subtitle: email == null
                      ? 'Needs a confirmed email address on your account.'
                      : 'Four digits only you know. Nothing on screen gives '
                          'it away.',
                  selected: usesPin,
                  recommended: recommendsPin && !usesPin && email != null,
                  onTap: email == null
                      ? null
                      : () => _setPin(isChange: usesPin),
                ),

                if (recommendsPin && !usesPin) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.star_rounded,
                          size: 16, color: Color(0xFFDD9B4A)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Your child is $age. Most children this age can '
                          'read the number words on the unlock screen, so we '
                          'recommend setting your own PIN. You know your '
                          'child best — the word code is still fine if '
                          'reading is not yet a strength.',
                          style: AppTextStyles.bodySmall
                              .copyWith(color: AppColors.mutedForeground),
                        ),
                      ),
                    ],
                  ),
                ],

                if (email == null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline_rounded,
                          size: 16, color: AppColors.mutedForeground),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          widget.authService.isGuestMode
                              ? 'Bind your account and confirm your email to '
                                  'use your own PIN. A one-time code sent to '
                                  'that address is the only way back in if '
                                  'you forget it.'
                              : 'Confirm the email on your account to use '
                                  'your own PIN. A one-time code sent to '
                                  'that address is the only way back in if '
                                  'you forget it.',
                          style: AppTextStyles.bodySmall
                              .copyWith(color: AppColors.mutedForeground),
                        ),
                      ),
                    ],
                  ),
                ],

                if (usesPin) ...[
                  const SizedBox(height: AppSpacing.md),
                  const _SectionLabel('Your PIN'),
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Forgot it? Tap "Forgot PIN?" on the unlock screen '
                          'and we email a one-time code to $email. We never '
                          'send the PIN itself — you pick a new one.',
                          style: AppTextStyles.bodySmall
                              .copyWith(color: AppColors.mutedForeground),
                        ),
                      ),
                      TextButton(
                        onPressed: () => _setPin(isChange: true),
                        child: const Text('Change'),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  SettingsHintText(
                    'After ${ParentPinService.maxAttempts} wrong tries the '
                    'keypad pauses for '
                    '${ParentPinService.lockoutDuration.inSeconds} seconds, '
                    'so the PIN cannot be guessed by trial and error.',
                  ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

/// One selectable unlock method, styled like a settings row.
class _LockModeOption extends StatelessWidget {
  const _LockModeOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.recommended = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final bool recommended;

  /// Null disables the row (already selected, or unavailable).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null && !selected;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: selected ? AppColors.lavenderLight : AppColors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppColors.primaryPurple : AppColors.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              size: 22,
              color: disabled
                  ? AppColors.mutedForeground
                  : AppColors.primaryPurple,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: AppTextStyles.titleMedium.copyWith(
                          color: disabled
                              ? AppColors.mutedForeground
                              : AppColors.textPrimary,
                        ),
                      ),
                      if (recommended) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.star_rounded,
                            size: 14, color: Color(0xFFDD9B4A)),
                        const SizedBox(width: 2),
                        Text(
                          'Recommended',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: const Color(0xFFDD9B4A),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: AppTextStyles.bodySmall
                        .copyWith(color: AppColors.mutedForeground),
                  ),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle_rounded,
                  size: 20, color: AppColors.primaryPurple),
          ],
        ),
      ),
    );
  }
}
