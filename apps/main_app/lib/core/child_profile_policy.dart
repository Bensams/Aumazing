enum ChildBirthDateValidation { valid, missing, futureDate, tooYoung, tooOld }

/// Calculates age in whole years from date-only values.
///
/// Future birth dates can produce negative ages. Call
/// [validateBirthDate] when you need eligibility checks.
/// Leap-day birthdays are treated as having their birthday on February 28 in
/// non-leap years.
int calculateAgeYears(DateTime birthDate, {DateTime? today}) {
  final now = today ?? DateTime.now();
  final dateOnlyToday = DateTime(now.year, now.month, now.day);
  final dateOnlyBirth = DateTime(
    birthDate.year,
    birthDate.month,
    birthDate.day,
  );

  var years = dateOnlyToday.year - dateOnlyBirth.year;
  final birthdayDay = _birthdayDayForYear(dateOnlyBirth, dateOnlyToday.year);
  final hadBirthday =
      dateOnlyToday.month > dateOnlyBirth.month ||
      (dateOnlyToday.month == dateOnlyBirth.month &&
          dateOnlyToday.day >= birthdayDay);

  if (!hadBirthday) {
    years -= 1;
  }

  return years;
}

ChildBirthDateValidation validateBirthDate(
  DateTime? birthDate, {
  DateTime? today,
}) {
  if (birthDate == null) {
    return ChildBirthDateValidation.missing;
  }

  final now = today ?? DateTime.now();
  final dateOnlyNow = DateTime(now.year, now.month, now.day);
  final dateOnlyBirth = DateTime(
    birthDate.year,
    birthDate.month,
    birthDate.day,
  );

  if (dateOnlyBirth.isAfter(dateOnlyNow)) {
    return ChildBirthDateValidation.futureDate;
  }

  final age = calculateAgeYears(dateOnlyBirth, today: dateOnlyNow);

  if (age < 2) {
    return ChildBirthDateValidation.tooYoung;
  }

  if (age > 6) {
    return ChildBirthDateValidation.tooOld;
  }

  return ChildBirthDateValidation.valid;
}

int _birthdayDayForYear(DateTime birthDate, int year) {
  if (birthDate.month == 2 && birthDate.day == 29 && !_isLeapYear(year)) {
    return 28;
  }

  return birthDate.day;
}

bool _isLeapYear(int year) {
  return year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);
}
