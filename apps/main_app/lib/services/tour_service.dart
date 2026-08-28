import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Remembers whether the parent has already been walked through the
/// dashboard, so the guided tour runs once — on the first visit — and
/// afterwards only when the parent asks for it from the help button.
///
/// Deliberately fail-open: if the preference cannot be read we treat the
/// tour as *already seen*. A parent who loses storage gets no tour, which
/// is far less annoying than one that reappears on every launch.
class TourService {
  TourService._();

  static final TourService instance = TourService._();

  /// Bump the suffix when the dashboard changes enough that returning
  /// parents deserve the tour again.
  static const _parentTourKey = 'parent_dashboard_tour_seen_v1';

  bool? _cached;

  /// True when the parent dashboard tour has already been shown.
  Future<bool> hasSeenParentTour() async {
    final cached = _cached;
    if (cached != null) return cached;
    try {
      final prefs = await SharedPreferences.getInstance();
      return _cached = prefs.getBool(_parentTourKey) ?? false;
    } catch (e) {
      debugPrint('[TourService] Could not read tour flag: $e');
      return _cached = true;
    }
  }

  /// Records that the tour finished (or was skipped — same thing).
  Future<void> markParentTourSeen() async {
    _cached = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_parentTourKey, true);
    } catch (e) {
      debugPrint('[TourService] Could not save tour flag: $e');
    }
  }

  /// Test hook: forget the cached answer.
  @visibleForTesting
  void resetCache() => _cached = null;
}
