import 'package:flutter/material.dart';

import 'package:shared_ui/shared_ui.dart';

import 'pre_assessment_progress_screen.dart';

/// Sensory preferences setup screen.
///
/// Lets the caregiver/child configure music, vibration, and animation
/// preferences before the assessment games begin.
class SensoryPreferencesScreen extends StatefulWidget {
  const SensoryPreferencesScreen({super.key});

  @override
  State<SensoryPreferencesScreen> createState() =>
      _SensoryPreferencesScreenState();
}

class _SensoryPreferencesScreenState extends State<SensoryPreferencesScreen> {
  bool _musicEnabled = true;
  double _musicVolume = 0.5;
  double _sfxVolume = 0.7;
  bool _vibrationEnabled = true;
  double _animationIntensity = 1.0;
  double _promptSpeed = 1.0; // 1.0 = normal

  Map<String, dynamic> get _settings => {
        'music_enabled': _musicEnabled,
        'music_volume': _musicVolume,
        'sfx_volume': _sfxVolume,
        'vibration_enabled': _vibrationEnabled,
        'animation_intensity': _animationIntensity,
        'prompt_speed': _promptSpeed,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppGradients.parentSkyButter),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('🎵', style: TextStyle(fontSize: 48)),
                  const SizedBox(height: 8),
                  Text(
                    'Sensory Preferences',
                    style: AppTextStyles.headlineLarge.copyWith(
                      color: AppColors.primaryPurple,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Adjust settings to make the experience comfortable.',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.mutedForeground,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),

                  _buildSettingsCard(),

                  const SizedBox(height: 24),

                  SizedBox(
                    width: 260,
                    child: AppPrimaryButton(
                      label: 'Start Games',
                      icon: Icons.play_arrow_rounded,
                      onPressed: () {
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                            builder: (_) => PreAssessmentProgressScreen(
                              sensorySettings: _settings,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white.withAlpha(200),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Music toggle
          _switchRow(
            icon: Icons.music_note_rounded,
            label: 'Background Music',
            value: _musicEnabled,
            onChanged: (v) => setState(() => _musicEnabled = v),
          ),
          if (_musicEnabled) ...[
            const SizedBox(height: 4),
            _sliderRow('Volume', _musicVolume,
                (v) => setState(() => _musicVolume = v)),
          ],
          const Divider(height: 20),

          // SFX
          _sliderRow('Sound Effects', _sfxVolume,
              (v) => setState(() => _sfxVolume = v)),
          const Divider(height: 20),

          // Vibration
          _switchRow(
            icon: Icons.vibration_rounded,
            label: 'Vibration',
            value: _vibrationEnabled,
            onChanged: (v) => setState(() => _vibrationEnabled = v),
          ),
          const Divider(height: 20),

          // Animation intensity
          _sliderRow('Animation Intensity', _animationIntensity,
              (v) => setState(() => _animationIntensity = v)),
          const Divider(height: 20),

          // Prompt speed
          _sliderRow('Prompt Speed', _promptSpeed,
              (v) => setState(() => _promptSpeed = v)),
        ],
      ),
    );
  }

  Widget _switchRow({
    required IconData icon,
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      children: [
        Icon(icon, color: AppColors.lavender, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Text(label, style: AppTextStyles.bodyMedium),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeTrackColor: AppColors.primaryPurple,
        ),
      ],
    );
  }

  Widget _sliderRow(
    String label,
    double value,
    ValueChanged<double> onChanged,
  ) {
    return Row(
      children: [
        SizedBox(
          width: 140,
          child: Text(label, style: AppTextStyles.bodySmall),
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
            style: AppTextStyles.bodySmall,
          ),
        ),
      ],
    );
  }
}
