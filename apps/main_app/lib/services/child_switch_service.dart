import 'package:flutter/foundation.dart';
import 'package:shared_audio/shared_audio.dart';

import '../providers/assessment_provider.dart';
import '../providers/child_provider.dart';
import '../providers/progress_provider.dart';
import 'screen_time_service.dart';

/// Makes another child the active one and rebuilds every piece of
/// child-specific state around it.
///
/// [ChildProvider] owns the selection itself; this is the one place that
/// fans the change out to the providers and services that cache per-child
/// data, so no screen has to remember the full list:
///
/// * assessment results, recommendations and learning-path progress
/// * gameplay records and module progress
/// * screen-time limit and today's usage
/// * audio configuration (the new child's music / effect levels)
///
/// Each of those is cleared before it is reloaded, so the previous child's
/// data can never show up under the newly selected one — not even for the
/// frame between the switch and the reload finishing.
///
/// Returns false when [childId] does not belong to the current parent.
Future<bool> switchActiveChild({
  required String childId,
  required ChildProvider childProvider,
  AssessmentProvider? assessmentProvider,
  ProgressProvider? progressProvider,
  ScreenTimeService? screenTimeService,
  AudioService? audioService,
}) async {
  // Clear first: an await between the switch and the reload would otherwise
  // leave the outgoing child's results on screen under the new child's name.
  assessmentProvider?.clear();
  progressProvider?.clear();

  final selected = await childProvider.selectChild(childId);
  if (!selected) {
    debugPrint('[switchActiveChild] Unknown child: $childId');
    return false;
  }

  await reloadChildScopedState(
    childId: childId,
    childProvider: childProvider,
    assessmentProvider: assessmentProvider,
    progressProvider: progressProvider,
    screenTimeService: screenTimeService,
    audioService: audioService,
  );
  return true;
}

/// Reloads the child-scoped providers and services for [childId].
///
/// Split out from [switchActiveChild] so callers that already changed the
/// active child (deleting the active profile, for instance) can refresh
/// everything the same way.
Future<void> reloadChildScopedState({
  required String childId,
  required ChildProvider childProvider,
  AssessmentProvider? assessmentProvider,
  ProgressProvider? progressProvider,
  ScreenTimeService? screenTimeService,
  AudioService? audioService,
}) async {
  await (screenTimeService ?? ScreenTimeService.instance).load(childId);

  audioService?.updateConfig(
    AudioConfig(
      musicEnabled: childProvider.musicEnabled,
      musicVolume: childProvider.musicVolume,
      sfxEnabled: true,
      sfxVolume: childProvider.sfxVolume,
    ),
  );

  await assessmentProvider?.loadAssessments(childId);
  await progressProvider?.loadProgress(childId);
}
