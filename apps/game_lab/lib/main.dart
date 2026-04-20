import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_ui/shared_ui.dart';

import 'screens/launcher_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const GameLabApp());
}

class GameLabApp extends StatelessWidget {
  const GameLabApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Aumazing Game Lab',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const LauncherScreen(),
    );
  }
}
