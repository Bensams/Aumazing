import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../services/offline_web_service.dart';
import 'widgets/settings_scaffold.dart';

/// Settings page for the web build (AUM-334): shows whether the app and its
/// games are saved for offline play, and lets a parent save everything now
/// instead of waiting for the background download.
class OfflinePlayScreen extends StatefulWidget {
  const OfflinePlayScreen({
    super.key,
    required this.palette,
    this.service = const OfflineWebService(),
  });

  final GamePalette palette;
  final OfflineWebService service;

  @override
  State<OfflinePlayScreen> createState() => _OfflinePlayScreenState();
}

class _OfflinePlayScreenState extends State<OfflinePlayScreen> {
  OfflineStatus? _status;
  bool _loading = true;
  bool _downloading = false;
  bool _downloadFailed = false;
  int _done = 0;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final status = await widget.service.status();
    if (!mounted) return;
    setState(() {
      _status = status;
      _loading = false;
    });
  }

  Future<void> _downloadAll() async {
    setState(() {
      _downloading = true;
      _downloadFailed = false;
      _done = 0;
      _total = 0;
    });
    final status = await widget.service.downloadAll(
      onProgress: (done, total) {
        if (!mounted) return;
        setState(() {
          _done = done;
          _total = total;
        });
      },
    );
    if (!mounted) return;
    setState(() {
      _downloading = false;
      _downloadFailed = status == null || !status.fullyReady;
      if (status != null) _status = status;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SettingsScaffold(
      title: 'Offline Play',
      icon: Icons.cloud_off_rounded,
      palette: widget.palette,
      children: [
        SettingsCard(
          children:
              _loading
                  ? const [Center(child: CircularProgressIndicator())]
                  : _status == null
                  ? _unavailable()
                  : _details(_status!),
        ),
      ],
    );
  }

  List<Widget> _unavailable() => [
    Text(
      'Offline play is not ready yet',
      style: AppTextStyles.labelLarge.copyWith(color: AppColors.textPrimary),
    ),
    const SizedBox(height: AppSpacing.sm),
    const SettingsHintText(
      'Open Aumazing once with an internet connection and it will start '
      'saving itself for offline play. Offline play needs a browser that '
      'supports it, such as Safari or Chrome.',
    ),
  ];

  List<Widget> _details(OfflineStatus status) {
    final percent = (status.fraction * 100).floor();
    return [
      _StatusRow(
        ready: status.appReady,
        label:
            status.appReady
                ? 'The app opens without internet'
                : 'Saving the app for offline use…',
      ),
      const SizedBox(height: AppSpacing.sm),
      _StatusRow(
        ready: status.fullyReady,
        label:
            status.fullyReady
                ? 'Every game and its sounds are saved'
                : 'Games saved so far: $percent%',
      ),
      const SizedBox(height: AppSpacing.md),
      if (_downloading) ...[
        LinearProgressIndicator(
          value: _total == 0 ? null : _done / _total,
          color: widget.palette.primary,
        ),
        const SizedBox(height: AppSpacing.xs),
        SettingsHintText(
          _total == 0 ? 'Getting ready…' : 'Saved $_done of $_total files',
        ),
        const SizedBox(height: AppSpacing.md),
      ],
      if (!status.fullyReady)
        AppPrimaryButton(
          key: const Key('offline-download-all'),
          label: 'Save everything now',
          icon: Icons.download_rounded,
          onPressed: _downloading ? null : _downloadAll,
          isLoading: _downloading,
        ),
      if (_downloadFailed) ...[
        const SizedBox(height: AppSpacing.sm),
        const SettingsHintText(
          'Some files could not be saved. Check the internet connection and '
          'try again.',
        ),
      ],
      const SizedBox(height: AppSpacing.md),
      const SettingsHintText(
        'Aumazing saves itself in the background while it is open online. '
        'On iPhone and iPad, add it to the Home Screen so Safari keeps these '
        'files. Progress made offline is uploaded when the connection returns.',
      ),
    ];
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.ready, required this.label});

  final bool ready;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          ready ? Icons.check_circle_rounded : Icons.downloading_rounded,
          color: ready ? AppColors.statusSuccessDark : AppColors.textSecondary,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            label,
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}
