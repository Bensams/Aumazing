import 'dart:ui';

import 'package:flame/game.dart';
import 'package:game_core/game_core.dart';
import 'package:shared_audio/shared_audio.dart';

import 'game_lab_services.dart';

/// Creates Flame games with full audio callbacks wired.
///
/// The [GameRegistry]'s `create` factory doesn't expose audio callback
/// parameters, so this factory creates games directly using their
/// constructors while wiring all SFX and voice-over callbacks through
/// [GameLabServices].
class GameLabGameFactory {
  GameLabGameFactory._();

  /// Create a game by its registry ID with all audio callbacks wired.
  ///
  /// Falls back to the registry's `create` method if the game ID is
  /// not recognized (future-proofing for new games).
  static FlameGame createWithAudio({
    required String gameId,
    required GameConfig config,
    required void Function(int currentStep) onStepChanged,
    required void Function({
      required int score,
      required int totalItems,
      required int errorCount,
      required int totalResponseTimeMs,
    }) onGameComplete,
    VoidCallback? onCorrectMatch,
  }) {
    final services = GameLabServices.instance;
    final audio = services.audioService;
    final vo = services.voiceOverService;
    final haptic = services.hapticService;

    // Wrap onCorrectMatch to include haptic feedback
    void wrappedOnCorrectMatch() {
      haptic.correctFeedback();
      onCorrectMatch?.call();
    }

    // Common SFX callbacks
    void playCorrectSfx() {
      audio.playCorrectSfx();
      services.lastPlayedSfx = 'correct';
    }

    void playWrongSfx() {
      audio.playWrongSfx();
      services.lastPlayedSfx = 'wrong';
    }

    void playTapSfx() {
      audio.playGameTapSfx();
      services.lastPlayedSfx = 'game_tap';
    }

    void playDragSfx() {
      audio.playDragSfx();
      services.lastPlayedSfx = 'drag';
    }

    void playDropSfx() {
      audio.playDropSfx();
      services.lastPlayedSfx = 'drop';
    }

    void playLevelCompleteSfx() {
      audio.playLevelCompleteSfx();
      services.lastPlayedSfx = 'level_complete';
    }

    void playGameCompleteSfx() {
      audio.playGameCompleteSfx();
      services.lastPlayedSfx = 'game_complete';
    }

    // Common VO callbacks
    void playCorrectVo() {
      vo.playCorrectPraise();
      services.lastPlayedVo = 'correct_praise (random)';
    }

    void playWrongVo() {
      vo.playWrongEncouragement();
      services.lastPlayedVo = 'wrong_encouragement (random)';
    }

    void playTransitionVo() {
      vo.playTransition();
      services.lastPlayedVo = 'transition (random)';
    }

    void playCelebrationVo() {
      vo.playRewardCelebration();
      services.lastPlayedVo = 'celebration (random)';
    }

    switch (gameId) {
      case 'match_it':
        return MatchItGame(
          totalRounds: config.totalRounds,
          childId: config.childId,
          gameVersion: config.gameVersion,
          onStepChanged: onStepChanged,
          onCorrectMatch: wrappedOnCorrectMatch,
          onGameComplete: ({
            required int score,
            required int totalItems,
            required int errorCount,
            required int totalResponseTimeMs,
            analytics,
          }) {
            onGameComplete(
              score: score,
              totalItems: totalItems,
              errorCount: errorCount,
              totalResponseTimeMs: totalResponseTimeMs,
            );
          },
          // SFX callbacks
          onPlayCorrectSfx: playCorrectSfx,
          onPlayWrongSfx: playWrongSfx,
          onPlayTapSfx: playTapSfx,
          onPlayDragSfx: playDragSfx,
          onPlayDropSfx: playDropSfx,
          onPlayLevelCompleteSfx: playLevelCompleteSfx,
          onPlayGameCompleteSfx: playGameCompleteSfx,
          // VO callbacks
          onPlayCorrectVo: playCorrectVo,
          onPlayWrongVo: playWrongVo,
          onPlayTransitionVo: playTransitionVo,
          onPlayCelebrationVo: playCelebrationVo,
          onPlayInstructionVo: () {
            vo.play(VoiceOverCue.matchIt);
            services.lastPlayedVo = 'matchIt';
          },
        );

      case 'copy_me':
        return CopyMeGame(
          totalRounds: config.totalRounds,
          childId: config.childId,
          gameVersion: config.gameVersion,
          onStepChanged: onStepChanged,
          onCorrectMatch: wrappedOnCorrectMatch,
          onGameComplete: ({
            required int score,
            required int totalItems,
            required int errorCount,
            required int totalResponseTimeMs,
            analytics,
          }) {
            onGameComplete(
              score: score,
              totalItems: totalItems,
              errorCount: errorCount,
              totalResponseTimeMs: totalResponseTimeMs,
            );
          },
          // SFX callbacks
          onPlayCorrectSfx: playCorrectSfx,
          onPlayWrongSfx: playWrongSfx,
          onPlayTapSfx: playTapSfx,
          onPlayDragSfx: playDragSfx,
          onPlayDropSfx: playDropSfx,
          onPlayLevelCompleteSfx: playLevelCompleteSfx,
          onPlayGameCompleteSfx: playGameCompleteSfx,
          // VO callbacks
          onPlayCorrectVo: playCorrectVo,
          onPlayWrongVo: playWrongVo,
          onPlayTransitionVo: playTransitionVo,
          onPlayCelebrationVo: playCelebrationVo,
          onPlayInstructionVo: () {
            vo.play(VoiceOverCue.copyMe);
            services.lastPlayedVo = 'copyMe';
          },
          // Game-specific VO
          onPlayMyTurnVo: () {
            vo.play(VoiceOverCue.watchMeFirst);
            services.lastPlayedVo = 'watchMeFirst';
          },
          onPlayYourTurnVo: () {
            vo.play(VoiceOverCue.nowYouTry);
            services.lastPlayedVo = 'nowYouTry';
          },
          // Sequence highlight shimmer SFX
          onPlaySequenceHighlightSfx: (position) {
            audio.playSequenceShimmerSfx(position);
            services.lastPlayedSfx = 'shimmer_${position + 1}';
          },
        );

      case 'do_what_i_say':
        return DoWhatISayGame(
          totalRounds: config.totalRounds,
          childId: config.childId,
          gameVersion: config.gameVersion,
          onStepChanged: onStepChanged,
          onCorrectMatch: wrappedOnCorrectMatch,
          onInstructionChanged: (_) {},
          onGameComplete: ({
            required int score,
            required int totalItems,
            required int errorCount,
            required int totalResponseTimeMs,
            required Map<String, dynamic> extras,
            analytics,
          }) {
            onGameComplete(
              score: score,
              totalItems: totalItems,
              errorCount: errorCount,
              totalResponseTimeMs: totalResponseTimeMs,
            );
          },
          // SFX callbacks
          onPlayCorrectSfx: playCorrectSfx,
          onPlayWrongSfx: playWrongSfx,
          onPlayTapSfx: playTapSfx,
          onPlayDragSfx: playDragSfx,
          onPlayDropSfx: playDropSfx,
          onPlayLevelCompleteSfx: playLevelCompleteSfx,
          onPlayGameCompleteSfx: playGameCompleteSfx,
          // VO callbacks
          onPlayCorrectVo: playCorrectVo,
          onPlayWrongVo: playWrongVo,
          onPlayTransitionVo: playTransitionVo,
          onPlayCelebrationVo: playCelebrationVo,
          onPlayInstructionVo: () {
            vo.play(VoiceOverCue.listen);
            services.lastPlayedVo = 'listen';
          },
          // Game-specific VO
          onPlayListenVo: () {
            vo.play(VoiceOverCue.listenCarefully);
            services.lastPlayedVo = 'listenCarefully';
          },
          onPlayInstructionVoiceOver: (action, color, shape) {
            final cues = VoiceOverService.composeInstruction(
              action: action,
              color: color,
              shape: shape,
            );
            vo.playSequence(cues);
            services.lastPlayedVo = 'composite: $action $color $shape';
          },
        );

      case 'my_turn_your_turn':
        return MyTurnYourTurnGame(
          totalRounds: config.totalRounds,
          childId: config.childId,
          gameVersion: config.gameVersion,
          onStepChanged: onStepChanged,
          onCorrectMatch: wrappedOnCorrectMatch,
          onTurnChanged: (_) {},
          onGameComplete: ({
            required int score,
            required int totalItems,
            required int errorCount,
            required int totalResponseTimeMs,
            required Map<String, dynamic> extras,
            analytics,
          }) {
            onGameComplete(
              score: score,
              totalItems: totalItems,
              errorCount: errorCount,
              totalResponseTimeMs: totalResponseTimeMs,
            );
          },
          // SFX callbacks
          onPlayCorrectSfx: playCorrectSfx,
          onPlayWrongSfx: playWrongSfx,
          onPlayTapSfx: playTapSfx,
          onPlayDragSfx: playDragSfx,
          onPlayDropSfx: playDropSfx,
          onPlayLevelCompleteSfx: playLevelCompleteSfx,
          onPlayGameCompleteSfx: playGameCompleteSfx,
          // VO callbacks
          onPlayCorrectVo: playCorrectVo,
          onPlayWrongVo: playWrongVo,
          onPlayTransitionVo: playTransitionVo,
          onPlayCelebrationVo: playCelebrationVo,
          onPlayInstructionVo: () {
            vo.play(VoiceOverCue.letsTakeTurns);
            services.lastPlayedVo = 'letsTakeTurns';
          },
          // Game-specific VO
          onPlayMyTurnVo: () {
            vo.play(VoiceOverCue.myTurn);
            services.lastPlayedVo = 'myTurn';
          },
          onPlayYourTurnVo: () {
            vo.play(VoiceOverCue.yourTurn);
            services.lastPlayedVo = 'yourTurn';
          },
          onPlayWaitVo: () {
            vo.play(VoiceOverCue.wait);
            services.lastPlayedVo = 'wait';
          },
        );

      case 'sari_sari_sort':
        return SariSariSortGame(
          totalRounds: config.totalRounds,
          itemsPerRound: config.itemsPerRound,
          childId: config.childId,
          gameVersion: config.gameVersion,
          strings: config.strings,
          onStepChanged: onStepChanged,
          onCorrectDrop: wrappedOnCorrectMatch,
          onGameComplete: ({
            required int score,
            required int totalItems,
            required int errorCount,
            required int totalResponseTimeMs,
            analytics,
          }) {
            onGameComplete(
              score: score,
              totalItems: totalItems,
              errorCount: errorCount,
              totalResponseTimeMs: totalResponseTimeMs,
            );
          },
          // SFX callbacks
          onPlayCorrectSfx: playCorrectSfx,
          onPlayWrongSfx: playWrongSfx,
          onPlayDragSfx: playDragSfx,
          onPlayDropSfx: playDropSfx,
          onPlayLevelCompleteSfx: playLevelCompleteSfx,
          onPlayGameCompleteSfx: playGameCompleteSfx,
          // VO callbacks
          onPlayCorrectVo: playCorrectVo,
          onPlayWrongVo: playWrongVo,
          onPlayTransitionVo: playTransitionVo,
          onPlayCelebrationVo: playCelebrationVo,
          onPlayInstructionVo: () {
            vo.play(VoiceOverCue.matchIt);
            services.lastPlayedVo = 'matchIt';
          },
        );

      default:
        // Fallback: use registry without audio callbacks
        final entry = GameRegistry.find(gameId);
        if (entry != null) {
          return entry.create(
            config: config,
            onStepChanged: onStepChanged,
            onGameComplete: onGameComplete,
          );
        }
        throw ArgumentError('Unknown game ID: $gameId');
    }
  }
}
