/// Developmental skill categories that games can target.
/// A game may belong to multiple categories (many-to-many).
enum SkillCategory {
  communication('communication', 'Communication'),
  socialInteraction('social_interaction', 'Social Interaction'),
  playSkills('play_skills', 'Play Skills');

  const SkillCategory(this.slug, this.displayName);

  /// Database slug (matches `skill_categories.slug` in Supabase).
  final String slug;

  /// Human-readable name.
  final String displayName;

  /// Look up a category by its database slug.
  static SkillCategory? fromSlug(String slug) {
    try {
      return values.firstWhere((c) => c.slug == slug);
    } catch (_) {
      return null;
    }
  }
}
