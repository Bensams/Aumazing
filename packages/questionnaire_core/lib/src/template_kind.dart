/// The three question sets a practitioner can author (AUM-344, AUM-352).
enum TemplateKind {
  /// What the parent sees at home: frequency ratings in the four domains,
  /// asked identically before and after (AUM-341) — the "before" once at
  /// child profile setup, the "after" at the post-assessment (AUM-364).
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

  /// [label] as it applies to [kind]. The home questionnaire's "pre" report
  /// is given when the child's profile is set up, not at the pre-assessment
  /// (AUM-364).
  String labelFor(TemplateKind kind) {
    if (kind != TemplateKind.home) return label;
    return switch (this) {
      pre => 'Child setup only',
      post => 'Post-assessment only',
      both => 'Child setup and post-assessment',
    };
  }

  /// Where a template serving only this scope is in use, for [kind].
  String inUseFor(TemplateKind kind) => switch (this) {
    pre =>
      kind == TemplateKind.home
          ? 'In use at child setup'
          : 'In use for pre-assessment',
    post => 'In use for post-assessment',
    both => 'In use',
  };

  static AssessmentScope? fromKey(Object? key) {
    for (final scope in values) {
      if (scope.key == key) return scope;
    }
    return null;
  }
}
