import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Orientations the last `SystemChrome.setPreferredOrientations` asked for.
  List<String>? lastRequest;

  setUp(() {
    lastRequest = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'SystemChrome.setPreferredOrientations') {
            lastRequest = (call.arguments as List).cast<String>();
          }
          return null;
        });
  });

  tearDown(() {
    debugSetDeviceSmallestWidthDp(null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  group('parentOrientationsFor', () {
    test('phone widths get portrait', () {
      expect(parentOrientationsFor(360), [DeviceOrientation.portraitUp]);
      // The letterboxed-tablet window width that used to misclassify a tablet
      // as a phone — as a *device* width it really is a phone.
      expect(parentOrientationsFor(577), [DeviceOrientation.portraitUp]);
      expect(parentOrientationsFor(599.9), [DeviceOrientation.portraitUp]);
    });

    test('tablet widths get landscape, both ways', () {
      expect(parentOrientationsFor(600), kChildOrientations);
      expect(parentOrientationsFor(800), kChildOrientations);
    });
  });

  group('lockParentAdaptive', () {
    test('a phone-sized device is locked portrait', () async {
      debugSetDeviceSmallestWidthDp(411);

      lockParentAdaptive();
      await null;

      expect(lastRequest, ['DeviceOrientation.portraitUp']);
      expect(isParentPortraitDevice, isTrue);
      expect(isTabletFormFactor, isFalse);
    });

    test('a tablet is locked landscape, never portrait', () async {
      debugSetDeviceSmallestWidthDp(800);

      lockParentAdaptive();
      await null;

      expect(lastRequest, [
        'DeviceOrientation.landscapeLeft',
        'DeviceOrientation.landscapeRight',
      ]);
      expect(isParentPortraitDevice, isFalse);
      expect(isTabletFormFactor, isTrue);
    });

    test(
      'a tablet whose window is letterboxed to 577dp still gets landscape',
      () async {
        // The device width comes from the platform, not the squeezed window,
        // so the app can unwind the letterboxing instead of re-requesting the
        // portrait that caused it.
        debugSetDeviceSmallestWidthDp(800);

        lockParentAdaptive();
        await null;

        expect(lastRequest, isNot(contains('DeviceOrientation.portraitUp')));
      },
    );
  });

  group('child-facing screens', () {
    test('lock landscape regardless of form factor', () async {
      for (final width in [411.0, 800.0]) {
        debugSetDeviceSmallestWidthDp(width);

        lockParentLandscape();
        await null;

        expect(lastRequest, [
          'DeviceOrientation.landscapeLeft',
          'DeviceOrientation.landscapeRight',
        ]);
      }
    });

    test('unlockParentOrientation restores the parent policy', () async {
      debugSetDeviceSmallestWidthDp(411);
      lockParentLandscape();
      await null;

      unlockParentOrientation();
      await null;

      expect(lastRequest, ['DeviceOrientation.portraitUp']);
    });
  });
}
