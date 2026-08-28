import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Service for monitoring network connectivity status.
///
/// Provides streams and callbacks for connectivity changes, enabling
/// automatic sync when the device comes back online.
///
/// Usage:
/// ```dart
/// final connectivity = ConnectivityService();
/// connectivity.onConnectivityChanged.listen((isOnline) {
///   if (isOnline) syncService.startSync();
/// });
/// ```
class ConnectivityService {
  final Connectivity _connectivity = Connectivity();

  StreamSubscription<List<ConnectivityResult>>? _subscription;
  final _controller = StreamController<bool>.broadcast();

  bool _isOnline = true;
  bool _isInitialized = false;

  /// Current online status
  bool get isOnline => _isOnline;
  bool get isOffline => !_isOnline;

  /// Stream of connectivity changes (true = online, false = offline)
  Stream<bool> get onConnectivityChanged => _controller.stream;

  /// Initialize and start monitoring connectivity
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Check initial status
      final results = await _connectivity.checkConnectivity();
      _updateStatus(results);

      // Listen for changes
      _subscription = _connectivity.onConnectivityChanged.listen(
        _updateStatus,
        onError: (error) {
          debugPrint('[ConnectivityService] Stream error: $error');
          // Assume online on error to avoid blocking user
          _setOnlineStatus(true);
        },
      );

      _isInitialized = true;
      debugPrint('[ConnectivityService] Initialized: online=$_isOnline');
    } catch (e) {
      debugPrint('[ConnectivityService] Initialization error: $e');
      // Assume online if we can't determine status
      _setOnlineStatus(true);
    }
  }

  /// Update internal status from connectivity results
  void _updateStatus(List<ConnectivityResult> results) {
    // Consider online if any connection is not "none"
    final hasConnection = results.any(
      (result) => result != ConnectivityResult.none,
    );
    _setOnlineStatus(hasConnection);
  }

  /// Set online status and notify listeners if changed
  void _setOnlineStatus(bool online) {
    final wasOffline = !_isOnline && online;
    final previousStatus = _isOnline;

    _isOnline = online;

    if (previousStatus != online) {
      debugPrint('[ConnectivityService] Status changed: online=$online');
      _controller.add(online);
    }

    // Special callback for when coming back online
    if (wasOffline) {
      _onBackOnline();
    }
  }

  /// Called when device transitions from offline to online
  void _onBackOnline() {
    debugPrint('[ConnectivityService] Device back online - triggering sync');
    // SyncService will listen to this and trigger sync
  }

  /// Manually check current connectivity status
  Future<bool> checkConnectivity() async {
    try {
      final results = await _connectivity.checkConnectivity();
      final isConnected = results.any(
        (result) => result != ConnectivityResult.none,
      );
      _setOnlineStatus(isConnected);
      return isConnected;
    } catch (e) {
      debugPrint('[ConnectivityService] Check error: $e');
      return true; // Assume online on error
    }
  }

  /// Dispose and clean up resources
  void dispose() {
    _subscription?.cancel();
    _controller.close();
    _isInitialized = false;
  }
}

/// Global instance for app-wide access
final connectivityService = ConnectivityService();
