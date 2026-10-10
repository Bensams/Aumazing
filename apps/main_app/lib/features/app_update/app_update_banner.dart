import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import 'app_update_dialog.dart';
import 'app_update_service.dart';

/// Parent-dashboard notice that a newer Aumazing build is out.
///
/// It lives on the parent dashboard only, never in child mode, so an update
/// never interrupts play. Hidden when there is nothing to offer, or once the
/// parent has set this version aside (a required update cannot be).
class AppUpdateBanner extends StatelessWidget {
  const AppUpdateBanner({super.key, this.service});

  /// Defaults to [AppUpdateService.instance]; injectable for tests.
  final AppUpdateService? service;

  @override
  Widget build(BuildContext context) {
    final service = this.service ?? AppUpdateService.instance;
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        final release = service.latest;
        if (release == null || !service.shouldPrompt) {
          return const SizedBox.shrink();
        }
        final required = service.isRequired;
        final background =
            required ? AppColors.statusWarningBg : AppColors.statusInfoBg;
        final foreground =
            required ? AppColors.statusWarningDark : AppColors.statusInfoDark;
        final message = switch (service.status) {
          AppUpdateStatus.downloading =>
            'Downloading version '
                '${release.versionName}…',
          AppUpdateStatus.readyToInstall || AppUpdateStatus.needsPermission =>
            'Version ${release.versionName} is downloaded — tap to install',
          _ when required => 'Update required: version ${release.versionName}',
          _ => 'Version ${release.versionName} of Aumazing is available',
        };

        return Padding(
          key: const Key('app-update-banner'),
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Material(
            color: background,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => showAppUpdateDialog(context, service: service),
              child: Container(
                padding: const EdgeInsets.only(
                  left: AppSpacing.md,
                  top: AppSpacing.xs,
                  bottom: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: foreground.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.system_update_rounded,
                      size: 18,
                      color: foreground,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        message,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: foreground,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed:
                          () => showAppUpdateDialog(context, service: service),
                      child: Text(
                        'Update',
                        style: TextStyle(color: foreground),
                      ),
                    ),
                    if (!required)
                      IconButton(
                        key: const Key('app-update-dismiss'),
                        tooltip: 'Not now',
                        icon: Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: foreground,
                        ),
                        onPressed: service.dismiss,
                      )
                    else
                      const SizedBox(width: AppSpacing.sm),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
