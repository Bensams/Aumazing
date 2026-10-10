import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../core/web/offline_save_status.dart';

/// Settings › Offline Play (web only): how far the games have got saving in
/// the background, so a parent knows when it is safe to play without
/// internet. Hidden on Android and iOS, where every file ships in the app.
class OfflinePlayTile extends StatelessWidget {
  const OfflinePlayTile({super.key, this.status});

  /// Defaults to [OfflineSaveStatus.instance].
  final OfflineSaveStatus? status;

  @override
  Widget build(BuildContext context) {
    final source = status ?? OfflineSaveStatus.instance;
    return ListenableBuilder(
      listenable: source,
      builder: (context, _) {
        final progress = source.progress;
        if (progress == null) return const SizedBox.shrink();
        return _OfflinePlayCard(progress: progress);
      },
    );
  }
}

class _OfflinePlayCard extends StatelessWidget {
  const _OfflinePlayCard({required this.progress});

  final OfflineSaveProgress progress;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (progress.state) {
      OfflineSaveState.ready => (
        Icons.offline_pin_rounded,
        AppColors.statusSuccessDark,
      ),
      OfflineSaveState.paused => (
        Icons.cloud_off_rounded,
        AppColors.statusWarningDark,
      ),
      OfflineSaveState.unavailable => (
        Icons.cloud_off_rounded,
        AppColors.textSecondary,
      ),
      OfflineSaveState.checking || OfflineSaveState.saving => (
        Icons.cloud_download_rounded,
        AppColors.statusInfoDark,
      ),
    };
    final showBar =
        progress.state == OfflineSaveState.saving ||
        progress.state == OfflineSaveState.paused ||
        progress.state == OfflineSaveState.checking;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Material(
        key: const Key('offline-play-tile'),
        color: AppColors.white.withAlpha(240),
        borderRadius: BorderRadius.circular(20),
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
                      'Offline Play',
                      style: AppTextStyles.titleMedium.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      progress.summary,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    if (showBar) ...[
                      const SizedBox(height: AppSpacing.sm),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          // Indeterminate while checking what is saved.
                          value:
                              progress.state == OfflineSaveState.checking
                                  ? null
                                  : progress.fraction ?? 0,
                          minHeight: 8,
                          color: color,
                          backgroundColor: color.withValues(alpha: 0.14),
                          semanticsLabel: 'Saved for offline play',
                          semanticsValue: '${progress.percent}%',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
