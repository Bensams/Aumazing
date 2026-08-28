import 'package:aumazing/core/services/auth_service.dart';
import 'package:aumazing/features/stars/star_catalogue.dart';
import 'package:aumazing/features/stars/star_shop_screen.dart';
import 'package:aumazing/features/stars/widgets/character_picker.dart';
import 'package:aumazing/features/stars/widgets/costume_card.dart';
import 'package:aumazing/model/child_profile.dart';
import 'package:aumazing/providers/child_provider.dart';
import 'package:aumazing/providers/stars_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _phonePortrait = Size(390, 844);
const _phoneLandscape = Size(844, 390);

final _profile = ChildProfile(
  id: 'geometry-child',
  userId: 'geometry-user',
  displayName: 'Geometry',
  birthDate: DateTime(2022),
  avatar: 'bear',
  characterId: 'bps',
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
);

void main() {
  for (final viewport in [_phonePortrait, _phoneLandscape]) {
    final orientation = viewport == _phonePortrait ? 'portrait' : 'landscape';

    testWidgets(
      'owned and unowned costume geometry stays invariant on a phone $orientation',
      (tester) async {
        for (final character in ChildCharacter.values) {
          await _pumpShop(tester, viewport, character: character, owned: {});
          final unownedTarget = tester.getRect(_costumeTarget(Costume.teddy));
          final unownedCard = tester.getRect(_costumeCardRect(Costume.teddy));
          final unownedArtwork = tester.getRect(_costumeArtwork(Costume.teddy));

          await _pumpShop(
            tester,
            viewport,
            character: character,
            owned: {Costume.teddy},
          );
          final ownedTarget = tester.getRect(_costumeTarget(Costume.teddy));
          final ownedCard = tester.getRect(_costumeCardRect(Costume.teddy));
          final ownedArtwork = tester.getRect(_costumeArtwork(Costume.teddy));

          _expectSameRect(ownedTarget, unownedTarget);
          _expectSameRect(ownedCard, unownedCard);
          _expectSameRect(ownedArtwork, unownedArtwork);
          expect(tester.takeException(), isNull);
        }
      },
    );

    testWidgets(
      'selected and unselected character geometry stays invariant on a phone $orientation',
      (tester) async {
        await _setViewport(tester, viewport);

        for (final character in ChildCharacter.values) {
          await tester.pumpWidget(_picker(selected: character));
          await tester.pumpAndSettle();
          final selectedTarget = tester.getRect(_characterTarget(character));
          final selectedCard = tester.getRect(_characterContainer(character));
          final selectedArtwork = tester.getRect(_characterArtwork(character));

          final other = character == ChildCharacter.bps
              ? ChildCharacter.lexianne
              : ChildCharacter.bps;
          await tester.pumpWidget(_picker(selected: other));
          await tester.pumpAndSettle();
          final unselectedTarget = tester.getRect(_characterTarget(character));
          final unselectedCard = tester.getRect(_characterContainer(character));
          final unselectedArtwork = tester.getRect(_characterArtwork(character));

          _expectSameRect(selectedTarget, unselectedTarget);
          _expectSameRect(selectedCard, unselectedCard);
          _expectSameRect(selectedArtwork, unselectedArtwork);
          expect(tester.takeException(), isNull);
        }
      },
    );
  }
}

Future<void> _setViewport(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _pumpShop(
  WidgetTester tester,
  Size size, {
  required ChildCharacter character,
  required Set<Costume> owned,
}) async {
  await _setViewport(tester, size);
  await tester.pumpWidget(
    KeyedSubtree(
      key: ValueKey('${character.id}-${owned.contains(Costume.teddy)}'),
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider<ChildProvider>(
            create: (_) => _TestChild(character),
          ),
          ChangeNotifierProvider<StarsProvider>(
            create: (_) => _TestStars(owned),
          ),
        ],
        child: MaterialApp(theme: AppTheme.light, home: const StarShopScreen()),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Widget _picker({required ChildCharacter selected}) => MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: CharacterPicker(selected: selected, onSelected: (_) {}),
      ),
    );

Finder _costumeCard(Costume costume) => find.byWidgetPredicate(
      (widget) => widget is CostumeCard && widget.offer.costume == costume,
    );

Finder _costumeTarget(Costume costume) => find.descendant(
      of: _costumeCard(costume),
      matching: find.byType(InkWell),
    );

Finder _costumeCardRect(Costume costume) => find.descendant(
      of: _costumeCard(costume),
      matching: find.byType(Container),
    );

Finder _costumeArtwork(Costume costume) => find.descendant(
      of: _costumeCard(costume),
      matching: find.byType(Stack),
    );

Finder _characterTarget(ChildCharacter character) => find.ancestor(
      of: find.text(character.displayName),
      matching: find.byType(InkWell),
    );

Finder _characterContainer(ChildCharacter character) => find.ancestor(
      of: find.text(character.displayName),
      matching: find.byType(AnimatedContainer),
    );

Finder _characterArtwork(ChildCharacter character) {
  final image = find.byWidgetPredicate(
    (widget) =>
        widget is Image &&
        widget.image is AssetImage &&
        (widget.image as AssetImage).assetName == character.baseArtAsset,
  );
  return find.ancestor(of: image, matching: find.byType(SizedBox)).first;
}

void _expectSameRect(Rect actual, Rect expected) {
  expect(actual.left, moreOrLessEquals(expected.left, epsilon: 0.01));
  expect(actual.top, moreOrLessEquals(expected.top, epsilon: 0.01));
  expect(actual.width, moreOrLessEquals(expected.width, epsilon: 0.01));
  expect(actual.height, moreOrLessEquals(expected.height, epsilon: 0.01));
}

class _TestChild extends ChildProvider {
  _TestChild(this._character)
      : super(authService: AuthService(supabaseAuth: _FakeSupabaseAuth()));

  final ChildCharacter _character;

  @override
  ChildProfile? get profile => _profile.copyWith(characterId: _character.id);

  @override
  Future<void> loadProfile() async {}
}

class _TestStars extends StarsProvider {
  _TestStars(this._owned);

  final Set<Costume> _owned;

  @override
  int get balance => 0;

  @override
  bool get atDailyCap => false;

  @override
  bool get isLoading => false;

  @override
  List<CostumeOffer> get offers => [
    for (final costume in Costume.inStock)
      CostumeOffer(
        costume: costume,
        owned: _owned.contains(costume),
        balance: 0,
      ),
  ];

  @override
  Future<void> refresh() async {}
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
