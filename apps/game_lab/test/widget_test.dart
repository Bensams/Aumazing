import 'package:flutter_test/flutter_test.dart';

import 'package:game_lab/main.dart';

void main() {
  testWidgets('GameLabApp launches', (WidgetTester tester) async {
    await tester.pumpWidget(const GameLabApp());
    // The launcher screen title includes an emoji prefix
    expect(find.textContaining('Game Lab'), findsOneWidget);
  });
}
