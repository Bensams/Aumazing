import 'package:aumazing/core/services/auth_service.dart';
import 'package:aumazing/features/rewards/reward_type.dart';
import 'package:aumazing/features/rewards/widgets/reward_overlay.dart';
import 'package:aumazing/providers/child_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// AUM-312 — the reward overlay is shown through `showDialog` with no `Material`
/// ancestor, so on some devices `Text` inherits Flutter's fallback
/// [DefaultTextStyle] (which carries a yellow underline). The overlay's build
/// wraps everything in `DefaultTextStyle.merge(decoration: none)`, and these
/// tests pin that each hint resolves to no decoration even under a buggy
/// ancestor.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> drainReward(WidgetTester tester) async {
    // The reward's own auto-proceed/effect-completion timers go out to ~24s
    // (balloons advance past 12s), so advance well past them, then dispose the
    // overlay to stop its indefinitely-animating effects (rockets, balloons)
    // and flush every timer their launch chains queued. pumpAndSettle is never
    // used: these effects do not settle.
    await tester.pump(const Duration(seconds: 30));
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    await tester.pump();
    await tester.pump();
  }

  Future<void> assertHintNotUnderlined(
    WidgetTester tester,
    RewardType type,
    String hint,
  ) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<ChildProvider>(
        create: (_) => _QuietChild(),
        child: MaterialApp(
          home: DefaultTextStyle(
            style: const TextStyle(
              decoration: TextDecoration.underline,
              decorationColor: Colors.yellow,
            ),
            child: RewardOverlay(
              rewardType: type,
              onComplete: () {},
              minDisplayDuration: const Duration(seconds: 10),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text(hint), findsOneWidget,
        reason: 'expected hint "$hint" to be visible');
    final style = _resolved(tester, hint);
    expect(style.decoration, TextDecoration.none,
        reason: 'hint "$hint" must not be underlined');
    expect(style.decorationColor, isNot(Colors.yellow),
        reason: 'hint "$hint" must not be yellow-underlined');

    expect(tester.takeException(), isNull);
    await drainReward(tester);
  }

  testWidgets('balloons hint is not underlined', (tester) async {
    await assertHintNotUnderlined(tester, RewardType.balloons, '🎈 Pop the balloons!');
  });

  testWidgets('fireworks hint is not underlined', (tester) async {
    await assertHintNotUnderlined(tester, RewardType.fireworks, '🎆 Tap the rockets!');
  });

  testWidgets('bubbles hint is not underlined', (tester) async {
    await assertHintNotUnderlined(tester, RewardType.bubbles, '🫧 Pop the bubbles!');
  });

  testWidgets('candy hint is not underlined', (tester) async {
    await assertHintNotUnderlined(tester, RewardType.candy, '🍬 Collect the candy!');
  });
}

/// The style a [Text] actually renders with — the inherited [DefaultTextStyle]
/// merged over the widget's own [Text.style]. This is what [RenderParagraph]
/// draws, and what the AUM-312 wrapper is responsible for.
TextStyle _resolved(WidgetTester tester, String text) {
  final finder = find.text(text).first;
  final context = tester.element(finder);
  final own = tester.widget<Text>(finder).style;
  return DefaultTextStyle.of(context).style.merge(own);
}

class _QuietChild extends ChildProvider {
  _QuietChild()
      : super(authService: AuthService(supabaseAuth: _FakeSupabaseAuth()));

  // Avoid the celebration haptic read in _startRewardFlow: a widget test has
  // no HapticService, and the only consumer here is the overlay's own toggle.
  @override
  bool get vibrationEnabled => false;

  @override
  Future<void> loadProfile() async {}
}

class _FakeSupabaseAuth implements SupabaseAuthClient {
  @override
  User? get currentUser => null;

  @override
  Session? get currentSession => null;

  @override
  Stream<AuthState> get onAuthStateChange => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
