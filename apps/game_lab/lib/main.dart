import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import 'screens/launcher_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
