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
export 'src/games/shared/answer_label.dart';
export 'src/games/shared/ghost_hand.dart';
// Exported so the parent-facing settings previews can draw object cards
// with the same code the games use, rather than a copy that drifts.
export 'src/games/shared/shape_painter_3d.dart';

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

// Games — Hintay! (Wait For It)
export 'src/games/hintay/hintay_game.dart';
export 'src/games/hintay/components/sleepy_star.dart';

// Games — Ano'ng Susunod? (What's Next?)
export 'src/games/anong_susunod/anong_susunod_game.dart';
export 'src/games/anong_susunod/routine_steps.dart';
export 'src/games/anong_susunod/routine_art_cache.dart';
export 'src/games/anong_susunod/components/routine_card.dart';
export 'src/games/anong_susunod/components/sequence_slot.dart';

// Games — Sabay Tayo! (joint attention)
export 'src/games/sabay_tayo/sabay_tayo_game.dart';
export 'src/games/sabay_tayo/components/attention_object.dart';
export 'src/games/sabay_tayo/components/buddy_character.dart';
export 'src/games/sabay_tayo/components/buddy_art_cache.dart';

// Analytics - Full XGBoost-Ready Analytics System
export 'src/analytics/analytics.dart';

// Registry
export 'src/registry/game_registry.dart';
export 'src/registry/skill_category.dart';
