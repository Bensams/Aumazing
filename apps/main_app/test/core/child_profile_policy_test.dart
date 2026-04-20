import 'package:aumazing/core/child_profile_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'calculateAgeYears treats Feb 29 birthdays as Feb 28 in non-leap years at age 2',
    () {
      final today = DateTime(2026, 2, 28);
      final birthDate = DateTime(2024, 2, 29);

      expect(calculateAgeYears(birthDate, today: today), 2);
    },
  );

  test(
    'calculateAgeYears treats Feb 29 birthdays as Feb 28 in non-leap years at age 6',
    () {
      final today = DateTime(2026, 2, 28);
      final birthDate = DateTime(2020, 2, 29);

      expect(calculateAgeYears(birthDate, today: today), 6);
    },
  );

  test('calculateAgeYears returns negative ages for future dates', () {
    final today = DateTime(2026, 4, 20);
    final birthDate = DateTime(2026, 4, 21);

    expect(calculateAgeYears(birthDate, today: today), -1);
  });

  test('calculateAgeYears returns 2 on the second birthday', () {
    final today = DateTime(2026, 4, 20);
    final birthDate = DateTime(2024, 4, 20);

    expect(calculateAgeYears(birthDate, today: today), 2);
  });

  test('calculateAgeYears returns 6 before the seventh birthday', () {
    final today = DateTime(2026, 4, 20);
    final birthDate = DateTime(2019, 4, 21);

    expect(calculateAgeYears(birthDate, today: today), 6);
  });

  test('validateBirthDate rejects future dates', () {
    final today = DateTime(2026, 4, 20);
    final result = validateBirthDate(DateTime(2026, 4, 21), today: today);

    expect(result, ChildBirthDateValidation.futureDate);
  });

  test('validateBirthDate rejects children younger than two', () {
    final today = DateTime(2026, 4, 20);
    final result = validateBirthDate(DateTime(2025, 4, 21), today: today);

    expect(result, ChildBirthDateValidation.tooYoung);
  });

  test('validateBirthDate rejects children older than six', () {
    final today = DateTime(2026, 4, 20);
    final result = validateBirthDate(DateTime(2018, 4, 19), today: today);

    expect(result, ChildBirthDateValidation.tooOld);
  });

  test('validateBirthDate accepts children between two and six inclusive', () {
    final today = DateTime(2026, 4, 20);

    expect(
      validateBirthDate(DateTime(2020, 4, 20), today: today),
      ChildBirthDateValidation.valid,
    );
  });
}
