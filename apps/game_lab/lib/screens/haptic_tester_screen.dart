import 'package:flutter/material.dart';
import 'package:shared_haptic/shared_haptic.dart';
import 'package:shared_ui/shared_ui.dart';

import '../services/game_lab_services.dart';

/// A dedicated screen for testing all haptic feedback types in Game Lab.
///
/// Provides controls to:
/// - Trigger each standard haptic pattern via [HapticService]
/// - Fire custom multi-step haptic sequences (double tap, heartbeat, etc.)
/// - Toggle haptic feedback on/off
/// - See the last triggered pattern name
class HapticTesterScreen extends StatefulWidget {
  const HapticTesterScreen({super.key});

  @override
  State<HapticTesterScreen> createState() => _HapticTesterScreenState();
}

class _HapticTesterScreenState extends State<HapticTesterScreen> {
  final _services = GameLabServices.instance;

  HapticService get _hapticService => GameLabServices.instance.hapticService;

  String _lastPattern = 'None';

  bool get _hapticEnabled => _hapticService.config.enabled;

  // ── Pattern descriptions for the info panel ──────────────────────────
  static const Map<String, String> _patternDescriptions = {
    // Standard
    'lightImpact': 'A light tap sensation. Ideal for subtle UI confirmations '
        'like toggling a switch or selecting a list item.',
    'mediumImpact': 'A medium tap sensation. Good for confirming actions like '
        'button presses or drag-and-drop placement.',
    'heavyImpact': 'A strong tap sensation. Use for significant events like '
        'errors, warnings, or completing a major action.',
    'selectionClick': 'A brief click for selection changes. Perfect for '
        'picker wheels, segmented controls, or stepping through options.',
    'vibrate': 'The default system vibration. A longer, more noticeable buzz '
        'suitable for alerts or notifications.',
    // Custom
    'doubleTap': 'Two quick light impacts with a 100ms gap. Mimics a '
        'double-tap confirmation gesture.',
    'triplePulse': 'Three medium impacts spaced 150ms apart. Creates a '
        'rhythmic pulsing effect for progress or counting.',
    'success': 'An ascending pattern: light → medium → heavy. Conveys '
        'building intensity, great for success/completion feedback.',
    'error': 'Two heavy impacts with a pause between them. A jarring double '
        'buzz that signals something went wrong.',
    'heartbeat': 'Two quick heavy impacts, a pause, then two more. Mimics '
        'a heartbeat rhythm for emotional or health-related cues.',
  };

  // ── Trigger helpers ──────────────────────────────────────────────────

  void _triggerLightImpact() {
    _hapticService.lightImpact();
    setState(() => _lastPattern = 'Light Impact');
  }

  void _triggerMediumImpact() {
    _hapticService.mediumImpact();
    setState(() => _lastPattern = 'Medium Impact');
  }

  void _triggerHeavyImpact() {
    _hapticService.heavyImpact();
    setState(() => _lastPattern = 'Heavy Impact');
  }

  void _triggerSelectionClick() {
    _hapticService.selectionClick();
    setState(() => _lastPattern = 'Selection Click');
  }

  void _triggerVibrate() {
    _hapticService.vibrate();
    setState(() => _lastPattern = 'Vibrate');
  }

  // Custom patterns — delegated to HapticService
  void _triggerDoubleTap() {
    _hapticService.doubleTap();
    setState(() => _lastPattern = 'Double Tap');
  }

  void _triggerTriplePulse() {
    _hapticService.triplePulse();
    setState(() => _lastPattern = 'Triple Pulse');
  }

  void _triggerSuccess() {
    _hapticService.successPattern();
    setState(() => _lastPattern = 'Success');
  }

  void _triggerError() {
    _hapticService.errorPattern();
    setState(() => _lastPattern = 'Error');
  }

  void _triggerHeartbeat() {
    _hapticService.heartbeatPattern();
    setState(() => _lastPattern = 'Heartbeat');
  }

  // ── Build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration:
            const BoxDecoration(gradient: AppGradients.parentLavenderMint),
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '📳 Haptic Feedback Tester',
                      style: AppTextStyles.headlineMedium.copyWith(
                        color: AppColors.primaryPurple,
                      ),
                    ),
                    const Spacer(),
                    // Status chip
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Last: $_lastPattern',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Main content
              Expanded(
                child: Row(
                  children: [
                    // ── Left: Haptic pattern buttons ─────────────────
                    SizedBox(
                      width: 260,
                      child: _buildPatternPanel(),
                    ),

                    // ── Right: Info / documentation ─────────────────
                    Expanded(
                      child: _buildInfoPanel(),
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

  Widget _buildPatternPanel() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 6, 12),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(230),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Haptic toggle
            Row(
              children: [
                Icon(
                  Icons.vibration_rounded,
                  size: 18,
                  color: _hapticEnabled
                      ? AppColors.primaryPurple
                      : AppColors.mutedForeground,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Haptics Enabled',
                    style: AppTextStyles.labelLarge,
                  ),
                ),
                SizedBox(
                  height: 28,
                  child: Switch(
                    value: _hapticEnabled,
                    onChanged: (v) => setState(() {
                      _hapticService.updateConfig(
                        _hapticService.config.copyWith(enabled: v),
                      );
                      _services.hapticEnabled = v;
                    }),
                    activeThumbColor: AppColors.primaryPurple,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),

            if (!_hapticEnabled) ...[
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        size: 16, color: Colors.orange.shade700),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Haptics are disabled. Toggle on to test.',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.orange.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 16),

            // Standard Patterns
            Text('🔹 Standard Patterns',
                style: AppTextStyles.titleMedium
                    .copyWith(color: AppColors.primaryPurple)),
            const SizedBox(height: 10),

            _HapticButton(
              label: '💡 Light Impact',
              enabled: _hapticEnabled,
              onTap: _triggerLightImpact,
            ),
            _HapticButton(
              label: '✋ Medium Impact',
              enabled: _hapticEnabled,
              onTap: _triggerMediumImpact,
            ),
            _HapticButton(
              label: '💪 Heavy Impact',
              enabled: _hapticEnabled,
              onTap: _triggerHeavyImpact,
            ),
            _HapticButton(
              label: '👆 Selection Click',
              enabled: _hapticEnabled,
              onTap: _triggerSelectionClick,
            ),
            _HapticButton(
              label: '📳 Vibrate',
              enabled: _hapticEnabled,
              onTap: _triggerVibrate,
            ),

            const Divider(height: 24),

            // Custom Patterns
            Text('🔸 Custom Patterns',
                style: AppTextStyles.titleMedium
                    .copyWith(color: AppColors.primaryPurple)),
            const SizedBox(height: 10),

            _HapticButton(
              label: '👏 Double Tap',
              enabled: _hapticEnabled,
              onTap: _triggerDoubleTap,
            ),
            _HapticButton(
              label: '🫀 Triple Pulse',
              enabled: _hapticEnabled,
              onTap: _triggerTriplePulse,
            ),
            _HapticButton(
              label: '✅ Success',
              enabled: _hapticEnabled,
              onTap: _triggerSuccess,
            ),
            _HapticButton(
              label: '❌ Error',
              enabled: _hapticEnabled,
              onTap: _triggerError,
            ),
            _HapticButton(
              label: '💓 Heartbeat',
              enabled: _hapticEnabled,
              onTap: _triggerHeartbeat,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoPanel() {
    return Container(
      margin: const EdgeInsets.fromLTRB(6, 0, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(230),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text('📖 Pattern Reference',
                style: AppTextStyles.titleMedium
                    .copyWith(color: AppColors.primaryPurple)),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                // Device note
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline_rounded,
                          size: 18, color: Colors.blue.shade700),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Haptic feedback only works on physical devices. '
                          'Emulators and desktop platforms will not produce '
                          'vibration. Test on a real iOS or Android device '
                          'for accurate results.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blue.shade800,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Standard section
                _buildSectionHeader('Standard Patterns'),
                const SizedBox(height: 8),
                _buildDescriptionCard(
                    'Light Impact', _patternDescriptions['lightImpact']!),
                _buildDescriptionCard(
                    'Medium Impact', _patternDescriptions['mediumImpact']!),
                _buildDescriptionCard(
                    'Heavy Impact', _patternDescriptions['heavyImpact']!),
                _buildDescriptionCard('Selection Click',
                    _patternDescriptions['selectionClick']!),
                _buildDescriptionCard(
                    'Vibrate', _patternDescriptions['vibrate']!),

                const SizedBox(height: 16),

                // Custom section
                _buildSectionHeader('Custom Patterns'),
                const SizedBox(height: 8),
                _buildDescriptionCard(
                    'Double Tap', _patternDescriptions['doubleTap']!),
                _buildDescriptionCard(
                    'Triple Pulse', _patternDescriptions['triplePulse']!),
                _buildDescriptionCard(
                    'Success', _patternDescriptions['success']!),
                _buildDescriptionCard(
                    'Error', _patternDescriptions['error']!),
                _buildDescriptionCard(
                    'Heartbeat', _patternDescriptions['heartbeat']!),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: AppTextStyles.titleMedium.copyWith(
        color: AppColors.primaryPurple,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _buildDescriptionCard(String name, String description) {
    final isActive = _lastPattern == name;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isActive ? AppColors.lavenderLight : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isActive ? AppColors.primaryPurple : AppColors.border,
          width: isActive ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: isActive
                  ? AppColors.primaryPurple
                  : AppColors.foreground,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            description,
            style: TextStyle(
              fontSize: 11,
              color: AppColors.mutedForeground,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Animated Haptic Button ─────────────────────────────────────────────

/// A button that briefly scales down when tapped, providing visual feedback
/// alongside the haptic vibration.
class _HapticButton extends StatefulWidget {
  const _HapticButton({
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_HapticButton> createState() => _HapticButtonState();
}

class _HapticButtonState extends State<_HapticButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.92).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTap() {
    if (!widget.enabled) return;
    _controller.forward().then((_) => _controller.reverse());
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: SizedBox(
          width: double.infinity,
          height: 36,
          child: ElevatedButton(
            onPressed: widget.enabled ? _handleTap : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.lavenderLight,
              foregroundColor: AppColors.primaryPurple,
              disabledBackgroundColor: Colors.grey.shade200,
              disabledForegroundColor: Colors.grey.shade400,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(widget.label,
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ),
      ),
    );
  }
}
