import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aumazing/core/services/sync_service.dart';
import 'package:aumazing/core/widgets/sync_status_banner.dart';

void main() {
  late StreamController<SyncState> syncStates;
  late StreamController<bool> connectivity;

  setUp(() {
    syncStates = StreamController<SyncState>.broadcast();
    connectivity = StreamController<bool>.broadcast();
  });

  tearDown(() async {
    await syncStates.close();
    await connectivity.close();
  });

  Future<void> pumpBanner(
    WidgetTester tester, {
    required Future<int> Function() pendingCount,
    bool online = true,
    Duration syncedVisibleFor = const Duration(seconds: 4),
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SyncStatusBanner(
            syncStates: syncStates.stream,
            connectivityChanges: connectivity.stream,
            pendingCount: pendingCount,
            initiallyOnline: online,
            syncedVisibleFor: syncedVisibleFor,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('stays out of the way when online with nothing pending',
      (tester) async {
    await pumpBanner(tester, pendingCount: () async => 0);

    expect(find.byType(Container), findsNothing);
    expect(find.textContaining('sync'), findsNothing);
  });

  testWidgets('offline reports what is being held on the device',
      (tester) async {
    await pumpBanner(tester, pendingCount: () async => 3, online: false);

    expect(find.text('Offline — 3 changes saved on this device'),
        findsOneWidget);
  });

  testWidgets('a single pending change reads in the singular', (tester) async {
    await pumpBanner(tester, pendingCount: () async => 1, online: false);

    expect(find.text('Offline — 1 change saved on this device'), findsOneWidget);
  });

  testWidgets('offline with nothing pending still reassures', (tester) async {
    await pumpBanner(tester, pendingCount: () async => 0, online: false);

    expect(find.text('Offline — you can keep playing'), findsOneWidget);
  });

  testWidgets('going offline then back online walks pending → syncing → synced',
      (tester) async {
    var pending = 2;
    await pumpBanner(tester, pendingCount: () async => pending, online: false);
    expect(find.text('Offline — 2 changes saved on this device'),
        findsOneWidget);

    // Airplane mode off: the network returns and the queue starts moving.
    connectivity.add(true);
    await tester.pump();
    await tester.pump();
    syncStates.add(const SyncState(status: SyncStatusEnum.syncing));
    await tester.pump();
    await tester.pump();
    expect(find.text('Syncing 2 changes…'), findsOneWidget);

    // The queue drains.
    pending = 0;
    syncStates.add(const SyncState(status: SyncStatusEnum.completed));
    await tester.pump();
    await tester.pump();
    expect(find.text('All synced'), findsOneWidget);
  });

  testWidgets('"All synced" retreats once it has been seen', (tester) async {
    var pending = 1;
    await pumpBanner(
      tester,
      pendingCount: () async => pending,
      online: false,
      syncedVisibleFor: const Duration(seconds: 2),
    );

    connectivity.add(true);
    await tester.pump();
    await tester.pump();

    pending = 0;
    syncStates.add(const SyncState(status: SyncStatusEnum.completed));
    await tester.pump();
    await tester.pump();
    expect(find.text('All synced'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    expect(find.text('All synced'), findsNothing);
  });

  testWidgets('a failed pass promises a retry rather than going quiet',
      (tester) async {
    await pumpBanner(tester, pendingCount: () async => 0);

    syncStates.add(const SyncState(
      status: SyncStatusEnum.completed,
      failedCount: 2,
    ));
    await tester.pump();
    await tester.pump();

    expect(find.text("Some changes haven't synced yet — we'll keep trying"),
        findsOneWidget);
  });

  testWidgets('an unreadable count does not take the banner down',
      (tester) async {
    await pumpBanner(
      tester,
      pendingCount: () async => throw Exception('db locked'),
      online: false,
    );

    // Offline still has something true to say even with no count.
    expect(find.text('Offline — you can keep playing'), findsOneWidget);
  });
}
