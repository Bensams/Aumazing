import 'package:aumazing/core/services/auth_service.dart';
import 'package:aumazing/features/home/home_screen.dart' show HomeScreen;
import 'package:aumazing/features/therapy/therapy_directory_screen.dart';
import 'package:aumazing/model/child_profile.dart';
import 'package:aumazing/model/gameplay_session.dart';
import 'package:aumazing/providers/assessment_provider.dart';
import 'package:aumazing/providers/child_provider.dart';
import 'package:aumazing/providers/progress_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Parent-facing CTAs must read in full in every layout the parent can put
/// the app in. These labels used to be ellipsised — "Start Pre-Assessm…",
/// "Upgr…", "Unlo…", "Unlock lo…" — by fixed button widths and a fixed
/// 540px dashboard breakpoint that ignored the tablet sidebar.

/// Representative surfaces. The tablet sizes matter most: the dashboard
/// draws an expanded sidebar there, leaving the action row far less width
/// than the raw screen suggests.
const _phonePortrait = Size(360, 800);
const _phoneLandscape = Size(800, 360);
const _tabletPortrait = Size(800, 1280);
const _tabletLandscape = Size(1280, 800);

final _profile = ChildProfile(
  id: 'child-1',
  userId: 'user-1',
  displayName: 'Test',
  birthDate: DateTime(2022, 4, 20),
  avatar: 'bear',
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
);

/// Fails if the text matched by [finder] had to drop any of itself to fit.
void _expectFullyLaidOut(WidgetTester tester, Finder finder, String what) {
  for (final element in finder.evaluate()) {
    final paragraph = element.renderObject! as RenderParagraph;
    expect(
      paragraph.didExceedMaxLines,
      isFalse,
      reason: '"$what" does not fit the space it was given',
    );
  }
}

/// Fails if any CTA on screen is ellipsised or clipped, or is shorter than
/// a usable touch target.
void _expectNoTruncatedCtas(WidgetTester tester) {
  for (final element in find.byType(AppPrimaryButton).evaluate()) {
    final button = element.widget as AppPrimaryButton;
    final scoped = find.descendant(
      of: find.byWidget(button),
      matching: find.byType(Text),
    );
    for (final textElement in scoped.evaluate()) {
      final text = textElement.widget as Text;
      expect(
        text.overflow,
        isNot(TextOverflow.ellipsis),
        reason: 'CTA "${button.label}" is ellipsised',
      );
    }
    _expectFullyLaidOut(
      tester,
      find.descendant(
        of: find.byWidget(button),
        matching: find.text(button.label),
      ),
      button.label,
    );
    expect(
      tester.getSize(find.byWidget(button)).height,
      greaterThanOrEqualTo(AppPrimaryButton.minTouchTarget),
      reason: 'CTA "${button.label}" is below the minimum touch target',
    );
  }
}

Future<void> _settleUi(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  group('parent dashboard', () {
    for (final entry
        in {
          'portrait phone': _phonePortrait,
          'landscape phone': _phoneLandscape,
          'portrait tablet': _tabletPortrait,
          // The sidebar is expanded by default here, so the action row gets
          // only part of the 1280px — the case that used to clip the label.
          'landscape tablet with the sidebar expanded': _tabletLandscape,
        }.entries) {
      for (final scale in [1.0, 1.3]) {
        testWidgets('shows every action label in full on a ${entry.key} '
            'at ${scale}x text scale', (tester) async {
          await tester.binding.setSurfaceSize(entry.value);
          addTearDown(() => tester.binding.setSurfaceSize(null));

          await tester.pumpWidget(_wrapDashboard(textScale: scale));
          await _settleUi(tester);

          expect(tester.takeException(), isNull);
          expect(find.text('Start Pre-Assessment'), findsOneWidget);
          expect(find.text('Enter Child Mode'), findsOneWidget);
          expect(find.text('Therapy Directory'), findsOneWidget);
          _expectNoTruncatedCtas(tester);
          // The two action cards carry their names as text, not as a CTA
          // button — they must read in full as well.
          _expectFullyLaidOut(
            tester,
            find.text('Enter Child Mode'),
            'Enter Child Mode',
          );
          _expectFullyLaidOut(
            tester,
            find.text('Therapy Directory'),
            'Therapy Directory',
          );

          // Let the delayed music check fire so no timer outlives the test.
          await tester.pump(const Duration(milliseconds: 700));
        });
      }
    }

    testWidgets('the premium CTA reads "Upgrade" in full', (tester) async {
      await tester.binding.setSurfaceSize(_tabletLandscape);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_wrapDashboard());
      await _settleUi(tester);

      expect(find.text('Upgrade'), findsOneWidget);
      _expectNoTruncatedCtas(tester);
      expect(tester.takeException(), isNull);

      await tester.pump(const Duration(milliseconds: 700));
    });
  });

  group('therapy directory', () {
    for (final entry
        in {
          'portrait phone': _phonePortrait,
          'landscape phone': _phoneLandscape,
          'portrait tablet': _tabletPortrait,
          'landscape tablet': _tabletLandscape,
        }.entries) {
      for (final scale in [1.0, 1.3]) {
        testWidgets('shows "Unlock locator" in full on a ${entry.key} '
            'at ${scale}x text scale', (tester) async {
          await tester.binding.setSurfaceSize(entry.value);
          addTearDown(() => tester.binding.setSurfaceSize(null));

          await tester.pumpWidget(
            _wrapScreen(const TherapyDirectoryScreen(), textScale: scale),
          );
          await _settleUi(tester);

          expect(tester.takeException(), isNull);
          expect(find.text('Therapy Directory'), findsOneWidget);
          // Free tier: the locator is gated behind this CTA.
          expect(find.text('Unlock locator'), findsOneWidget);
          _expectNoTruncatedCtas(tester);
        });
      }
    }
  });
}

Widget _wrapDashboard({double textScale = 1.0}) {
  return _wrapScreen(
    HomeScreen(
      authService: AuthService(supabaseAuth: _FakeSupabaseAuthClient()),
    ),
    textScale: textScale,
  );
}

Widget _wrapScreen(Widget screen, {double textScale = 1.0}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ChildProvider>(
        create: (_) => _TestChildProvider(),
      ),
      ChangeNotifierProvider<AssessmentProvider>(
        create: (_) => _TestAssessmentProvider(),
      ),
      ChangeNotifierProvider<ProgressProvider>(
        create: (_) => _TestProgressProvider(),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      builder:
          (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
      home: screen,
    ),
  );
}

class _TestChildProvider extends ChildProvider {
  _TestChildProvider()
    : super(authService: AuthService(supabaseAuth: _FakeSupabaseAuthClient()));

  @override
  ChildProfile? get profile => _profile;

  @override
  Future<void> loadProfile() async {}
}

class _TestAssessmentProvider extends AssessmentProvider {
  @override
  bool get hasPreAssessment => false;

  @override
  String? get recommendedModuleName => null;

  @override
  int get recommendedLevel => 1;

  @override
  Future<void> loadAssessments(String childId) async {}
}

class _TestProgressProvider extends ProgressProvider {
  @override
  int get completedModules => 0;

  @override
  int get totalSessions => 0;

  @override
  List<GameplaySession> get recentSessions => const [];

  @override
  Future<void> loadProgress(String childId) async {}
}

class _FakeSupabaseAuthClient implements SupabaseAuthClient {
  @override
  User? get currentUser => null;

  @override
  Session? get currentSession => null;

  @override
  Stream<AuthState> get onAuthStateChange => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
