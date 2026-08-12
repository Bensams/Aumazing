import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Service that queries the `learning_modules` Supabase table to determine
/// which games are currently active (enabled by the administrator).
///
/// The active set is cached in memory for the lifetime of the app session
/// so that repeated renders don't trigger redundant network calls.
///
/// Usage:
/// ```dart
/// final activeIds = await ActiveGamesService.instance.activeGameIds;
/// ```
class ActiveGamesService {
  ActiveGamesService._();

  /// Singleton instance — lives for the entire app session.
  static final ActiveGamesService instance = ActiveGamesService._();

  /// In-memory cache. `null` means "not yet fetched".
  Set<String>? _cache;

  /// Known mapping from `learning_modules.title` → canonical `game_id`.
  ///
  /// The AI API uses snake_case game IDs (e.g. `copy_me`) while the
  /// Supabase `learning_modules` table stores human-readable titles
  /// (e.g. `Copy Me`). This map bridges the two.
  static const Map<String, String> _titleToGameId = {
    'Copy Me': 'copy_me',
    'Do What I Say': 'do_what_i_say',
    'My Turn, Your Turn': 'my_turn_your_turn',
    'Match It': 'match_it',
    'Sari-Sari Store Sorting': 'sari_sari_sort',
    'Trace It': 'trace_it',
    'Hintay!': 'hintay',
    "Ano'ng Susunod?": 'anong_susunod',
    'Sabay Tayo!': 'sabay_tayo',
    'Kumusta!': 'kumusta',
    "Ano'ng Nararamdaman?": 'anong_nararamdaman',
  };

  /// Returns the set of active game IDs (e.g. `{'copy_me', 'match_it'}`).
  ///
  /// On the first call the set is fetched from Supabase and cached.
  /// Subsequent calls return the cached value immediately.
  ///
  /// If the Supabase query fails (e.g. offline), returns **all** known
  /// game IDs so that no recommendations are incorrectly hidden.
  Future<Set<String>> get activeGameIds async {
    if (_cache != null) return _cache!;

    try {
      final client = Supabase.instance.client;
      final rows = await client
          .from('learning_modules')
          .select('title')
          .eq('active', true);

      final titles = List<Map<String, dynamic>>.from(rows);
      final ids = <String>{};

      for (final row in titles) {
        final title = row['title'] as String?;
        if (title == null) continue;
        final gameId = _titleToGameId[title];
        if (gameId != null) {
          ids.add(gameId);
        } else {
          // Fallback: convert title to snake_case slug so new games
          // added to the DB still work without a code change.
          ids.add(title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_'));
          debugPrint('[ActiveGamesService] Unknown title "$title" — '
              'using slug fallback');
        }
      }

      _cache = ids;
      debugPrint('[ActiveGamesService] Active game IDs loaded: $_cache');
      return _cache!;
    } catch (e) {
      debugPrint('[ActiveGamesService] ⚠️ Failed to fetch active games: $e. '
          'Falling back to all-active.');
      // Fail-open: treat every game as active so we never hide valid
      // recommendations just because of a transient network issue.
      _cache = _titleToGameId.values.toSet();
      return _cache!;
    }
  }

  /// The cached active set, or null when it hasn't been fetched yet.
  /// Synchronous — for widgets that can't await (they should treat null as
  /// "all active").
  Set<String>? get cachedActiveGameIds => _cache;

  /// Force-refresh the cache on the next access (e.g. after an admin
  /// enables/disables a game and the parent pulls-to-refresh).
  void invalidateCache() {
    _cache = null;
    debugPrint('[ActiveGamesService] Cache invalidated');
  }
}
