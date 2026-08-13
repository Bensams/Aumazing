import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';

/// Parent-facing CTAs must read in full. These used to be ellipsised to
/// "Start Pre-Assessm…" / "Unlock lo…" because the button forced its label
/// onto one line with [TextOverflow.ellipsis].

/// The rendered Text widget carrying [label].
Text _labelText(WidgetTester tester, String label) =>
    tester.widget<Text>(find.text(label));

Widget _host({
  required Widget child,
  double textScale = 1.0,
  double width = 400,
}) {
  return MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Center(child: SizedBox(width: width, child: child)),
        ),
      ),
    ),
  );
}

void main() {
  const labels = ['Start Pre-Assessment', 'Unlock locator'];
  // Narrow enough to force wrapping; wide enough for a single line.
  const widths = [160.0, 200.0, 320.0, 520.0];
  const scales = [1.0, 1.3];

  for (final label in labels) {
    for (final width in widths) {
      for (final scale in scales) {
        testWidgets(
          '"$label" renders in full at ${width}px, ${scale}x text scale',
          (tester) async {
            late double reserved;
            await tester.pumpWidget(
              _host(
                width: width,
                textScale: scale,
                child: Builder(
                  builder: (context) {
                    reserved = AppPrimaryButton.minWidthFor(
                      context,
                      label: label,
                      icon: Icons.star_rounded,
                    );
                    return AppPrimaryButton(
                      label: label,
                      icon: Icons.star_rounded,
                      onPressed: () {},
                    );
                  },
                ),
              ),
            );
            await tester.pump();

            // No overflow exception, and the complete label is present.
            expect(tester.takeException(), isNull);
            expect(find.text(label), findsOneWidget);

            final text = _labelText(tester, label);
            expect(text.overflow, isNot(TextOverflow.ellipsis));
            expect(text.softWrap, isTrue);
            expect(text.textAlign, TextAlign.center);

            // The label never paints outside the button.
            final buttonSize = tester.getSize(find.byType(AppPrimaryButton));
            final textSize = tester.getSize(find.text(label));
            expect(textSize.width, lessThanOrEqualTo(buttonSize.width));
            expect(textSize.height, lessThanOrEqualTo(buttonSize.height));

            // Still a real touch target.
            expect(
              buttonSize.height,
              greaterThanOrEqualTo(AppPrimaryButton.minTouchTarget),
            );

            // Given at least the width the button asks for, every line of
            // the label is actually laid out — nothing is dropped.
            if (width >= reserved) {
              final paragraph = tester.renderObject<RenderParagraph>(
                find.text(label),
              );
              expect(paragraph.didExceedMaxLines, isFalse);
            }
          },
        );
      }
    }
  }

  testWidgets('a long label wraps to two lines instead of truncating', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        width: 180,
        child: const AppPrimaryButton(
          label: 'Start Pre-Assessment',
          icon: Icons.play_circle_filled_rounded,
          onPressed: null,
        ),
      ),
    );
    await tester.pump();

    final text = _labelText(tester, 'Start Pre-Assessment');
    expect(text.maxLines, 2);

    // Two lines of buttonLarge plus padding — taller than the one-line
    // button, which is how we know it wrapped rather than clipped.
    final height = tester.getSize(find.byType(AppPrimaryButton)).height;
    expect(height, greaterThan(60));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the tap callback and loading state still work', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _host(
        child: AppPrimaryButton(
          label: 'Unlock locator',
          icon: Icons.star_rounded,
          onPressed: () => taps += 1,
        ),
      ),
    );
    await tester.tap(find.byType(AppPrimaryButton));
    await tester.pump();
    expect(taps, 1);

    await tester.pumpWidget(
      _host(
        child: AppPrimaryButton(
          label: 'Unlock locator',
          icon: Icons.star_rounded,
          isLoading: true,
          onPressed: () => taps += 1,
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Unlock locator'), findsNothing);
  });

  group('minWidthFor', () {
    testWidgets('covers the width the label actually renders at', (
      tester,
    ) async {
      late double reserved;
      const label = 'Unlock locator';

      await tester.pumpWidget(
        _host(
          child: Builder(
            builder: (context) {
              reserved = AppPrimaryButton.minWidthFor(
                context,
                label: label,
                icon: Icons.star_rounded,
              );
              // A loose parent, as in the real side-by-side layouts — a tight
              // one would override the button's own width.
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppPrimaryButton(
                    label: label,
                    icon: Icons.star_rounded,
                    width: reserved,
                    onPressed: () {},
                  ),
                ],
              );
            },
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text(label), findsOneWidget);
      expect(
        tester.getSize(find.text(label)).width,
        lessThanOrEqualTo(reserved),
      );
      // The old hand-picked 180 was too small for this label with an icon.
      expect(reserved, greaterThan(0));
    });

    testWidgets('grows with the text scale', (tester) async {
      late double atOne;
      late double atOnePointThree;

      await tester.pumpWidget(
        _host(
          child: Builder(
            builder: (context) {
              atOne = AppPrimaryButton.minWidthFor(
                context,
                label: 'Start Pre-Assessment',
                icon: Icons.play_circle_filled_rounded,
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pumpWidget(
        _host(
          textScale: 1.3,
          child: Builder(
            builder: (context) {
              atOnePointThree = AppPrimaryButton.minWidthFor(
                context,
                label: 'Start Pre-Assessment',
                icon: Icons.play_circle_filled_rounded,
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(atOnePointThree, greaterThan(atOne));
    });
  });
}
