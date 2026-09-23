import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aumazing/features/settings/offline_play_screen.dart';
import 'package:aumazing/services/offline_web_service.dart';
import 'package:shared_ui/shared_ui.dart';

/// Stands in for the browser's offline service worker (AUM-334).
class _FakeOfflineService extends OfflineWebService {
  _FakeOfflineService(this._status, {this.afterDownload});

  OfflineStatus? _status;
  final OfflineStatus? afterDownload;
  int downloads = 0;

  @override
  bool get isSupported => _status != null;

  @override
  Future<OfflineStatus?> status() async => _status;

  @override
  Future<OfflineStatus?> downloadAll({
    void Function(int done, int total)? onProgress,
  }) async {
    downloads++;
    onProgress?.call(0, 2);
    onProgress?.call(2, 2);
    _status = afterDownload;
    return afterDownload;
  }
}

const _appOnly = OfflineStatus(
  coreCached: 10,
  coreTotal: 10,
  lazyCached: 1,
  lazyTotal: 10,
);

const _everything = OfflineStatus(
  coreCached: 10,
  coreTotal: 10,
  lazyCached: 10,
  lazyTotal: 10,
);

Future<void> _pump(WidgetTester tester, OfflineWebService service) async {
  await tester.pumpWidget(
    MaterialApp(
      home: OfflinePlayScreen(palette: GamePalettes.neutral, service: service),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('explains how to turn it on when the worker is not running', (
    tester,
  ) async {
    await _pump(tester, _FakeOfflineService(null));

    expect(find.text('Offline play is not ready yet'), findsOneWidget);
    expect(find.byKey(const Key('offline-download-all')), findsNothing);
  });

  testWidgets('shows progress and offers to save the remaining games', (
    tester,
  ) async {
    await _pump(tester, _FakeOfflineService(_appOnly));

    expect(find.text('The app opens without internet'), findsOneWidget);
    expect(find.text('Games saved so far: 55%'), findsOneWidget);
    expect(find.byKey(const Key('offline-download-all')), findsOneWidget);
  });

  testWidgets('saving everything marks every game ready', (tester) async {
    final service = _FakeOfflineService(_appOnly, afterDownload: _everything);
    await _pump(tester, service);

    await tester.tap(find.byKey(const Key('offline-download-all')));
    await tester.pump();
    await tester.pump();

    expect(service.downloads, 1);
    expect(find.text('Every game and its sounds are saved'), findsOneWidget);
    expect(find.byKey(const Key('offline-download-all')), findsNothing);
  });

  testWidgets('says so when some files could not be saved', (tester) async {
    await _pump(tester, _FakeOfflineService(_appOnly, afterDownload: _appOnly));

    await tester.tap(find.byKey(const Key('offline-download-all')));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('could not be saved'), findsOneWidget);
  });
}
