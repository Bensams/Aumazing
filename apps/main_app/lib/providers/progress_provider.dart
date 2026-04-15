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

  ProgressProvider({LocalDbService? localDb})
      : _localDb = localDb ?? LocalDbService();

  List<ModuleProgress> get modules => _modules;
  List<GameplaySession> get recentSessions => _recentSessions;
  bool get isLoading => _isLoading;

  int get completedModules =>
      _modules.where((m) => m.isCompleted).length;
  int get inProgressModules =>
      _modules.where((m) => m.isInProgress).length;
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
  Future<void> loadProgress(String childId) async {
    _isLoading = true;
    notifyListeners();

    try {
      _modules = await _localDb.getModuleProgress(childId);
      _recentSessions = await _localDb.getSessionsForChild(childId);
    } catch (e) {
      debugPrint('[ProgressProvider] loadProgress error: $e');
    } finally {
      _isLoading = false;
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
  void addSession(GameplaySession session) {
    _recentSessions.insert(0, session);
    notifyListeners();
  }

  void clear() {
    _modules.clear();
    _recentSessions.clear();
    notifyListeners();
  }
}
