import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'package:aumazing/features/therapy/therapy_directory_screen.dart';
import 'package:aumazing/features/therapy/therapy_map_view.dart';
import 'package:aumazing/providers/child_provider.dart';
import 'package:aumazing/services/entitlement_service.dart';
import 'package:aumazing/services/therapy_center_service.dart';

import '../../support/fake_auth.dart';
import '../../support/fake_map_tiles.dart';

/// Directory screen tests for the embedded therapy-center map (AUM-164).
///
/// Supabase is never initialized here, so [TherapyCenterService.getCenters]
/// always falls back to the SharedPreferences cache — every test therefore
/// also exercises the offline-directory path. Tiles come from
/// [FakeTileProvider] and GPS/launches from platform-interface fakes, so no
/// test touches the network or a real device sensor.
const _phonePortrait = Size(360, 800);
const _phoneLandscape = Size(800, 360);

Map<String, dynamic> _centerMap(
  String id,
  String name,
  double lat,
  double lng,
) => {
  'id': id,
  'name': name,
  'address': '$name Address',
  'city': 'Davao City',
  'latitude': lat,
  'longitude': lng,
  'phone': '0900',
  'services': ['Speech Therapy'],
};

// Poblacion (near the fake GPS fix), Bunawan (far), and a row whose
// coordinates never made it into Supabase (0,0 fromMap fallback).
final _cacheRows = [
  _centerMap('alpha', 'Alpha Center', 7.0736, 125.6110),
  _centerMap('bravo', 'Bravo Center', 7.2278, 125.6483),
  _centerMap('noloc', 'NoLoc Center', 0, 0),
];

Position _davaoFix() => Position(
  latitude: 7.0730,
  longitude: 125.6120,
  timestamp: DateTime(2026),
  accuracy: 5,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

class _FakeGeolocator extends GeolocatorPlatform {
  _FakeGeolocator({
    this.serviceEnabled = true,
    LocationPermission permission = LocationPermission.denied,
    this.permissionAfterRequest,
  }) : _permission = permission;

  bool serviceEnabled;
  LocationPermission _permission;
  final LocationPermission? permissionAfterRequest;

  int requestCount = 0;
  int getPositionCount = 0;

  @override
  Future<bool> isLocationServiceEnabled() async => serviceEnabled;

  @override
  Future<LocationPermission> checkPermission() async => _permission;

  @override
  Future<LocationPermission> requestPermission() async {
    requestCount++;
    final after = permissionAfterRequest;
    if (after != null) _permission = after;
    return _permission;
  }

  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async {
    getPositionCount++;
    return _davaoFix();
  }
}

class _FakeUrlLauncher extends UrlLauncherPlatform {
  _FakeUrlLauncher({this.canLaunchGeo = true});

  /// Whether a `geo:` handler (a native maps app) exists on the device.
  final bool canLaunchGeo;

  final List<String> launched = [];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async =>
      url.startsWith('geo:') ? canLaunchGeo : true;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.add(url);
    return true;
  }
}

class _TestChildProvider extends ChildProvider {
  _TestChildProvider() : super(authService: FakeAuthService.boundAccount());

  @override
  Future<void> loadProfile() async {}
}

/// Scrolls [name]'s card into view. With the map taking the top third of
/// a phone screen, later cards start below the fold and the lazy
/// [ListView] hasn't built them — being reachable by scrolling is what
/// "still listed" means here.
Future<void> _scrollToCard(WidgetTester tester, String name) async {
  await tester.scrollUntilVisible(
    find.text(name),
    120,
    scrollable:
        find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
  );
  await tester.pump();
}

Widget _wrap() => ChangeNotifierProvider<ChildProvider>(
  create: (_) => _TestChildProvider(),
  child: MaterialApp(
    theme: AppTheme.light,
    home: const TherapyDirectoryScreen(),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeGeolocator geolocator;
  late _FakeUrlLauncher urlLauncher;

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'therapy_centers_cache': jsonEncode(_cacheRows),
    });
    TherapyCenterService.instance.debugResetMemoryCache();
    TherapyMapView.debugTileProviderFactory = () => FakeTileProvider();
    geolocator = _FakeGeolocator();
    GeolocatorPlatform.instance = geolocator;
    urlLauncher = _FakeUrlLauncher();
    UrlLauncherPlatform.instance = urlLauncher;
  });

  tearDown(() {
    TherapyMapView.debugTileProviderFactory = null;
    EntitlementService.instance.debugSetRealPremium(false);
  });

  Future<void> pumpDirectory(
    WidgetTester tester, {
    Size size = _phonePortrait,
    bool premium = true,
  }) async {
    EntitlementService.instance.debugSetRealPremium(premium);
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_wrap());
    await tester.pump(); // async cache load
    await tester.pump(const Duration(milliseconds: 400)); // tiles + fade
  }

  group('premium gating', () {
    testWidgets('free tier: the map renders with markers while details '
        'stay gated', (tester) async {
      await pumpDirectory(tester, premium: false);

      // AUM-164: the embedded interactive map is not Premium-gated — every
      // valid center gets a marker and invalid coordinates are omitted.
      expect(find.byType(TherapyMapView), findsOneWidget);
      expect(
        find.byKey(const ValueKey('therapy-marker-alpha')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('therapy-marker-bravo')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('therapy-marker-noloc')), findsNothing);
      expect(find.textContaining('OpenStreetMap'), findsOneWidget);
      // Merely opening the map never touches location; no user dot either.
      expect(geolocator.requestCount, 0);
      expect(geolocator.getPositionCount, 0);
      expect(find.byKey(const ValueKey('therapy-user-marker')), findsNothing);
      // Free stays city-level: no address, services, distance, or
      // Directions hand-off.
      expect(find.text('Unlock locator'), findsOneWidget);
      expect(find.text('Alpha Center'), findsOneWidget);
      expect(find.text('Alpha Center Address'), findsNothing);
      expect(find.text('Speech Therapy'), findsNothing);
      expect(find.text('Directions'), findsNothing);
      expect(find.textContaining(' km'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('free tier: marker selection highlights the card without '
        'unlocking details', (tester) async {
      await pumpDirectory(tester, premium: false);

      await tester.tap(
        find.byKey(const ValueKey('therapy-marker-alpha')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<TherapyMapView>(find.byType(TherapyMapView))
            .selectedCenterId,
        'alpha',
      );
      // Selection reveals nothing gated.
      expect(find.text('Alpha Center'), findsOneWidget);
      expect(find.text('Alpha Center Address'), findsNothing);
      expect(find.text('Speech Therapy'), findsNothing);
      expect(find.text('Directions'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('premium: embedded map, full details, and directions', (
      tester,
    ) async {
      await pumpDirectory(tester);

      expect(find.byType(TherapyMapView), findsOneWidget);
      expect(find.text('Find near me'), findsOneWidget);
      expect(find.text('Alpha Center Address'), findsOneWidget);
      expect(find.text('Speech Therapy'), findsWidgets);
      expect(find.text('Directions'), findsWidgets);
      expect(find.textContaining('OpenStreetMap'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('markers and selection sync', () {
    testWidgets('valid centers get markers; invalid coordinates are omitted '
        'without crashing and the card stays listed', (tester) async {
      await pumpDirectory(tester);

      expect(
        find.byKey(const ValueKey('therapy-marker-alpha')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('therapy-marker-bravo')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('therapy-marker-noloc')), findsNothing);
      // The unmappable center still appears in the directory list.
      await _scrollToCard(tester, 'NoLoc Center');
      expect(find.text('NoLoc Center'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('tapping a card focuses its marker', (tester) async {
      await pumpDirectory(tester);

      await tester.tap(find.text('Bravo Center'));
      await tester.pump();

      final mapWidget = tester.widget<TherapyMapView>(
        find.byType(TherapyMapView),
      );
      expect(mapWidget.selectedCenterId, 'bravo');

      final camera =
          tester
              .state<TherapyMapViewState>(find.byType(TherapyMapView))
              .debugMapController
              .camera;
      expect(camera.center.latitude, closeTo(7.2278, 0.0001));
      expect(camera.center.longitude, closeTo(125.6483, 0.0001));
    });

    testWidgets('tapping a marker selects the matching card', (tester) async {
      await pumpDirectory(tester);

      await tester.tap(
        find.byKey(const ValueKey('therapy-marker-alpha')),
        warnIfMissed: false,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final mapWidget = tester.widget<TherapyMapView>(
        find.byType(TherapyMapView),
      );
      expect(mapWidget.selectedCenterId, 'alpha');
      expect(tester.takeException(), isNull);
    });

    testWidgets('selecting a marker whose card is offscreen and unbuilt '
        'scrolls that card into view', (tester) async {
      // Enough centers that the last card sits far below the fold, beyond
      // the lazy ListView's build window — its GlobalKey has no context,
      // which is exactly the case Scrollable.ensureVisible alone misses.
      SharedPreferences.setMockInitialValues({
        'therapy_centers_cache': jsonEncode([
          for (var i = 0; i < 14; i++)
            _centerMap(
              'center-$i',
              'Center Number $i',
              7.05 + i * 0.01,
              125.60 + i * 0.01,
            ),
        ]),
      });
      TherapyCenterService.instance.debugResetMemoryCache();
      await pumpDirectory(tester);

      expect(find.text('Center Number 13'), findsNothing);

      // Drive the screen's marker handler by stable ID — synthetic taps on
      // overlapping pins are ambiguous, and the tap→ID wiring is already
      // covered above and in the map view tests.
      tester.widget<TherapyMapView>(find.byType(TherapyMapView)).onMarkerTap!(
        'center-13',
      );
      await tester.pumpAndSettle();

      expect(find.text('Center Number 13'), findsOneWidget);
      expect(
        tester
            .widget<TherapyMapView>(find.byType(TherapyMapView))
            .selectedCenterId,
        'center-13',
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('location permission', () {
    testWidgets('the map renders without any location call', (tester) async {
      await pumpDirectory(tester);

      expect(find.byType(TherapyMapView), findsOneWidget);
      expect(geolocator.requestCount, 0);
      expect(geolocator.getPositionCount, 0);
      expect(find.byKey(const ValueKey('therapy-user-marker')), findsNothing);
    });

    testWidgets('declining the disclosure never raises the OS prompt', (
      tester,
    ) async {
      await pumpDirectory(tester);

      await tester.tap(find.text('Find near me'));
      await tester.pump();
      expect(find.text('Find centers near you'), findsOneWidget);

      await tester.tap(find.text('Not now'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(geolocator.requestCount, 0);
      expect(geolocator.getPositionCount, 0);
      expect(find.textContaining('shown without distances'), findsOneWidget);
      expect(find.byType(TherapyMapView), findsOneWidget);
    });

    testWidgets('granted: distances rank the list and the map shows the '
        'user dot', (tester) async {
      GeolocatorPlatform.instance =
          geolocator = _FakeGeolocator(
            permission: LocationPermission.denied,
            permissionAfterRequest: LocationPermission.whileInUse,
          );
      await pumpDirectory(tester);

      await tester.tap(find.text('Find near me'));
      await tester.pump();
      await tester.tap(find.text('Continue'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(geolocator.requestCount, 1);
      expect(geolocator.getPositionCount, 1);
      expect(find.textContaining('km'), findsWidgets);
      expect(find.byKey(const ValueKey('therapy-user-marker')), findsOneWidget);
      // Haversine ranking puts Poblacion (alpha) before Bunawan (bravo).
      expect(
        tester.getTopLeft(find.text('Alpha Center')).dy,
        lessThan(tester.getTopLeft(find.text('Bravo Center')).dy),
      );
      expect(find.text('Update location'), findsOneWidget);
    });

    testWidgets('denied after the OS prompt keeps everything usable', (
      tester,
    ) async {
      GeolocatorPlatform.instance =
          geolocator = _FakeGeolocator(
            permission: LocationPermission.denied,
            permissionAfterRequest: LocationPermission.denied,
          );
      await pumpDirectory(tester);

      await tester.tap(find.text('Find near me'));
      await tester.pump();
      await tester.tap(find.text('Continue'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(geolocator.getPositionCount, 0);
      expect(find.textContaining('permission is needed'), findsOneWidget);
      expect(find.byType(TherapyMapView), findsOneWidget);
      expect(find.text('Alpha Center'), findsOneWidget);
    });

    testWidgets('permanently denied points at app settings, no OS prompt', (
      tester,
    ) async {
      GeolocatorPlatform.instance =
          geolocator = _FakeGeolocator(
            permission: LocationPermission.deniedForever,
          );
      await pumpDirectory(tester);

      await tester.tap(find.text('Find near me'));
      await tester.pump();
      await tester.tap(find.text('Continue'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(geolocator.requestCount, 0);
      expect(geolocator.getPositionCount, 0);
      expect(find.textContaining('blocked for Aumazing'), findsOneWidget);
      expect(find.byType(TherapyMapView), findsOneWidget);
    });

    testWidgets('location services off shows a hint instead of a prompt', (
      tester,
    ) async {
      GeolocatorPlatform.instance =
          geolocator = _FakeGeolocator(serviceEnabled: false);
      await pumpDirectory(tester);

      await tester.tap(find.text('Find near me'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.textContaining('Turn on Location'), findsOneWidget);
      expect(geolocator.requestCount, 0);
    });
  });

  group('offline and failure handling', () {
    testWidgets('the directory loads from cache when Supabase is unreachable', (
      tester,
    ) async {
      // Supabase was never initialized in this test process, so the fetch
      // throws and the SharedPreferences cache is the only source.
      await pumpDirectory(tester);

      expect(find.text('Alpha Center'), findsOneWidget);
      expect(find.text('Bravo Center'), findsOneWidget);
      await _scrollToCard(tester, 'NoLoc Center');
      expect(find.text('NoLoc Center'), findsOneWidget);
    });

    testWidgets('no cache at all shows the empty state, not a crash', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      TherapyCenterService.instance.debugResetMemoryCache();
      await pumpDirectory(tester);

      expect(
        find.textContaining('No therapy centers available yet.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('tile failure keeps the cached list and details usable', (
      tester,
    ) async {
      await pumpDirectory(tester);

      tester
          .state<TherapyMapViewState>(find.byType(TherapyMapView))
          .debugSimulateTileFailure();
      await tester.pump();

      expect(find.textContaining('Map imagery unavailable'), findsOneWidget);
      expect(find.text('Alpha Center'), findsOneWidget);
      expect(find.text('Alpha Center Address'), findsOneWidget);
      expect(find.text('Directions'), findsWidgets);
    });
  });

  group('layout', () {
    testWidgets('portrait stacks map above the list', (tester) async {
      await pumpDirectory(tester);

      expect(find.byType(TherapyMapView), findsOneWidget);
      expect(find.text('Alpha Center'), findsOneWidget);
      expect(
        tester.getTopLeft(find.byType(TherapyMapView)).dy,
        lessThan(tester.getTopLeft(find.text('Alpha Center')).dy),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('landscape puts map and list side by side', (tester) async {
      await pumpDirectory(tester, size: _phoneLandscape);

      expect(find.byType(TherapyMapView), findsOneWidget);
      expect(find.text('Alpha Center'), findsOneWidget);
      expect(
        tester.getTopLeft(find.byType(TherapyMapView)).dx,
        lessThan(tester.getTopLeft(find.text('Alpha Center')).dx),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('large text keeps the map and list usable', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      await pumpDirectory(tester);

      expect(find.byType(TherapyMapView), findsOneWidget);
      expect(find.text('Alpha Center'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('external directions', () {
    testWidgets('uses the geo: intent when a maps app exists', (tester) async {
      await pumpDirectory(tester);

      await tester.tap(find.text('Directions').first, warnIfMissed: false);
      await tester.pump();

      expect(urlLauncher.launched, hasLength(1));
      expect(urlLauncher.launched.single, startsWith('geo:'));
    });

    testWidgets('falls back to the web maps URL without a maps app', (
      tester,
    ) async {
      UrlLauncherPlatform.instance =
          urlLauncher = _FakeUrlLauncher(canLaunchGeo: false);
      await pumpDirectory(tester);

      await tester.tap(find.text('Directions').first, warnIfMissed: false);
      await tester.pump();

      expect(urlLauncher.launched, hasLength(1));
      expect(urlLauncher.launched.single, contains('google.com/maps/dir'));
    });
  });
}
