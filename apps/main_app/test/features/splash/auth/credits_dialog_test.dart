import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:aumazing/features/splash/auth/credits_dialog.dart';

void main() {
  testWidgets('credits dialog displays sections and closes', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: CreditsDialog())),
    );
    expect(find.text('Aumazing'), findsOneWidget);
    expect(find.text('PROJECT PROPONENTS & DEVELOPERS'), findsOneWidget);
    expect(find.text('EXPERT VALIDATORS & PRACTITIONERS'), findsOneWidget);
    expect(find.text('INSTITUTIONAL & CAPSTONE DETAILS'), findsOneWidget);
    expect(find.text('SYSTEM ARCHITECTURE & CORE TECHNOLOGIES'), findsOneWidget);
    expect(find.text('ART, AUDIO & SENSORY DESIGN'), findsOneWidget);
    expect(find.text('DISCLAIMER'), findsOneWidget);
    expect(find.text('Benedict Paul S. Samson'), findsOneWidget);
    expect(find.text('Ruel Jr. A. Mendio'), findsOneWidget);
    expect(find.text('Alexandra Mendoza'), findsOneWidget);
    expect(find.text("Ma'am Lea"), findsOneWidget);
    expect(find.text('Kenneth Ray'), findsOneWidget);
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
