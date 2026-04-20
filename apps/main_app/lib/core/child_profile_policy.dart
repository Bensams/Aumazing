enum ChildBirthDateValidation { valid, missing, futureDate, tooYoung, tooOld }

int calculateAgeYears(DateTime birthDate, {DateTime? today}) {
  final now = today ?? DateTime.now();
  var years = now.year - birthDate.year;
  final hadBirthday =
      now.month > birthDate.month ||
      (now.month == birthDate.month && now.day >= birthDate.day);

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
