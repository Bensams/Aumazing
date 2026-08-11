/// What the child just answered correctly, in words that can be said back.
///
/// A correct answer no longer earns praise in the moment — praise belongs to
/// the end-of-game reward. What it earns instead is a *label*: the game names
/// the thing the child got right ("red circle", "Gatas", "A"), which turns
/// every success into one more paired exposure to the target vocabulary and
/// tells the child which part of what they did was the right part. Repeated,
/// unvarying naming is also the feedback style that reads as predictable
/// rather than startling for autistic children, where a burst of enthusiastic
/// praise on every trial does not.
///
/// The game layer knows what was answered but not how to say it; the audio
/// layer knows how to say things but not what happened. This carries the first
/// across to the second as plain strings, which is also why it lives in
/// game_core: game_core does not depend on shared_audio, and should not.
///
/// Every field is optional — a game fills in only the dimensions it actually
/// varies. An instance with nothing set (`AnswerLabel.none`) means "correct,
/// but there is nothing here worth naming", and the audio layer stays quiet
/// rather than substituting praise.
class AnswerLabel {
  const AnswerLabel({
    this.color,
    this.shape,
    this.letter,
    this.item,
    this.routineStep,
  });

  /// Colour name, e.g. `'red'`. Case-insensitive.
  final String? color;

  /// Shape name, e.g. `'circle'`. Case-insensitive.
  final String? shape;

  /// A traced glyph: a letter (`'A'`) or a numeral (`'3'`).
  final String? letter;

  /// A named object, e.g. a sari-sari store item (`'Gatas'`).
  final String? item;

  /// An Ano'ng Susunod routine step, carried as its language-independent
  /// `RoutineStep.id` (`'wash'`, `'bath'`) rather than its printed label.
  ///
  /// The id is what the audio layer maps to a recording, and the recording is
  /// already in the child's language — passing the visible Tagalog or Cebuano
  /// text instead would force the audio layer to know every translation.
  final String? routineStep;

  /// Nothing to name — the correct answer was a position, a turn, or an
  /// action rather than a thing with a name.
  static const AnswerLabel none = AnswerLabel();

  /// Whether any dimension of this answer can be named.
  bool get isEmpty =>
      color == null &&
      shape == null &&
      letter == null &&
      item == null &&
      routineStep == null;

  @override
  String toString() => 'AnswerLabel(color: $color, shape: $shape, '
      'letter: $letter, item: $item, routineStep: $routineStep)';
}

/// Called when the child answers correctly, carrying what they got right so
/// the app can name it back to them.
typedef AnswerLabelCallback = void Function(AnswerLabel label);
