import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_audio/shared_audio.dart';
import 'package:shared_haptic/shared_haptic.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config/supabase_config.dart';
import 'core/services/db_web_factory.dart';
import 'core/offline_first_integration.dart';
import 'dev/developer_tools_overlay.dart';
import 'features/parent_lock/parent_pin_delegate.dart';
import 'features/splash/splash_screen.dart';
import 'providers/assessment_provider.dart';
import 'providers/child_provider.dart';
import 'providers/progress_provider.dart';
import 'providers/stars_provider.dart';
import 'services/entitlement_service.dart';
import 'services/parent_pin_service.dart';
import 'services/rubric/rubric_threshold_service.dart';

/// True for transient network failures (offline, DNS, unreachable host) —
/// expected in an offline-first app and never worth an unhandled-crash dump.
bool _isTransientNetworkError(Object error) {
  if (error is AuthRetryableFetchException) return true;
  final text = error.toString();
  return text.contains('SocketException') ||
      text.contains('Failed host lookup') ||
      text.contains('Connection refused') ||
      text.contains('Network is unreachable') ||
      text.contains('Connection reset') ||
      text.contains('Connection timed out');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Install the platform's sqflite factory. No-op on mobile/desktop; on the web
  // it swaps in the WASM-backed factory so the offline-first local database
  // works in the browser. Must run before any LocalDbService access below.
  initPlatformDatabaseFactory();

  // Offline-first: transient network errors from background work (token
  // refresh, sync retries) are expected while offline. Log one quiet line
  // instead of an unhandled-exception dump; let real errors through.
  PlatformDispatcher.instance.onError = (error, stack) {
    if (_isTransientNetworkError(error)) {
      debugPrint(
        '[Offline] Suppressed transient network error: '
        '${error.runtimeType}',
      );
      return true; // handled
    }
    return false; // let the default handler report it
  };

  // Phones are portrait on parent screens; tablets are landscape-only. Games
  // re-lock landscape themselves when entered.
  //
  // Ask the platform for the device size first: the Flutter window can already
  // be letterboxed at this point, and classifying from it would lock a tablet
  // into the portrait strip that caused the letterboxing.
  await initializeDeviceFormFactor();
  lockParentAdaptive();

  // Enable fullscreen mode to hide mobile header/status bar
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  // Credentials are injected at build time; fail fast with a clear message
  // instead of an opaque Supabase error when the define file is missing.
  assert(
    SupabaseConfig.isConfigured,
    'Missing backend config. Run with '
    '--dart-define-from-file=env/dev.json '
    '(copy env/dev.example.json and fill in the values).',
  );

  await Supabase.initialize(
    url: SupabaseConfig.supabaseUrl,
    anonKey: SupabaseConfig.supabaseAnonKey,
  );

  // Initialize offline-first services (guest mode, connectivity monitoring, sync)
  await OfflineFirstIntegration.initialize();

  // Premium entitlement: cached state loads immediately, backend refresh
  // and auth-change reloads happen in the background (never blocks launch).
  EntitlementService.instance.init();

  // Admin-configured rubric thresholds: cache-first with hardcoded
  // defaults, so scoring works offline; refreshed in the background.
  RubricThresholdService.instance.load();

  // Parent lock: load the account's PIN state (and follow account changes),
  // then install the delegate so every ParentVerificationDialog call site
  // picks the right challenge without knowing which one is configured.
  ParentPinService.instance.init();
  ParentVerificationDialog.pinDelegate = const AppParentPinDelegate();

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  /// Shared audio service for UI sound effects (button taps, etc.).
  late final AudioService _audioService;

  /// Shared haptic service for game feedback (correct match vibrations, etc.).
  late final HapticService _hapticService;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _audioService = AudioService();
    _hapticService = HapticService();
  }

  /// Pause music when the app goes to background, resume when it returns.
  ///
  /// Blurring the app also mutes every live narrator through
  /// [VoiceOverService.stopAll]: voice-over instances are per-screen and not
  /// lifecycle-observed. Narration is contextual — screens re-trigger it on
  /// interaction — so it stops rather than pauses and never auto-resumes.
  ///
  /// [resumeMusic] already checks [AudioConfig.musicEnabled] internally,
  /// so music will only resume if the user hasn't disabled it in settings.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _audioService.pauseMusic();
      VoiceOverService.stopAll();
    } else if (state == AppLifecycleState.resumed) {
      // resumeMusic() checks _config.musicEnabled — if the user turned
      // music off in settings and we properly synced AudioConfig, this
      // will be a no-op.
      _audioService.resumeMusic();
      // Re-enable fullscreen mode when app resumes
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _audioService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ChildProvider()),
        ChangeNotifierProvider(create: (_) => AssessmentProvider()),
        ChangeNotifierProvider(create: (_) => ProgressProvider()),
        ChangeNotifierProvider(create: (_) => StarsProvider()),
      ],
      child: Provider<AudioService>.value(
        value: _audioService,
        child: Provider<HapticService>.value(
          value: _hapticService,
          child: UiTapSfxProvider(
            onTap: _audioService.playButtonTap,
            child: RewardSfxProvider(
              onBalloonPop: _audioService.playBalloonPopSfx,
              onBubblePop: _audioService.playBubblePopSfx,
              onFireworkPop: _audioService.playFireworkPopSfx,
              onCandyPop: _audioService.playCandyPopSfx,
              onStarPop: _audioService.playStarPopSfx,
              onTrophyPop: _audioService.playTrophyPopSfx,
              child: MaterialApp(
                title: 'Aumazing',
                debugShowCheckedModeBanner: false,
                theme: AppTheme.light,
                // Both are inert in a normal build: the key is null and the
                // builder returns the navigator untouched, so nothing extra
                // enters the tree. See DeveloperToolsConfig.
                navigatorKey: DeveloperToolsOverlay.navigatorKey,
                builder: DeveloperToolsOverlay.wrap,
                home: const AumazingSplashScreen(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
