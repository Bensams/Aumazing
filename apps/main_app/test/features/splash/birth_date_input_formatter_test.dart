import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aumazing/features/splash/auth/child_profile_setup_screen.dart';

void main() {
  const formatter = BirthDateInputFormatter();

  TextEditingValue format(String oldText, String newText, {int? cursor}) {
    return formatter.formatEditUpdate(
      TextEditingValue(
        text: oldText,
        selection: TextSelection.collapsed(offset: oldText.length),
      ),
      TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: cursor ?? newText.length),
      ),
    );
  }

  test('inserts month and day separators for digits-only entry', () {
    expect(format('', '04212005').text, '04/21/2005');
  });

  test('normalizes pasted slashes and ignores non-digit characters', () {
    expect(format('', '04/21/2005').text, '04/21/2005');
    expect(format('', '04-21-2005').text, '04/21/2005');
  });

  test('limits the field to a complete eight-digit date', () {
    expect(format('', '0421200599').text, '04/21/2005');
  });

  test('keeps the cursor beside the same digit after inserting a slash', () {
    final value = format('04', '042', cursor: 3);
    expect(value.text, '04/2');
    expect(value.selection.baseOffset, 4);
  });

  test('removes an automatically inserted slash when fewer digits remain', () {
    final value = format('04/', '04/', cursor: 3);
    expect(value.text, '04');
    expect(value.selection.baseOffset, 2);
  });
}
