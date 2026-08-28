import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aumazing/features/splash/auth/child_profile_setup_screen.dart';

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
    await tester.pumpWidget(
      const MaterialApp(home: ChildProfileSetupScreen()),
    );
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

  testWidgets('portrait asks gender before birth date', (tester) async {
    await pumpAt(tester, const Size(500, 1600));
    expectGenderAboveBirthDate(tester);
  });

  testWidgets('landscape asks gender before birth date', (tester) async {
    // The wide layout builds a different column; it must not disagree.
    await pumpAt(tester, const Size(1400, 1000));
    expectGenderAboveBirthDate(tester);
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
}
