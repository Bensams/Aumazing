import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';

/// The offline web build (AUM-334) cannot reach fonts.gstatic.com, so every
/// typeface variant the theme asks google_fonts for must be bundled under
/// assets/google_fonts/, named the way google_fonts looks it up
/// (`<Family>-<Variant>.ttf`).
///
/// google_fonts names each loaded family `<Family>_<variant>`, e.g.
/// `Poppins_regular` or `Nunito_500`; this maps that back to the file name.
const _variantNames = {
  'regular': 'Regular',
  '100': 'Thin',
  '200': 'ExtraLight',
  '300': 'Light',
  '500': 'Medium',
  '600': 'SemiBold',
  '700': 'Bold',
  '800': 'ExtraBold',
  '900': 'Black',
};

String _expectedFileName(String family) {
  final split = family.lastIndexOf('_');
  final name = family.substring(0, split);
  final variant = family.substring(split + 1);
  return '$name-${_variantNames[variant]}.ttf';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every theme font variant is bundled as an asset', () async {
    final theme = AppTheme.light;
    final families = <String>{
      for (final style in [
        AppTextStyles.headlineMedium,
        AppTextStyles.bodyMedium,
        AppTextStyles.buttonMedium,
        AppTextStyles.labelLarge,
        theme.snackBarTheme.contentTextStyle!,
      ])
        style.fontFamily!,
    };
    expect(families, isNotEmpty);

    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final assets = manifest.listAssets();

    for (final family in families) {
      final file = _expectedFileName(family);
      expect(
        assets.any((a) => a.endsWith('google_fonts/$file')),
        isTrue,
        reason: '$family needs assets/google_fonts/$file to render offline',
      );
    }
  });
}
