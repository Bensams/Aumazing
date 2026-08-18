import 'package:aumazing/core/services/auth_service.dart';
import 'package:aumazing/model/support_profile.dart';
import 'package:aumazing/providers/child_provider.dart';
import 'package:aumazing/services/recommended_settings_applier.dart';
import 'package:aumazing/services/screen_time_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The parent presses "Use these settings" on an assessment summary and the
/// child's settings actually change. These tests pin *which* settings — the
/// half-applied version, where a card says "Settings updated" and only some
/// of it happened, is the failure that matters.

SupportProfile _profile({
  String difficulty = 'intermediate',
  int sessionMinutes = 5,
  bool lowStimulation = false,
}) =>
    SupportProfile(
      communication: 'emerging',
      socialInteraction: 'emerging',
      playSkills: 'emerging',
      attention: 'short attention',
      recommendedDifficulty: difficulty,
      recommendedSessionMinutes: sessionMinutes,
      lowStimulationMode: lowStimulation,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('what the button writes', () {
    test('difficulty, session length and low-stimulation mode', () async {
      final childProv = _RecordingChildProvider('child-1');
      final screenTime = ScreenTimeService.instance;
      await screenTime.load('child-1');

      final ok = await RecommendedSettingsApplier.apply(
        profile: _profile(
          difficulty: 'advanced',
          sessionMinutes: 12,
          lowStimulation: true,
        ),
        childProv: childProv,
        childId: 'child-1',
        screenTime: screenTime,
      );

      expect(ok, isTrue);
      expect(childProv.difficulty, 3);
      expect(screenTime.sessionLimitMinutes, 12);
      expect(
        childProv.animationIntensityWritten,
        RecommendedSettingsApplier.lowStimulationAnimationIntensity,
      );
    });

    test('a run that did not recommend low stimulation leaves it alone',
        () async {
      final childProv = _RecordingChildProvider('child-1');
      final screenTime = ScreenTimeService.instance;
      await screenTime.load('child-1');

      await RecommendedSettingsApplier.apply(
        profile: _profile(lowStimulation: false),
        childProv: childProv,
        childId: 'child-1',
        screenTime: screenTime,
      );

      // Never turned back up either: a parent's own sensory settings are not
      // this button's to undo.
      expect(childProv.animationIntensityWritten, isNull);
    });

    test('the three difficulty words map to the three override levels', () {
      expect(RecommendedSettingsApplier.difficultyLevels['beginner'], 1);
      expect(RecommendedSettingsApplier.difficultyLevels['intermediate'], 2);
      expect(RecommendedSettingsApplier.difficultyLevels['advanced'], 3);
    });
  });

  group('what it refuses to do', () {
    test('writes nothing when the child is not the active one', () async {
      final childProv = _RecordingChildProvider('child-1');
      final screenTime = ScreenTimeService.instance;
      await screenTime.load('child-2');

      final ok = await RecommendedSettingsApplier.apply(
        profile: _profile(lowStimulation: true),
        childProv: childProv,
        childId: 'child-2',
        screenTime: screenTime,
      );

      // The provider persists against its own active child, so applying
      // here would have written child-1's settings from child-2's summary.
      expect(ok, isFalse);
      expect(childProv.difficulty, isNull);
      expect(childProv.animationIntensityWritten, isNull);
      expect(screenTime.sessionLimitMinutes, isNull);
    });

    test('leaves the session limit alone while a session is running',
        () async {
      final childProv = _RecordingChildProvider('child-1');
      final screenTime = ScreenTimeService.instance;
      await screenTime.load('child-2');
      await screenTime.startSession();

      final ok = await RecommendedSettingsApplier.apply(
        profile: _profile(sessionMinutes: 12),
        childProv: childProv,
        childId: 'child-1',
        screenTime: screenTime,
      );

      // Taking the service over mid-session would end child-2's play. The
      // difficulty still applies — a partial write is reported as success
      // because something really did change.
      expect(ok, isTrue);
      expect(childProv.difficulty, 2);
      expect(screenTime.loadedChildId, 'child-2');
      expect(screenTime.sessionLimitMinutes, isNull);

      await screenTime.endSession();
    });
  });

  group('the card and the applier agree', () {
    test('every label is either appliable or explicitly recorded-only', () {
      const shown = {
        AssessmentLabels.difficulty,
        AssessmentLabels.promptStyle,
        AssessmentLabels.sessionLength,
        AssessmentLabels.promptRepetition,
        AssessmentLabels.lowStimulationMode,
        AssessmentLabels.turnTakingPractice,
      };
      // A label in neither set is a recommendation the card would show with
      // no decision made about whether the button covers it.
      expect(
        shown.difference(RecommendedSettingsApplier.appliableLabels
            .union(RecommendedSettingsApplier.recordedOnlyLabels)),
        isEmpty,
      );
      expect(
        RecommendedSettingsApplier.appliableLabels
            .intersection(RecommendedSettingsApplier.recordedOnlyLabels),
        isEmpty,
      );
    });
  });
}

/// Records what the applier asked for.
///
/// [ChildProvider]'s writers persist against a profile loaded from Supabase,
/// which a unit test has no way to produce — so the calls are captured here
/// and the assertions are about which settings the applier decided to change.
class _RecordingChildProvider extends ChildProvider {
  _RecordingChildProvider(this._activeChildId)
      : super(authService: AuthService(supabaseAuth: _FakeSupabaseAuth()));

  final String _activeChildId;

  int? difficulty;
  double? animationIntensityWritten;

  @override
  String? get activeChildId => _activeChildId;

  @override
  Future<void> setDifficultyOverride(int level) async {
    difficulty = level;
  }

  @override
  Future<void> updateComfortSettings({
    bool? musicEnabled,
    double? musicVolume,
    String? musicCategory,
    double? sfxVolume,
    bool? vibrationEnabled,
    double? animationIntensity,
    double? promptSpeed,
    bool? sensoryPreferencesSet,
  }) async {
    animationIntensityWritten = animationIntensity;
  }
}

class _FakeSupabaseAuth implements SupabaseAuthClient {
  @override
  User? get currentUser => null;

  @override
  Session? get currentSession => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
