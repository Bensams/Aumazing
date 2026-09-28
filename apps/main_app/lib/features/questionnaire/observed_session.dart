/// The observed assessment (AUM-351): the child plays the assessment games
/// while an adult sits beside them and watches.
///
/// Nothing is asked while the child plays. The adult answers twice:
/// - **before** the first game — who is watching, then the "Before your
///   child starts" template's questions ([IntakeRecord]);
/// - **after** the last game, before any result is shown — the "What did
///   you see?" template's questions, per game and for the session
///   ([ObservationRecord]).
///
/// The questions come from templates a practitioner writes in the portal
/// (AUM-352), with bundled defaults. Who is watching stays fixed in the app,
/// because it is stored as the record's `completed_by_role`.
///
/// Each record keeps the readable summary and flags worked out when it was
/// saved, so it still reads correctly after the template is reworded.
/// Records never change a score.
library;

import 'package:questionnaire_core/questionnaire_core.dart';

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

  static ObserverRole? fromKey(Object? key) {
    for (final role in values) {
      if (role.key == key) return role;
    }
    return null;
  }
}

Map<String, Object?> _answers(Object? raw) =>
    raw is Map ? {for (final e in raw.entries) '${e.key}': e.value} : {};

List<String> _strings(Object? raw) => [
  if (raw is List)
    for (final v in raw)
      if (v is String) v,
];

/// What was answered before the session.
class IntakeRecord {
  const IntakeRecord({
    required this.role,
    this.answers = const {},
    this.summary = const [],
  });

  /// The record to store for [template]'s [answers].
  factory IntakeRecord.answer(
    ChoiceTemplate template,
    ObserverRole role,
    Map<String, Object?> answers,
  ) => IntakeRecord(
    role: role,
    answers: answers,
    summary: template.summary(answers, QuestionScope.session),
  );

  final ObserverRole role;
  final Map<String, Object?> answers;

  /// Readable answers as they were worded when saved.
  final List<String> summary;

  Map<String, dynamic> toResponses(ChoiceTemplate template) => {
    ...template.stamp,
    'observer_role': role.key,
    'answers': answers,
    'summary': summary,
  };

  static IntakeRecord? fromResponses(Map<String, dynamic> r) {
    final role = ObserverRole.fromKey(r['observer_role']);
    if (role == null) return null;
    return IntakeRecord(
      role: role,
      answers: _answers(r['answers']),
      summary: _strings(r['summary']),
    );
  }

  /// "Watched by: SPED teacher · Diagnosed with autism · Kinder".
  String get headline =>
      ['Watched by: ${role.label}', ...summary].join(' · ');
}

/// What was seen in one game.
class GameRecord {
  const GameRecord({
    this.answers = const {},
    this.summary = const [],
    this.flags = const [],
  });

  final Map<String, Object?> answers;
  final List<String> summary;
  final List<String> flags;

  Map<String, dynamic> toMap() => {
    'answers': answers,
    'summary': summary,
    'flags': flags,
  };

  static GameRecord fromMap(Object? raw) {
    final m = raw is Map ? raw : const {};
    return GameRecord(
      answers: _answers(m['answers']),
      summary: _strings(m['summary']),
      flags: _strings(m['flags']),
    );
  }
}

/// What was answered after the session.
class ObservationRecord {
  const ObservationRecord({
    required this.games,
    this.role,
    this.sessionAnswers = const {},
    this.sessionSummary = const [],
    this.sessionFlags = const [],
    this.notes = const [],
  });

  /// The record to store for [template]'s answers.
  factory ObservationRecord.answer(
    ChoiceTemplate template, {
    required ObserverRole? role,
    required Map<String, Map<String, Object?>> games,
    required Map<String, Object?> session,
  }) => ObservationRecord(
    role: role,
    games: {
      for (final entry in games.entries)
        entry.key: GameRecord(
          answers: entry.value,
          summary: template.summary(entry.value, QuestionScope.game),
          flags: template.flags(entry.value, QuestionScope.game),
        ),
    },
    sessionAnswers: session,
    sessionSummary: template.summary(session, QuestionScope.session),
    sessionFlags: template.flags(session, QuestionScope.session),
    notes: template.notes(session, QuestionScope.session),
  );

  /// Game id → what was seen, in play order.
  final Map<String, GameRecord> games;

  /// Carried from the intake, so the record says who observed.
  final ObserverRole? role;
  final Map<String, Object?> sessionAnswers;
  final List<String> sessionSummary;
  final List<String> sessionFlags;
  final List<String> notes;

  Map<String, dynamic> toResponses(ChoiceTemplate template) => {
    ...template.stamp,
    'observer_role': role?.key,
    'games': {
      for (final entry in games.entries) entry.key: entry.value.toMap(),
    },
    'session': {
      'answers': sessionAnswers,
      'summary': sessionSummary,
      'flags': sessionFlags,
      'notes': notes,
    },
  };

  static ObservationRecord fromResponses(Map<String, dynamic> r) {
    final games = r['games'];
    final session = r['session'] is Map ? r['session'] as Map : const {};
    return ObservationRecord(
      role: ObserverRole.fromKey(r['observer_role']),
      games: {
        if (games is Map)
          for (final entry in games.entries)
            '${entry.key}': GameRecord.fromMap(entry.value),
      },
      sessionAnswers: _answers(session['answers']),
      sessionSummary: _strings(session['summary']),
      sessionFlags: _strings(session['flags']),
      notes: _strings(session['notes']),
    );
  }
}

/// Questionnaire type strings for one assessment type.
String intakeTypeFor(String assessmentType) => '${assessmentType}_intake';
String observationTypeFor(String assessmentType) =>
    '${assessmentType}_observation';
