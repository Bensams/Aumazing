import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:aumazing/features/splash/auth/credits_dialog.dart';

void main() {
  testWidgets('credits dialog displays sections and closes', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: CreditsDialog())),
    );
    expect(find.text('Credits'), findsOneWidget);
    expect(find.text('Capstone Team & Characters'), findsOneWidget);
    expect(find.text('Institutional & Capstone Details'), findsOneWidget);
    expect(find.text('Art & Visual Media'), findsOneWidget);
    expect(find.text('Audio & Music'), findsOneWidget);
    expect(find.text('Open Source & Technology'), findsOneWidget);
    expect(find.text('Benedict Paul S. Samson'), findsOneWidget);
    expect(find.text('Ruel Jr. A. Mendio'), findsOneWidget);
    expect(find.text('Alexandra Mendoza'), findsOneWidget);
  });

  testWidgets('close control dismisses dialog', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: false),
        home: Builder(
          builder:
              (context) => ElevatedButton(
                onPressed: () => showCreditsDialog(context),
                child: const Text('Open'),
              ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Close credits'), findsOneWidget);
    await tester.tap(find.byTooltip('Close credits'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Close credits'), findsNothing);
  });
}
