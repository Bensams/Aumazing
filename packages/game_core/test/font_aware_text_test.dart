import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/src/games/shared/font_aware_text.dart';

/// A [TextPaint] keeps the first layout of every string it renders. On the web
/// that first layout of an emoji is a placeholder box whenever the emoji font
/// is still loading, so components must rebuild their paints once the engine
/// reports the font has arrived — and stop listening once they are gone.
class _Probe extends PositionComponent with FontAwareText {
  int builds = 0;

  @override
  void buildTextPaints() => builds++;
}

void main() {
  Future<void> fontsChanged() =>
      PaintingBinding.instance.handleSystemMessage({'type': 'fontsChange'});

  Future<_Probe> mountProbe(WidgetTester tester, FlameGame game) async {
    await tester.pumpWidget(GameWidget(game: game));
    final probe = _Probe();
    game.add(probe);
    // A frame to attach the game, one more to mount what was added to it.
    await tester.pump();
    await tester.pump();
    expect(probe.isMounted, isTrue);
    return probe;
  }

  testWidgets('builds its paints on mount and again when a font loads',
      (tester) async {
    final probe = await mountProbe(tester, FlameGame());
    expect(probe.builds, 1);

    await fontsChanged();
    expect(probe.builds, 2);
  });

  testWidgets('stops rebuilding once removed', (tester) async {
    final game = FlameGame();
    final probe = await mountProbe(tester, game);

    probe.removeFromParent();
    await tester.pump();
    expect(probe.isMounted, isFalse);

    await fontsChanged();
    expect(probe.builds, 1);
  });
}
