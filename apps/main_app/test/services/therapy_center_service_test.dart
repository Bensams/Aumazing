import 'package:flutter_test/flutter_test.dart';

import 'package:aumazing/model/therapy_center.dart';
import 'package:aumazing/services/therapy_center_service.dart';

TherapyCenter _center(String id, double lat, double lng) => TherapyCenter(
      id: id,
      name: id,
      address: 'Davao City',
      latitude: lat,
      longitude: lng,
    );

void main() {
  group('haversineKm', () {
    test('zero distance for identical points', () {
      expect(TherapyCenterService.haversineKm(7.07, 125.61, 7.07, 125.61), 0);
    });

    test('matches a known Davao City distance within tolerance', () {
      // Poblacion (Rizal SPED) → Bunawan (Daniel M. Perez): ~17-18 km
      // great-circle.
      final km = TherapyCenterService.haversineKm(
          7.0736, 125.6110, 7.2278, 125.6483);
      expect(km, greaterThan(15));
      expect(km, lessThan(20));
    });

    test('is symmetric', () {
      final ab =
          TherapyCenterService.haversineKm(7.05, 125.59, 7.22, 125.64);
      final ba =
          TherapyCenterService.haversineKm(7.22, 125.64, 7.05, 125.59);
      expect(ab, closeTo(ba, 1e-9));
    });
  });

  group('rankByDistance', () {
    test('sorts nearest first with distances attached', () {
      final centers = [
        _center('far', 7.2278, 125.6483), // Bunawan
        _center('near', 7.0736, 125.6110), // Poblacion
        _center('mid', 7.1064, 125.6215), // Buhangin
      ];

      // Parent standing in Poblacion.
      final ranked = TherapyCenterService.rankByDistance(
        centers,
        latitude: 7.0730,
        longitude: 125.6120,
      );

      expect(ranked.map((r) => r.center.id).toList(),
          ['near', 'mid', 'far']);
      expect(ranked.first.distanceKm, lessThan(1));
      for (var i = 1; i < ranked.length; i++) {
        expect(ranked[i].distanceKm,
            greaterThanOrEqualTo(ranked[i - 1].distanceKm));
      }
    });
  });
}
