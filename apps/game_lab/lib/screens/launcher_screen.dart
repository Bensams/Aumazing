import 'package:flutter/material.dart';
import 'package:game_core/game_core.dart';
import 'package:shared_audio/shared_audio.dart';
import 'package:shared_ui/shared_ui.dart';

import '../services/game_lab_services.dart';
import 'audio_tester_screen.dart';
import 'haptic_tester_screen.dart';
import 'game_flow_screen.dart';
import 'game_test_screen.dart';
import 'reward_tester_screen.dart';

/// The launcher screen for Game Lab.
///
/// Displays a grid of all registered games from [GameRegistry] along with
/// a config panel for adjusting difficulty, animation intensity, volume,
/// haptic feedback, and voice-over settings.
class LauncherScreen extends StatefulWidget {
  const LauncherScreen({super.key});

  @override
  State<LauncherScreen> createState() => _LauncherScreenState();
}

class _LauncherScreenState extends State<LauncherScreen> {
  GameConfig _config = GameConfig.defaults;

  // Audio toggles (separate from volume sliders)
  bool _sfxEnabled = true;
  bool _musicEnabled = true;
  bool _voEnabled = true;
  double _voVolume = 1.0;
  bool _hapticEnabled = true;

  GameLabServices get _services => GameLabServices.instance;

  @override
  void initState() {
    super.initState();
    // Sync initial state from services
    _hapticEnabled = _services.hapticEnabled;
    _voEnabled = _services.voiceOverService.isEnabled;
    _voVolume = _services.voiceOverService.volume;
    _sfxEnabled = _services.audioService.config.sfxEnabled;
    _musicEnabled = _services.audioService.config.musicEnabled;
  }

  /// Push updated audio config to the shared services.
  void _syncAudioConfig() {
    _services.updateAudioConfig(
      AudioConfig(
        musicVolume: _config.bgMusicVolume,
        sfxVolume: _config.sfxVolume,
        musicEnabled: _musicEnabled,
        sfxEnabled: _sfxEnabled,
      ),
    );
    _services.updateVoiceOverSettings(
      volume: _voVolume,
      enabled: _voEnabled,
    );
    _services.hapticEnabled = _hapticEnabled;
  }

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
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              ElevatedButton.icon(
                                onPressed: _launchGameFlow,
                                icon: const Icon(Icons.playlist_play, size: 18),
                                label: const Text('Test Game Flow'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF9B82C4),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 10),
                                ),
                              ),
                              ElevatedButton.icon(
                                onPressed: _launchRewardTester,
                                icon:
                                    const Icon(Icons.card_giftcard, size: 18),
                                label: const Text('Test Rewards'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF6B8BC4),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 10),
                                ),
                              ),
                              ElevatedButton.icon(
                                onPressed: _launchAudioTester,
                                icon: const Icon(Icons.headphones, size: 18),
                                label: const Text('Test Audio'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF4CAF50),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 10),
                                ),
                              ),
                              ElevatedButton.icon(
                                onPressed: _launchHapticTester,
                                icon: const Icon(Icons.vibration, size: 18),
                                label: const Text('Test Haptics'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF43A047),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 10),
                                ),
                              ),
                            ],
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

  void _launchGameFlow() {
    _syncAudioConfig();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GameFlowScreen(
          config: _config,
          gameIds: ['copy_me', 'do_what_i_say', 'my_turn_your_turn'],
        ),
      ),
    );
  }

  void _launchRewardTester() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const RewardTesterScreen(),
      ),
    );
  }

  void _launchAudioTester() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const AudioTesterScreen(),
      ),
    );
  }

  void _launchHapticTester() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const HapticTesterScreen(),
      ),
    );
  }

  void _launchGame(GameEntry entry) {
    _syncAudioConfig();
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

            // ── Audio Section ──────────────────────────────────────
            Row(
              children: [
                const Icon(Icons.volume_up_rounded,
                    color: AppColors.primaryPurple, size: 18),
                const SizedBox(width: 6),
                Text('Audio',
                    style: AppTextStyles.titleMedium
                        .copyWith(color: AppColors.primaryPurple)),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),

            // Music enabled toggle
            _buildToggleRow(
              label: 'Music',
              icon: Icons.music_note_rounded,
              value: _musicEnabled,
              onChanged: (v) => setState(() {
                _musicEnabled = v;
                _syncAudioConfig();
              }),
            ),

            // BG Music Volume
            _buildSliderSection(
              label: 'Music Volume',
              value: _config.bgMusicVolume,
              min: 0.0,
              max: 1.0,
              divisions: 10,
              displayValue: '${(_config.bgMusicVolume * 100).round()}%',
              icon: Icons.music_note_rounded,
              onChanged: (v) => setState(() {
                _config = _config.copyWith(bgMusicVolume: v);
                _syncAudioConfig();
              }),
            ),

            // SFX enabled toggle
            _buildToggleRow(
              label: 'SFX',
              icon: Icons.volume_up_rounded,
              value: _sfxEnabled,
              onChanged: (v) => setState(() {
                _sfxEnabled = v;
                _syncAudioConfig();
              }),
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
              onChanged: (v) => setState(() {
                _config = _config.copyWith(sfxVolume: v);
                _syncAudioConfig();
              }),
            ),

            const Divider(height: 24),

            // ── Voice-Over Section ─────────────────────────────────
            Row(
              children: [
                const Icon(Icons.record_voice_over_rounded,
                    color: AppColors.primaryPurple, size: 18),
                const SizedBox(width: 6),
                Text('Voice-Over',
                    style: AppTextStyles.titleMedium
                        .copyWith(color: AppColors.primaryPurple)),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),

            // VO enabled toggle
            _buildToggleRow(
              label: 'Voice-Over',
              icon: Icons.record_voice_over_rounded,
              value: _voEnabled,
              onChanged: (v) => setState(() {
                _voEnabled = v;
                _syncAudioConfig();
              }),
            ),

            // VO Volume
            _buildSliderSection(
              label: 'VO Volume',
              value: _voVolume,
              min: 0.0,
              max: 1.0,
              divisions: 10,
              displayValue: '${(_voVolume * 100).round()}%',
              icon: Icons.record_voice_over_rounded,
              onChanged: (v) => setState(() {
                _voVolume = v;
                _syncAudioConfig();
              }),
            ),

            const Divider(height: 24),

            // ── Haptic Section ─────────────────────────────────────
            _buildToggleRow(
              label: 'Haptic Feedback',
              icon: Icons.vibration_rounded,
              value: _hapticEnabled,
              onChanged: (v) => setState(() {
                _hapticEnabled = v;
                _services.hapticEnabled = v;
              }),
            ),

            const SizedBox(height: AppSpacing.md),

            // Reset button
            Center(
              child: TextButton.icon(
                onPressed: () => setState(() {
                  _config = GameConfig.defaults;
                  _sfxEnabled = true;
                  _musicEnabled = true;
                  _voEnabled = true;
                  _voVolume = 1.0;
                  _hapticEnabled = true;
                  _syncAudioConfig();
                }),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Reset to Defaults'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToggleRow({
    required String label,
    required IconData icon,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.mutedForeground),
          const SizedBox(width: 6),
          Expanded(
            child: Text(label, style: AppTextStyles.labelLarge),
          ),
          SizedBox(
            height: 28,
            child: Switch(
              value: value,
              onChanged: onChanged,
              activeThumbColor: AppColors.primaryPurple,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
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
