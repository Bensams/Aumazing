import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

/// The common frame of every settings page: the child's background gradient,
/// a back button, an icon and the page title, over a centred scrolling column.
///
/// Shared by the settings hub, its sub-pages and the child-profile screens so
/// they cannot drift apart visually.
class SettingsScaffold extends StatelessWidget {
  const SettingsScaffold({
    super.key,
    required this.title,
    required this.icon,
    required this.palette,
    required this.children,
    this.floatingActionButton,
  });

  final String title;
  final IconData icon;
  final GamePalette palette;
  final List<Widget> children;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: floatingActionButton,
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

/// A white rounded panel grouping related settings controls.
class SettingsCard extends StatelessWidget {
  const SettingsCard({super.key, required this.children});

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

/// Small muted caption under a control, explaining what it changes.
class SettingsHintText extends StatelessWidget {
  const SettingsHintText(this.text, {super.key});

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
