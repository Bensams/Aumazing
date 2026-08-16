import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:aumazing/features/therapy/therapy_map_view.dart';
import 'package:aumazing/model/therapy_center.dart';

import '../../support/fake_map_tiles.dart';

TherapyCenter _center(String id, double lat, double lng) => TherapyCenter(
  id: id,
  name: 'Center $id',
  address: 'Address $id',
  latitude: lat,
  longitude: lng,
);

// Davao City fixtures: Poblacion, Bunawan, Buhangin.
final _alpha = _center('alpha', 7.0736, 125.6110);
final _bravo = _center('bravo', 7.2278, 125.6483);
final _invalidZero = _center('zero', 0, 0);
final _invalidRange = _center('range', 123, 456);

Future<void> _pumpMap(
  WidgetTester tester,
  Widget map, {
  bool reduceMotion = false,
}) async {
  Widget body = SizedBox(width: 400, height: 600, child: map);
  if (reduceMotion) {
    body = MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: body,
    );
  }
  await tester.pumpWidget(
    MaterialApp(home: Scaffold(body: Center(child: body))),
  );
  await tester.pump();
  // Lets the fake tiles decode and the tile fade-in finish.
  await tester.pump(const Duration(milliseconds: 300));
}

TherapyMapViewState _state(WidgetTester tester) =>
    tester.state<TherapyMapViewState>(find.byType(TherapyMapView));

void main() {
  testWidgets('creates one marker per valid center and omits invalid ones', (
    tester,
  ) async {
    await _pumpMap(
      tester,
      TherapyMapView(
        centers: [_alpha, _invalidZero, _bravo, _invalidRange],
        tileProvider: FakeTileProvider(),
      ),
    );

    expect(find.byKey(const ValueKey('therapy-marker-alpha')), findsOneWidget);
    expect(find.byKey(const ValueKey('therapy-marker-bravo')), findsOneWidget);
    expect(find.byKey(const ValueKey('therapy-marker-zero')), findsNothing);
    expect(find.byKey(const ValueKey('therapy-marker-range')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows a placeholder instead of an empty world map', (
    tester,
  ) async {
    await _pumpMap(
      tester,
      TherapyMapView(centers: [_invalidZero], tileProvider: FakeTileProvider()),
    );

    expect(find.byType(FlutterMap), findsNothing);
    expect(
      find.textContaining('Center locations aren\'t available'),
      findsOneWidget,
    );
  });

  testWidgets('a single center gets the fixed zoom, not a zero-area fit', (
    tester,
  ) async {
    await _pumpMap(
      tester,
      TherapyMapView(centers: [_alpha], tileProvider: FakeTileProvider()),
    );

    final camera = _state(tester).debugMapController.camera;
    expect(camera.zoom, closeTo(15, 0.001));
    expect(camera.center.latitude, closeTo(_alpha.latitude, 0.0001));
    expect(camera.center.longitude, closeTo(_alpha.longitude, 0.0001));
  });

  testWidgets('multiple centers start with bounds covering all of them', (
    tester,
  ) async {
    await _pumpMap(
      tester,
      TherapyMapView(
        centers: [_alpha, _bravo],
        tileProvider: FakeTileProvider(),
      ),
    );

    final visible = _state(tester).debugMapController.camera.visibleBounds;
    expect(visible.contains(LatLng(_alpha.latitude, _alpha.longitude)), isTrue);
    expect(visible.contains(LatLng(_bravo.latitude, _bravo.longitude)), isTrue);
  });

  testWidgets('tapping a marker reports that center\'s stable ID', (
    tester,
  ) async {
    String? tapped;
    await _pumpMap(
      tester,
      TherapyMapView(
        centers: [_alpha, _bravo],
        tileProvider: FakeTileProvider(),
        onMarkerTap: (id) => tapped = id,
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('therapy-marker-bravo')),
      warnIfMissed: false,
    );
    await tester.pump();

    expect(tapped, 'bravo');
  });

  testWidgets('the selected marker is highlighted and gaining selection '
      'focuses the camera on it', (tester) async {
    Widget build(String? selectedId) => TherapyMapView(
      centers: [_alpha, _bravo],
      selectedCenterId: selectedId,
      tileProvider: FakeTileProvider(),
    );

    Icon iconOf(String id) => tester.widget<Icon>(
      find.descendant(
        of: find.byKey(ValueKey('therapy-marker-$id')),
        matching: find.byType(Icon),
      ),
    );

    // Nothing selected: the initial fit shows both markers, both plain.
    await _pumpMap(tester, build(null));
    expect(iconOf('alpha').size, 34);
    expect(iconOf('bravo').size, 34);

    // Rebuild with bravo selected — same element, so didUpdateWidget runs.
    await _pumpMap(tester, build('bravo'));

    expect(iconOf('bravo').size, 44);
    // Alpha is ~17km away, so focusing bravo at zoom 15 pushes it out of
    // the viewport and flutter_map culls its marker — expected, not a
    // regression: the highlight contract is about the selected marker.
    expect(find.byKey(const ValueKey('therapy-marker-alpha')), findsNothing);

    final camera = _state(tester).debugMapController.camera;
    expect(camera.center.latitude, closeTo(_bravo.latitude, 0.0001));
    expect(camera.center.longitude, closeTo(_bravo.longitude, 0.0001));
    expect(camera.zoom, greaterThanOrEqualTo(15));
  });

  testWidgets('shows a user-location dot only when a position is provided', (
    tester,
  ) async {
    await _pumpMap(
      tester,
      TherapyMapView(
        centers: [_alpha, _bravo],
        tileProvider: FakeTileProvider(),
      ),
    );
    expect(find.byKey(const ValueKey('therapy-user-marker')), findsNothing);

    await _pumpMap(
      tester,
      TherapyMapView(
        centers: [_alpha, _bravo],
        tileProvider: FakeTileProvider(),
        userLatitude: 7.0730,
        userLongitude: 125.6120,
      ),
    );
    expect(find.byKey(const ValueKey('therapy-user-marker')), findsOneWidget);
  });

  testWidgets('zoom controls change the camera zoom', (tester) async {
    await _pumpMap(
      tester,
      TherapyMapView(centers: [_alpha], tileProvider: FakeTileProvider()),
    );

    final before = _state(tester).debugMapController.camera.zoom;
    await tester.tap(find.byTooltip('Zoom in'));
    await tester.pump();
    expect(_state(tester).debugMapController.camera.zoom, before + 1);

    await tester.tap(find.byTooltip('Zoom out'));
    await tester.pump();
    expect(_state(tester).debugMapController.camera.zoom, before);
  });

  testWidgets('a tile failure shows a non-blocking banner; markers survive', (
    tester,
  ) async {
    await _pumpMap(
      tester,
      TherapyMapView(
        centers: [_alpha, _bravo],
        tileProvider: FakeTileProvider(),
      ),
    );

    _state(tester).debugSimulateTileFailure();
    await tester.pump();

    expect(find.textContaining('Map imagery unavailable'), findsOneWidget);
    expect(find.byKey(const ValueKey('therapy-marker-alpha')), findsOneWidget);
    expect(find.byKey(const ValueKey('therapy-marker-bravo')), findsOneWidget);
  });

  testWidgets('OpenStreetMap attribution is visible', (tester) async {
    await _pumpMap(
      tester,
      TherapyMapView(centers: [_alpha], tileProvider: FakeTileProvider()),
    );

    expect(find.textContaining('OpenStreetMap'), findsOneWidget);
  });

  testWidgets('reduced motion disables the fling animation flag', (
    tester,
  ) async {
    await _pumpMap(
      tester,
      TherapyMapView(centers: [_alpha], tileProvider: FakeTileProvider()),
      reduceMotion: true,
    );
    var map = tester.widget<FlutterMap>(find.byType(FlutterMap));
    expect(
      map.options.interactionOptions.flags & InteractiveFlag.flingAnimation,
      0,
    );

    await _pumpMap(
      tester,
      TherapyMapView(centers: [_alpha], tileProvider: FakeTileProvider()),
    );
    map = tester.widget<FlutterMap>(find.byType(FlutterMap));
    expect(
      map.options.interactionOptions.flags & InteractiveFlag.flingAnimation,
      isNot(0),
    );
  });
}
