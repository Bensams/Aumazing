import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aumazing/features/games/my_turn_your_turn/widgets/turn_goal_card.dart';
import 'package:shared_ui/shared_ui.dart';

/// The goal card shown before the first round of My Turn, Your Turn practice
/// (AUM-365). Testers said the activity "has no objective"; the card states
/// it in the words the voice speaks, in the child's language, with the two
/// players' own pieces so a child who cannot read still sees the order.
void main() {
  Future<void> pumpCard(
    WidgetTester tester, {
    GameLanguage language = GameLanguage.english,
    VoidCallback? onStart,
    Size screen = const Size(915, 412), // a phone held landscape
  }) async {
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TurnGoalCard(
            buddyEmoji: '🦊',
            childEmoji: '🐼',
            strings: AppStrings(language),
            onStart: onStart ?? () {},
          ),
        ),
      ),
    );
  }

  testWidgets('states the goal with both players\' pieces', (tester) async {
    await pumpCard(tester);
    expect(find.text("Let's take turns."), findsOneWidget);
    expect(find.text("Buddy goes first. Then it's your turn!"), findsOneWidget);
    expect(find.text('🦊'), findsOneWidget);
    expect(find.text('🐼'), findsOneWidget);
    expect(find.text('Buddy'), findsOneWidget);
    expect(find.text('You'), findsOneWidget);
    expect(find.text("Let's play!"), findsOneWidget);
  });

  testWidgets('speaks the child\'s language', (tester) async {
    await pumpCard(tester, language: GameLanguage.tagalog);
    expect(find.text('Magpalitan tayo.'), findsOneWidget);
    expect(find.text('Ikaw'), findsOneWidget);

    await pumpCard(tester, language: GameLanguage.cebuano);
    expect(find.text('Magpuli-puli ta.'), findsOneWidget);
  });

  testWidgets('a tap anywhere starts the game', (tester) async {
    var started = 0;
    await pumpCard(tester, onStart: () => started++);
    await tester.tapAt(const Offset(20, 20)); // the dimmed edge, not the card
    expect(started, 1);
    await tester.tap(find.text("Let's play!"));
    expect(started, 2);
  });

  for (final screen in const [Size(915, 412), Size(640, 360), Size(1280, 800)]) {
    testWidgets('fits a ${screen.width.toInt()}x${screen.height.toInt()} '
        'screen without overflow', (tester) async {
      await pumpCard(tester, screen: screen);
      expect(tester.takeException(), isNull);
    });
  }

  group('goal card strings', () {
    for (final language in GameLanguage.values) {
      test('${language.slug} has every line filled in', () {
        final strings = AppStrings(language);
        expect(strings.turnGoalTitle, isNotEmpty);
        expect(strings.turnGoalOrder, isNotEmpty);
        expect(strings.turnGoalYou, isNotEmpty);
      });
    }

    test('the Filipino lines are not the English ones', () {
      const en = AppStrings(GameLanguage.english);
      expect(const AppStrings(GameLanguage.tagalog).turnGoalTitle,
          isNot(en.turnGoalTitle));
      expect(const AppStrings(GameLanguage.cebuano).turnGoalOrder,
          isNot(en.turnGoalOrder));
    });
  });
}
