import 'package:aumazing/core/child_profile_policy.dart';
import 'package:aumazing/model/child_profile.dart';
import 'package:flutter_test/flutter_test.dart';

ChildProfile _buildProfile({
  DateTime? birthDate,
}) {
  return ChildProfile(
    id: 'child-1',
    userId: 'user-1',
    displayName: 'Mika',
    birthDate: birthDate ?? DateTime(2022, 4, 20),
    avatar: 'bear',
    createdAt: DateTime(2026, 4, 20),
    updatedAt: DateTime(2026, 4, 20),
  );
}

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

  // AUMazing serves autistic children with no age limit. A birth date is
  // rejected only when it is absent or impossible — never for the age it
  // implies, at either end.
  test('validateBirthDate accepts a child under two', () {
    final today = DateTime(2026, 4, 20);
    final result = validateBirthDate(DateTime(2025, 4, 21), today: today);

    expect(result, ChildBirthDateValidation.valid);
  });

  test('validateBirthDate accepts a child older than six', () {
    final today = DateTime(2026, 4, 20);
    final result = validateBirthDate(DateTime(2018, 4, 19), today: today);

    expect(result, ChildBirthDateValidation.valid);
  });

  test('validateBirthDate accepts a much older child', () {
    final today = DateTime(2026, 4, 20);
    final result = validateBirthDate(DateTime(2005, 1, 1), today: today);

    expect(result, ChildBirthDateValidation.valid);
  });

  test('validateBirthDate accepts a child inside the former range', () {
    final today = DateTime(2026, 4, 20);

    expect(
      validateBirthDate(DateTime(2020, 4, 20), today: today),
      ChildBirthDateValidation.valid,
    );
  });

  test('a birth date is still required', () {
    expect(validateBirthDate(null), ChildBirthDateValidation.missing);
  });

  test('child profile derives age from birth date', () {
    final profile = _buildProfile();

    expect(profile.ageYears(today: DateTime(2026, 4, 20)), 4);
  });

  test('child profile compatibility getters mirror canonical state', () {
    final profile = _buildProfile(birthDate: DateTime(2022, 4, 20));

    expect(profile.name, 'Mika');
    expect(profile.age, 4);
  });
}
