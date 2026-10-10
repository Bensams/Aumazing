import 'package:aumazing/core/web/offline_save_status.dart';
import 'package:aumazing/features/settings/widgets/offline_play_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';

/// Settings › Offline Play: the web build saves the games in the background
/// while the child plays, and this tile tells a parent how far it has got.
void main() {
  final status = OfflineSaveStatus.instance;

  tearDown(() => status.debugSetProgress(null));

  Future<void> pumpTile(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(body: OfflinePlayTile()),
      ),
    );
  }

  testWidgets('is hidden when nothing is being saved (Android, iOS)', (
    tester,
  ) async {
    await pumpTile(tester);
    expect(find.byKey(const Key('offline-play-tile')), findsNothing);
  });

  testWidgets('shows the percentage and a progress bar while saving', (
    tester,
  ) async {
    await pumpTile(tester);
    status.debugSetProgress(
      const OfflineSaveProgress(
        state: OfflineSaveState.saving,
        doneBytes: 64 << 20,
        totalBytes: 100 << 20,
      ),
    );
    await tester.pump();

    expect(find.text('Offline Play'), findsOneWidget);
    expect(
      find.text('Saving games for offline play · 64% (64 of 100 MB)'),
      findsOneWidget,
    );
    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.value, closeTo(0.64, 0.001));
  });

  testWidgets('says when saving is paused for lack of internet', (
    tester,
  ) async {
    await pumpTile(tester);
    status.debugSetProgress(
      const OfflineSaveProgress(
        state: OfflineSaveState.paused,
        reason: OfflinePauseReason.offline,
        doneBytes: 1,
        totalBytes: 4,
      ),
    );
    await tester.pump();

    expect(
      find.textContaining('Paused, no internet · 25% saved'),
      findsOneWidget,
    );
  });

  testWidgets('says when every game plays offline, without a bar', (
    tester,
  ) async {
    await pumpTile(tester);
    status.debugSetProgress(
      const OfflineSaveProgress(
        state: OfflineSaveState.ready,
        doneBytes: 4,
        totalBytes: 4,
      ),
    );
    await tester.pump();

    expect(
      find.text('Ready: every game plays without internet'),
      findsOneWidget,
    );
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  group('OfflineSaveProgress.parse', () {
    test('reads the loading page values', () {
      expect(
        OfflineSaveProgress.parse(
          status: 'paused',
          reason: 'retrying',
          done: 10,
          total: 40,
        ),
        const OfflineSaveProgress(
          state: OfflineSaveState.paused,
          reason: OfflinePauseReason.retrying,
          doneBytes: 10,
          totalBytes: 40,
        ),
      );
    });

    test('ignores a status this build does not know', () {
      expect(OfflineSaveProgress.parse(status: 'teleporting'), isNull);
      expect(OfflineSaveProgress.parse(status: null), isNull);
    });

    test('has no fraction before the total is known', () {
      const checking = OfflineSaveProgress(state: OfflineSaveState.checking);
      expect(checking.fraction, isNull);
      expect(checking.percent, 0);
    });
  });
}
