import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_audio/shared_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:video_player/video_player.dart';

import '../../core/services/auth_service.dart';
import '../../core/services/child_bootstrap_service.dart';
import '../../core/services/connectivity_service.dart';
import '../../core/services/local_db_service.dart';
import '../../core/services/supabase_service.dart';
import '../../providers/child_provider.dart';
import '../../services/tour_service.dart';
import '../home/home_screen.dart';
import 'auth/child_profile_setup_screen.dart';
import 'auth/login_screen.dart';

/// Where a completed launch (splash → asset preload → bootstrap) should land.
enum AppLaunchTarget {
  /// Authentication / the mandatory Data Privacy Notice.
  login,

  /// First-run child profile creation.
  childProfileSetup,

  /// The parent dashboard, shown on top (first login / onboarding).
  parentHome,

  /// A returning authenticated user, dropped into child/game mode with the
  /// dashboard mounted underneath as the PIN-protected parent base.
  childMode,
}

/// Pure launch-routing decision, split out from navigation so every session
/// and account edge (restore, restart, expiry, logout/login, multi-account)
/// is unit-testable without pumping the loading screen.
///
/// [sessionExpired] and a missing privacy consent both fail closed to
/// [AppLaunchTarget.login]. Only a fully set-up account ([BootstrapDestination.home])
/// that has already seen the parent dashboard tour — i.e. is past first-time
/// registration/login — opens directly in child mode; everyone else keeps
/// their existing destination so onboarding and first login are preserved.
AppLaunchTarget resolveLaunchTarget({
  required BootstrapDestination destination,
  required bool sessionExpired,
  required bool hasConsent,
  required bool hasSeenParentTour,
}) {
  if (sessionExpired || !hasConsent) return AppLaunchTarget.login;
  switch (destination) {
    case BootstrapDestination.login:
      return AppLaunchTarget.login;
    case BootstrapDestination.childProfileSetup:
      return AppLaunchTarget.childProfileSetup;
    case BootstrapDestination.home:
      return hasSeenParentTour
          ? AppLaunchTarget.childMode
          : AppLaunchTarget.parentHome;
  }
}

/// Whether a launch to [target] has a child whose artwork is worth decoding
/// before the first frame (AUM-329).
///
/// Only the two destinations that render a mascot do. Authentication and
/// first-run setup have no active child at all, and making them wait on a
/// profile lookup would slow the one path where nothing is gained — the
/// parent who is signing in has no companion to meet yet.
///
/// Pure and public for the same reason [resolveLaunchTarget] is: the rule is
/// worth stating once and testing without pumping a video player.
bool launchWarmsChildArt(AppLaunchTarget target) => switch (target) {
  AppLaunchTarget.login || AppLaunchTarget.childProfileSetup => false,
  AppLaunchTarget.parentHome || AppLaunchTarget.childMode => true,
};

/// Where a launch lands, and what to tell the parent when it gets there.
///
/// [errorMessage] only ever accompanies [AppLaunchTarget.childProfileSetup] —
/// it is bootstrap's explanation for sending them back to setup.
class _LaunchPlan {
  const _LaunchPlan({required this.target, this.errorMessage});

  final AppLaunchTarget target;
  final String? errorMessage;
}

/// Loading screen with video background and real assets loading progress.
///
/// Pre-loads and initializes:
/// - Background video
/// - Audio files (the default background-music category, ui_tap.wav)
/// - Other critical assets
class LoadingScreen extends StatefulWidget {
  const LoadingScreen({
    super.key,
    ChildBootstrapService? bootstrapService,
    AuthService? authService,
  }) : _bootstrapService = bootstrapService,
       _authService = authService;

  final ChildBootstrapService? _bootstrapService;
  final AuthService? _authService;

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen> {
  late final AuthService _authService;
  late final ChildBootstrapService _bootstrapService;
  VideoPlayerController? _videoController;
  bool _videoInitialized = false;

  double _progress = 0.0;
  String _status = 'Preparing...';

  /// How long the launch may wait on the child's profile and artwork.
  ///
  /// Generous enough that a mid-range phone finishes its 21 sheets inside it,
  /// short enough that a device having a bad day is not held at the progress
  /// bar. Whichever way it goes the app opens; only the first frame of the
  /// mascot differs.
  static const _artWarmBudget = Duration(seconds: 5);

  /// Warmed before the first note plays, so the opening track never stutters.
  ///
  /// The child's profile is not loaded yet at this point, so this screen plays
  /// the default category — and every track in it is a candidate for the
  /// random pick, so all of them are pre-cached.
  final List<String> _assetsToPreload = [
    for (final track in bgmCategoryOrDefault(kDefaultBgmCategory).tracks)
      'packages/shared_audio/assets/audio/'
          '${bgmCategoryOrDefault(kDefaultBgmCategory).trackPath(track)}',
    'packages/shared_audio/assets/audio/ui_tap.wav',
  ];


  @override
  void initState() {
    super.initState();
    _authService = widget._authService ?? AuthService();
    _bootstrapService =
        widget._bootstrapService ??
        ChildBootstrapService(
          authService: _authService,
          connectivityService: connectivityService,
          supabaseService: supabaseService,
          localDbService: localDbService,
        );

    // Same orientation as the splash before it and the parent screen after,
    // so launching on a phone never rotates mid-flow.
    lockParentAdaptive();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _initLoading();
  }

  Future<void> _initLoading() async {
    // Start video initialization
    _initVideo();

    // Start the launch decision immediately rather than after the media is
    // ready (AUM-329). It is the only step that touches the network, and until
    // it answers nothing downstream knows *which* child is launching — so the
    // character's sheets could not begin decoding until the lobby was already
    // on screen. Running it alongside the preload puts the wait somewhere the
    // progress bar is already covering.
    final launchPlan = _resolveLaunch();

    // Pre-load audio assets
    await _preloadAssets();

    // Initialize audio service
    await _initAudio();

    // Ensure video is ready
    await _waitForVideo();

    final plan = await launchPlan;
    if (!mounted) return;

    await _warmActiveChildArt(plan.target);
    if (!mounted) return;

    _navigateTo(plan);
  }

  Future<void> _initVideo() async {
    // Lower graphics tiers: skip the video (release _waitForVideo) and keep
    // the static gradient background.
    if (await ChildProvider.readUseStaticBackground()) {
      if (mounted) setState(() => _videoInitialized = true);
      return;
    }

    final videoPaths = [
      'assets/videos/login_page_bg.mp4',
      'assets/videos/login_page_bg.webm',
    ];

    for (final path in videoPaths) {
      try {
        // Use mixWithOthers so video doesn't request audio focus and pause music
        final controller = VideoPlayerController.asset(
          path,
          videoPlayerOptions: VideoPlayerOptions(
            mixWithOthers: true,
            allowBackgroundPlayback: false,
          ),
        );
        await controller.setLooping(true);
        await controller.setVolume(0);
        await controller.initialize();

        if (mounted) {
          setState(() {
            _videoController = controller;
            _videoInitialized = true;
          });
          controller.play();
          return;
        }
      } catch (_) {
        continue;
      }
    }
  }

  Future<void> _preloadAssets() async {
    final totalAssets = _assetsToPreload.length;

    for (var i = 0; i < totalAssets; i++) {
      final asset = _assetsToPreload[i];
      setState(() {
        _status = 'Loading audio... (${i + 1}/$totalAssets)';
        _progress = (i + 1) / (totalAssets + 2); // +2 for audio init and video wait
      });

      try {
        // Pre-cache the asset in memory
        await rootBundle.load(asset);
        debugPrint('[LoadingScreen] Preloaded: $asset');
      } catch (e) {
        debugPrint('[LoadingScreen] Failed to preload $asset: $e');
      }
      // No pause between assets any more (AUM-329). It existed to keep the bar
      // moving when there was nothing else to do; the launch decision and the
      // character warm now fill that time with work the child can feel.
    }
  }

  Future<void> _initAudio() async {
    setState(() {
      _status = 'Initializing audio...';
      _progress = (_assetsToPreload.length + 1) / (_assetsToPreload.length + 2);
    });

    final audioService = context.read<AudioService>();
    debugPrint('[LoadingScreen] AudioService config: musicEnabled=${audioService.config.musicEnabled}, volume=${audioService.config.musicVolume}');

    // Wait a moment for AudioPlayer to fully initialize
    await Future.delayed(const Duration(milliseconds: 500));

    // Start music playing - it will continue through to LoginScreen
    try {
      debugPrint('[LoadingScreen] Starting music...');
      // No profile yet — the default category plays until HomeScreen loads the
      // child's own choice and switches if it differs.
      await audioService.playCategoryMusic(kDefaultBgmCategory);
      debugPrint('[LoadingScreen] Music started, will continue to LoginScreen');
    } catch (e, stackTrace) {
      debugPrint('[LoadingScreen] ✖ Music start error: $e');
      debugPrint('[LoadingScreen] Stack: $stackTrace');
    }

    await Future.delayed(const Duration(milliseconds: 300));
  }

  Future<void> _waitForVideo() async {
    setState(() {
      _status = 'Finalizing...';
      _progress = 1.0;
    });

    // Wait for video to be ready
    while (!_videoInitialized && mounted) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  /// Gets the launching child's outfit decoding before the lobby is built
  /// (AUM-329).
  ///
  /// [ChildProvider.loadProfile] resolves the active child and every per-child
  /// preference, and its own warm is fire-and-forget — right for a child
  /// switch, which must not stall on artwork, but it means a cold start hands
  /// off with 21 sheets still being sliced and the mascot showing its fallback
  /// until they land. Here the wait is worth having: the progress bar is
  /// already up, and this is the difference between a child meeting their own
  /// companion and meeting a placeholder.
  ///
  /// Bounded and best-effort throughout. A target with no child skips it
  /// outright rather than making the login path pay for a profile nobody
  /// asked for; a slow decode gives up at [_artWarmBudget] and lets the app
  /// through, because arriving with the fallback beats not arriving.
  Future<void> _warmActiveChildArt(AppLaunchTarget target) async {
    if (!launchWarmsChildArt(target)) return;

    final childProvider = context.read<ChildProvider>();
    setState(() {
      _status = 'Waking up your buddy...';
      _progress = 1.0;
    });

    try {
      await childProvider.loadProfile().timeout(_artWarmBudget);
      final profile = childProvider.profile;
      if (profile == null) return;
      await CharacterSprites.precacheCostumed(
        profile.characterId,
        profile.equippedCostume,
      ).timeout(_artWarmBudget);
    } catch (e) {
      // Includes the timeout. Warming is an optimisation; the mascot still
      // renders, just a moment later, and that must never cost a launch.
      debugPrint('[LoadingScreen] character warm skipped: $e');
    }
  }

  /// Decides where this launch lands, without touching the widget tree.
  ///
  /// Split from the navigation itself (AUM-329) so it can run alongside the
  /// media preload instead of after it. Nothing here reads `context`, which is
  /// what makes it safe to start before the screen has finished building.
  Future<_LaunchPlan> _resolveLaunch() async {
    // The loading screen must never dead-end: if bootstrap (which touches
    // Supabase/auth) throws — bad config, backend down, or an offline cold
    // start — fall back to the login screen instead of hanging on the logo.
    BootstrapResult result;
    try {
      result = await _bootstrapService.bootstrap();
    } catch (e) {
      debugPrint('[LoadingScreen] bootstrap failed, routing to login: $e');
      result = const BootstrapResult(
        destination: BootstrapDestination.login,
      );
    }

    // Never route into the app with a token that has already expired. Supabase
    // normally refreshes sessions, but a stale/offline restore must fail
    // closed and return the parent to authentication.
    final sessionExpired = _authService.isSessionExpired;
    if (sessionExpired) {
      try {
        await _authService.signOut();
      } catch (e) {
        debugPrint('[LoadingScreen] expired-session cleanup failed: $e');
      }
    }

    // First open / fresh install: until the Data Privacy Notice is accepted,
    // always land on the login page (which shows the mandatory notice) so the
    // parent cannot skip straight to child profile setup or home.
    bool hasConsent = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      hasConsent = prefs.getString('privacy_consent_accepted_at') != null;
    } catch (_) {}

    // A returning parent has already been walked through the dashboard once;
    // that is the signal that first-time registration/login is behind them,
    // so their next open drops straight into child/game mode (AUM-306).
    final hasSeenParentTour = await TourService.instance.hasSeenParentTour();

    return _LaunchPlan(
      target: resolveLaunchTarget(
        destination: result.destination,
        sessionExpired: sessionExpired,
        hasConsent: hasConsent,
        hasSeenParentTour: hasSeenParentTour,
      ),
      errorMessage: result.errorMessage,
    );
  }

  void _navigateTo(_LaunchPlan plan) {
    final Widget destination = switch (plan.target) {
      AppLaunchTarget.login => const LoginScreen(),
      AppLaunchTarget.childProfileSetup => ChildProfileSetupScreen(
        initialErrorMessage: plan.errorMessage,
      ),
      AppLaunchTarget.parentHome => const HomeScreen(),
      AppLaunchTarget.childMode => const HomeScreen(openChildMode: true),
    };

    // Use fade transition to avoid audio/video interruptions
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => destination,
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  @override
  void dispose() {
    // Dispose video controller safely
    if (_videoController != null && _videoController!.value.isInitialized) {
      _videoController!.pause();
      _videoController!.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Video background (null controller under reduced motion → gradient)
          if (_videoInitialized && _videoController != null)
            SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _videoController!.value.size.width,
                  height: _videoController!.value.size.height,
                  child: VideoPlayer(_videoController!),
                ),
              ),
            )
          else
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF87CEEB), Color(0xFF98FB98)],
                ),
              ),
            ),

          // Dark overlay for readability
          Container(color: Colors.black.withValues(alpha: 0.4)),

          // Loading UI at bottom
          Positioned(
            left: 0,
            right: 0,
            bottom: 20,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 60),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Status text
                  Text(
                    _status,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Progress bar background
                  Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: _progress,
                        backgroundColor: Colors.transparent,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Color(0xFF9B7EDC),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Percentage text
                  Text(
                    '${(_progress * 100).toInt()}%',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
