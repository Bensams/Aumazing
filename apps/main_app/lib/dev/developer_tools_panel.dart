import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../features/child_mode/game_launcher.dart';
import '../features/post_assessment/post_assessment_handoff_screen.dart';
import '../features/post_assessment/post_assessment_progress_screen.dart';
import '../features/pre_assessment/pre_assessment_result_screen.dart';
import '../features/pre_assessment/pre_assessment_progress_screen.dart';
import '../features/pre_assessment/sensory/sensory.dart';
import '../features/pre_assessment/waiting_for_parent_screen.dart';
import '../providers/assessment_provider.dart';
import '../model/assessment_result.dart';
import '../model/support_profile.dart';
import '../providers/child_provider.dart';
import '../services/active_games_service.dart';
import '../services/entitlement_service.dart';
import '../services/learning_path_service.dart';
import '../widgets/assessment_handoff.dart';
import 'build_info.dart';
import 'developer_automation_registry.dart';
import 'developer_autoplay_controller.dart';
import 'developer_tools_config.dart';
import 'developer_tools_service.dart';

/// The "Developer Tools" sheet: current state, plus the four shortcuts.
///
/// Every action is confirmed, runs with the whole sheet disabled, and reports
/// its own outcome. Nothing here reports success before the underlying write
/// and finalization have actually succeeded.
class DeveloperToolsPanel extends StatefulWidget {
  const DeveloperToolsPanel({
    super.key,
    this.service = const DeveloperToolsService(),
    this.handoffVoiceOverFactory,
  });

  final DeveloperToolsService service;

  /// Test seam for keeping shortcut navigation tests off platform audio.
  @visibleForTesting
  final HandoffVoiceOverFactory? handoffVoiceOverFactory;

  /// Whether a toolbox sheet is on screen right now.
  static bool _isOpen = false;

  /// True while the toolbox is open. There is only ever one.
  static bool get isOpen => _isOpen;

  /// Opens the panel on the root navigator, so it works from nested routes
  /// (games, assessment progress screens, dialogs) alike.
  ///
  /// Exactly one instance: tapping the floating button again while the sheet
  /// is up does nothing rather than stacking a second identical sheet over
  /// the first. Guarded here rather than at the button, so every entry point
  /// gets the same behaviour.
  static Future<void> show(BuildContext context) async {
    if (_isOpen) return;
    _isOpen = true;
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useRootNavigator: true,
        builder: (_) => const DeveloperToolsPanel(),
      );
    } finally {
      _isOpen = false;
    }
  }

  /// Test seam: clears the open flag if a test tore the sheet down without
  /// letting its route future complete.
  @visibleForTesting
  static void resetOpenStateForTest() => _isOpen = false;

  @override
  State<DeveloperToolsPanel> createState() => _DeveloperToolsPanelState();
}

class _DeveloperToolsPanelState extends State<DeveloperToolsPanel> {
  /// Set while any action runs — blocks every other action and duplicate taps.
  bool _busy = false;

  /// What the running action is doing, shown next to the busy indicator.
  String? _busyLabel;

  /// The last outcome, shown in the sheet itself (the snackbar can be missed
  /// when the sheet closes and a new route is installed).
  String? _status;
  bool _statusIsError = false;

  Set<String>? get _activeGameIds =>
      ActiveGamesService.instance.cachedActiveGameIds;

  @override
  Widget build(BuildContext context) {
    // Rebuilds with the providers and the entitlement, so the state readout
    // never drifts from what the app actually believes.
    final assessment = context.watch<AssessmentProvider>();
    final child = context.watch<ChildProvider>();

    return ListenableBuilder(
      listenable: Listenable.merge([
        EntitlementService.instance,
        DeveloperAutoPlayController.instance,
      ]),
      builder: (context, _) => _buildSheet(context, assessment, child),
    );
  }

  Widget _buildSheet(
    BuildContext context,
    AssessmentProvider assessment,
    ChildProvider child,
  ) {
    final entitlement = EntitlementService.instance;
    final profile = child.profile;
    final childId = profile?.id;
    final hasChild = childId != null && childId.isNotEmpty && childId != 'unknown';

    final path = DeveloperToolsService.learningPath(assessment,
        activeGameIds: _activeGameIds);
    final completed = assessment.pathCompletedGameIds;
    final completedOnPath =
        path.where((e) => completed.contains(e.game.id)).length;
    final nextModule = DeveloperToolsService.nextIncompleteModule(assessment,
        activeGameIds: _activeGameIds);
    final hasPre = DeveloperToolsService.hasPreAssessmentBaseline(assessment);
    final hasPost = assessment.hasPostAssessment;

    final premiumState = entitlement.isDeveloperPremiumOverrideActive
        ? 'Developer override (real: ${entitlement.isRealPremium ? 'yes' : 'no'})'
        : entitlement.isRealPremium
            ? 'Real Premium'
            : 'Inactive';

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.developer_mode_rounded),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Developer Tools',
                      style: TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: _busy ? null : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const Divider(),
              // Build provenance first: a tester checks this to confirm they
              // are running the updated code rather than a stale build.
              _stateRow('Build', BuildInfo.summary),
              _stateRow('Child',
                  hasChild ? '${profile!.displayName} ($childId)' : 'None selected'),
              _stateRow('Premium', premiumState),
              _stateRow('Pre-assessment', hasPre ? 'Exists' : 'None'),
              _stateRow('Path progress',
                  path.isEmpty ? 'No path yet' : '$completedOnPath of ${path.length}'),
              // "All completed" and "there is no path" are different states;
              // reporting the first for the second reads as a finished path
              // before the child has even been assessed.
              _stateRow(
                  'Next module',
                  path.isEmpty
                      ? 'No path yet'
                      : nextModule?.game.name ??
                          'All recommended modules completed'),
              _stateRow('Post-assessment', hasPost ? 'Exists' : 'None'),
              const Divider(),
              if (_busy)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Text(_busyLabel ?? 'Working…')),
                    ],
                  ),
                ),
              if (_status != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    _status!,
                    key: const Key('developerToolsStatus'),
                    style: TextStyle(
                      color: _statusIsError
                          ? Theme.of(context).colorScheme.error
                          : Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              SwitchListTile(
                key: const Key('developerToolsPremiumToggle'),
                title: const Text('Premium Access'),
                subtitle: Text(entitlement.isDeveloperPremiumOverrideActive
                    ? 'In-memory override — no entitlement data is written'
                    : 'Temporarily unlock Premium gates for this run'),
                value: entitlement.isDeveloperPremiumOverrideActive,
                onChanged: _busy ? null : _togglePremium,
              ),
              _actionTile(
                key: const Key('developerToolsCompletePre'),
                icon: Icons.assignment_turned_in_rounded,
                title: hasPre
                    ? 'Complete Pre-Assessment (retake)'
                    : 'Complete Pre-Assessment',
                subtitle: hasChild
                    ? 'Simulates all four games, then shows the normal hand-off'
                    : 'Needs an active child profile',
                enabled: hasChild,
                onTap: () => _completePreAssessment(childId!, retake: hasPre),
              ),
              _actionTile(
                key: const Key('developerToolsPreviewCritical'),
                icon: Icons.health_and_safety_outlined,
                title: 'Preview Critical Pre-Assessment Result',
                subtitle: hasChild
                    ? 'Shows the non-clinical Therapy Center support prompt'
                    : 'Needs an active child profile',
                enabled: hasChild,
                onTap: () => _previewCriticalPreAssessment(childId!),
              ),
              _actionTile(
                key: const Key('developerToolsCompleteModule'),
                icon: Icons.playlist_add_check_rounded,
                title: 'Complete Next Module',
                subtitle: !hasChild
                    ? 'Needs an active child profile'
                    : path.isEmpty
                        ? 'Needs a completed pre-assessment and learning path'
                        : nextModule == null
                            ? 'All recommended modules completed'
                            : 'Completes ${nextModule.game.name}',
                enabled: hasChild && nextModule != null,
                onTap: () => _completeNextModule(childId!),
              ),
              _actionTile(
                key: const Key('developerToolsCompletePost'),
                icon: Icons.compare_arrows_rounded,
                title: hasPost
                    ? 'Complete Post-Assessment (retake)'
                    : 'Complete Post-Assessment',
                subtitle: !hasChild
                    ? 'Needs an active child profile'
                    : !hasPre
                        ? 'Needs a completed pre-assessment baseline'
                        : 'Simulates all four games, then shows the normal '
                            'hand-off',
                enabled: hasChild && hasPre,
                onTap: () => _completePostAssessment(childId!, retake: hasPost),
              ),
              const Divider(),
              _autoPlaySection(context, hasChild: hasChild, hasPre: hasPre),
            ],
          ),
        ),
      ),
    );
  }

  /// Auto-play differs from the instant shortcuts above: it walks the real
  /// game screens, so the whole UI flow can be watched rather than inferred
  /// from the final state.
  Widget _autoPlaySection(
    BuildContext context, {
    required bool hasChild,
    required bool hasPre,
  }) {
    final controller = DeveloperAutoPlayController.instance;
    final running = controller.isActive;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 4),
          child: Text('Auto-play (plays the real games)',
              style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        // The label sits above rather than beside the control: on a phone in
        // portrait a leading column squeezed "Normal" into "Norm/al".
        const Padding(
          padding: EdgeInsets.only(top: 4, bottom: 6),
          child: Text('Speed'),
        ),
        SegmentedButton<AutoPlaySpeed>(
          key: const Key('developerAutoPlaySpeed'),
          showSelectedIcon: false,
          style: SegmentedButton.styleFrom(
            textStyle: const TextStyle(fontSize: 13),
            padding: const EdgeInsets.symmetric(horizontal: 8),
          ),
          segments: [
            for (final speed in AutoPlaySpeed.values)
              ButtonSegment(
                value: speed,
                label: Text(speed.label, maxLines: 1),
              ),
          ],
          selected: {controller.speed},
          onSelectionChanged: (selection) =>
              controller.setSpeed(selection.first),
        ),
        if (controller.message != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              controller.message!,
              key: const Key('developerAutoPlayMessage'),
              style: TextStyle(
                color: controller.status == AutoPlayStatus.failed
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        _actionTile(
          key: const Key('developerAutoPlayPre'),
          icon: Icons.smart_display_rounded,
          title: 'Auto-play Pre-Assessment',
          subtitle: !hasChild
              ? 'Needs an active child profile'
              : running
                  ? 'Auto-play is already running'
                  : 'Starts the real flow and plays all four games',
          enabled: hasChild && !running,
          onTap: () => _startAutoPlay(
            AutoPlayMode.preAssessment,
            () => _openPreAssessment(context),
          ),
        ),
        _actionTile(
          key: const Key('developerAutoPlayPost'),
          icon: Icons.smart_display_outlined,
          title: 'Auto-play Post-Assessment',
          subtitle: !hasChild
              ? 'Needs an active child profile'
              : !hasPre
                  ? 'Needs a completed pre-assessment baseline'
                  : running
                      ? 'Auto-play is already running'
                      : 'Starts the real flow and plays all four games',
          enabled: hasChild && hasPre && !running,
          onTap: () => _startAutoPlay(
            AutoPlayMode.postAssessment,
            () => _openPostAssessment(context),
          ),
        ),
        _autoPlayNextModuleTile(context, hasChild: hasChild, running: running),
        _actionTile(
          key: const Key('developerAutoPlayStop'),
          icon: Icons.stop_circle_outlined,
          title: 'Stop Auto-play',
          subtitle: running
              ? 'Stops after the current action; leaves the app where it is'
              : 'Nothing is running',
          enabled: running,
          onTap: () {
            DeveloperAutoPlayController.instance.stop();
            _snack('Auto-play stopping.');
          },
        ),
      ],
    );
  }

  Widget _stateRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 130,
              child: Text('$label:',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            Expanded(child: Text(value)),
          ],
        ),
      );

  Widget _actionTile({
    required Key key,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    final usable = enabled && !_busy;
    return ListTile(
      key: key,
      enabled: usable,
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      onTap: usable ? onTap : null,
    );
  }

  // ── Actions ──────────────────────────────────────────────────────────

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _togglePremium(bool value) async {
    if (!DeveloperToolsConfig.isAvailable) return;
    final confirmed = await _confirm(
      title: value ? 'Enable Premium override?' : 'Disable Premium override?',
      message: value
          ? 'Premium gates will behave as if this account were subscribed. '
              'This is in-memory only: nothing is written to the entitlements '
              'table, no checkout runs, and a restart clears it.'
          : 'Premium gates go back to the genuine entitlement for this '
              'account.',
      confirmLabel: value ? 'Enable' : 'Disable',
    );
    if (!confirmed || !mounted) return;

    EntitlementService.instance.setDeveloperPremiumOverride(value);
    final active = EntitlementService.instance.isDeveloperPremiumOverrideActive;
    setState(() {
      _statusIsError = value && !active;
      _status = _statusIsError
          ? 'The Premium override is not available in this build.'
          : active
              ? 'Premium override enabled (in-memory only).'
              : 'Premium override disabled — genuine entitlement restored.';
    });
  }

  /// Runs [action] with the sheet locked, and reports the outcome.
  ///
  /// Returns the action's value, or null when it failed — the caller must not
  /// navigate to a success state in that case.
  Future<T?> _run<T>({
    required String busyLabel,
    required Future<T> Function() action,
  }) async {
    if (_busy) return null;
    setState(() {
      _busy = true;
      _busyLabel = busyLabel;
      _status = null;
      _statusIsError = false;
    });
    try {
      return await action();
    } on DeveloperToolsException catch (e) {
      if (mounted) {
        setState(() {
          _status = e.message;
          _statusIsError = true;
        });
      }
      return null;
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = 'Failed: $e';
          _statusIsError = true;
        });
      }
      return null;
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyLabel = null;
        });
      }
    }
  }

  Future<void> _completePreAssessment(String childId,
      {required bool retake}) async {
    final confirmed = await _confirm(
      title: retake ? 'Developer retake?' : 'Complete pre-assessment?',
      message: '${retake ? 'This replaces the existing pre-assessment and '
          'invalidates the post-assessment comparison. ' : ''}'
          'Four simulated gameplay sessions and a full assessment run will be '
          'created as local test records for this child, and they may sync to '
          'the backend for the signed-in account.',
      confirmLabel: retake ? 'Retake' : 'Complete',
    );
    if (!confirmed || !mounted) return;

    final assessment = context.read<AssessmentProvider>();
    final result = await _run(
      busyLabel: 'Simulating the four pre-assessment games…',
      action: () => widget.service
          .completePreAssessment(provider: assessment, childId: childId),
    );
    if (result == null || !mounted) return;

    _closeAndInstall(
      message: 'Pre-assessment simulated — handing off to the parent.',
      screen: WaitingForParentScreen(
        results: result.results,
        profile: result.profile,
        aiResponse: result.aiResponse,
        voiceOverFactory: widget.handoffVoiceOverFactory,
      ),
    );
  }

  Future<void> _previewCriticalPreAssessment(String childId) async {
    if (!DeveloperToolsConfig.isAvailable) return;

    final confirmed = await _confirm(
      title: 'Preview critical pre-assessment result?',
      message: 'This opens an in-memory poor-result preview for the active '
          'child. No assessment, session, or child data will be written.',
      confirmLabel: 'Preview',
    );
    if (!confirmed || !mounted) return;

    final result = AssessmentResult(
      id: 'developer-critical-preview',
      childId: childId,
      type: 'pre',
      gameId: 'match_it',
      score: 1,
      totalItems: 10,
      errorCount: 9,
      avgResponseTimeMs: 5000,
      completedAt: DateTime.utc(2026, 1, 1),
    );
    const profile = SupportProfile(
      communication: 'emerging',
      socialInteraction: 'emerging',
      playSkills: 'emerging',
      attention: 'short attention',
    );

    _closeAndInstall(
      message: 'Critical pre-assessment preview opened.',
      screen: PreAssessmentResultScreen(
        results: [result],
        profile: profile,
      ),
    );
  }

  Future<void> _completePostAssessment(String childId,
      {required bool retake}) async {
    final confirmed = await _confirm(
      title: retake ? 'Developer retake?' : 'Complete post-assessment?',
      message: '${retake ? 'This replaces the existing post-assessment '
          'results. ' : ''}'
          'Four simulated gameplay sessions and a full post-assessment run '
          'will be created as local test records for this child, and they may '
          'sync to the backend for the signed-in account. The pre-assessment '
          'baseline is left untouched.',
      confirmLabel: retake ? 'Retake' : 'Complete',
    );
    if (!confirmed || !mounted) return;

    final assessment = context.read<AssessmentProvider>();
    final result = await _run(
      busyLabel: 'Simulating the four post-assessment games…',
      action: () => widget.service
          .completePostAssessment(provider: assessment, childId: childId),
    );
    if (result == null || !mounted) return;

    _closeAndInstall(
      message: 'Post-assessment simulated — handing off to the parent.',
      screen: PostAssessmentHandoffScreen(
        improvement: result.improvement,
        nextModulePremiumRequired: result.nextModulePremiumRequired,
        voiceOverFactory: widget.handoffVoiceOverFactory,
      ),
    );
  }

  Future<void> _completeNextModule(String childId) async {
    final assessment = context.read<AssessmentProvider>();
    final next = DeveloperToolsService.nextIncompleteModule(assessment,
        activeGameIds: _activeGameIds);
    if (next == null) return;

    final confirmed = await _confirm(
      title: 'Complete ${next.game.name}?',
      message: 'A simulated practice session will be recorded as a local test '
          'record for this child (it may sync for the signed-in account), and '
          'the learning path will advance one step. No reward animation is '
          'shown.',
      confirmLabel: 'Complete',
    );
    if (!confirmed || !mounted) return;

    final result = await _run(
      busyLabel: 'Completing ${next.game.name}…',
      action: () => widget.service.completeNextModule(
        provider: assessment,
        childId: childId,
        activeGameIds: _activeGameIds,
      ),
    );
    if (result == null || !mounted) return;

    // The path/dashboard listen to the provider, which recordGameSession and
    // markPathGameCompleted already notified — the readout above rebuilds
    // with them.
    setState(() {
      _statusIsError = false;
      _status = 'Completed ${result.gameName} '
          '(${result.remaining} module(s) remaining).';
    });
    _snack('Completed ${result.gameName}.');
  }

  /// "Auto-play Next Module Only" — opens the next incomplete path module's
  /// real practice screen and plays it.
  ///
  /// Disabled, with the reason spelled out, when that module's game has no
  /// automation hook yet: starting a run that can only time out would be a
  /// worse answer than saying so.
  Widget _autoPlayNextModuleTile(
    BuildContext context, {
    required bool hasChild,
    required bool running,
  }) {
    final assessment = context.read<AssessmentProvider>();
    final next = DeveloperToolsService.nextIncompleteModule(assessment,
        activeGameIds: _activeGameIds);
    final automatable =
        next != null && DeveloperAutomationRegistry.canAutomate(next.game.id);

    return _actionTile(
      key: const Key('developerAutoPlayNextModule'),
      icon: Icons.play_circle_outline_rounded,
      title: 'Auto-play Next Module Only',
      subtitle: !hasChild
          ? 'Needs an active child profile'
          : next == null
              ? 'All recommended modules completed'
              : !automatable
                  ? '${next.game.name} has no auto-play hook yet'
                  : running
                      ? 'Auto-play is already running'
                      : 'Plays ${next.game.name} through the practice pipeline',
      enabled: hasChild && automatable && !running,
      onTap: () => _autoPlayNextModule(next!),
    );
  }

  Future<void> _autoPlayNextModule(
    LearningPathEntry next,
  ) async {
    // Read difficulty before the dialog: it comes from the app's own rule
    // (parent override → AI level → fallback), so the automated run plays the
    // module at the level the child would actually get.
    final difficulty = GameLauncher.difficultyFor(context, next.game,
        fallback: next.difficulty);

    final confirmed = await _confirm(
      title: 'Auto-play ${next.game.name}?',
      message: 'The real practice screen for ${next.game.name} opens and '
          'automation plays it. A genuine practice session is recorded and '
          'the learning path advances one step, so this creates local test '
          'records that may sync for the current account.',
      confirmLabel: 'Auto-play',
    );
    if (!confirmed || !mounted) return;

    final screen = GameLauncher.screenFor(next.game.id, difficulty);
    if (screen == null) {
      setState(() {
        _statusIsError = true;
        _status = 'No practice screen is wired up for ${next.game.name}.';
      });
      return;
    }

    unawaited(DeveloperAutoPlayController.instance
        .start(mode: AutoPlayMode.nextModule, expectedGameCount: 1));
    _closeAndInstall(
      message: 'Auto-playing ${next.game.name}.',
      screen: screen,
    );
  }

  /// Confirms, closes the toolbox, installs the real flow screen, and starts
  /// the automation run.
  ///
  /// The controller is started first and is deliberately reactive: it drives
  /// whatever registers itself, so it simply waits for [openFlow]'s screen to
  /// appear rather than needing to be handed one.
  Future<void> _startAutoPlay(
    AutoPlayMode mode,
    void Function() openFlow,
  ) async {
    final confirmed = await _confirm(
      title: 'Auto-play ${mode.label.toLowerCase()}?',
      message: 'The real ${mode.label.toLowerCase()} flow will open and '
          'automation will play all four games by performing valid in-game '
          'actions. Real sessions are recorded, so this creates local test '
          'records that may sync for the current account. The flow still ends '
          'at the hand-off to the parent.',
      confirmLabel: 'Auto-play',
    );
    if (!confirmed || !mounted) return;

    unawaited(DeveloperAutoPlayController.instance
        .start(mode: mode, expectedGameCount: 4));
    openFlow();
  }

  /// Opens the genuine pre-assessment progress screen.
  ///
  /// Consent is passed as declined: no sensory experiment is run for an
  /// automated pass, so the child's existing comfort settings are used and no
  /// sensory conclusion is fabricated.
  void _openPreAssessment(BuildContext context) => _closeAndInstall(
        message: 'Auto-playing the pre-assessment.',
        screen: const PreAssessmentProgressScreen(
          sensoryConsentResult: SensoryConsentResult.declined,
        ),
      );

  void _openPostAssessment(BuildContext context) => _closeAndInstall(
        message: 'Auto-playing the post-assessment.',
        screen: const PostAssessmentProgressScreen(),
      );

  /// Closes the toolbox, then installs [screen] as the active route on top of
  /// the app's first route.
  ///
  /// Everything in between — the game screens, the assessment progress screen,
  /// a reward dialog left open — is removed, so no orphaned timer or callback
  /// can finish the same run a second time underneath the hand-off.
  void _closeAndInstall({required String message, required Widget screen}) {
    final navigator = Navigator.of(context, rootNavigator: true);
    navigator.pop(); // the toolbox sheet
    navigator.pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => screen),
      (route) => route.isFirst,
    );
    _snack(message, navigatorContext: navigator.context);
  }

  void _snack(String message, {BuildContext? navigatorContext}) {
    final messengerContext = navigatorContext ?? context;
    final messenger = ScaffoldMessenger.maybeOf(messengerContext);
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }
}
