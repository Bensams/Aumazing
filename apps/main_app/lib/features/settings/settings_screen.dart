import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_audio/shared_audio.dart';
import 'package:shared_haptic/shared_haptic.dart';

import 'package:shared_ui/shared_ui.dart';

import '../../core/services/auth_service.dart';
import '../../providers/child_provider.dart';
import '../rewards/widgets/reward_preference_selector.dart';
import 'bind_account_modal.dart';

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

    return _SettingsScaffold(
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
          icon: Icons.child_care_rounded,
          color: AppColors.primaryPurple,
          title: 'Child Preferences',
          subtitle: 'Avatar, theme, game difficulty, language, rewards',
          onTap: () =>
              _push(context, _ChildPreferencesScreen(palette: palette)),
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
    return _SettingsScaffold(
      title: 'Video',
      icon: Icons.monitor_rounded,
      palette: palette,
      children: [
        Consumer<ChildProvider>(
          builder: (context, childProv, _) {
            return _SettingsCard(
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
                const _HintText(
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
                const _HintText(
                  'Reduce visual stimulation for children sensitive to '
                  'movement.',
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
    return _SettingsScaffold(
      title: 'Audio',
      icon: Icons.volume_up_rounded,
      palette: palette,
      children: [
        Consumer<ChildProvider>(
          builder: (context, childProv, _) {
            return _SettingsCard(
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
                      audioService.playRandomMusic(
                          ['bg_music.ogg', 'bg_music1.ogg']);
                    } else {
                      audioService.stopMusic();
                    }
                  },
                ),
                if (childProv.musicEnabled)
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
                _SettingSlider(
                  label: 'Prompt Speed',
                  value: childProv.promptSpeed,
                  onChanged: (val) =>
                      childProv.updateComfortSettings(promptSpeed: val),
                ),
                const _HintText(
                  'How quickly voice prompts and instructions play.',
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
    return _SettingsScaffold(
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
                _SettingsCard(
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
                _SettingsCard(
                  children: [
                    const _SectionLabel('Background Theme'),
                    const SizedBox(height: 2),
                    const _HintText(
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
                  ],
                ),
                const SizedBox(height: AppSpacing.md),

                // ── Game difficulty ───────────────────────────────────
                _SettingsCard(
                  children: [
                    const _SectionLabel('Game Difficulty'),
                    const SizedBox(height: 2),
                    _HintText(
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
                _SettingsCard(
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

                // ── Reward celebration ────────────────────────────────
                _SettingsCard(
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
                    const _HintText('A different celebration every time!'),
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
// Shared scaffold + widgets
// ─────────────────────────────────────────────────────────────────────────

/// Full-screen settings page: themed gradient, header with back button,
/// scrollable centered content column.
class _SettingsScaffold extends StatelessWidget {
  const _SettingsScaffold({
    required this.title,
    required this.icon,
    required this.palette,
    required this.children,
  });

  final String title;
  final IconData icon;
  final GamePalette palette;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: palette.parentBackground),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.sm),
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
                      child: Icon(icon, color: palette.primary),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Flexible(
                      child: Text(
                        title,
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
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg, AppSpacing.sm, AppSpacing.lg,
                      AppSpacing.xl),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: children,
                      ),
                    ),
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

/// White rounded content card wrapping one settings section.
class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.white.withAlpha(240),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

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

class _HintText extends StatelessWidget {
  const _HintText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppTextStyles.bodySmall.copyWith(
        color: AppColors.textSecondary,
        fontStyle: FontStyle.italic,
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
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;

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
