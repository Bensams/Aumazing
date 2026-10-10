import 'package:aumazing/features/app_update/app_release.dart';
import 'package:aumazing/features/app_update/app_update_banner.dart';
import 'package:aumazing/features/app_update/app_update_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakePlatform extends AppUpdatePlatform {
  const FakePlatform();

  @override
  Future<InstalledVersion> installedVersion() async =>
      const InstalledVersion(code: 8, name: '1.6.0');
}

AppRelease release({int? minSupported}) => AppRelease(
  versionName: '1.6.1',
  versionCode: 9,
  downloadUrl: Uri.parse('https://example.com/aumazing.apk'),
  sha256: 'a' * 64,
  releaseNotes: 'Smoother games',
  minSupportedCode: minSupported,
);

Future<AppUpdateService> checked(AppRelease? latest) async {
  final service = AppUpdateService(
    fetchLatest: () async => latest,
    platform: const FakePlatform(),
    supported: true,
  );
  await service.check();
  return service;
}

Widget host(AppUpdateService service) =>
    MaterialApp(home: Scaffold(body: AppUpdateBanner(service: service)));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('hidden when the app is up to date', (tester) async {
    final service = await tester.runAsync(() => checked(null));
    await tester.pumpWidget(host(service!));
    expect(find.byKey(const Key('app-update-banner')), findsNothing);
  });

  testWidgets('announces a newer version and opens the dialog', (tester) async {
    final service = await tester.runAsync(() => checked(release()));
    await tester.pumpWidget(host(service!));

    expect(find.text('Version 1.6.1 of Aumazing is available'), findsOneWidget);
    await tester.tap(find.text('Update'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('app-update-dialog')), findsOneWidget);
    expect(find.text('Version 1.6.1 is ready'), findsOneWidget);
    expect(find.text('Smoother games'), findsOneWidget);
    expect(find.text('Update now'), findsOneWidget);
  });

  testWidgets('the parent can set it aside', (tester) async {
    final service = await tester.runAsync(() => checked(release()));
    await tester.pumpWidget(host(service!));

    await tester.tap(find.byKey(const Key('app-update-dismiss')));
    await tester.pump();
    expect(find.byKey(const Key('app-update-banner')), findsNothing);
  });

  testWidgets('a required update cannot be set aside', (tester) async {
    final service = await tester.runAsync(
      () => checked(release(minSupported: 9)),
    );
    await tester.pumpWidget(host(service!));

    expect(find.text('Update required: version 1.6.1'), findsOneWidget);
    expect(find.byKey(const Key('app-update-dismiss')), findsNothing);
  });
}
