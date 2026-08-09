import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('shows the caption by default', (tester) async {
    await tester.pumpWidget(wrap(
      const VoiceOverPromptBubble(text: 'Tap the shapes that look the same!'),
    ));
    expect(find.text('Tap the shapes that look the same!'), findsOneWidget);
  });

  testWidgets('showText: false hides the caption', (tester) async {
    await tester.pumpWidget(wrap(
      const VoiceOverPromptBubble(text: 'Tap the shapes', showText: false),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Tap the shapes'), findsNothing);
  });

  testWidgets('hiding the caption still plays the voice-over', (tester) async {
    // The whole point of the setting is to remove clutter for pre-readers.
    // If it also muted the spoken prompt it would remove the instruction
    // itself, leaving those children with nothing.
    var played = 0;
    await tester.pumpWidget(wrap(
      VoiceOverPromptBubble(
        text: 'Tap the shapes',
        showText: false,
        onPlayVoiceOver: () => played++,
      ),
    ));
    await tester.pumpAndSettle();
    expect(played, 1);
  });

  testWidgets('the whole bubble replays the prompt, not just the speaker',
      (tester) async {
    // Accessibility Scanner flagged the old speaker icon at 22x22dp with no
    // label. The bubble itself is the button now, so a child who missed the
    // instruction has a target they can actually hit.
    var played = 0;
    await tester.pumpWidget(wrap(
      VoiceOverPromptBubble(
        text: 'Tap the shapes',
        autoPlayOnAppear: false,
        onPlayVoiceOver: () => played++,
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Tap the shapes'));
    expect(played, 1);

    final size = tester.getSize(find.byKey(
      const ValueKey('voice_over_prompt_bubble_visible'),
    ));
    expect(size.height, greaterThanOrEqualTo(kMinInteractiveDimension));
  });

  testWidgets('the bubble exposes one named button to screen readers',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(wrap(
      const VoiceOverPromptBubble(
        text: 'Tap the orange star',
        autoPlayOnAppear: false,
      ),
    ));
    await tester.pumpAndSettle();

    expect(
      find.bySemanticsLabel('Tap the orange star'),
      findsOneWidget,
      reason: 'exactly one node carries the prompt, not a bare unlabelled icon',
    );
    handle.dispose();
  });

  testWidgets('an inactive prompt stays silent', (tester) async {
    var played = 0;
    await tester.pumpWidget(wrap(
      VoiceOverPromptBubble(
        text: 'Tap the shapes',
        isVisible: false,
        onPlayVoiceOver: () => played++,
      ),
    ));
    await tester.pumpAndSettle();
    expect(played, 0);
  });
}
