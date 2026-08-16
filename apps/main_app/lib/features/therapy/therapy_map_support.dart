import '../../model/therapy_center.dart';

/// Geographic bounds of a set of centers, kept free of flutter_map types so
/// the marker/bounds logic stays unit-testable without widgets or tiles.
class TherapyMapBounds {
  const TherapyMapBounds({
    required this.southLat,
    required this.westLng,
    required this.northLat,
    required this.eastLng,
  });

  final double southLat;
  final double westLng;
  final double northLat;
  final double eastLng;

  /// True when the bounds collapse to (roughly) a single point, e.g. a
  /// directory with one center — fitting a zero-area box would zoom to
  /// street level or blow up, so callers use a fixed zoom instead.
  bool get isSinglePoint =>
      (northLat - southLat).abs() < 1e-6 && (eastLng - westLng).abs() < 1e-6;
}

/// Pure map-support logic for the therapy directory (AUM-164).
class TherapyMapSupport {
  TherapyMapSupport._();

  /// Zoom used when the bounds collapse to a single center.
  static const double singleCenterZoom = 15;

  /// Whether [center] can be placed on the map without lying or crashing.
  ///
  /// Rejects out-of-range and non-finite values, and (0, 0) — the
  /// [TherapyCenter.fromMap] fallback for missing coordinates — so a row
  /// with no coordinates never renders a marker in the Gulf of Guinea.
  static bool hasValidCoordinates(TherapyCenter center) {
    final lat = center.latitude;
    final lng = center.longitude;
    if (!lat.isFinite || !lng.isFinite) return false;
    if (lat < -90 || lat > 90) return false;
    if (lng < -180 || lng > 180) return false;
    if (lat == 0 && lng == 0) return false;
    return true;
  }

  /// The centers that get a marker; invalid coordinates are safely omitted
  /// (they stay in the directory list, just not on the map).
  static List<TherapyCenter> mappableCenters(List<TherapyCenter> centers) =>
      centers.where(hasValidCoordinates).toList();

  /// Bounds covering every mappable center, or null when nothing is
  /// mappable (callers show an empty/placeholder state instead of an
  /// empty world map).
  static TherapyMapBounds? boundsFor(List<TherapyCenter> centers) {
    final mappable = mappableCenters(centers);
    if (mappable.isEmpty) return null;
    var south = mappable.first.latitude;
    var north = mappable.first.latitude;
    var west = mappable.first.longitude;
    var east = mappable.first.longitude;
    for (final c in mappable.skip(1)) {
      if (c.latitude < south) south = c.latitude;
      if (c.latitude > north) north = c.latitude;
      if (c.longitude < west) west = c.longitude;
      if (c.longitude > east) east = c.longitude;
    }
    return TherapyMapBounds(
      southLat: south,
      westLng: west,
      northLat: north,
      eastLng: east,
    );
  }
}
