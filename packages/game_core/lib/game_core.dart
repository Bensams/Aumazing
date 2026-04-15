/// Game core package for the Aumazing app ecosystem.
///
/// Contains all Flame game logic, game configuration, and the game
/// registry. Shared by both main_app and game_lab.
library game_core;

// Configuration
export 'src/config/game_config.dart';

// Games
export 'src/games/match_it/match_it_game.dart';
export 'src/games/match_it/components/matchable_shape.dart';

// Registry
export 'src/registry/game_registry.dart';
