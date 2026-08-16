import 'package:flutter_test/flutter_test.dart';

import 'package:aumazing/features/therapy/therapy_map_support.dart';
import 'package:aumazing/model/therapy_center.dart';

TherapyCenter _center(String id, double lat, double lng) => TherapyCenter(
  id: id,
  name: 'Center $id',
  address: 'Address $id',
  latitude: lat,
  longitude: lng,
);

void main() {
  group('hasValidCoordinates', () {
    test('accepts a normal Davao City coordinate', () {
      expect(
        TherapyMapSupport.hasValidCoordinates(_center('a', 7.07, 125.61)),
        isTrue,
      );
    });

    test('rejects non-finite values', () {
      expect(
        TherapyMapSupport.hasValidCoordinates(
          _center('nan', double.nan, 125.61),
        ),
        isFalse,
      );
      expect(
        TherapyMapSupport.hasValidCoordinates(
          _center('inf', 7.07, double.infinity),
        ),
        isFalse,
      );
    });

    test('rejects out-of-range latitudes and longitudes', () {
      expect(
        TherapyMapSupport.hasValidCoordinates(_center('lat+', 91, 125.61)),
        isFalse,
      );
      expect(
        TherapyMapSupport.hasValidCoordinates(_center('lat-', -91, 125.61)),
        isFalse,
      );
      expect(
        TherapyMapSupport.hasValidCoordinates(_center('lng+', 7.07, 181)),
        isFalse,
      );
      expect(
        TherapyMapSupport.hasValidCoordinates(_center('lng-', 7.07, -181)),
        isFalse,
      );
    });

    test('rejects (0, 0) — the fromMap fallback for missing coordinates', () {
      expect(
        TherapyMapSupport.hasValidCoordinates(_center('zero', 0, 0)),
        isFalse,
      );
    });
  });

  group('mappableCenters', () {
    test('keeps valid centers and omits invalid ones', () {
      final centers = [
        _center('ok-1', 7.0736, 125.6110),
        _center('zero', 0, 0),
        _center('nan', double.nan, 125.61),
        _center('ok-2', 7.2278, 125.6483),
        _center('range', 123, 456),
      ];
      expect(TherapyMapSupport.mappableCenters(centers).map((c) => c.id), [
        'ok-1',
        'ok-2',
      ]);
    });
  });

  group('boundsFor', () {
    test('returns null when there is nothing to map', () {
      expect(TherapyMapSupport.boundsFor(const []), isNull);
      expect(TherapyMapSupport.boundsFor([_center('zero', 0, 0)]), isNull);
    });

    test('a single center collapses to a point with a fixed zoom', () {
      final bounds =
          TherapyMapSupport.boundsFor([_center('only', 7.07, 125.61)])!;
      expect(bounds.isSinglePoint, isTrue);
      expect(bounds.southLat, 7.07);
      expect(bounds.northLat, 7.07);
      expect(bounds.westLng, 125.61);
      expect(bounds.eastLng, 125.61);
      expect(TherapyMapSupport.singleCenterZoom, 15);
    });

    test(
      'multiple centers produce the enclosing box, ignoring invalid ones',
      () {
        final bounds =
            TherapyMapSupport.boundsFor([
              _center('a', 7.0736, 125.6110),
              _center('b', 7.2278, 125.6483),
              _center('c', 7.1064, 125.6215),
              _center(
                'bad',
                0,
                0,
              ), // must not drag the box to the Gulf of Guinea
            ])!;
        expect(bounds.isSinglePoint, isFalse);
        expect(bounds.southLat, 7.0736);
        expect(bounds.northLat, 7.2278);
        expect(bounds.westLng, 125.6110);
        expect(bounds.eastLng, 125.6483);
      },
    );
  });
}
