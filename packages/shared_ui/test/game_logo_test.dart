import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';

void main() {
  final logoDir = Directory('assets/game_logos');
  final logos = logoDir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.svg'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  test('there is artwork to test', () {
    expect(logos, isNotEmpty);
  });

  // A malformed logo does not crash the app — GameLogo just falls back to the
  // icon — so a broken tile would ship silently. This compiles each one the
  // same way flutter_svg does at runtime, which is where a bad path or an
  // unresolved gradient/clip reference throws.
  for (final file in logos) {
    testWidgets('${file.uri.pathSegments.last} compiles', (tester) async {
      await tester.runAsync(() async {
        final bytes =
            await SvgStringLoader(file.readAsStringSync()).loadBytes(null);
        expect(bytes.lengthInBytes, greaterThan(0));
      });
    });
  }

  testWidgets('GameLogo falls back to the icon when there is no artwork',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: GameLogo(asset: null, size: 48, fallbackIcon: Icons.extension),
    ));
    expect(find.byIcon(Icons.extension), findsOneWidget);
  });
}
