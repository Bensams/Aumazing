import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import 'package:aumazing/features/splash/auth/child_profile_setup_screen.dart';
import 'package:aumazing/core/child_profile_policy.dart';

/// The first screen a parent ever sees asks for name, gender, then birth
/// date. Gender is a two-tap choice; the birth date opens a modal picker, so
/// it goes last and the run of inline fields is not interrupted part-way.
///
/// Asserted on real laid-out positions rather than widget order, because
/// this screen has separate portrait and landscape layouts and both have to
/// agree.
void main() {
  Future<void> pumpAt(WidgetTester tester, Size size) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: ChildProfileSetupScreen()));
    await tester.pump();
  }

  void expectGenderAboveBirthDate(WidgetTester tester) {
    final gender = find.text('Gender');
    final birthDate = find.text('Birth Date');
    expect(gender, findsOneWidget);
    expect(birthDate, findsOneWidget);
    expect(
      tester.getTopLeft(gender).dy,
      lessThan(tester.getTopLeft(birthDate).dy),
      reason: 'gender must be asked before the birth date',
    );
  }

  Future<void> expectDateAndCalculatedAge(WidgetTester tester) async {
    final button = find.byKey(const Key('birth-date-button'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    final dialog = tester.widget<DatePickerDialog>(
      find.byType(DatePickerDialog),
    );
    final birthDate = dialog.initialDate!;
    final localizations = MaterialLocalizations.of(tester.element(button));
    await tester.tap(find.text(localizations.okButtonLabel));
    await tester.pumpAndSettle();
    final formattedDate = DateFormat.yMMMMd().format(birthDate);

    expect(
      find.descendant(of: button, matching: find.text(formattedDate)),
      findsOneWidget,
    );
    expect(find.text('Calculated age'), findsOneWidget);
    final age = calculateAgeYears(birthDate);
    final ageText = find.text('$age ${age == 1 ? 'year' : 'years'} old');
    expect(ageText, findsOneWidget);
    expect(find.descendant(of: button, matching: ageText), findsNothing);
    expect(
      find.text('Age is calculated automatically from the birth date.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  }

  testWidgets('portrait asks gender before birth date', (tester) async {
    await pumpAt(tester, const Size(500, 1600));
    expectGenderAboveBirthDate(tester);
    await expectDateAndCalculatedAge(tester);
  });

  testWidgets('landscape asks gender before birth date', (tester) async {
    // The wide layout builds a different column; it must not disagree.
    await pumpAt(tester, const Size(1400, 1000));
    expectGenderAboveBirthDate(tester);
    await expectDateAndCalculatedAge(tester);
  });

  testWidgets('the name field still comes first', (tester) async {
    await pumpAt(tester, const Size(500, 1600));
    final name = find.byType(TextFormField);
    expect(name, findsOneWidget);
    expect(
      tester.getTopLeft(name).dy,
      lessThan(tester.getTopLeft(find.text('Gender')).dy),
    );
  });

  testWidgets('birth date input inserts separators while typing', (
    tester,
  ) async {
    await pumpAt(tester, const Size(500, 1600));
    final button = find.byKey(const Key('birth-date-button'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();

    final localizations = MaterialLocalizations.of(tester.element(button));
    final inputModeButton = find.byTooltip(
      localizations.inputDateModeButtonLabel,
    );
    expect(inputModeButton, findsOneWidget);
    await tester.tap(inputModeButton);
    await tester.pumpAndSettle();

    final dialog = find.byType(DatePickerDialog);
    final input = find.descendant(
      of: dialog,
      matching: find.byType(TextFormField),
    );
    expect(input, findsOneWidget);
    await tester.enterText(input, '04212005');
    await tester.pump();

    expect(
      find.descendant(of: input, matching: find.text('04/21/2005')),
      findsOneWidget,
    );
    await tester.tap(find.text(localizations.okButtonLabel));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: button,
        matching: find.text(DateFormat.yMMMMd().format(DateTime(2005, 4, 21))),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
