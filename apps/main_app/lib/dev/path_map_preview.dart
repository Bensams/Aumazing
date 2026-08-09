// Developer preview for the "My Path" level map.
//
// The real screen only renders once a child has a completed assessment (the
// learning path is built from the AI prediction), which makes eyeballing a
// visual change expensive. This entrypoint renders the *real* PathMapView and
// WorldBackdrop against a fixed sample path so the scene can be checked
// directly.
//
//   flutter run -d windows -t lib/dev/path_map_preview.dart --dart-define=WORLD=night
//   flutter run -d windows -t lib/dev/path_map_preview.dart --dart-define=WORLD=classic
//
// Not shipped: nothing in lib/features imports this file.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show DeviceOrientation, SystemChrome;

import 'package:game_core/game_core.dart';
import 'package:shared_ui/shared_ui.dart';

import '../features/child_mode/path_map_view.dart';
import '../services/learning_path_service.dart';

const _worldFlag = String.fromEnvironment('WORLD', defaultValue: 'night');

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Child mode is landscape everywhere, and the map is laid out for it.
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const _PreviewApp());
}

class _PreviewApp extends StatelessWidget {
  const _PreviewApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: const _PreviewScreen(),
    );
  }
}

class _PreviewScreen extends StatelessWidget {
  const _PreviewScreen();

  /// Six real registry games, so the per-game gradients and icons on the
  /// platforms are the ones the child would actually see.
  List<LearningPathEntry> get _path {
    const ids = [
      'match_it',
      'copy_me',
      'do_what_i_say',
      'trace_it',
      'sari_sari_sort',
      'my_turn_your_turn',
    ];
    final entries = <LearningPathEntry>[];
    for (var i = 0; i < ids.length; i++) {
      final game = GameRegistry.find(ids[i]);
      if (game == null) continue;
      entries.add(LearningPathEntry(
        game: game,
        difficulty: (i % 3) + 1,
        areaKey: 'play',
      ));
    }
    return entries;
  }

  @override
  Widget build(BuildContext context) {
    final world = _worldFlag == 'classic'
        ? WorldStyles.classic
        : WorldStyles.nightSky;
    final path = _path;
    // Two done, so the trail shows both a travelled and an ahead stretch and
    // step 3 is the current one.
    final completed = {path[0].game.id, path[1].game.id};
    final showScene = world.hasBackdrop;

    return Scaffold(
      body: Container(
        decoration: showScene
            ? null
            : const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFFA9E3CC),
                    Color(0xFFABD2F0),
                    Color(0xFFC7B4EC),
                  ],
                ),
              ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (showScene) WorldBackdrop(style: world),
            SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(),
                  Expanded(
                    child: PathMapView(
                      path: path,
                      completedGameIds: completed,
                      difficultyOverride: null,
                      style: world,
                      currentStepKey: GlobalKey(),
                      onLaunch: (_, __) {},
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Mirrors the lobby header so its readability against the scene can be
  /// judged from the same screenshot.
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.sm),
      child: Row(
        children: [
          Material(
            color: AppColors.white.withAlpha(200),
            shape: const CircleBorder(),
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: Icon(Icons.arrow_back_rounded,
                  color: AppColors.primaryPurple),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.white.withAlpha(235),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'My Path',
                  style: AppTextStyles.displayMedium.copyWith(
                    color: AppColors.primaryPurple,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primaryPurple.withAlpha(30),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'Level 2',
                    style: AppTextStyles.labelSmall.copyWith(
                      color: AppColors.primaryPurple,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
