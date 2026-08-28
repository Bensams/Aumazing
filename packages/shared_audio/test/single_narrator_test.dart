import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_audio/shared_audio.dart';

/// Two voices talking over each other, reported when opening a game.
///
/// Each screen builds its own [VoiceOverService], and screens outlive each
/// other: the child-mode lobby is still mounted underneath an open game, so
/// its service is still alive and still owns three audio players. Tapping a
/// game card makes the lobby speak a confirmation, then the game screen's own
/// service speaks the instruction — two narrators, neither able to see the
/// other, both audible.
///
/// There is one narrator in this app. These tests pin that.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final name in const [
      'xyz.luan/audioplayers',
      'xyz.luan/audioplayers.global',
    ]) {
      messenger.setMockMethodCallHandler(MethodChannel(name), (call) async {
        return call.method == 'create' ? null : 1;
      });
    }
  });

  late VoiceOverService lobby;
  late VoiceOverService game;

  setUp(() {
    lobby = VoiceOverService(languageCode: 'en_adult_woman');
    game = VoiceOverService(languageCode: 'en_adult_woman');
  });

  tearDown(() async {
    await lobby.dispose();
    await game.dispose();
  });

  test('a service speaking takes the floor from every other one', () async {
    // The lobby confirms the child's tap...
    await lobby.play(VoiceOverCue.letsBegin);
    expect(game.yieldedCount, 1);

    // ...then the game screen starts its instruction over the top.
    await game.play(VoiceOverCue.matchIt);
    expect(lobby.yieldedCount, 1,
        reason: 'the lobby must yield when the game speaks');
  });

  test('a phrase sequence also takes the floor', () async {
    await game.playAnswerLabel(color: 'teal', shape: 'heart');
    expect(lobby.yieldedCount, greaterThan(0),
        reason: 'a composed phrase must silence other services too');
  });

  test('a disposed service is no longer part of the floor', () async {
    await lobby.dispose();
    final before = lobby.yieldedCount;

    await game.play(VoiceOverCue.matchIt);

    expect(lobby.yieldedCount, before,
        reason: 'a disposed service must not be tracked or touched');
  });

  // The game-launch overlap: the lobby says "Let's go" as the game screen says
  // "Match it". Both are mid-flight, neither is `playing` yet, so scanning for
  // something to silence finds nothing — the loser has to abandon itself.
  test('the later claim wins even while the earlier one is still starting',
      () async {
    // No await between them, exactly as `_launch` fires them.
    final lobbyCue = lobby.play(VoiceOverCue.letsGo);
    final gameCue = game.play(VoiceOverCue.matchIt);
    await Future.wait([lobbyCue, gameCue]);

    expect(game.holdsFloor, isTrue);
    expect(lobby.holdsFloor, isFalse,
        reason: 'the lobby cue must abandon itself rather than surface late');
  });

  test('a sequence yields the floor to a later single cue', () async {
    final phrase = game.playAnswerLabel(color: 'teal', shape: 'heart');
    final interrupt = lobby.play(VoiceOverCue.letsGo);
    await Future.wait([phrase, interrupt]);

    expect(lobby.holdsFloor, isTrue);
    expect(game.holdsFloor, isFalse);
  });

  test('a service does not take the floor from itself', () async {
    await game.play(VoiceOverCue.matchIt);
    expect(game.yieldedCount, 0);
  });
}
