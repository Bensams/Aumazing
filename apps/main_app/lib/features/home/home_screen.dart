import 'dart:async';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_audio/shared_audio.dart';

import 'package:shared_ui/shared_ui.dart';

import '../../core/child_profile_policy.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/child_bootstrap_service.dart';
import '../../core/services/sync_service.dart';
import '../../core/widgets/sync_status_banner.dart';
import '../../providers/assessment_provider.dart';
import '../../providers/child_provider.dart';
import '../../providers/progress_provider.dart';
import '../../services/active_games_service.dart';
import '../../services/entitlement_service.dart';
import '../../services/learning_path_service.dart';
import '../../services/screen_time_service.dart';
import '../../services/tour_service.dart';
import 'widgets/guided_tour_overlay.dart';
import '../premium/premium_upgrade_screen.dart';
import '../settings/settings_screen.dart';
import '../child_mode/child_mode_lobby_screen.dart';
import '../post_assessment/post_assessment_progress_screen.dart';
import '../pre_assessment/assessment_dashboard_screen.dart';
import '../therapy/therapy_directory_screen.dart';
import '../pre_assessment/pre_assessment_intro_screen.dart';
import '../splash/auth/child_profile_setup_screen.dart';
import '../splash/auth/login_screen.dart';

/// Parent Dashboard — the main hub after login.
///
/// Shows child summary, assessment status, progress, and action buttons
/// for starting pre-assessment or entering child mode.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.authService, this.syncStates});

  final AuthService? authService;

  /// Sync-state feed the dashboard refreshes on. Defaults to the live
  /// [syncService]; injectable so a test can land a synced pass without a
  /// database or a network.
  final Stream<SyncState>? syncStates;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final AuthService _authService;
  bool _isLeftPanelExpanded = true;

  /// Portrait only: whether the child summary card is showing its details.
  bool _isSummaryExpanded = false;

  /// Whether the guided tour is currently dimming the dashboard.
  bool _isTourActive = false;

  // Tour targets. Landscape and portrait draw different widgets for the
  // same thing, so each has its own key; the tour skips whichever pair is
  // not on screen.
  final _childPanelKey = GlobalKey();
  final _summaryCardKey = GlobalKey();
  final _settingsWideKey = GlobalKey();
  final _settingsPortraitKey = GlobalKey();
  final _signOutWideKey = GlobalKey();
  final _signOutPortraitKey = GlobalKey();
  final _assessmentButtonKey = GlobalKey();
  final _childModeKey = GlobalKey();
  final _therapyKey = GlobalKey();
  final _assessmentStatusKey = GlobalKey();
  final _scoresKey = GlobalKey();
  final _screenTimeKey = GlobalKey();
  final _recentActivityKey = GlobalKey();

  /// Re-queries the dashboard when a sync pass lands rows.
  ///
  /// Progress is read once per child load, so a sync that finished while the
  /// parent was already looking at the dashboard left the new rows invisible
  /// until they switched child or came back to the screen. The banner was
  /// the only thing listening; now the data listens too.
  StreamSubscription<SyncState>? _syncSubscription;

  @override
  void initState() {
    super.initState();
    _authService = widget.authService ?? AuthService();
    lockParentAdaptive();
    _listenForSyncedRows();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (mounted) {
        await _loadData();
        if (mounted) {
          await _verifyMusicPlaying();
        }
      }
    });
  }

  void _listenForSyncedRows() {
    _syncSubscription = (widget.syncStates ?? syncService.onSyncStateChanged)
        .listen((state) {
          // Only a completed pass that actually brought something down is worth
          // a re-query — a clean pass with nothing to do would just churn the
          // dashboard, and 'syncing' has no rows yet.
          if (state.status != SyncStatusEnum.completed) return;
          if (state.syncedCount <= 0) return;
          _reloadChildScopedData();
        });
  }

  /// Re-reads the selected child's dashboard data, if one is still selected.
  void _reloadChildScopedData() {
    if (!mounted) return;
    final childId = context.read<ChildProvider>().profile?.id;
    if (childId == null) return;
    context.read<AssessmentProvider>().loadAssessments(childId);
    context.read<ProgressProvider>().loadProgress(childId);
  }

  Future<void> _verifyMusicPlaying() async {
    try {
      // Longer delay to ensure navigation transition is fully complete
      await Future.delayed(const Duration(milliseconds: 600));
      if (!mounted) return;

      final audioService = context.read<AudioService>();
      final childProvider = context.read<ChildProvider>();
      debugPrint(
        '[HomeScreen] Checking music state: isMusicPlaying=${audioService.isMusicPlaying}, musicEnabled=${childProvider.musicEnabled}',
      );

      if (!childProvider.musicEnabled) {
        // User has music disabled — stop any music that may have started
        // during LoadingScreen before the profile was loaded.
        if (audioService.isMusicPlaying) {
          debugPrint('[HomeScreen] Music disabled but playing — stopping...');
          await audioService.stopMusic();
        } else {
          debugPrint('[HomeScreen] Music disabled and not playing — OK');
        }
      } else if (!audioService.isMusicPlaying) {
        debugPrint(
          '[HomeScreen] Music enabled but not playing, trying to resume...',
        );
        await audioService.resumeMusic();

        // Double-check if music is playing after resume attempt
        await Future.delayed(const Duration(milliseconds: 200));
        if (!audioService.isMusicPlaying) {
          debugPrint('[HomeScreen] Resume failed, starting fresh track...');
          await audioService.playCategoryMusic(childProvider.musicCategory);
        }
      } else if (audioService.currentCategory != childProvider.musicCategory) {
        // LoadingScreen and LoginScreen start the default category because no
        // profile exists yet. Now that it is loaded, move to the child's own
        // choice. This is the one place a track changes mid-run, and it
        // happens before the child reaches any game.
        debugPrint(
          '[HomeScreen] Switching music to '
          '${childProvider.musicCategory}',
        );
        await audioService.playCategoryMusic(childProvider.musicCategory);
      } else {
        debugPrint('[HomeScreen] Music already playing and enabled — OK');
      }
    } catch (e, stackTrace) {
      debugPrint('[HomeScreen] Error checking music: $e');
      debugPrint('[HomeScreen] Stack trace: $stackTrace');
    }
  }

  @override
  void dispose() {
    _syncSubscription?.cancel();
    unlockParentOrientation();
    super.dispose();
  }

  Future<void> _loadData() async {
    final childProvider = context.read<ChildProvider>();
    await childProvider.loadProfile();

    if (!mounted) return;

    // Sync AudioConfig from the child's persisted settings so that
    // lifecycle callbacks (pause/resume) and playMusic() respect them.
    if (childProvider.hasProfile) {
      final audioService = context.read<AudioService>();
      audioService.updateConfig(
        AudioConfig(
          musicEnabled: childProvider.musicEnabled,
          musicVolume: childProvider.musicVolume,
          sfxEnabled: true,
          sfxVolume: childProvider.sfxVolume,
        ),
      );
      debugPrint(
        '[HomeScreen] Synced AudioConfig from profile: '
        'musicEnabled=${childProvider.musicEnabled}, '
        'musicVolume=${childProvider.musicVolume}',
      );
    }

    // Only an actually-unusable birth date (missing or in the future) sends the
    // parent back to setup. Ages outside 2–6 are accepted here to stay
    // consistent with the child-setup screen and ChildBootstrapService, neither
    // of which enforces a range any more.
    final profile = childProvider.profile;
    final validation =
        profile == null
            ? ChildBirthDateValidation.missing
            : validateBirthDate(profile.birthDate);
    if (profile == null ||
        validation == ChildBirthDateValidation.missing ||
        validation == ChildBirthDateValidation.futureDate) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder:
              (_) => const ChildProfileSetupScreen(
                initialErrorMessage:
                    ChildBootstrapService.missingChildProfileMessage,
              ),
        ),
        (_) => false,
      );
      return;
    }

    final childId = profile.id;

    context.read<AssessmentProvider>().loadAssessments(childId);
    context.read<ProgressProvider>().loadProgress(childId);

    await _maybeStartTour();
  }

  // ── Guided tour ─────────────────────────────────────────────────────

  /// Runs the walkthrough automatically on the parent's first visit only.
  Future<void> _maybeStartTour() async {
    if (await TourService.instance.hasSeenParentTour()) return;
    if (!mounted || _isTourActive) return;
    setState(() => _isTourActive = true);
  }

  /// Replays the walkthrough from the help button.
  void _startTour() {
    if (_isTourActive) return;
    setState(() => _isTourActive = true);
  }

  void _endTour() {
    TourService.instance.markParentTourSeen();
    if (mounted) setState(() => _isTourActive = false);
  }

  /// The walkthrough itself: one short sentence per control, in the order a
  /// parent meets them. Steps whose target is missing (wrong layout, card
  /// hidden) are skipped by the overlay, so both keys of a pair can be
  /// listed and only the mounted one is shown.
  List<TourStep> _tourSteps() {
    return [
      const TourStep(
        title: 'Welcome',
        body:
            'A quick tour of the parent dashboard — tap Next to step '
            'through it, or Skip to explore on your own.',
        icon: Icons.waving_hand_rounded,
      ),
      TourStep(
        targetKey: _childPanelKey,
        title: 'Your child',
        body: "Your child's name, age and quick stats live here.",
        icon: Icons.person_rounded,
      ),
      TourStep(
        targetKey: _summaryCardKey,
        title: 'Your child',
        body:
            "Tap this card to expand your child's quick stats and your "
            'account details.',
        icon: Icons.person_rounded,
      ),
      TourStep(
        targetKey: _assessmentButtonKey,
        title: 'Assessment',
        body:
            'Start the pre-assessment here to find your child\'s starting '
            'level and get a recommended module.',
        icon: Icons.assessment_rounded,
      ),
      TourStep(
        targetKey: _childModeKey,
        title: 'Child mode',
        body:
            'Tap here, then hand the device to your child — the games open '
            'in a full-screen, child-safe lobby.',
        icon: Icons.child_care_rounded,
      ),
      TourStep(
        targetKey: _childModeKey,
        title: 'Coming back',
        body:
            'To return here, tap the lock button at the top of the child '
            'screen and enter your parent PIN.',
        icon: Icons.lock_rounded,
      ),
      TourStep(
        targetKey: _therapyKey,
        title: 'Therapy directory',
        body: 'Find therapy centers near you and get directions.',
        icon: Icons.location_on_rounded,
      ),
      TourStep(
        targetKey: _screenTimeKey,
        title: 'Screen time',
        body: "Today's play time against the daily limit you set in Settings.",
        icon: Icons.timer_rounded,
      ),
      TourStep(
        targetKey: _assessmentStatusKey,
        title: 'Recommended module',
        body:
            'The activity your child should work on next — tap it to open '
            'that learning path straight away.',
        icon: Icons.recommend_rounded,
      ),
      TourStep(
        targetKey: _scoresKey,
        title: 'Assessment scores',
        body: 'How your child scored on each assessment activity.',
        icon: Icons.bar_chart_rounded,
      ),
      TourStep(
        targetKey: _recentActivityKey,
        title: 'Recent activity',
        body:
            'The last few sessions your child played, with score and time '
            'spent.',
        icon: Icons.history_rounded,
      ),
      TourStep(
        targetKey: _settingsWideKey,
        title: 'Settings',
        body:
            'Set the parent PIN, screen-time limit, sounds and profile '
            'details here.',
        icon: Icons.settings_rounded,
      ),
      TourStep(
        targetKey: _settingsPortraitKey,
        title: 'Settings',
        body:
            'Set the parent PIN, screen-time limit, sounds and profile '
            'details here.',
        icon: Icons.settings_rounded,
      ),
      TourStep(
        targetKey: _signOutWideKey,
        title: 'Sign out',
        body:
            'Signs you out of your account — your child\'s progress stays '
            'saved.',
        icon: Icons.logout_rounded,
      ),
      TourStep(
        targetKey: _signOutPortraitKey,
        title: 'Sign out',
        body:
            'Signs you out of your account — your child\'s progress stays '
            'saved.',
        icon: Icons.logout_rounded,
      ),
      const TourStep(
        title: 'That\'s it',
        body:
            'You can replay this tour any time from the ? button at the '
            'top of the dashboard.',
        icon: Icons.help_outline_rounded,
      ),
    ];
  }

  Future<void> _signOut() async {
    await _authService.signOut();
    if (mounted) {
      context.read<ChildProvider>().clear();
      context.read<AssessmentProvider>().clear();
      context.read<ProgressProvider>().clear();
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
    }
  }

  /// Pushes a route that may lock landscape (child mode, the games, the
  /// assessment activities) and re-applies the parent orientation when it
  /// returns — HomeScreen's initState does not run again on pop.
  Future<void> _pushChildFacing(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    if (mounted) lockParentAdaptive();
  }

  void _startPreAssessment() {
    final hasAssessment = context.read<AssessmentProvider>().hasPreAssessment;
    _pushChildFacing(
      hasAssessment
          ? const AssessmentDashboardScreen()
          : const PreAssessmentIntroScreen(),
    );
  }

  void _enterChildMode() {
    _pushChildFacing(const ChildModeLobbyScreen());
  }

  /// True when the child has finished every step of the learning path and
  /// hasn't taken the post-assessment yet — time to measure improvement.
  bool _postAssessmentReady(AssessmentProvider assessProv) {
    if (assessProv.aiPrediction == null) return false;
    if (assessProv.hasPostAssessment) return false;
    final path = LearningPathService.fromContext(
      context,
      activeGameIds: ActiveGamesService.instance.cachedActiveGameIds,
    );
    if (path.isEmpty) return false;
    final done = assessProv.pathCompletedGameIds;
    return path.every((e) => done.contains(e.game.id));
  }

  /// Opens the child lobby directly on the AI-recommended learning path
  /// (from the Recommended Module card).
  void _openLearningPath() {
    _pushChildFacing(const ChildModeLobbyScreen(openPath: true));
  }

  void _toggleLeftPanel() {
    setState(() {
      _isLeftPanelExpanded = !_isLeftPanelExpanded;
    });
  }

  void _showSettingsModal() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(authService: _authService),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        // The tour overlay is only worth anything at full screen size, so
        // the stack takes the whole body rather than the dashboard's
        // intrinsic size.
        fit: StackFit.expand,
        children: [
          Container(
            decoration: BoxDecoration(
              gradient:
                  context.watch<ChildProvider>().activePalette.parentBackground,
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Phones run this screen in portrait; tablets stay landscape.
                return constraints.maxWidth >= constraints.maxHeight
                    ? _buildWideLayout()
                    : _buildPortraitLayout();
              },
            ),
          ),
          if (_isTourActive)
            GuidedTourOverlay(steps: _tourSteps(), onFinish: _endTour),
        ],
      ),
    );
  }

  /// Landscape: child summary in a collapsible left panel beside the content.
  Widget _buildWideLayout() {
    return Row(
      children: [
        // ── Left Panel: Child Summary (no SafeArea, sticks to edge) ────
        AnimatedContainer(
          key: _childPanelKey,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          width: _isLeftPanelExpanded ? 280 : 56,
          child: _buildChildPanel(),
        ),

        // ── Main Content ──────────────────────────────────────
        Expanded(
          child: SafeArea(
            left: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(),
                  const SizedBox(height: AppSpacing.md),
                  ..._buildDashboardSections(),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Portrait: no room for a side panel, so the child summary folds into a
  /// card at the top of the single scrolling column.
  Widget _buildPortraitLayout() {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildChildSummaryCard(),
            const SizedBox(height: AppSpacing.md),
            ..._buildDashboardSections(),
          ],
        ),
      ),
    );
  }

  /// The dashboard content itself — identical in both layouts; the sections
  /// reflow on their own width.
  List<Widget> _buildDashboardSections() {
    return [
      // Hides itself when online with nothing pending, so it only costs
      // space when there is genuinely something to say.
      const SyncStatusBanner(),
      _buildActionButtons(),
      _buildPremiumBanner(),
      _buildScreenTimeStatus(),
      const SizedBox(height: AppSpacing.md),
      KeyedSubtree(key: _assessmentStatusKey, child: _buildAssessmentStatus()),
      const SizedBox(height: AppSpacing.md),
      KeyedSubtree(key: _scoresKey, child: _buildProgressSection()),
      const SizedBox(height: AppSpacing.md),
      _buildAdvancedTrends(),
      KeyedSubtree(key: _recentActivityKey, child: _buildRecentActivity()),
    ];
  }

  /// Portrait header: the side panel's child summary folded into a card.
  /// Collapsed it says whose dashboard this is; expanding it reveals the
  /// account email and the quick stats the panel shows in landscape.
  Widget _buildChildSummaryCard() {
    return Consumer<ChildProvider>(
      builder: (context, childProv, _) {
        final profile = childProv.profile;
        final name = profile?.displayName ?? 'Child';
        final age = profile?.birthDate != null ? profile!.ageYears() : '?';
        final avatar = profile?.avatarEmoji ?? '🐻';
        final email = _authService.currentUser?.email ?? '';

        return Container(
          key: _summaryCardKey,
          decoration: BoxDecoration(
            color: AppColors.white.withAlpha(200),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap:
                    () => setState(
                      () => _isSummaryExpanded = !_isSummaryExpanded,
                    ),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppColors.lavenderLight,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Text(
                            avatar,
                            style: const TextStyle(fontSize: 24),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "$name's Dashboard",
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.titleLarge.copyWith(
                                color: AppColors.textPrimary,
                              ),
                            ),
                            Text(
                              'Age $age',
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.help_outline_rounded),
                        tooltip: 'Dashboard guide',
                        onPressed: _startTour,
                        color: AppColors.textSecondary,
                      ),
                      IconButton(
                        key: _settingsPortraitKey,
                        icon: const Icon(Icons.settings_rounded),
                        tooltip: 'Settings',
                        onPressed: _showSettingsModal,
                        color: AppColors.textSecondary,
                      ),
                      Icon(
                        _isSummaryExpanded
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        color: AppColors.textSecondary,
                      ),
                    ],
                  ),
                ),
              ),
              if (_isSummaryExpanded) ...[
                const Divider(height: 1),
                const SizedBox(height: AppSpacing.sm),
                if (email.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                      vertical: 6,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.email_outlined,
                          size: 20,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            email,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                _buildQuickStat(
                  Icons.games_rounded,
                  'Sessions',
                  context.watch<ProgressProvider>().totalSessions.toString(),
                ),
                _buildQuickStat(
                  Icons.trending_up_rounded,
                  'Modules',
                  '${context.watch<ProgressProvider>().completedModules} done',
                ),
                _buildQuickStat(
                  Icons.assessment_rounded,
                  'Assessment',
                  context.watch<AssessmentProvider>().hasPreAssessment
                      ? 'Completed'
                      : 'Pending',
                ),
                const SizedBox(height: AppSpacing.xs),
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(
                      right: AppSpacing.sm,
                      bottom: AppSpacing.xs,
                    ),
                    child: TextButton.icon(
                      key: _signOutPortraitKey,
                      onPressed: _signOut,
                      icon: const Icon(Icons.logout_rounded, size: 18),
                      label: const Text('Sign Out'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader() {
    return Consumer<ChildProvider>(
      builder: (context, childProv, _) {
        final profile = childProv.profile;
        final name = profile?.displayName ?? 'Child';
        final age = profile?.birthDate != null ? profile!.ageYears() : '?';
        final avatar = profile?.avatarEmoji ?? '🐻';
        final email = _authService.currentUser?.email ?? '';

        return Row(
          children: [
            // Avatar
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AppColors.lavenderLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(avatar, style: const TextStyle(fontSize: 28)),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            // Child info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "$name's Dashboard",
                    style: AppTextStyles.headlineSmall.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    'Age $age',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  alignment: WrapAlignment.end,
                  children: [
                    if (email.isNotEmpty)
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 240),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.white.withAlpha(180),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.email_outlined,
                                size: 16,
                                color: AppColors.textSecondary,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  email,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTextStyles.bodySmall.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    IconButton(
                      icon: const Icon(Icons.help_outline_rounded),
                      tooltip: 'Dashboard guide',
                      onPressed: _startTour,
                      color: AppColors.textSecondary,
                    ),
                    IconButton(
                      key: _settingsWideKey,
                      icon: const Icon(Icons.settings_rounded),
                      tooltip: 'Settings',
                      onPressed: _showSettingsModal,
                      color: AppColors.textSecondary,
                    ),
                    IconButton(
                      key: _signOutWideKey,
                      icon: const Icon(Icons.logout_rounded),
                      tooltip: 'Sign Out',
                      onPressed: _signOut,
                      color: AppColors.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ── Left Panel: Child Info ──────────────────────────────────────────

  Widget _buildChildPanel() {
    return Consumer<ChildProvider>(
      builder: (context, childProv, _) {
        final profile = childProv.profile;
        final name = profile?.displayName ?? 'Child';
        final age = profile?.birthDate != null ? profile!.ageYears() : '?';
        final avatar = profile?.avatarEmoji ?? '🐻';

        return Container(
          decoration: BoxDecoration(
            color: AppColors.white.withAlpha(200),
            border: Border(
              right: BorderSide(color: AppColors.border, width: 1),
            ),
          ),
          child: Column(
            children: [
              // Toggle button (always visible, right-aligned)
              SizedBox(
                height: 48,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    icon: Icon(
                      _isLeftPanelExpanded
                          ? Icons.chevron_left_rounded
                          : Icons.chevron_right_rounded,
                    ),
                    onPressed: _toggleLeftPanel,
                    tooltip: _isLeftPanelExpanded ? 'Collapse' : 'Expand',
                  ),
                ),
              ),
              const Divider(height: 1),

              // Collapsed view - just avatar
              if (!_isLeftPanelExpanded)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.sm,
                    ),
                    child: Column(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: const BoxDecoration(
                            color: AppColors.lavenderLight,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              avatar,
                              style: const TextStyle(fontSize: 20),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // Expanded view - full content
              if (_isLeftPanelExpanded) ...[
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(top: AppSpacing.md),
                    child: Column(
                      children: [
                        // Avatar
                        Container(
                          width: 64,
                          height: 64,
                          decoration: const BoxDecoration(
                            color: AppColors.lavenderLight,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              avatar,
                              style: const TextStyle(fontSize: 32),
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),

                        // Name
                        Text(
                          name.toString(),
                          style: AppTextStyles.titleLarge.copyWith(
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Age $age',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),

                        const SizedBox(height: AppSpacing.sm),
                        const Divider(indent: 24, endIndent: 24, height: 1),
                        const SizedBox(height: AppSpacing.sm),

                        // Quick stats
                        _buildQuickStat(
                          Icons.games_rounded,
                          'Sessions',
                          context
                              .watch<ProgressProvider>()
                              .totalSessions
                              .toString(),
                        ),
                        _buildQuickStat(
                          Icons.trending_up_rounded,
                          'Modules',
                          '${context.watch<ProgressProvider>().completedModules} done',
                        ),
                        _buildQuickStat(
                          Icons.assessment_rounded,
                          'Assessment',
                          context.watch<AssessmentProvider>().hasPreAssessment
                              ? 'Completed'
                              : 'Pending',
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildQuickStat(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: 6,
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.textSecondary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              label,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Text(
            value,
            style: AppTextStyles.labelLarge.copyWith(
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  // ── Action Buttons ──────────────────────────────────────────────────

  Widget _buildActionButtons() {
    return Consumer<AssessmentProvider>(
      builder: (context, assessProv, _) {
        final assessment = AppPrimaryButton(
          key: _assessmentButtonKey,
          label:
              assessProv.hasPreAssessment
                  ? 'Assessment'
                  : 'Start Pre-Assessment',
          onPressed: _startPreAssessment,
          icon:
              assessProv.hasPreAssessment
                  ? Icons.assessment_rounded
                  : Icons.play_circle_filled_rounded,
        );
        final childMode = _ActionCard(
          key: _childModeKey,
          icon: Icons.child_care_rounded,
          label: 'Enter Child Mode',
          subtitle: 'Hand device to child',
          color: AppColors.mint,
          onTap: _enterChildMode,
        );
        final therapy = _ActionCard(
          key: _therapyKey,
          icon: Icons.location_on_rounded,
          label: 'Therapy Directory',
          subtitle: 'Centers near you',
          color: AppColors.peach,
          onTap:
              () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const TherapyDirectoryScreen(),
                ),
              ),
        );

        // What each action needs to read in full, measured from its own
        // label at the ambient text scale. A fixed 540 breakpoint clipped
        // "Start Pre-Assessment" once the tablet sidebar had taken its
        // share of the width.
        final assessmentMin = AppPrimaryButton.minWidthFor(
          context,
          label:
              assessProv.hasPreAssessment
                  ? 'Assessment'
                  : 'Start Pre-Assessment',
          icon: Icons.play_circle_filled_rounded,
        );
        final cardMin = _ActionCard.minWidthFor(
          context,
          labels: const ['Enter Child Mode', 'Therapy Directory'],
        );

        return LayoutBuilder(
          builder: (context, constraints) {
            const gap = AppSpacing.md;
            final width = constraints.maxWidth;

            // Three across only when every label fits at once. Spare space
            // is shared proportionally, so the assessment CTA — the widest
            // label — keeps the largest column.
            if (width >= assessmentMin + cardMin * 2 + gap * 2) {
              // IntrinsicHeight keeps the three tiles the same height even
              // when one of them wraps its label.
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: assessmentMin.round(), child: assessment),
                    const SizedBox(width: gap),
                    Expanded(flex: cardMin.round(), child: childMode),
                    const SizedBox(width: gap),
                    Expanded(flex: cardMin.round(), child: therapy),
                  ],
                ),
              );
            }

            // Two columns: the long CTA takes a full-width row of its own
            // and the two shorter cards pair up beneath it.
            if (width >= cardMin * 2 + gap && width >= assessmentMin) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  assessment,
                  const SizedBox(height: gap),
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: childMode),
                        const SizedBox(width: gap),
                        Expanded(child: therapy),
                      ],
                    ),
                  ),
                ],
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                assessment,
                const SizedBox(height: gap),
                childMode,
                const SizedBox(height: gap),
                therapy,
              ],
            );
          },
        );
      },
    );
  }

  /// Freemium gateway (FR-10): upgrade banner for Free parents; hidden
  /// once Premium is active. Rebuilds live when the entitlement changes.
  Widget _buildPremiumBanner() {
    return ListenableBuilder(
      listenable: EntitlementService.instance,
      builder: (context, _) {
        if (EntitlementService.instance.isPremium) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.only(top: AppSpacing.md),
          child: RainbowBorderCard(
            child: AppCard(
              child: _CtaBand(
                leading: const Text('⭐', style: TextStyle(fontSize: 28)),
                content: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Aumazing Premium',
                      style: AppTextStyles.titleMedium.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      'Interactive therapy locator, skill trends, and '
                      'fresh AI recommendations — ₱149/month.',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.mutedForeground,
                      ),
                    ),
                  ],
                ),
                label: 'Upgrade',
                icon: Icons.star_rounded,
                onPressed:
                    () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder:
                            (_) =>
                                PremiumUpgradeScreen(authService: _authService),
                      ),
                    ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Compact "screen time today" monitor for the parent (FR: parents
  /// monitor screen time from the dashboard). Hidden when no limits are set.
  Widget _buildScreenTimeStatus() {
    final childId = context.watch<ChildProvider>().profile?.id;
    final screenTime = ScreenTimeService.instance;
    if (childId != null && screenTime.loadedChildId != childId) {
      screenTime.load(childId);
    }
    return ListenableBuilder(
      listenable: screenTime,
      builder: (context, _) {
        final limit = screenTime.limitMinutes;
        final sessionLimit = screenTime.sessionLimitMinutes;
        if (limit == null && sessionLimit == null) {
          return const SizedBox.shrink();
        }
        // Each budget reads "used of configured · remaining left", so the
        // dashboard stays one glance wide while still distinguishing the
        // three values the parent needs, and states the no-limit case
        // outright instead of omitting the line (AUM-162). Seconds drive the
        // bar so a part-minute of play is not rounded away.
        final dailyRemaining = screenTime.remainingSeconds;
        final sessionRemaining = screenTime.sessionRemainingSeconds;
        final dailyLine =
            limit == null
                ? 'Today: ${ScreenTimeService.formatDuration(screenTime.usedTodaySeconds)} played · no daily limit'
                : 'Today: ${ScreenTimeService.formatDuration(screenTime.usedTodaySeconds)}'
                    ' of ${ScreenTimeService.formatDuration(limit * 60)}'
                    ' · ${ScreenTimeService.formatDuration(dailyRemaining ?? 0)} left';
        final sessionLine =
            sessionLimit == null
                ? 'Session: ${ScreenTimeService.formatDuration(screenTime.sessionUsedSeconds)} played · no session limit'
                : 'Session: ${ScreenTimeService.formatDuration(screenTime.sessionUsedSeconds)}'
                    ' of ${ScreenTimeService.formatDuration(sessionLimit * 60)}'
                    ' · ${ScreenTimeService.formatDuration(sessionRemaining ?? 0)} left';
        // The bar tracks the daily budget when there is one; with only a
        // session limit set it tracks the current session instead.
        final fraction =
            limit != null
                ? (screenTime.usedTodaySeconds / (limit * 60)).clamp(0.0, 1.0)
                : (screenTime.sessionUsedSeconds / (sessionLimit! * 60)).clamp(
                  0.0,
                  1.0,
                );
        return Padding(
          key: _screenTimeKey,
          padding: const EdgeInsets.only(top: AppSpacing.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.timer_rounded,
                  size: 16,
                  color: AppColors.mutedForeground,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dailyLine,
                      key: const Key('dashboard.screenTime.daily'),
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.mutedForeground,
                      ),
                    ),
                    Text(
                      sessionLine,
                      key: const Key('dashboard.screenTime.session'),
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.mutedForeground,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: fraction,
                        minHeight: 6,
                        backgroundColor: AppColors.lavenderLight,
                        valueColor: AlwaysStoppedAnimation(
                          fraction >= 1.0
                              ? AppColors.statusWarningDark
                              : AppColors.mint,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Assessment Status ───────────────────────────────────────────────

  /// A quiet placeholder card shown while the newly selected child's data
  /// loads, so the previous child's numbers are never on screen meanwhile.
  Widget _buildLoadingCard(String message) {
    return AppCard(
      child: Row(
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              message,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAssessmentStatus() {
    return Consumer<AssessmentProvider>(
      builder: (context, assessProv, _) {
        if (assessProv.isLoading) {
          return _buildLoadingCard('Loading assessment results…');
        }
        if (!assessProv.hasPreAssessment) {
          return AppCard(
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.statusWarningBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.info_outline_rounded,
                    color: AppColors.statusWarningDark,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final title = Text(
                            'Pre-Assessment Needed',
                            style: AppTextStyles.titleMedium.copyWith(
                              color: AppColors.textPrimary,
                            ),
                          );
                          // The pill repeats the heading word for word. On a
                          // narrow card there is no room for both, and the
                          // heading already carries the message.
                          if (constraints.maxWidth < 320) return title;
                          return Row(
                            children: [
                              Expanded(child: title),
                              const SizedBox(width: AppSpacing.sm),
                              const StatusPillBadge(
                                label: 'Pre-Assessment Needed',
                                level: StatusLevel.warning,
                                compact: true,
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Start the pre-assessment to determine your child\'s starting level and get a recommended learning module.',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        // Show recommendation — tapping opens the child lobby directly on
        // the AI-recommended learning path.
        return AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _openLearningPath,
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppColors.statusSuccessBg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.recommend_rounded,
                        color: AppColors.statusSuccessDark,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Recommended Module',
                            style: AppTextStyles.titleMedium.copyWith(
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            assessProv.recommendedModuleName ?? 'Basic Skills',
                            style: AppTextStyles.headlineSmall.copyWith(
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    StatusPillBadge(
                      label: 'Level ${assessProv.recommendedLevel}',
                      level: StatusLevel.info,
                      compact: true,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.textSecondary,
                    ),
                  ],
                ),
              ),
              if (assessProv.hasPostAssessment) ...[
                const SizedBox(height: AppSpacing.sm),
                const Divider(),
                const SizedBox(height: AppSpacing.xs),
                Row(
                  children: [
                    const Icon(
                      Icons.trending_up_rounded,
                      size: 18,
                      color: AppColors.statusSuccessDark,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Post-assessment completed — view progress below',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.statusSuccessDark,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              // Learning path finished → offer the post-assessment so the
              // improvement can be measured (Use Case 7).
              if (_postAssessmentReady(assessProv)) ...[
                const SizedBox(height: AppSpacing.sm),
                const Divider(),
                const SizedBox(height: AppSpacing.xs),
                _CtaBand(
                  leading: const Icon(
                    Icons.emoji_events_rounded,
                    size: 18,
                    color: AppColors.primaryPurple,
                  ),
                  content: Text(
                    'Learning path complete! Measure the progress with '
                    'a post-assessment.',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                  label: 'Start Post-Assessment',
                  icon: Icons.play_arrow_rounded,
                  onPressed:
                      () => _pushChildFacing(
                        const PostAssessmentProgressScreen(),
                      ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  // ── Progress Section ────────────────────────────────────────────────

  Widget _buildProgressSection() {
    return Consumer<AssessmentProvider>(
      builder: (context, assessProv, _) {
        // While a switch is loading the new child's rows, showing the chart
        // would render the previous child's scores under the new name.
        if (assessProv.isLoading || assessProv.preResults.isEmpty) {
          return const SizedBox.shrink();
        }

        final results = assessProv.preResults;
        final barGroups = <BarChartGroupData>[];

        for (var i = 0; i < results.length && i < 4; i++) {
          barGroups.add(
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: results[i].adjustedAccuracy * 100,
                  color: AppColors.primaryPurple,
                  width: 20,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(6),
                  ),
                ),
              ],
            ),
          );
        }

        final gameLabels =
            results.take(4).map((r) => r.gameId.replaceAll('_', ' ')).toList();

        return AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Assessment Scores',
                style: AppTextStyles.titleMedium.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                height: 160,
                child: BarChart(
                  BarChartData(
                    maxY: 100,
                    barGroups: barGroups,
                    borderData: FlBorderData(show: false),
                    gridData: const FlGridData(show: false),
                    titlesData: FlTitlesData(
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 32,
                          getTitlesWidget: (value, meta) {
                            if (value % 25 == 0) {
                              return Text(
                                '${value.toInt()}%',
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                              );
                            }
                            return const SizedBox.shrink();
                          },
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (value, meta) {
                            final idx = value.toInt();
                            if (idx < gameLabels.length) {
                              return Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  gameLabels[idx],
                                  style: AppTextStyles.bodySmall.copyWith(
                                    fontSize: 10,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              );
                            }
                            return const SizedBox.shrink();
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Advanced Trends (Premium dashboard) ─────────────────────────────

  /// The Advanced Parent Dashboard (Premium): historical pre → post skill
  /// trends. Free users see a locked teaser; Premium users see the
  /// per-game improvement once a post-assessment exists. Rebuilds live when
  /// the entitlement changes.
  Widget _buildAdvancedTrends() {
    return ListenableBuilder(
      listenable: EntitlementService.instance,
      builder: (context, _) {
        final isPremium = EntitlementService.instance.isPremium;
        if (!isPremium) {
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: AppCard(
              child: _CtaBand(
                leading: const Icon(
                  Icons.lock_rounded,
                  color: AppColors.mutedForeground,
                ),
                content: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Advanced Trends',
                      style: AppTextStyles.titleMedium.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      'See how skills improve across assessment cycles '
                      '— a Premium feature.',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.mutedForeground,
                      ),
                    ),
                  ],
                ),
                label: 'Unlock',
                icon: Icons.star_rounded,
                onPressed:
                    () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder:
                            (_) =>
                                PremiumUpgradeScreen(authService: _authService),
                      ),
                    ),
              ),
            ),
          );
        }

        return Consumer<AssessmentProvider>(
          builder: (context, assessProv, _) {
            // Mid-switch the pre/post rows may still be the previous
            // child's; say nothing until the new child's rows are in.
            if (assessProv.isLoading) return const SizedBox.shrink();
            if (!assessProv.hasPostAssessment) {
              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: AppCard(
                  child: Row(
                    children: [
                      const Icon(
                        Icons.insights_rounded,
                        color: AppColors.primaryPurple,
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Text(
                          'Complete a post-assessment to see pre → post '
                          'progress trends here.',
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            // Match pre and post results by game for a paired comparison.
            final postByGame = {
              for (final r in assessProv.postResults) r.gameId: r,
            };
            final rows = <(String, double, double)>[];
            for (final pre in assessProv.preResults) {
              final post = postByGame[pre.gameId];
              if (post == null) continue;
              rows.add((
                pre.gameId.replaceAll('_', ' '),
                pre.adjustedAccuracy * 100,
                post.adjustedAccuracy * 100,
              ));
            }
            if (rows.isEmpty) return const SizedBox.shrink();

            final avgDelta =
                rows.map((r) => r.$3 - r.$2).reduce((a, b) => a + b) /
                rows.length;

            return Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Advanced Trends',
                          style: AppTextStyles.titleMedium.copyWith(
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const Spacer(),
                        Icon(
                          avgDelta >= 0
                              ? Icons.trending_up_rounded
                              : Icons.trending_down_rounded,
                          size: 18,
                          color:
                              avgDelta >= 0
                                  ? AppColors.statusSuccessDark
                                  : AppColors.mutedForeground,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${avgDelta >= 0 ? '+' : ''}'
                          '${avgDelta.toStringAsFixed(0)}% overall',
                          style: AppTextStyles.bodySmall.copyWith(
                            color:
                                avgDelta >= 0
                                    ? AppColors.statusSuccessDark
                                    : AppColors.mutedForeground,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Pre vs Post accuracy per activity',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.mutedForeground,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    for (final (label, pre, post) in rows)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 96,
                              child: Text(
                                label,
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: AppColors.textPrimary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: Stack(
                                  children: [
                                    LinearProgressIndicator(
                                      value: pre / 100,
                                      minHeight: 12,
                                      backgroundColor: AppColors.lavenderLight,
                                      valueColor: const AlwaysStoppedAnimation(
                                        AppColors.lavender,
                                      ),
                                    ),
                                    LinearProgressIndicator(
                                      value: post / 100,
                                      minHeight: 12,
                                      backgroundColor: Colors.transparent,
                                      valueColor: const AlwaysStoppedAnimation(
                                        AppColors.primaryPurple,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${(post - pre) >= 0 ? '+' : ''}'
                              '${(post - pre).toStringAsFixed(0)}%',
                              style: AppTextStyles.bodySmall.copyWith(
                                color:
                                    (post - pre) >= 0
                                        ? AppColors.statusSuccessDark
                                        : AppColors.mutedForeground,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ── Recent Activity ─────────────────────────────────────────────────

  Widget _buildRecentActivity() {
    return Consumer<ProgressProvider>(
      builder: (context, progressProv, _) {
        if (progressProv.isLoading) {
          return _buildLoadingCard('Loading recent activity…');
        }
        final sessions = progressProv.recentSessions;
        final childName = context.watch<ChildProvider>().profile?.displayName;

        if (sessions.isEmpty) {
          return AppCard(
            child: Center(
              child: Padding(
                padding: AppSpacing.paddingMd,
                child: Column(
                  children: [
                    Icon(
                      Icons.history_rounded,
                      size: 36,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      childName == null
                          ? 'No activity yet'
                          : 'No activity for $childName yet',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Start a pre-assessment or enter child mode to begin!',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Recent Activity',
                style: AppTextStyles.titleMedium.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              ...sessions.take(5).map((session) {
                final gameName = session.gameId.replaceAll('_', ' ');
                final time = _formatDuration(session.duration);
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppColors.lavenderLight,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.games_rounded,
                          size: 18,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              gameName[0].toUpperCase() + gameName.substring(1),
                              style: AppTextStyles.labelLarge.copyWith(
                                color: AppColors.textPrimary,
                              ),
                            ),
                            Text(
                              '${session.score}/${session.totalItems} correct · $time',
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        _formatDate(session.endedAt),
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  String _formatDuration(Duration d) {
    if (d.inMinutes > 0) {
      return '${d.inMinutes}m ${d.inSeconds % 60}s';
    }
    return '${d.inSeconds}s';
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

// ── Supporting Widgets ────────────────────────────────────────────────

/// A card body that pairs a message with a call-to-action button. Side by
/// side when the card is wide enough; on a portrait phone the button drops
/// below the text at full width instead of squeezing it to nothing.
class _CtaBand extends StatelessWidget {
  const _CtaBand({
    required this.leading,
    required this.content,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final Widget leading;
  final Widget content;
  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  /// Comfortable width for a CTA beside a message — a short label like
  /// "Upgrade" still reads as a proper button rather than a chip.
  static const double _preferredButtonWidth = 190;

  /// Below this the message stops being readable, so the CTA moves under
  /// it instead of taking more width.
  static const double _minMessageWidth = 220;

  @override
  Widget build(BuildContext context) {
    // What the label itself demands, before any layout preference.
    final labelMin = AppPrimaryButton.minWidthFor(
      context,
      label: label,
      icon: icon,
    );
    final textScale =
        (MediaQuery.maybeOf(context)?.textScaler ?? TextScaler.noScaling).scale(
          14,
        ) /
        14;
    final messageMin = _minMessageWidth * textScale;

    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = AppSpacing.sm;
        // Side by side only when the message *and* the CTA each keep a
        // readable width. The old `buttonWidth * 2.6` rule ignored what the
        // label needed and clipped "Upgrade" to "Upgr…".
        final stacked = constraints.maxWidth < messageMin + gap + labelMin;
        final buttonWidth =
            stacked
                ? null
                : math.max(
                  labelMin,
                  math.min(
                    _preferredButtonWidth,
                    constraints.maxWidth - messageMin - gap,
                  ),
                );
        final button = AppPrimaryButton(
          label: label,
          icon: icon,
          width: buttonWidth,
          onPressed: onPressed,
        );
        final message = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            leading,
            const SizedBox(width: AppSpacing.md),
            Expanded(child: content),
          ],
        );

        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [message, const SizedBox(height: gap), button],
          );
        }

        return Row(
          children: [
            Expanded(child: message),
            const SizedBox(width: gap),
            button,
          ],
        );
      },
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    super.key,
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  /// Horizontal padding, leading circle, and the gap after it — what a card
  /// spends before its label gets any width.
  static const double _chrome = AppSpacing.lg * 2 + 44 + AppSpacing.sm;

  /// Width the widest of [labels] needs beside the card's icon, allowing it
  /// two lines, at the ambient text scale.
  static double minWidthFor(
    BuildContext context, {
    required List<String> labels,
  }) {
    var widest = 0.0;
    for (final label in labels) {
      widest = math.max(
        widest,
        minWidthToFitLines(
          context,
          text: label,
          style: AppTextStyles.titleMedium,
          maxLines: 2,
        ),
      );
    }
    return widest + _chrome;
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.white.withAlpha(230),
      borderRadius: AppRadius.card,
      child: InkWell(
        borderRadius: AppRadius.card,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            borderRadius: AppRadius.card,
            border: Border.all(color: color.withAlpha(80)),
            boxShadow: AppShadows.card,
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withAlpha(40),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // The action's name is a CTA label: it wraps rather than
                    // ellipsising, so "Therapy Directory" reads in full in a
                    // narrow column.
                    Text(
                      label,
                      style: AppTextStyles.titleMedium.copyWith(
                        color: AppColors.textPrimary,
                      ),
                      softWrap: true,
                      maxLines: 2,
                    ),
                    Text(
                      subtitle,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                      softWrap: true,
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
