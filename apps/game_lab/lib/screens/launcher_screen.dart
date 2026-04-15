import 'package:flutter/material.dart';
import 'package:game_core/game_core.dart';
import 'package:shared_ui/shared_ui.dart';

import 'game_test_screen.dart';

/// The launcher screen for Game Lab.
///
/// Displays a grid of all registered games from [GameRegistry] along with
/// a config panel for adjusting difficulty, animation intensity, and volume.
class LauncherScreen extends StatefulWidget {
  const LauncherScreen({super.key});

  @override
  State<LauncherScreen> createState() => _LauncherScreenState();
}

class _LauncherScreenState extends State<LauncherScreen> {
  GameConfig _config = GameConfig.defaults;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration:
            const BoxDecoration(gradient: AppGradients.parentLavenderMint),
        child: SafeArea(
          child: Row(
            children: [
              // ── Config Panel (left) ────────────────────────────────
              SizedBox(
                width: 280,
                child: _buildConfigPanel(),
              ),

              // ── Game Grid (right) ──────────────────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        AppSpacing.md,
                        AppSpacing.lg,
                        AppSpacing.sm,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '🎮 Game Lab',
                            style: AppTextStyles.displayMedium.copyWith(
                              color: AppColors.primaryPurple,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Tap a game to launch it with the current config',
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: AppColors.mutedForeground,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: GridView.builder(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: AppSpacing.md,
                          crossAxisSpacing: AppSpacing.md,
                          childAspectRatio: 1.6,
                        ),
                        itemCount: GameRegistry.games.length,
                        itemBuilder: (context, index) {
                          final game = GameRegistry.games[index];
                          return _GameCard(
                            entry: game,
                            onTap: () => _launchGame(game),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _launchGame(GameEntry entry) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GameTestScreen(
          entry: entry,
          config: _config,
        ),
      ),
    );
  }

  Widget _buildConfigPanel() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white.withAlpha(220),
        border: Border(
          right: BorderSide(color: AppColors.border, width: 1),
        ),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title
            Row(
              children: [
                const Icon(Icons.tune_rounded,
                    color: AppColors.primaryPurple, size: 22),
                const SizedBox(width: AppSpacing.xs),
                Text('Config',
                    style: AppTextStyles.titleLarge
                        .copyWith(color: AppColors.primaryPurple)),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),

            // Difficulty
            _buildSliderSection(
              label: 'Difficulty',
              value: _config.difficulty.toDouble(),
              min: 1,
              max: 3,
              divisions: 2,
              displayValue: ['Easy', 'Medium', 'Hard'][_config.difficulty - 1],
              onChanged: (v) => setState(
                () => _config = _config.copyWith(difficulty: v.round()),
              ),
            ),

            // Prompt Repetition
            _buildSliderSection(
              label: 'Prompt Repetition',
              value: _config.promptRepetition.toDouble(),
              min: 1,
              max: 5,
              divisions: 4,
              displayValue: '${_config.promptRepetition}x',
              onChanged: (v) => setState(
                () =>
                    _config = _config.copyWith(promptRepetition: v.round()),
              ),
            ),

            // Animation Intensity
            _buildSliderSection(
              label: 'Animation Intensity',
              value: _config.animationIntensity,
              min: 0.0,
              max: 1.0,
              divisions: 10,
              displayValue:
                  '${(_config.animationIntensity * 100).round()}%',
              onChanged: (v) => setState(
                () => _config = _config.copyWith(animationIntensity: v),
              ),
            ),

            const Divider(height: 32),

            // BG Music Volume
            _buildSliderSection(
              label: 'Music Volume',
              value: _config.bgMusicVolume,
              min: 0.0,
              max: 1.0,
              divisions: 10,
              displayValue: '${(_config.bgMusicVolume * 100).round()}%',
              icon: Icons.music_note_rounded,
              onChanged: (v) => setState(
                () => _config = _config.copyWith(bgMusicVolume: v),
              ),
            ),

            // SFX Volume
            _buildSliderSection(
              label: 'SFX Volume',
              value: _config.sfxVolume,
              min: 0.0,
              max: 1.0,
              divisions: 10,
              displayValue: '${(_config.sfxVolume * 100).round()}%',
              icon: Icons.volume_up_rounded,
              onChanged: (v) => setState(
                () => _config = _config.copyWith(sfxVolume: v),
              ),
            ),

            const SizedBox(height: AppSpacing.md),

            // Reset button
            Center(
              child: TextButton.icon(
                onPressed: () =>
                    setState(() => _config = GameConfig.defaults),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Reset to Defaults'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSliderSection({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String displayValue,
    required ValueChanged<double> onChanged,
    IconData? icon,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: AppColors.mutedForeground),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(label, style: AppTextStyles.labelLarge),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.lavenderLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  displayValue,
                  style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.primaryPurple,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: AppColors.primaryPurple,
              inactiveTrackColor: AppColors.lavender,
              thumbColor: AppColors.primaryPurple,
              overlayColor: AppColors.primaryPurple.withAlpha(30),
              trackHeight: 4,
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Game Card ──────────────────────────────────────────────────────────

class _GameCard extends StatelessWidget {
  const _GameCard({required this.entry, required this.onTap});

  final GameEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: entry.gradientColors,
            ),
            boxShadow: [
              BoxShadow(
                color: entry.gradientColors.first.withAlpha(80),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.white.withAlpha(180),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(entry.icon,
                        color: AppColors.primaryPurple, size: 24),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      entry.name,
                      style: AppTextStyles.titleLarge.copyWith(
                        color: AppColors.foreground,
                      ),
                    ),
                  ),
                  const Icon(Icons.play_circle_fill_rounded,
                      color: AppColors.primaryPurple, size: 28),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                entry.description,
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.mutedForeground,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
