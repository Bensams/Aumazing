import 'package:aumazing/features/stars/star_catalogue.dart';
import 'package:aumazing/features/stars/widgets/character_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';

void main() {
  testWidgets('selected and unselected cards keep equal dimensions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_picker(selected: ChildCharacter.bps));
    await tester.pumpAndSettle();
    final selectedRect = tester.getRect(_card(ChildCharacter.bps));

    await tester.pumpWidget(_picker(selected: ChildCharacter.lexianne));
    await tester.pumpAndSettle();
    final unselectedRect = tester.getRect(_card(ChildCharacter.bps));

    expect(
      selectedRect.width,
      moreOrLessEquals(unselectedRect.width, epsilon: 0.01),
    );
    expect(
      selectedRect.height,
      moreOrLessEquals(unselectedRect.height, epsilon: 0.01),
    );
    expect(tester.takeException(), isNull);
  });
}

Widget _picker({required ChildCharacter selected}) => MaterialApp(
  theme: AppTheme.light,
  home: Scaffold(body: CharacterPicker(selected: selected, onSelected: (_) {})),
);

Finder _card(ChildCharacter character) => find.ancestor(
  of: find.text(character.displayName),
  matching: find.byType(InkWell),
);
