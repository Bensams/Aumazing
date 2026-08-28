import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../model/therapy_center.dart';

/// Fetches therapy center listings and ranks them by proximity.
///
/// - Listings come from Supabase and are cached locally so the directory
///   still opens offline (offline-first, like the rest of the app).
/// - Proximity uses the Haversine formula (manuscript FR). The parent's
///   GPS coordinates are only ever held in memory by the caller — this
///   service never stores a position.
class TherapyCenterService {
  TherapyCenterService._();

  static final TherapyCenterService instance = TherapyCenterService._();

  static const _cacheKey = 'therapy_centers_cache';

  List<TherapyCenter>? _memoryCache;

  /// Test seam: clears the in-memory cache so tests can seed the
  /// SharedPreferences cache and force a fresh load through it.
  @visibleForTesting
  void debugResetMemoryCache() {
    _memoryCache = null;
  }

  /// Loads active centers: Supabase first, falling back to the last
  /// successful fetch when offline.
  Future<List<TherapyCenter>> getCenters({bool forceRefresh = false}) async {
    if (!forceRefresh && _memoryCache != null) return _memoryCache!;

    try {
      final rows = await Supabase.instance.client
          .from('therapy_centers')
          .select()
          .eq('active', true)
          .order('sort_order');
      final centers = (rows as List<dynamic>)
          .map((r) => TherapyCenter.fromMap(r as Map<String, dynamic>))
          .toList();
      _memoryCache = centers;
      _persistCache(centers);
      return centers;
    } catch (e) {
      debugPrint('[TherapyCenters] fetch failed, using cache: $e');
      return _loadCache();
    }
  }

  Future<void> _persistCache(List<TherapyCenter> centers) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _cacheKey, jsonEncode(centers.map((c) => c.toMap()).toList()));
    } catch (e) {
      debugPrint('[TherapyCenters] cache write failed: $e');
    }
  }

  Future<List<TherapyCenter>> _loadCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null) return const [];
      final list = (jsonDecode(raw) as List<dynamic>)
          .map((r) => TherapyCenter.fromMap(r as Map<String, dynamic>))
          .toList();
      _memoryCache = list;
      return list;
    } catch (e) {
      debugPrint('[TherapyCenters] cache read failed: $e');
      return const [];
    }
  }

  /// Great-circle distance in kilometres between two coordinates
  /// (Haversine formula — manuscript FR for the Interactive Locator).
  static double haversineKm(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadiusKm = 6371.0;
    final dLat = _degToRad(lat2 - lat1);
    final dLon = _degToRad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degToRad(lat1)) *
            math.cos(_degToRad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusKm * c;
  }

  static double _degToRad(double deg) => deg * math.pi / 180.0;

  /// Ranks [centers] by distance from the parent's position (nearest
  /// first). The position stays in the caller's memory; nothing is stored.
  static List<RankedTherapyCenter> rankByDistance(
    List<TherapyCenter> centers, {
    required double latitude,
    required double longitude,
  }) {
    final ranked = centers
        .map((c) => RankedTherapyCenter(
              center: c,
              distanceKm:
                  haversineKm(latitude, longitude, c.latitude, c.longitude),
            ))
        .toList()
      ..sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
    return ranked;
  }
}
