import 'package:flutter/foundation.dart';

import '../model/gameplay_session.dart';
import '../model/module_progress.dart';
import '../services/local_db_service.dart';

/// Tracks module progress, completed activities, and level progression.
class ProgressProvider extends ChangeNotifier {
  final LocalDbService _localDb;

  List<ModuleProgress> _modules = [];
  List<GameplaySession> _recentSessions = [];
  bool _isLoading = false;

  /// The child the latest [loadProgress] call was for — every write after an
  /// await re-checks it, so a slow load for a previously selected child can
  /// never overwrite the newly selected child's data (AUM-160).
  String? _loadedChildId;

  /// Bumped by every [loadProgress] and [clear]; only the latest load may
  /// end the loading state.
  int _loadGeneration = 0;

  ProgressProvider({LocalDbService? localDb})
    : _localDb = localDb ?? LocalDbService();

  List<ModuleProgress> get modules => _modules;
  List<GameplaySession> get recentSessions => _recentSessions;
  bool get isLoading => _isLoading;

  /// The child the latest [loadProgress] call was for, or null after
  /// [clear]. Lets callers verify whose data they are looking at.
  String? get loadedChildId => _loadedChildId;

  int get completedModules => _modules.where((m) => m.isCompleted).length;
  int get inProgressModules => _modules.where((m) => m.isInProgress).length;
  int get totalSessions => _recentSessions.length;

  ModuleProgress? get currentModule {
    final inProgress = _modules.where((m) => m.isInProgress).toList();
    if (inProgress.isNotEmpty) return inProgress.first;
    final notStarted =
        _modules.where((m) => m.status == 'not_started').toList();
    if (notStarted.isNotEmpty) return notStarted.first;
    return null;
  }

  GameplaySession? get lastSession =>
      _recentSessions.isNotEmpty ? _recentSessions.first : null;

  /// Loads all progress data for a child.
  ///
  /// Safe against child switches mid-load (AUM-160): results are only
  /// applied when [childId] is still the child of the latest call, so a
  /// slower load for the previous child finishes without effect.
  Future<void> loadProgress(String childId) async {
    final generation = ++_loadGeneration;
    if (_loadedChildId != null && _loadedChildId != childId) {
      // A different child without an explicit clear() in between — drop the
      // previous child's rows now rather than showing them under the new
      // child's name while the queries run.
      _modules = [];
      _recentSessions = [];
    }
    _loadedChildId = childId;
    _isLoading = true;
    notifyListeners();

    try {
      final modules = await _localDb.getModuleProgress(childId);
      final sessions = await _localDb.getSessionsForChild(childId);
      // A newer load (or clear()) took over while the queries ran — these
      // rows belong to a child no longer on screen.
      if (childId == _loadedChildId) {
        _modules = modules;
        _recentSessions = sessions;
      }
    } catch (e) {
      debugPrint('[ProgressProvider] loadProgress error: $e');
    } finally {
      // Only the latest load may end the loading state — an older one
      // finishing must not hide the spinner of the load still in flight.
      if (generation == _loadGeneration) {
        _isLoading = false;
      }
      notifyListeners();
    }
  }

  /// Updates module progress (e.g. after completing a level).
  Future<void> updateModuleProgress(ModuleProgress progress) async {
    await _localDb.upsertModuleProgress(progress);

    final idx = _modules.indexWhere((m) => m.id == progress.id);
    if (idx >= 0) {
      _modules[idx] = progress;
    } else {
      _modules.add(progress);
    }
    notifyListeners();
  }

  /// Adds a completed session to the recent list.
  ///
  /// Ignored when the session belongs to a child other than the one this
  /// provider is loaded for — a completion callback that lands after a
  /// switch must not put the previous child's session on the new dashboard.
  void addSession(GameplaySession session) {
    if (_loadedChildId != null && session.childId != _loadedChildId) {
      debugPrint(
        '[ProgressProvider] Ignored session for '
        '${session.childId} (loaded child: $_loadedChildId)',
      );
      return;
    }
    _recentSessions.insert(0, session);
    notifyListeners();
  }

  void clear() {
    _modules.clear();
    _recentSessions.clear();
    // Invalidate any load still in flight: its child is no longer loaded,
    // so its late writes are discarded rather than resurrected (AUM-160).
    _loadedChildId = null;
    _loadGeneration++;
    _isLoading = false;
    notifyListeners();
  }
}
