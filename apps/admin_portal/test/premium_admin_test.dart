import 'package:admin_portal/data/premium_admin.dart';
import 'package:admin_portal/pages/premium_grant_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PremiumAdminStatus', () {
    test('guests cannot be granted Premium and are told to link first', () {
      final guest = PremiumAdminStatus.fromRow({
        'is_anonymous': true,
        'is_premium': true,
        'premium_source': 'free_month',
        'premium_until': '2026-11-10T00:00:00Z',
      });
      expect(guest.canGrant, isFalse);
      expect(guest.grantBlockedReason, contains('link this guest account'));
    });

    test('bound accounts can be granted Premium', () {
      final parent = PremiumAdminStatus.fromRow({'is_anonymous': false});
      expect(parent.canGrant, isTrue);
      expect(parent.grantBlockedReason, isNull);
      expect(parent.describe(), isNull);
    });

    test('only given Premium can be ended', () {
      PremiumAdminStatus row(String source, {bool active = true}) =>
          PremiumAdminStatus.fromRow({
            'is_premium': active,
            'premium_source': source,
            'premium_until': '2026-11-10T00:00:00Z',
          });
      expect(row('admin_grant').canEnd, isTrue);
      expect(row('free_month').canEnd, isTrue);
      expect(row('paymongo').canEnd, isFalse);
      expect(row('paymongo_test').canEnd, isFalse);
      expect(row('admin_grant', active: false).canEnd, isFalse);
    });

    test('describes where Premium came from and when it ends', () {
      final free = PremiumAdminStatus.fromRow({
        'is_premium': true,
        'premium_source': 'free_month',
        'premium_until': '2026-11-10T12:00:00Z',
      });
      expect(free.describe(), startsWith('Premium until Nov'));
      expect(free.describe(), endsWith('· free month'));

      final paidEnded = PremiumAdminStatus.fromRow({
        'is_premium': false,
        'premium_source': 'paymongo_test',
        'premium_until': '2026-10-01T12:00:00Z',
      });
      expect(paidEnded.describe(), startsWith('Premium ended Oct'));
      expect(paidEnded.describe(), endsWith('· paid'));

      final revoked = PremiumAdminStatus.fromRow({
        'is_premium': false,
        'premium_source': 'admin_revoke',
        'premium_until': '2026-10-01T12:00:00Z',
      });
      expect(revoked.describe(), endsWith('by an administrator'));
    });
  });

  testWidgets('grant dialog needs a reason and returns the chosen days', (
    tester,
  ) async {
    PremiumGrantChoice? choice;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              choice = await PremiumGrantDialog.show(
                context,
                accountLabel: 'parent@example.test',
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final confirm = find.byKey(const Key('grant-confirm'));
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);

    await tester.tap(find.byKey(const Key('grant-days-60')));
    await tester.enterText(
      find.byKey(const Key('grant-reason')),
      '  School study family  ',
    );
    await tester.pump();
    expect(find.text('Grant 60 days'), findsOneWidget);

    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(choice, (days: 60, reason: 'School study family'));
  });
}
