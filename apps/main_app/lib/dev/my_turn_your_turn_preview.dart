// Developer preview for My Turn, Your Turn (AUM-365 turn cues).
//
// The real screen only opens from a signed-in child's practice lobby or an
// assessment run, which makes checking the turn cues slow. This entrypoint
// opens the *real* MyTurnYourTurnScreen for a fixed sample child, with a
// launcher to compare practice on each difficulty against assessment play
// (which must show none of the cues), in each language.
//
//   flutter run -d chrome -t lib/dev/my_turn_your_turn_preview.dart
//   flutter run -d windows -t lib/dev/my_turn_your_turn_preview.dart
//
// The Supabase client points at a dead local address, so nothing here can
// read or write live data; finishing a game logs a failed session write,
// which the screen already tolerates.
//
// Not shipped: nothing in lib/features imports this file.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show DeviceOrientation, SystemChrome;
import 'package:provider/provider.dart';
import 'package:shared_audio/shared_audio.dart';
import 'package:shared_haptic/shared_haptic.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/games/my_turn_your_turn/my_turn_your_turn_screen.dart';
import '../model/child_profile.dart';
import '../providers/child_provider.dart';
import '../widgets/mascot_host.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // ChildProvider's auth service needs a client to exist; this one has no
  // server behind it.
  await Supabase.initialize(
    url: 'http://127.0.0.1:9',
    publishableKey: 'preview-only',
  );
  // Child mode is landscape everywhere, and the board is laid out for it.
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const _PreviewApp());
}

class _PreviewApp extends StatefulWidget {
  const _PreviewApp();

  @override
  State<_PreviewApp> createState() => _PreviewAppState();
}

class _PreviewAppState extends State<_PreviewApp> {
  final _audio = AudioService();
  final _haptic = HapticService();

  @override
  void dispose() {
    _audio.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ChildProvider>(
      create: (_) => _PreviewChildProvider(),
      child: Provider<AudioService>.value(
        value: _audio,
        child: Provider<HapticService>.value(
          value: _haptic,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            home: const _Launcher(),
          ),
        ),
      ),
    );
  }
}

/// A fixed sample child; nothing is loaded or saved.
class _PreviewChildProvider extends ChildProvider {
  @override
  ChildProfile? get profile => _sampleChild;

  @override
  Future<void> loadProfile() async {}
}

final _sampleChild = ChildProfile(
  id: 'preview-child',
  userId: 'preview-parent',
  displayName: 'Mika',
  birthDate: DateTime(2022, 4, 20),
  avatar: 'avatar_2', // the panda
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

class _Launcher extends StatelessWidget {
  const _Launcher();

  void _open(BuildContext context, String assessmentContext, int difficulty) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => MascotHost(
              showMascot: false, // My Turn Your Turn draws its own buddy.
              child: MyTurnYourTurnScreen(
                assessmentContext: assessmentContext,
                difficulty: difficulty,
              ),
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final child = context.watch<ChildProvider>();
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: AppSpacing.paddingLg,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('My Turn, Your Turn preview',
                    style: AppTextStyles.headlineSmall),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.xs,
                  children: [
                    for (final language in GameLanguage.values)
                      ChoiceChip(
                        label: Text(language.label),
                        selected: child.language == language,
                        onSelected: (_) => child.setLanguage(language),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final (label, level) in const [
                      ('Practice · Easy', 1),
                      ('Practice · Medium', 2),
                      ('Practice · Hard', 3),
                    ])
                      FilledButton(
                        key: Key('preview.practice.$level'),
                        onPressed: () => _open(context, 'practice', level),
                        child: Text(label),
                      ),
                    OutlinedButton(
                      key: const Key('preview.assessment'),
                      onPressed: () => _open(context, 'pre_assessment', 2),
                      child: const Text('Assessment (no cues)'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
