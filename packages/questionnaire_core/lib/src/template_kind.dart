/// The three question sets a practitioner can author (AUM-344, AUM-352).
enum TemplateKind {
  /// What the parent sees at home: frequency ratings in the four domains,
  /// asked identically before and after (AUM-341).
  home('home', 'Home questionnaire'),

  /// "Before your child starts": background asked of the watching adult
  /// before the first assessment game (AUM-351).
  intake('intake', 'Before the session'),

  /// "What did you see?": asked of the watching adult after the last game,
  /// per game and for the session (AUM-351).
  observation('observation', 'After the session');

  const TemplateKind(this.key, this.label);

  /// Stored in `questionnaire_templates.kind`.
  final String key;
  final String label;

  static TemplateKind? fromKey(Object? key) {
    for (final kind in values) {
      if (kind.key == key) return kind;
    }
    return null;
  }
}

/// Which assessment a template serves, stored in
/// `questionnaire_templates.questionnaire_type`.
enum AssessmentScope {
  pre('pre', 'Pre-assessment only'),
  post('post', 'Post-assessment only'),
  both('both', 'Pre- and post-assessment');

  const AssessmentScope(this.key, this.label);

  final String key;
  final String label;

  static AssessmentScope? fromKey(Object? key) {
    for (final scope in values) {
      if (scope.key == key) return scope;
    }
    return null;
  }
}
