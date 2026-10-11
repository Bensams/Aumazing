import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shared_ui/shared_ui.dart';

/// The theme purple carries button labels, links and headings, so it must
/// clear WCAG 2.2 AA 1.4.3 (4.5:1) wherever the app puts text on or in it.
void main() {
  const aa = 4.5;

  testWidgets('white text on the theme purple clears AA', (tester) async {
    final scheme = AppTheme.light.colorScheme;
    expect(Contrast.contrastRatio(scheme.onPrimary, scheme.primary),
        greaterThanOrEqualTo(aa));
  });

  test('purple text clears AA on every light surface', () {
    for (final surface in [
      AppColors.white,
      AppColors.background,
      AppColors.muted,
      AppColors.lavenderLight,
      AppColors.lavender,
    ]) {
      expect(
        Contrast.contrastRatio(AppColors.primaryPurpleDark, surface),
        greaterThanOrEqualTo(aa),
        reason: 'on $surface',
      );
    }
  });

  testWidgets('buttons and links in the theme use the readable purple', (
    tester,
  ) async {
    final theme = AppTheme.light;
    Color? resolve(WidgetStateProperty<Color?>? p) => p?.resolve({});
    expect(resolve(theme.elevatedButtonTheme.style!.backgroundColor),
        AppColors.primaryPurpleDark);
    expect(resolve(theme.textButtonTheme.style!.foregroundColor),
        AppColors.primaryPurpleDark);
  });

  test('the soft purple stays decorative: it fails AA behind white text', () {
    // Guards the doc comment on AppColors.primaryPurple.
    expect(Contrast.contrastRatio(AppColors.white, AppColors.primaryPurple),
        lessThan(aa));
  });
}
