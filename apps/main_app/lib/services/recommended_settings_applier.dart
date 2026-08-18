import 'package:flutter/foundation.dart';
import 'package:shared_ui/shared_ui.dart';

import '../model/support_profile.dart';
import '../providers/child_provider.dart';
import 'screen_time_service.dart';

/// Writes an assessment's Recommended Settings into the child's actual
/// settings.
///
/// Three of the six recommendations have a setting behind them today, and
/// this applies exactly those three. The rest are listed by
/// [recordedOnlyLabels] and are deliberately *not* faked: prompt style and
/// prompt repetition have no runtime control at all, and extra turn-taking
/// practice is already expressed by the recommended activities rather than by
/// a switch. Writing something approximate for them would tell a parent their
/// child's prompts changed when nothing about the prompts changed.
///
/// [SupportProfile] is the finalized profile of the run being viewed, so
/// applying an older summary applies what *that* run recommended — the same
/// rule the card itself follows.
abstract final class RecommendedSettingsApplier {
  /// Difficulty override levels, matching `ChildProvider.setDifficultyOverride`
  /// (1 Easy / 2 Medium / 3 Hard).
  static const difficultyLevels = <String, int>{
    'beginner': 1,
    'intermediate': 2,
    'advanced': 3,
  };

  /// Animation intensity used for low-stimulation mode.
  ///
  /// Reduced rather than zero: motion is how this app shows a child that
  /// something responded to them, and removing it entirely makes the games
  /// read as broken. The sensory sliders remain the finer control.
  static const lowStimulationAnimationIntensity = 0.3;

  /// The recommendation labels this can write.
  static const appliableLabels = <String>{
    AssessmentLabels.difficulty,
    AssessmentLabels.sessionLength,
    AssessmentLabels.lowStimulationMode,
  };

  /// The labels recorded with the assessment that have no setting behind them.
  static const recordedOnlyLabels = <String>{
    AssessmentLabels.promptStyle,
    AssessmentLabels.promptRepetition,
    AssessmentLabels.turnTakingPractice,
  };

  static bool isAppliable(String label) => appliableLabels.contains(label);

  /// Applies [profile] to [childId]'s settings. Returns false when nothing
  /// could be written, so the caller can say so rather than claim success.
  ///
  /// Low-stimulation mode is only ever turned *on*, never off: a run that did
  /// not recommend it is not a run that recommended undoing a parent's own
  /// sensory settings.
  static Future<bool> apply({
    required SupportProfile profile,
    required ChildProvider childProv,
    required String childId,
    ScreenTimeService? screenTime,
  }) async {
    // The provider persists against its active child, so applying to any
    // other child would silently write the wrong row.
    if (childProv.activeChildId != childId) {
      debugPrint('[RecommendedSettings] $childId is not the active child');
      return false;
    }

    var wrote = false;

    final level = difficultyLevels[profile.recommendedDifficulty.toLowerCase()];
    if (level != null) {
      await childProv.setDifficultyOverride(level);
      wrote = true;
    }

    if (await _applySessionLength(
      minutes: profile.recommendedSessionMinutes,
      childId: childId,
      screenTime: screenTime ?? ScreenTimeService.instance,
    )) {
      wrote = true;
    }

    if (profile.lowStimulationMode) {
      await childProv.updateComfortSettings(
        animationIntensity: lowStimulationAnimationIntensity,
      );
      wrote = true;
    }

    return wrote;
  }

  /// Sets the per-session play limit.
  ///
  /// The service holds one child at a time. It is loaded for [childId] when
  /// it is not already — except while a session is running for someone else,
  /// where taking it over would end that child's play mid-game.
  static Future<bool> _applySessionLength({
    required int minutes,
    required String childId,
    required ScreenTimeService screenTime,
  }) async {
    if (minutes <= 0) return false;
    if (screenTime.loadedChildId != childId) {
      if (screenTime.sessionActive) {
        debugPrint('[RecommendedSettings] session running; skipped limit');
        return false;
      }
      await screenTime.load(childId);
    }
    await screenTime.setSessionLimitMinutes(minutes);
    return true;
  }
}
