import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_ui/shared_ui.dart';

import 'screens/launcher_screen.dart';
import 'services/game_lab_services.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // Initialize shared audio services at app level
  GameLabServices.instance.initialize();

  runApp(const GameLabApp());
}

class GameLabApp extends StatefulWidget {
  const GameLabApp({super.key});

  @override
  State<GameLabApp> createState() => _GameLabAppState();
}

class _GameLabAppState extends State<GameLabApp> {
  @override
  void dispose() {
    GameLabServices.instance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final audio = GameLabServices.instance.audioService;
    return RewardSfxProvider(
      onBalloonPop: audio.playBalloonPopSfx,
      onBubblePop: audio.playBubblePopSfx,
      onFireworkPop: audio.playFireworkPopSfx,
      onCandyPop: audio.playCandyPopSfx,
      child: MaterialApp(
        title: 'Aumazing Game Lab',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: const LauncherScreen(),
      ),
    );
  }
}
