/// Game core package for the Aumazing app ecosystem.
///
/// Contains all Flame game logic, game configuration, and the game
/// registry. Shared by both main_app and game_lab.
library game_core;

// Configuration
export 'src/config/adaptive_difficulty.dart';
export 'src/config/difficulty_profile.dart';
export 'src/config/game_config.dart';
export 'src/config/game_motion.dart';

// Shared game components
export 'src/games/shared/ghost_hand.dart';

// Games — Match It
export 'src/games/match_it/match_it_game.dart';
export 'src/games/match_it/components/matchable_shape.dart';

// Games — Copy Me
export 'src/games/copy_me/copy_me_game.dart';
export 'src/games/copy_me/components/sequence_shape.dart';

// Games — Do What I Say
export 'src/games/do_what_i_say/do_what_i_say_game.dart';
export 'src/games/do_what_i_say/components/instruction_shape.dart';

// Games — My Turn Your Turn
export 'src/games/my_turn_your_turn/my_turn_your_turn_game.dart';
export 'src/games/my_turn_your_turn/components/turn_slot.dart';

// Games — Sari-Sari Store Sorting
export 'src/games/sari_sari_sort/sari_sari_sort_game.dart';
export 'src/games/sari_sari_sort/components/draggable_item.dart';
export 'src/games/sari_sari_sort/components/category_bin.dart';

// Games — Trace It
export 'src/games/trace_it/trace_it_game.dart';
export 'src/games/trace_it/trace_glyphs.dart';

// Analytics - Full XGBoost-Ready Analytics System
export 'src/analytics/analytics.dart';

// Registry
export 'src/registry/game_registry.dart';
export 'src/registry/skill_category.dart';
