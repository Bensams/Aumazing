import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Per-child daily screen-time limits with age-based recommendations.
///
/// Recommended limits follow AAP/WHO guidance (≤1 hour/day of high-quality
/// content for ages 2–5, none before age 2, "less is better" at 2 per WHO)
/// tightened for ASD learners, who research shows are especially prone to
/// excessive screen use. The app's own session design (short 3–7 minute
/// games) means a small daily budget still fits several learning sessions.
///
/// Usage is tracked while the child is in child mode (lobby + practice
/// games). Assessments are not counted — they are short, infrequent, and
/// parent-initiated.
class ScreenTimeService extends ChangeNotifier {
  ScreenTimeService._();

  static final ScreenTimeService instance = ScreenTimeService._();

  String? _childId;
  int? _limitMinutes; // null or 0 = no limit
  int _usedTodaySeconds = 0;
  int _bonusTodaySeconds = 0; // parent-granted extra time for today
  String _usageDate = '';

  static String _limitKey(String childId) => 'screen_time_limit_$childId';
  static String _usageKey(String childId) => 'screen_time_usage_$childId';
  static String _bonusKey(String childId) => 'screen_time_bonus_$childId';

  static String _today() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  /// Recommended daily limit (minutes) for a child's age, per AAP/WHO
  /// guidance adjusted conservatively for ASD:
  /// - age 2: 20 min (WHO: sedentary screen time at 2 — less is better)
  /// - ages 3–4: 30 min
  /// - age 5: 45 min
  /// - age 6+: 60 min (the AAP ≤1 hour ceiling)
  static int recommendedMinutesForAge(int ageYears) {
    if (ageYears <= 2) return 20;
    if (ageYears <= 4) return 30;
    if (ageYears == 5) return 45;
    return 60;
  }

  /// Loads limit + today's usage for [childId]. Call when the active child
  /// changes (and on app start).
  Future<void> load(String childId) async {
    _childId = childId;
    try {
      final prefs = await SharedPreferences.getInstance();
      final limit = prefs.getInt(_limitKey(childId));
      _limitMinutes = (limit == null || limit <= 0) ? null : limit;

      // Usage/bonus are stored as 'yyyy-mm-dd:seconds' so they naturally
      // reset each day.
      _usedTodaySeconds = _readDated(prefs.getString(_usageKey(childId)));
      _bonusTodaySeconds = _readDated(prefs.getString(_bonusKey(childId)));
      _usageDate = _today();
    } catch (e) {
      debugPrint('[ScreenTime] load failed: $e');
    }
    notifyListeners();
  }

  int _readDated(String? raw) {
    if (raw == null) return 0;
    final parts = raw.split(':');
    if (parts.length != 2 || parts[0] != _today()) return 0;
    return int.tryParse(parts[1]) ?? 0;
  }

  Future<void> _writeDated(String key, int seconds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, '${_today()}:$seconds');
  }

  /// The child the service is currently loaded for (null before [load]).
  String? get loadedChildId => _childId;

  /// The parent-configured daily limit in minutes; null = no limit set.
  int? get limitMinutes => _limitMinutes;

  /// Seconds of child-mode play used today.
  int get usedTodaySeconds => _usedTodaySeconds;

  /// Whether a limit is active for the loaded child.
  bool get limitEnabled => _limitMinutes != null;

  /// Remaining seconds today, or null when no limit is set.
  int? get remainingSeconds {
    final limit = _limitMinutes;
    if (limit == null) return null;
    final budget = limit * 60 + _bonusTodaySeconds;
    final left = budget - _usedTodaySeconds;
    return left < 0 ? 0 : left;
  }

  /// True when the limit is set and today's budget is used up.
  bool get isExhausted => (remainingSeconds ?? 1) <= 0;

  /// Sets (or clears, with null/0) the daily limit for the loaded child.
  Future<void> setLimitMinutes(int? minutes) async {
    final childId = _childId;
    if (childId == null) return;
    _limitMinutes = (minutes == null || minutes <= 0) ? null : minutes;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_limitMinutes == null) {
        await prefs.remove(_limitKey(childId));
      } else {
        await prefs.setInt(_limitKey(childId), _limitMinutes!);
      }
    } catch (e) {
      debugPrint('[ScreenTime] setLimit failed: $e');
    }
  }

  /// Adds [seconds] of play time to today's usage (rolls the date over
  /// automatically at midnight).
  Future<void> addUsage(int seconds) async {
    final childId = _childId;
    if (childId == null) return;
    if (_usageDate != _today()) {
      // Day rolled over while playing — start a fresh budget.
      _usedTodaySeconds = 0;
      _bonusTodaySeconds = 0;
      _usageDate = _today();
    }
    _usedTodaySeconds += seconds;
    notifyListeners();
    try {
      await _writeDated(_usageKey(childId), _usedTodaySeconds);
    } catch (e) {
      debugPrint('[ScreenTime] addUsage failed: $e');
    }
  }

  /// Parent override: grants [minutes] of extra play time for today only.
  Future<void> extendToday(int minutes) async {
    final childId = _childId;
    if (childId == null) return;
    _bonusTodaySeconds += minutes * 60;
    notifyListeners();
    try {
      await _writeDated(_bonusKey(childId), _bonusTodaySeconds);
    } catch (e) {
      debugPrint('[ScreenTime] extendToday failed: $e');
    }
  }

  /// Parent action: resets today's usage to zero.
  Future<void> resetToday() async {
    final childId = _childId;
    if (childId == null) return;
    _usedTodaySeconds = 0;
    _bonusTodaySeconds = 0;
    notifyListeners();
    try {
      await _writeDated(_usageKey(childId), 0);
      await _writeDated(_bonusKey(childId), 0);
    } catch (e) {
      debugPrint('[ScreenTime] resetToday failed: $e');
    }
  }
}
