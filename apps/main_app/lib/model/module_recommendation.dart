/// A structured module recommendation from the AI Assessment API.
///
/// Each recommendation includes the game identifier, display name,
/// and the starting difficulty level the child should begin at.
class ModuleRecommendation {
  /// Game identifier, e.g. 'copy_me', 'do_what_i_say'.
  final String gameId;

  /// Human-readable game name, e.g. 'Copy Me'.
  final String name;

  /// Recommended starting level (1-based).
  final int startingLevel;

  const ModuleRecommendation({
    required this.gameId,
    required this.name,
    required this.startingLevel,
  });

  factory ModuleRecommendation.fromJson(Map<String, dynamic> json) {
    return ModuleRecommendation(
      gameId: json['game_id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      startingLevel: (json['starting_level'] as num?)?.toInt() ?? 1,
    );
  }

  Map<String, dynamic> toJson() => {
        'game_id': gameId,
        'name': name,
        'starting_level': startingLevel,
      };

  @override
  String toString() =>
      'ModuleRecommendation(gameId=$gameId, name=$name, level=$startingLevel)';
}
