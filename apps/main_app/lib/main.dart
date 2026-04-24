import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_audio/shared_audio.dart';
import 'package:shared_haptic/shared_haptic.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config/supabase_config.dart';
import 'core/offline_first_integration.dart';
import 'features/splash/splash_screen.dart';
import 'providers/assessment_provider.dart';
import 'providers/child_provider.dart';
import 'providers/progress_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Force landscape orientation globally
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // Enable fullscreen mode to hide mobile header/status bar
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  await Supabase.initialize(
    url: SupabaseConfig.supabaseUrl,
    anonKey: SupabaseConfig.supabaseAnonKey,
  );

  // Initialize offline-first services (guest mode, connectivity monitoring, sync)
  await OfflineFirstIntegration.initialize();

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
  /// [resumeMusic] already checks [AudioConfig.musicEnabled] internally,
  /// so music will only resume if the user hasn't disabled it in settings.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _audioService.pauseMusic();
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
              child: MaterialApp(
                title: 'Aumazing',
                debugShowCheckedModeBanner: false,
                theme: AppTheme.light,
                home: const AumazingSplashScreen(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

