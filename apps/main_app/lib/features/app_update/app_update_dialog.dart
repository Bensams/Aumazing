import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import 'app_update_service.dart';

/// Opens the update dialog: what is new, the download, and the hand-off to
/// Android's installer. Used by the dashboard banner and Settings.
Future<void> showAppUpdateDialog(
  BuildContext context, {
  AppUpdateService? service,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => AppUpdateDialog(service: service),
  );
}

class AppUpdateDialog extends StatefulWidget {
  const AppUpdateDialog({super.key, this.service});

  /// Defaults to [AppUpdateService.instance]; injectable for tests.
  final AppUpdateService? service;

  @override
  State<AppUpdateDialog> createState() => _AppUpdateDialogState();
}

class _AppUpdateDialogState extends State<AppUpdateDialog>
    with WidgetsBindingObserver {
  late final AppUpdateService _service =
      widget.service ?? AppUpdateService.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Opened from Settings with nothing on offer yet: look now.
    if (_service.latest == null && !_service.isBusy) {
      _service.check();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Back from Android's "install unknown apps" page: carry straight on to
  /// the installer, which re-checks the permission itself.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _service.status == AppUpdateStatus.needsPermission) {
      _service.install();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _service,
      builder: (context, _) {
        final status = _service.status;
        final release = _service.latest;
        final installed = _service.installed;
        final required = _service.isRequired;

        final title = switch (status) {
          AppUpdateStatus.checking => 'Checking for updates',
          AppUpdateStatus.upToDate => "You're up to date",
          _ when release == null => 'App updates',
          _ when required => 'Update required',
          _ => 'Version ${release.versionName} is ready',
        };

        final lines = <Widget>[];
        void addText(String text, {Color? color, bool bold = false}) {
          lines.add(
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text(
                text,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: color ?? AppColors.textPrimary,
                  fontWeight: bold ? FontWeight.w600 : null,
                ),
              ),
            ),
          );
        }

        if (status == AppUpdateStatus.checking) {
          lines.add(const Center(child: CircularProgressIndicator()));
        } else if (status == AppUpdateStatus.upToDate) {
          addText(
            'Aumazing ${installed?.name ?? ''} is the latest version.'.trim(),
          );
        } else if (release != null) {
          addText(
            required
                ? 'This version (${installed?.name}) is no longer supported. '
                    'Please update to keep using Aumazing.'
                : 'You have version ${installed?.name}. Updating keeps every '
                    'child profile, star and result on this device.',
          );
          if (release.releaseNotes != null) {
            addText("What's new", bold: true);
            addText(release.releaseNotes!, color: AppColors.mutedForeground);
          }
        }

        switch (status) {
          case AppUpdateStatus.downloading:
            final progress = _service.progress;
            lines.add(
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: LinearProgressIndicator(value: progress),
              ),
            );
            addText(
              progress == null
                  ? 'Downloading…'
                  : 'Downloading… ${(progress * 100).floor()}%',
              color: AppColors.mutedForeground,
            );
          case AppUpdateStatus.needsPermission:
            addText(
              'Android needs your OK first. On the page that opened, turn on '
              '"Allow from this source", then come back here.',
              color: AppColors.statusWarningDark,
            );
          case AppUpdateStatus.readyToInstall:
            addText(
              "Tap Install on Android's screen to finish. Aumazing will "
              'restart on the new version.',
              color: AppColors.statusInfoDark,
            );
          case AppUpdateStatus.failed:
            addText(
              _service.error ?? 'Something went wrong. Try again.',
              color: AppColors.statusDangerDark,
            );
          default:
            break;
        }

        final String? actionLabel = switch (status) {
          _ when release == null =>
            status == AppUpdateStatus.failed ? 'Try again' : null,
          AppUpdateStatus.available => 'Update now',
          AppUpdateStatus.downloading => 'Downloading…',
          AppUpdateStatus.failed => 'Try again',
          _ => 'Install',
        };

        return AlertDialog(
          key: const Key('app-update-dialog'),
          title: Text(title),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: lines,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(release == null ? 'Close' : 'Later'),
            ),
            if (actionLabel != null)
              AppPrimaryButton(
                key: const Key('app-update-action'),
                label: actionLabel,
                icon: Icons.system_update_rounded,
                compact: true,
                isLoading: status == AppUpdateStatus.downloading,
                onPressed:
                    _service.isBusy
                        ? null
                        : release == null
                        ? _service.check
                        : _service.downloadAndInstall,
              ),
          ],
        );
      },
    );
  }
}
