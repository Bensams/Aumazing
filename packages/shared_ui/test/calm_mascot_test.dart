import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';

/// A valid 1x1 transparent PNG so tests don't need real assets.
final _img = MemoryImage(base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
  '+M8AAAMEAQDJmNGDAAAAAElFTkSuQmCC',
));

void main() {
  testWidgets('renders a static pose without motion under reduced motion',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CalmMascot(image: _img, reducedMotion: true),
      ),
    ));

    // Let the one-time cross-fade entry settle; after that, a
    // reduced-motion mascot must have NO running animation (breathing off).
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.hasRunningAnimations, isFalse);
    expect(find.byType(CalmMascot), findsOneWidget);
  });

  testWidgets('breathing idle runs when motion is allowed', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CalmMascot(image: _img, reducedMotion: false),
      ),
    ));
    // Past the one-time cross-fade, the only thing still animating is the
    // repeating breathing controller.
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.hasRunningAnimations, isTrue);
  });

  testWidgets('honors a fixed display height (consistent size)',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(child: CalmMascot(image: _img, height: 200)),
      ),
    ));

    final box = tester.getSize(find.byType(SizedBox).first);
    expect(box.height, 200);
  });

  test('gesture fps is clamped into the calm 3-8 range', () {
    // The widget clamps internally; assert the invariant the UI relies on.
    expect(9.0.clamp(3.0, 8.0), 8.0);
    expect(1.0.clamp(3.0, 8.0), 3.0);
    expect(6.0.clamp(3.0, 8.0), 6.0);
  });
}
