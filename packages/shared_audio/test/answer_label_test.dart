import 'package:flutter_test/flutter_test.dart';
import 'package:shared_audio/shared_audio.dart';

void main() {
  group('answerLabelCues', () {
    // A colour and a shape together are one phrase, not two words. Played as
    // two clips it never sounds like one, because an isolated word is rendered
    // sentence-final and its pitch drops hard at the end.
    test('a colour with a shape resolves to a single phrase recording', () {
      expect(
        VoiceOverService.answerLabelCues(color: 'red', shape: 'circle'),
        [VoiceOverCue.phraseRedCircle],
      );
      expect(
        VoiceOverService.answerLabelCues(color: 'purple', shape: 'heart'),
        [VoiceOverCue.phrasePurpleHeart],
      );
    });

    test('names are matched case- and whitespace-insensitively', () {
      expect(
        VoiceOverService.answerLabelCues(color: ' Gold ', shape: 'STAR'),
        [VoiceOverCue.phraseGoldStar],
      );
    });

    test('a colour alone keeps its own sentence-final recording', () {
      expect(VoiceOverService.answerLabelCues(color: 'red'),
          [VoiceOverCue.colorRed]);
    });

    // A pair the games never show has no phrase recording; naming it as two
    // words is worse than silence but far better than dropping the feedback.
    test('a pair with no phrase recording falls back to two words', () {
      expect(
        VoiceOverService.answerLabelCues(color: 'teal', shape: 'heart'),
        [VoiceOverCue.colorTeal, VoiceOverCue.shapeHeart],
      );
    });

    test('every phrase cue resolves to an asset path', () {
      final phrases = VoiceOverCue.values
          .where((c) => c.name.startsWith('phrase'));
      expect(phrases, hasLength(30));
      for (final cue in phrases) {
        expect(VoiceOverService.assetPathCandidates(cue, 'en_adult_woman'),
            isNotEmpty, reason: '${cue.name} has no asset path');
      }
    });

    test('a glyph label resolves as either a letter or a numeral', () {
      expect(VoiceOverService.answerLabelCues(letter: 'A'),
          [VoiceOverCue.letterA]);
      expect(VoiceOverService.answerLabelCues(letter: '3'),
          [VoiceOverCue.numberThree]);
    });

    test('a sari-sari item resolves to its own cue', () {
      expect(VoiceOverService.answerLabelCues(item: 'Gatas'),
          [VoiceOverCue.itemGatas]);
    });

    // The contract the whole change rests on: a correct answer with nothing
    // nameable produces silence, never a praise line. Praise belongs to the
    // end-of-game reward, and a fallback here would quietly reintroduce it.
    test('an unrecognised or absent label yields no cues at all', () {
      expect(VoiceOverService.answerLabelCues(), isEmpty);
      expect(VoiceOverService.answerLabelCues(color: 'chartreuse'), isEmpty);
      expect(VoiceOverService.answerLabelCues(letter: 'line across'), isEmpty);
    });

    test('no label cue is a praise cue', () {
      const praise = {
        VoiceOverCue.greatJob,
        VoiceOverCue.wellDone,
        VoiceOverCue.correct,
        VoiceOverCue.thatsRight,
      };
      final cues = [
        ...VoiceOverService.answerLabelCues(color: 'blue', shape: 'heart'),
        ...VoiceOverService.answerLabelCues(letter: '1'),
        ...VoiceOverService.answerLabelCues(item: 'Tinapay'),
      ];
      expect(cues, isNotEmpty);
      expect(cues.any(praise.contains), isFalse);
    });
  });

  group('label cue assets', () {
    // Every cue the naming feedback can reach must resolve to a path; a cue
    // with no entry in the asset table plays nothing and the child hears
    // silence on a correct answer.
    test('every colour, shape, letter, number and item cue has a path', () {
      final labelCues = VoiceOverCue.values.where((c) =>
          c.name.startsWith('color') ||
          c.name.startsWith('shape') ||
          c.name.startsWith('letter') ||
          c.name.startsWith('number') ||
          c.name.startsWith('item'));
      expect(labelCues, isNotEmpty);
      for (final cue in labelCues) {
        expect(
          VoiceOverService.assetPathCandidates(cue, 'en'),
          isNotEmpty,
          reason: '${cue.name} has no asset path',
        );
      }
    });
  });
}
