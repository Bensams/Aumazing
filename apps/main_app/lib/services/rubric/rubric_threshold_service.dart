import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'rubric_thresholds.dart';

/// Delivers the current admin-configured rubric thresholds to the scoring
/// engine, offline-first:
///
/// 1. In memory: the last loaded values.
/// 2. On disk: the last successful fetch (SharedPreferences).
/// 3. Fallback: the validated defaults hardcoded in [RubricThresholds].
///
/// [load] is called at app startup (non-blocking); scoring always works
/// even if the device has never been online.
class RubricThresholdService {
  RubricThresholdService._();

  static final RubricThresholdService instance = RubricThresholdService._();

  static const _cacheKey = 'rubric_thresholds_cache';

  RubricThresholds _current = RubricThresholds.defaults;

  /// The thresholds the scoring engine should use right now.
  RubricThresholds get current => _current;

  /// Test hook: override the current thresholds directly.
  @visibleForTesting
  set current(RubricThresholds value) => _current = value;

  /// Loads cache, then refreshes from Supabase in the background.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw != null) {
        _current = RubricThresholds.fromMap(
            jsonDecode(raw) as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint('[RubricThresholds] cache read failed: $e');
    }
    await refresh();
  }

  /// Fetches the singleton config row; keeps the previous values on
  /// failure (offline).
  Future<void> refresh() async {
    try {
      final row = await Supabase.instance.client
          .from('rubric_thresholds')
          .select()
          .eq('id', 1)
          .maybeSingle();
      if (row == null) return;
      _current = RubricThresholds.fromMap(row);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, jsonEncode(_current.toMap()));
    } catch (e) {
      debugPrint('[RubricThresholds] refresh failed (keeping current): $e');
    }
  }
}
