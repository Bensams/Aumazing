import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

/// Theme Lab — preview the boy / girl / neutral palettes applied to both a
/// child game background and a parent dashboard, and switch between them live.
///
/// Validates the [AppThemeScope] / [GamePalette] system from shared_ui before
/// it is wired into main_app. The default theme is derived from the child's sex
/// (simulated here with a dropdown); the parent can override it with the chips.
class ThemeLabScreen extends StatefulWidget {
  const ThemeLabScreen({super.key});

  @override
  State<ThemeLabScreen> createState() => _ThemeLabScreenState();
}

class _ThemeLabScreenState extends State<ThemeLabScreen> {
  final AppThemeController _controller = AppThemeController(GameTheme.neutral);
  final AppLanguageController _lang =
      AppLanguageController(GameLanguage.english);

  /// Simulated child sex, to demonstrate the auto-from-sex default.
  String _simulatedSex = 'prefer_not_to_say';

  @override
  void dispose() {
    _controller.dispose();
    _lang.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppThemeScope(
      controller: _controller,
      child: AppLanguageScope(
        controller: _lang,
        child: ListenableBuilder(
          listenable: Listenable.merge([_controller, _lang]),
          builder: (context, _) {
            final palette = _controller.palette;
            final strings = _lang.strings;
            return Scaffold(
              appBar: AppBar(
                title: const Text('Theme & Language Lab'),
                backgroundColor: palette.primary,
                foregroundColor: palette.onPrimary,
              ),
              body: Container(
                decoration: BoxDecoration(gradient: palette.parentBackground),
                child: SafeArea(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildControls(palette),
                        const SizedBox(height: 24),
                        _sectionLabel('Child game background', palette),
                        const SizedBox(height: 8),
                        _buildGamePreview(palette, strings),
                        const SizedBox(height: 24),
                        _sectionLabel('Parent dashboard', palette),
                        const SizedBox(height: 8),
                        _buildDashboardPreview(palette),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // ── Controls ─────────────────────────────────────────────────────────

  Widget _buildControls(GamePalette palette) {
    return Card(
      color: Colors.white.withAlpha(230),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Theme (parent can override)',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: GameTheme.values.map((t) {
                final selected = _controller.theme == t;
                return ChoiceChip(
                  label: Text(t.label),
                  selected: selected,
                  selectedColor: palette.primary,
                  labelStyle: TextStyle(
                    color: selected ? palette.onPrimary : AppColors.foreground,
                    fontWeight: FontWeight.w600,
                  ),
                  onSelected: (_) => _controller.setTheme(t),
                );
              }).toList(),
            ),
            const Divider(height: 28),
            const Text('Simulated child sex (auto-default)',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: _simulatedSex,
                    items: const [
                      DropdownMenuItem(value: 'male', child: Text('male → Boy')),
                      DropdownMenuItem(
                          value: 'female', child: Text('female → Girl')),
                      DropdownMenuItem(
                          value: 'prefer_not_to_say',
                          child: Text('prefer not to say → Neutral')),
                    ],
                    onChanged: (v) {
                      setState(() => _simulatedSex = v ?? 'prefer_not_to_say');
                    },
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: () => _controller.setFromSex(_simulatedSex),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: palette.primary,
                    foregroundColor: palette.onPrimary,
                  ),
                  icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
                  label: const Text('Apply from sex'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Active: ${palette.theme.label}',
              style: TextStyle(
                color: palette.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Divider(height: 28),
            const Text('Language',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: GameLanguage.values.map((l) {
                final selected = _lang.language == l;
                return ChoiceChip(
                  label: Text(l.label),
                  selected: selected,
                  selectedColor: palette.primary,
                  labelStyle: TextStyle(
                    color: selected ? palette.onPrimary : AppColors.foreground,
                    fontWeight: FontWeight.w600,
                  ),
                  onSelected: (_) => _lang.setLanguage(l),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  // ── Previews ─────────────────────────────────────────────────────────

  Widget _sectionLabel(String text, GamePalette palette) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: AppColors.foreground,
      ),
    );
  }

  Widget _buildGamePreview(GamePalette palette, AppStrings strings) {
    // A mini sari-sari-style scene to show the game background + accents.
    final items = <(String, Color)>[
      ('🍌', const Color(0xFFF5D547)),
      ('🥛', const Color(0xFFF1EEE2)),
      ('🧼', const Color(0xFF8BC36A)),
    ];
    return Container(
      height: 200,
      decoration: BoxDecoration(
        gradient: palette.gameBackground,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.primary.withAlpha(60), width: 2),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: palette.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                strings.sortInstruction,
                style: TextStyle(
                  color: palette.onPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (final (emoji, color) in items)
                _itemChip(emoji, color),
            ],
          ),
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _binChip(strings.binToys, palette.primary),
              _binChip(strings.binFood, palette.accent),
              _binChip(strings.binEssentials, palette.accent),
            ],
          ),
        ],
      ),
    );
  }

  Widget _itemChip(String emoji, Color color) {
    return Container(
      width: 52,
      height: 52,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withAlpha(200), width: 2),
      ),
      child: Text(emoji, style: const TextStyle(fontSize: 26)),
    );
  }

  Widget _binChip(String label, Color color) {
    return Container(
      width: 90,
      padding: const EdgeInsets.symmetric(vertical: 8),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withAlpha(210), width: 2),
      ),
      child: Text(
        label,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _buildDashboardPreview(GamePalette palette) {
    return Container(
      decoration: BoxDecoration(
        color: palette.cardSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.primary.withAlpha(50), width: 1.5),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: palette.primary,
                child: Text('🐻', style: const TextStyle(fontSize: 20)),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Juan, 4 yrs',
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary)),
                  Text('Latest assessment cycle',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 12)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          _skillBar('Communication', 0.7, palette.primary),
          const SizedBox(height: 10),
          _skillBar('Social', 0.45, palette.accent),
          const SizedBox(height: 10),
          _skillBar('Play', 0.85, palette.primary),
          const SizedBox(height: 16),
          Row(
            children: [
              _statTile('Modules', '12', palette.primary),
              const SizedBox(width: 12),
              _statTile('Accuracy', '78%', palette.accent),
              const SizedBox(width: 12),
              _statTile('Streak', '5 days', palette.primary),
            ],
          ),
        ],
      ),
    );
  }

  Widget _skillBar(String label, double value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary)),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: value,
            minHeight: 10,
            backgroundColor: Colors.white.withAlpha(180),
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ],
    );
  }

  Widget _statTile(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(190),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withAlpha(70)),
        ),
        child: Column(
          children: [
            Text(value,
                style: TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 18, color: color)),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(
                    fontSize: 11, color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}
