import 'package:shared_ui/shared_ui.dart';
import 'round_policy.dart';

/// Shared game configuration used by all Aumazing mini-games.
///
/// Controls difficulty, feedback behaviour, animation intensity,
/// and audio levels. Both main_app and game_lab can pass a [GameConfig]
/// to any Flame game to customise the play experience.
class GameConfig {
  /// Difficulty level: 1 (easiest) to 3 (hardest).
  final int difficulty;

  /// How many times a prompt is repeated before advancing. (1–5)
  final int promptRepetition;

  /// Animation intensity multiplier: 0.0 (no animations) to 1.0 (full).
  /// ASD-friendly: allows caregivers to reduce visual stimulation.
  final double animationIntensity;

  /// Background music volume: 0.0 (muted) to 1.0 (full).
  final double bgMusicVolume;

  /// Sound-effect volume: 0.0 (muted) to 1.0 (full).
  final double sfxVolume;

  /// Unique identifier for the child playing (for analytics).
  final String childId;

  /// Optional game version string (for analytics).
  final String? gameVersion;

  /// Selected in-game language for on-screen labels (en / tl / ceb).
  final GameLanguage language;

  const GameConfig({
    this.difficulty = 1,
    this.promptRepetition = 1,
    this.animationIntensity = 1.0,
    this.bgMusicVolume = 0.5,
    this.sfxVolume = 0.7,
    this.childId = 'anonymous',
    this.gameVersion,
    this.language = GameLanguage.english,
  });

  /// Localized strings for the configured [language].
  AppStrings get strings => AppStrings(language);

  /// Default config suitable for first-time players.
  static const GameConfig defaults = GameConfig();

  GameConfig copyWith({
    int? difficulty,
    int? promptRepetition,
    double? animationIntensity,
    double? bgMusicVolume,
    double? sfxVolume,
    String? childId,
    String? gameVersion,
    GameLanguage? language,
  }) {
    return GameConfig(
      difficulty: difficulty ?? this.difficulty,
      promptRepetition: promptRepetition ?? this.promptRepetition,
      animationIntensity: animationIntensity ?? this.animationIntensity,
      bgMusicVolume: bgMusicVolume ?? this.bgMusicVolume,
      sfxVolume: sfxVolume ?? this.sfxVolume,
      childId: childId ?? this.childId,
      gameVersion: gameVersion ?? this.gameVersion,
      language: language ?? this.language,
    );
  }

  /// Number of rounds per game — standard three-round format (Card AUM-305).
  /// Pre-assessment adds a sensory round; see [GameRoundPolicy].
  int get totalRounds => GameRoundPolicy.standardRoundCount;

  /// Number of items per round based on difficulty.
  int get itemsPerRound {
    switch (difficulty) {
      case 1:
        return 3;
      case 2:
        return 3;
      case 3:
        return 4;
      default:
        return 3;
    }
  }

  @override
  String toString() => 'GameConfig('
      'difficulty: $difficulty, '
      'promptRepetition: $promptRepetition, '
      'animationIntensity: ${animationIntensity.toStringAsFixed(1)}, '
      'bgMusic: ${bgMusicVolume.toStringAsFixed(1)}, '
      'sfx: ${sfxVolume.toStringAsFixed(1)}, '
      'childId: $childId, '
      'gameVersion: $gameVersion)';
}
