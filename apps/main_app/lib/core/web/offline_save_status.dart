/// How far the web build has got saving the games for offline play.
///
/// The loading page (web/offline.js) saves what the app needs to open, starts
/// it, and then saves every picture, voice line and song in the background
/// while the child plays. It publishes its progress as
/// `window.aumazingOffline`; this mirrors it for the Offline Play tile in
/// Settings. Always null on Android and iOS, where every file ships inside
/// the app.
library;

import 'package:flutter/foundation.dart';

import 'offline_save_status_stub.dart'
    if (dart.library.js_interop) 'offline_save_status_web.dart';

enum OfflineSaveState { checking, saving, paused, ready, unavailable }

/// Why saving is paused.
enum OfflinePauseReason { offline, retrying }

@immutable
class OfflineSaveProgress {
  const OfflineSaveProgress({
    required this.state,
    this.reason,
    this.doneBytes = 0,
    this.totalBytes = 0,
  });

  /// Reads the loading page's published values; null for a status this
  /// build does not know.
  static OfflineSaveProgress? parse({
    required String? status,
    String? reason,
    double? done,
    double? total,
  }) {
    final state = OfflineSaveState.values.asNameMap()[status];
    if (state == null) return null;
    return OfflineSaveProgress(
      state: state,
      reason: OfflinePauseReason.values.asNameMap()[reason],
      doneBytes: (done ?? 0).round(),
      totalBytes: (total ?? 0).round(),
    );
  }

  final OfflineSaveState state;
  final OfflinePauseReason? reason;
  final int doneBytes;
  final int totalBytes;

  /// Share of the files saved so far, or null when the total is not known.
  double? get fraction =>
      totalBytes > 0 ? (doneBytes / totalBytes).clamp(0.0, 1.0) : null;

  int get percent => ((fraction ?? 0) * 100).floor();

  /// One line for a parent.
  String get summary {
    String mb(int bytes) => (bytes / (1 << 20)).toStringAsFixed(0);
    switch (state) {
      case OfflineSaveState.checking:
        return 'Checking which games are saved…';
      case OfflineSaveState.saving:
        return 'Saving games for offline play · $percent% '
            '(${mb(doneBytes)} of ${mb(totalBytes)} MB)';
      case OfflineSaveState.paused:
        return reason == OfflinePauseReason.retrying
            ? 'Some files did not download · $percent% saved. '
                'Trying again shortly.'
            : 'Paused, no internet · $percent% saved. '
                'Saving resumes when you reconnect.';
      case OfflineSaveState.ready:
        return 'Ready: every game plays without internet';
      case OfflineSaveState.unavailable:
        return 'Not available in this browser window. '
            'Games load as they are played.';
    }
  }

  @override
  bool operator ==(Object other) =>
      other is OfflineSaveProgress &&
      other.state == state &&
      other.reason == reason &&
      other.doneBytes == doneBytes &&
      other.totalBytes == totalBytes;

  @override
  int get hashCode => Object.hash(state, reason, doneBytes, totalBytes);
}

class OfflineSaveStatus extends ChangeNotifier {
  OfflineSaveStatus._() {
    watchOfflineSaves(_update);
  }

  static final OfflineSaveStatus instance = OfflineSaveStatus._();

  OfflineSaveProgress? _progress;

  /// Null when this build does not save for offline play (Android, iOS, or
  /// a web build started without the loading page).
  OfflineSaveProgress? get progress => _progress;

  void _update(OfflineSaveProgress? progress) {
    if (progress == _progress) return;
    _progress = progress;
    notifyListeners();
  }

  @visibleForTesting
  void debugSetProgress(OfflineSaveProgress? progress) => _update(progress);
}
