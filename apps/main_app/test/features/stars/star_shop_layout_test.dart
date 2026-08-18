import 'package:aumazing/core/services/auth_service.dart';
import 'package:aumazing/features/stars/star_catalogue.dart';
import 'package:aumazing/features/stars/star_shop_screen.dart';
import 'package:aumazing/features/stars/widgets/costume_card.dart';
import 'package:aumazing/model/child_profile.dart';
import 'package:aumazing/providers/child_provider.dart';
import 'package:aumazing/providers/stars_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The shop runs on whatever the family owns, which in practice means a phone
/// held either way up and sometimes a tablet. This file is the answer to the
/// gap that let a 197-pixel overflow ship: every size below is pumped, and a
/// RenderFlex overflow surfaces here as a test exception.
///
/// The sizes are the three shapes that behave differently, not an arbitrary
/// sample: a portrait phone is narrow, a landscape phone is *short* — which is
/// what the preview sheet used to fail on — and a tablet is large enough that
/// a layout tuned for a phone leaves the artwork stranded.
const _phonePortrait = Size(390, 844);
const _phoneLandscape = Size(844, 390);
const _tablet = Size(1024, 1366);

const _sizes = {
  'phone portrait': _phonePortrait,
  'phone landscape': _phoneLandscape,
  'tablet': _tablet,
};

final _profile = ChildProfile(
  id: 'child-1',
  userId: 'user-1',
  displayName: 'Test',
  birthDate: DateTime(2022, 4, 20),
  avatar: 'bear',
  characterId: 'bps',
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
);

void main() {
  for (final entry in _sizes.entries) {
    final label = entry.key;
    final size = entry.value;

    testWidgets('the shop grid fits a $label', (tester) async {
      await _pumpShop(tester, size);

      // "No costume" plus everything in stock, and nothing that is not.
      expect(
        find.byType(CostumeCard),
        findsNWidgets(Costume.inStock.length + 1),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the star balance sits in the top-right on a $label', (
      tester,
    ) async {
      await _pumpShop(tester, size, balance: 7);

      final balance = find.text('7');
      expect(balance, findsOneWidget);

      final rect = tester.getRect(balance);
      final title = tester.getRect(find.text('My Costumes'));

      // Right of the title, and level with it rather than in a band below —
      // the two together are what "in the header, top-right" means.
      expect(rect.left, greaterThan(title.right));
      expect(rect.right, lessThanOrEqualTo(size.width));
      expect(rect.top, lessThan(title.bottom + 24));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the costume preview sheet fits a $label', (tester) async {
      await _pumpShop(tester, size);

      // Teddy is the cheapest in-stock costume, so it is the first card after
      // "No costume" — and it is the one the reported overflow came from.
      await tester.tap(find.byType(CostumeCard).at(1));
      await tester.pumpAndSettle();

      expect(find.text(Costume.teddy.displayName), findsWidgets);
      // Both actions must be reachable without scrolling, on every size: a
      // child who opens the sheet has to be able to get back out of it.
      expect(find.text('Not yet'), findsOneWidget);
      final notYet = tester.getRect(find.text('Not yet'));
      expect(notYet.bottom, lessThanOrEqualTo(size.height));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a landscape phone puts the costume beside its actions', (
    tester,
  ) async {
    // Not just "it fits": on a short screen the sheet has to *change shape*.
    // Stacking is what ran out of vertical room in the first place, so this
    // pins the arrangement rather than only the absence of an overflow.
    await _pumpShop(tester, _phoneLandscape);
    await tester.tap(find.byType(CostumeCard).at(1));
    await tester.pumpAndSettle();

    final art = tester.getRect(
      find
          .byWidgetPredicate(
            (w) =>
                w is Image &&
                w.image is AssetImage &&
                (w.image as AssetImage).assetName ==
                    Costume.teddy.assetFor(ChildCharacter.bps),
          )
          .last,
    );
    final notYet = tester.getRect(find.text('Not yet'));

    expect(art.right, lessThanOrEqualTo(notYet.left));
    expect(notYet.bottom, lessThanOrEqualTo(_phoneLandscape.height));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the shop declares itself a child-facing landscape screen', (
    tester,
  ) async {
    // It used to inherit the previous route's orientation, which happened to
    // be landscape only because the child lobby is the sole way in. Declaring
    // it removes the dependency on where the child came from.
    final requested = <List<String>>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'SystemChrome.setPreferredOrientations') {
          requested.add((call.arguments as List).cast<String>());
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await _pumpShop(tester, _phonePortrait);

    expect(requested, isNotEmpty, reason: 'the shop set no orientation');
    expect(requested.last, [
      'DeviceOrientation.landscapeLeft',
      'DeviceOrientation.landscapeRight',
    ]);
    // And it must never be the thing that puts a parent phone in landscape:
    // the parent policy on a phone stays portrait, untouched by this screen.
    expect(parentOrientationsFor(390), [DeviceOrientation.portraitUp]);
    expect(parentOrientationsFor(599.9), [DeviceOrientation.portraitUp]);
  });

  testWidgets('an unaffordable costume is offered, not hidden', (tester) async {
    await _pumpShop(tester, _phonePortrait, balance: 0);

    // Every in-stock costume renders at a zero balance. "Not yet" is a
    // progress bar in this app, never a padlock and never an absence.
    expect(
      find.byType(CostumeCard),
      findsNWidgets(Costume.inStock.length + 1),
    );
    expect(find.byType(LinearProgressIndicator), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpShop(
  WidgetTester tester,
  Size size, {
  int balance = 0,
}) async {
  // The view, not `setSurfaceSize`: that resizes the render surface but
  // leaves MediaQuery reporting the default 800x600, so a screen that sizes
  // itself from MediaQuery — as the preview sheet does — would be measured
  // against a phone it is not being drawn on.
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ChildProvider>(create: (_) => _TestChild()),
        ChangeNotifierProvider<StarsProvider>(
          create: (_) => _TestStars(balance),
        ),
      ],
      child: MaterialApp(theme: AppTheme.light, home: const StarShopScreen()),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

class _TestChild extends ChildProvider {
  _TestChild()
      : super(authService: AuthService(supabaseAuth: _FakeSupabaseAuth()));

  @override
  ChildProfile? get profile => _profile;

  @override
  Future<void> loadProfile() async {}
}

/// Offers built from the catalogue rather than hand-listed, so a costume
/// gaining its sprite sheets is covered here the day it lands.
class _TestStars extends StarsProvider {
  _TestStars(this._balance);

  final int _balance;

  @override
  int get balance => _balance;

  @override
  bool get atDailyCap => false;

  @override
  bool get isLoading => false;

  @override
  List<CostumeOffer> get offers => [
        for (final costume in Costume.inStock)
          CostumeOffer(costume: costume, owned: false, balance: _balance),
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
