import 'package:aumazing/core/services/auth_service.dart';
import 'package:aumazing/features/stars/star_catalogue.dart';
import 'package:aumazing/features/stars/widgets/costume_apply_overlay.dart';
import 'package:aumazing/providers/child_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// AUM-312 — the costume overlay is shown through `showDialog` with no `Material`
/// ancestor, so on some devices `Text` inherits Flutter's fallback
/// [DefaultTextStyle] (which carries a yellow underline). The overlay's build
/// wraps everything in `DefaultTextStyle.merge(decoration: none)`, and these
/// tests pin that the message resolves to no decoration even under a buggy
/// ancestor.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> drainCostume(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 1)); // fire the 700ms hold
    await tester.pump(); // flush the precache/maybePop microtask chain
    await tester.pump();
  }

  testWidgets('the costume message is not underlined', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<ChildProvider>(
        create: (_) => _QuietChild(),
        child: MaterialApp(
          home: DefaultTextStyle(
            style: const TextStyle(
              decoration: TextDecoration.underline,
              decorationColor: Colors.yellow,
            ),
            child: const CostumeApplyOverlay(
              character: ChildCharacter.bps,
              costume: Costume.teddy,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    const message = 'Putting on the Teddy…';
    expect(find.text(message), findsOneWidget,
        reason: 'expected costume message "$message" to be visible');
    final style = _resolved(tester, message);
    expect(style.decoration, TextDecoration.none,
        reason: 'message "$message" must not be underlined');
    expect(style.decorationColor, isNot(Colors.yellow),
        reason: 'message "$message" must not be yellow-underlined');

    expect(tester.takeException(), isNull);
    await drainCostume(tester);
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

  // Keeps vibration reads inert in case the overlay or a sibling probe reaches
  // for them; there is no HapticService in this harness.
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
