/// The observed assessment (AUM-351): the child plays the assessment games
/// while an adult sits beside them and watches.
///
/// Nothing is asked while the child plays. The adult answers twice:
/// - **before** the first game — who is watching, and optional background
///   about the child ([ObserverIntake]);
/// - **after** the last game, before any result is shown — what they saw in
///   each game ([SessionObservation]).
///
/// Both are stored per assessment run in the caregiver questionnaire table,
/// as `<pre|post>_intake` and `<pre|post>_observation`. They describe the
/// session and sit beside the game scores; they never change a score.
library;

/// Who watched the child play. The keys match the cloud table's
/// `completed_by_role`.
enum ObserverRole {
  parent('parent', 'Parent'),
  guardian('guardian', 'Guardian'),
  teacher('teacher', 'SPED teacher'),
  therapist('therapist', 'Therapist');

  const ObserverRole(this.key, this.label);

  final String key;
  final String label;

  /// The label mid-sentence: "the parent", "the SPED teacher".
  String get inSentence => this == teacher ? label : label.toLowerCase();
}

enum DiagnosisStatus {
  diagnosed('diagnosed', 'Diagnosed with autism'),
  evaluating('evaluating', 'Being evaluated or suspected'),
  notDiagnosed('not_diagnosed', 'Not diagnosed'),
  preferNotToSay('prefer_not_to_say', 'Prefer not to say');

  const DiagnosisStatus(this.key, this.label);

  final String key;
  final String label;
}

enum SchoolLevel {
  notInSchool('not_in_school', 'Not in school yet'),
  daycare('daycare', 'Daycare'),
  kinder('kinder', 'Kinder'),
  grade1('grade_1', 'Grade 1'),
  grade2Up('grade_2_up', 'Grade 2 or higher'),
  sped('sped', 'SPED class or school'),
  inclusive('inclusive', 'Regular class with SPED support'),
  homeschool('homeschool', 'Home-schooled');

  const SchoolLevel(this.key, this.label);

  final String key;
  final String label;
}

enum Therapy {
  speech('speech', 'Speech'),
  occupational('occupational', 'Occupational'),
  behavioural('behavioural', 'Behavioural'),
  other('other', 'Other'),
  none('none', 'None');

  const Therapy(this.key, this.label);

  final String key;
  final String label;
}

T? _byKey<T extends Enum>(List<T> values, Object? key, String Function(T) k) {
  for (final v in values) {
    if (k(v) == key) return v;
  }
  return null;
}

/// Answered before the child starts.
class ObserverIntake {
  const ObserverIntake({
    required this.role,
    this.diagnosis,
    this.school,
    this.therapies = const {},
  });

  static const templateId = 'observer_intake';
  static const templateVersion = 1;

  final ObserverRole role;

  /// Background about the child — each one optional.
  final DiagnosisStatus? diagnosis;
  final SchoolLevel? school;
  final Set<Therapy> therapies;

  Map<String, dynamic> toResponses() => {
    'template_id': templateId,
    'template_version': templateVersion,
    'observer_role': role.key,
    'diagnosis': diagnosis?.key,
    'school': school?.key,
    'therapies': [for (final t in therapies) t.key],
  };

  static ObserverIntake? fromResponses(Map<String, dynamic> r) {
    final role = _byKey(ObserverRole.values, r['observer_role'], (v) => v.key);
    if (role == null) return null;
    final therapies = r['therapies'];
    return ObserverIntake(
      role: role,
      diagnosis: _byKey(DiagnosisStatus.values, r['diagnosis'], (v) => v.key),
      school: _byKey(SchoolLevel.values, r['school'], (v) => v.key),
      therapies: {
        if (therapies is List)
          ...therapies
              .map((t) => _byKey(Therapy.values, t, (v) => v.key))
              .whereType<Therapy>(),
      },
    );
  }

  /// "SPED teacher · Diagnosed with autism · Kinder · Speech, Occupational".
  String get summary => [
    'Watched by: ${role.label}',
    if (diagnosis != null && diagnosis != DiagnosisStatus.preferNotToSay)
      diagnosis!.label,
    if (school != null) school!.label,
    if (therapies.isNotEmpty && !therapies.contains(Therapy.none))
      'Therapy: ${therapies.map((t) => t.label).join(', ')}',
  ].join(' · ');
}

enum Understood {
  yes('yes', 'Yes'),
  partly('partly', 'Partly'),
  no('no', 'No');

  const Understood(this.key, this.label);

  final String key;
  final String label;
}

/// How much the adult helped, least to most — the prompt levels SPED
/// teachers use.
enum HelpGiven {
  none('none', 'No help'),
  told('told', 'Told them'),
  showed('showed', 'Pointed or showed'),
  hand('hand', 'Helped their hand');

  const HelpGiven(this.key, this.label);

  final String key;
  final String label;
}

enum ChildMood {
  calm('calm', 'Calm'),
  excited('excited', 'Excited'),
  upset('upset', 'Frustrated or upset');

  const ChildMood(this.key, this.label);

  final String key;
  final String label;
}

enum AsUsual {
  usual('usual', 'As usual'),
  better('better', 'Better than usual'),
  worse('worse', 'Worse than usual');

  const AsUsual(this.key, this.label);

  final String key;
  final String label;
}

enum SessionDay {
  normal('normal', 'A normal day'),
  tiredOrSick('tired_or_sick', 'Tired or sick'),
  distracted('distracted', 'New place or distracted');

  const SessionDay(this.key, this.label);

  final String key;
  final String label;
}

/// What the adult saw in one game.
class GameObservation {
  const GameObservation({
    this.understood,
    this.help,
    this.mood,
    this.asUsual,
  });

  final Understood? understood;
  final HelpGiven? help;
  final ChildMood? mood;
  final AsUsual? asUsual;

  bool get complete =>
      understood != null && help != null && mood != null && asUsual != null;

  GameObservation copyWith({
    Understood? understood,
    HelpGiven? help,
    ChildMood? mood,
    AsUsual? asUsual,
  }) => GameObservation(
    understood: understood ?? this.understood,
    help: help ?? this.help,
    mood: mood ?? this.mood,
    asUsual: asUsual ?? this.asUsual,
  );

  Map<String, dynamic> toMap() => {
    'understood': understood?.key,
    'help': help?.key,
    'mood': mood?.key,
    'as_usual': asUsual?.key,
  };

  static GameObservation fromMap(Map<String, dynamic> m) => GameObservation(
    understood: _byKey(Understood.values, m['understood'], (v) => v.key),
    help: _byKey(HelpGiven.values, m['help'], (v) => v.key),
    mood: _byKey(ChildMood.values, m['mood'], (v) => v.key),
    asUsual: _byKey(AsUsual.values, m['as_usual'], (v) => v.key),
  );

  /// What a reader of this game's score should know. Only the facts the
  /// adult reported; the score itself is never adjusted.
  List<String> get flags => [
    if (help == HelpGiven.showed || help == HelpGiven.hand)
      'Played with help (${help!.label.toLowerCase()})',
    if (understood == Understood.no) 'Did not understand the task',
    if (mood == ChildMood.upset) 'Was frustrated or upset',
    if (asUsual == AsUsual.worse) 'Worse than usual',
  ];
}

/// Answered after the child finishes, before results are shown.
class SessionObservation {
  const SessionObservation({
    required this.games,
    this.role,
    this.day,
    this.note = '',
  });

  static const templateId = 'session_observation';
  static const templateVersion = 1;

  /// Game id → what was seen, in play order.
  final Map<String, GameObservation> games;

  /// Carried from the intake, so the record says who observed.
  final ObserverRole? role;
  final SessionDay? day;
  final String note;

  bool get complete => day != null && games.values.every((g) => g.complete);

  Map<String, dynamic> toResponses() => {
    'template_id': templateId,
    'template_version': templateVersion,
    'observer_role': role?.key,
    'games': {
      for (final entry in games.entries) entry.key: entry.value.toMap(),
    },
    'day': day?.key,
    if (note.trim().isNotEmpty) 'note': note.trim(),
  };

  static SessionObservation fromResponses(Map<String, dynamic> r) {
    final games = r['games'];
    return SessionObservation(
      role: _byKey(ObserverRole.values, r['observer_role'], (v) => v.key),
      games: {
        if (games is Map)
          for (final entry in games.entries)
            if (entry.value is Map)
              '${entry.key}': GameObservation.fromMap(
                Map<String, dynamic>.from(entry.value as Map),
              ),
      },
      day: _byKey(SessionDay.values, r['day'], (v) => v.key),
      note: r['note'] as String? ?? '',
    );
  }

  /// Flag for the whole session, or null on a normal day.
  String? get dayFlag =>
      day == null || day == SessionDay.normal
          ? null
          : 'Not a typical day (${day!.label.toLowerCase()})';
}

/// Questionnaire type strings for one assessment type.
String intakeTypeFor(String assessmentType) => '${assessmentType}_intake';
String observationTypeFor(String assessmentType) =>
    '${assessmentType}_observation';
