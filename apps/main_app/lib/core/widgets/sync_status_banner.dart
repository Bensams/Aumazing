import 'dart:async';

import 'package:flutter/material.dart';

import 'package:shared_ui/shared_ui.dart';

import '../services/connectivity_service.dart';
import '../services/sync_service.dart';

/// Compact banner telling a parent where their data stands: how many changes
/// are held on the device, whether they are moving, and when everything has
/// landed.
///
/// The plumbing already existed — [SyncService.onSyncStateChanged] and
/// [SyncService.getTotalPendingCount] — but nothing rendered it, so an
/// offline session gave no sign that work was being kept safely. The counts
/// are what make offline-first legible: "saved on this device" is reassuring
/// in a way that a bare "offline" is not.
///
/// Hidden entirely in the steady state (online, nothing pending) so it costs
/// no space on a normal run.
class SyncStatusBanner extends StatefulWidget {
  /// Takes the three signals it reads rather than the services themselves:
  /// [SyncService] resolves a Supabase client at construction, so a widget
  /// test could not build one. Left unset, each falls back to the global
  /// service.
  const SyncStatusBanner({
    super.key,
    this.syncStates,
    this.pendingCount,
    this.connectivityChanges,
    this.initiallyOnline,
    this.syncedVisibleFor = const Duration(seconds: 4),
  });

  final Stream<SyncState>? syncStates;
  final Future<int> Function()? pendingCount;
  final Stream<bool>? connectivityChanges;
  final bool? initiallyOnline;

  /// How long "All synced" lingers before the banner retreats.
  final Duration syncedVisibleFor;

  @override
  State<SyncStatusBanner> createState() => _SyncStatusBannerState();
}

class _SyncStatusBannerState extends State<SyncStatusBanner> {
  late final Future<int> Function() _pendingCount;

  StreamSubscription<SyncState>? _syncSub;
  StreamSubscription<bool>? _connectivitySub;
  Timer? _hideTimer;

  bool _online = true;
  int _pending = 0;
  SyncState _state = SyncState.idle();
  bool _showSynced = false;

  @override
  void initState() {
    super.initState();
    _pendingCount = widget.pendingCount ?? syncService.getTotalPendingCount;
    _online = widget.initiallyOnline ?? connectivityService.isOnline;

    final connectivityChanges =
        widget.connectivityChanges ?? connectivityService.onConnectivityChanged;
    _connectivitySub = connectivityChanges.listen((online) {
      if (!mounted) return;
      setState(() => _online = online);
      _refreshPending();
    });

    final syncStates = widget.syncStates ?? syncService.onSyncStateChanged;
    _syncSub = syncStates.listen((state) {
      if (!mounted) return;
      setState(() => _state = state);
      _refreshPending();
    });

    _refreshPending();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _syncSub?.cancel();
    _connectivitySub?.cancel();
    super.dispose();
  }

  Future<void> _refreshPending() async {
    int pending;
    try {
      pending = await _pendingCount();
    } catch (_) {
      // A count we cannot read must not take the banner down with it —
      // treat it as nothing pending and let the next event correct us.
      pending = 0;
    }
    if (!mounted) return;

    // Everything landed while we were watching: say so, briefly.
    final justFinished =
        pending == 0 && _pending > 0 && _online && !_state.isSyncing;
    setState(() {
      _pending = pending;
      if (justFinished) _showSynced = true;
    });

    if (justFinished) {
      _hideTimer?.cancel();
      _hideTimer = Timer(widget.syncedVisibleFor, () {
        if (mounted) setState(() => _showSynced = false);
      });
    }
  }

  String _plural(int n) => n == 1 ? '1 change' : '$n changes';

  @override
  Widget build(BuildContext context) {
    final _BannerLook? look = _look();
    if (look == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: look.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: look.foreground.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            if (look.spinner)
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: look.foreground,
                ),
              )
            else
              Icon(look.icon, size: 18, color: look.foreground),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                look.message,
                style: AppTextStyles.bodySmall.copyWith(
                  color: look.foreground,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Offline outranks everything: it explains every other state, and it is
  /// the one a parent can act on.
  _BannerLook? _look() {
    if (!_online) {
      return _BannerLook(
        icon: Icons.cloud_off_rounded,
        background: AppColors.statusWarningBg,
        foreground: AppColors.statusWarningDark,
        message: _pending > 0
            ? 'Offline — ${_plural(_pending)} saved on this device'
            : 'Offline — you can keep playing',
      );
    }

    if (_state.isSyncing) {
      return _BannerLook(
        icon: Icons.sync_rounded,
        background: AppColors.statusInfoBg,
        foreground: AppColors.statusInfoDark,
        spinner: true,
        message: _pending > 0
            ? 'Syncing ${_plural(_pending)}…'
            : 'Syncing…',
      );
    }

    if (_state.hasError || _state.hasPartialFailure) {
      return _BannerLook(
        icon: Icons.cloud_queue_rounded,
        background: AppColors.statusWarningBg,
        foreground: AppColors.statusWarningDark,
        message: "Some changes haven't synced yet — we'll keep trying",
      );
    }

    if (_pending > 0) {
      return _BannerLook(
        icon: Icons.cloud_upload_rounded,
        background: AppColors.statusInfoBg,
        foreground: AppColors.statusInfoDark,
        message: '${_plural(_pending)} waiting to sync',
      );
    }

    if (_showSynced) {
      return _BannerLook(
        icon: Icons.cloud_done_rounded,
        background: AppColors.statusSuccessBg,
        foreground: AppColors.statusSuccessDark,
        message: 'All synced',
      );
    }

    return null;
  }
}

class _BannerLook {
  const _BannerLook({
    required this.icon,
    required this.background,
    required this.foreground,
    required this.message,
    this.spinner = false,
  });

  final IconData icon;
  final Color background;
  final Color foreground;
  final String message;
  final bool spinner;
}
