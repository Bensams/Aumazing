import 'package:flutter_test/flutter_test.dart';

import 'package:game_lab/main.dart';
import 'package:game_lab/services/game_lab_services.dart';

void main() {
  testWidgets('GameLabApp launches', (WidgetTester tester) async {
    GameLabServices.instance.initialize();
    await tester.pumpWidget(const GameLabApp());
    // The launcher screen title includes an emoji prefix
    expect(find.textContaining('Game Lab'), findsOneWidget);
  });
}
