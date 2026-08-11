import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart';
import 'package:shared_audio/shared_audio.dart';
import 'package:shared_ui/shared_ui.dart';

/// The routine content lives in game_core and the recordings that speak it live
/// in shared_audio, and neither package depends on the other — so nothing in
/// either one can notice when they drift apart. main_app sees both, which makes
/// this the only place the join can be checked at all.
///
/// The failure being guarded against is silent in the literal sense: a routine
/// step with no recording produces a correct placement that says nothing back,
/// which looks exactly like working software from the outside.
void main() {
  group('every routine step can be named aloud', () {
    for (final routine in kRoutines) {
      test('${routine.id} has a recorded title', () {
        expect(
          VoiceOverService.routineTitleCue(routine.id),
          isNotNull,
          reason: 'Routine "${routine.id}" opens its round in silence',
        );
      });

      for (final step in routine.steps) {
        test('${routine.id}/${step.id} has a recorded name', () {
          expect(
            VoiceOverService.answerLabelCues(routineStep: step.id),
            isNotEmpty,
            reason: 'RoutineStep "${step.id}" has no entry in the voice-over '
                'routine map, so seating it correctly is answered by silence',
          );
        });
      }
    }
  });

  group('every routine reads and speaks in the child language', () {
    for (final language in GameLanguage.values) {
      test('${language.slug} labels every step and titles every routine', () {
        for (final routine in kRoutines) {
          expect(routine.title(language), isNotEmpty,
              reason: '${routine.id} has no ${language.slug} title');
          for (final step in routine.steps) {
            expect(step.label(language), isNotEmpty,
                reason: '${step.id} has no ${language.slug} label');
          }
        }
      });
    }

    test('the labels actually differ between languages', () {
      // A translation table that silently fell back to English would still
      // pass the emptiness check above.
      final morning = kRoutines.first;
      expect(morning.title(GameLanguage.tagalog),
          isNot(morning.title(GameLanguage.english)));
      expect(morning.title(GameLanguage.cebuano),
          isNot(morning.title(GameLanguage.english)));
    });
  });

  group('both games carry localized captions', () {
    for (final language in GameLanguage.values) {
      test('${language.slug} has every prompt filled in', () {
        final strings = AppStrings(language);
        expect(strings.hintayInstruction, isNotEmpty);
        expect(strings.hintayComplete, isNotEmpty);
        expect(strings.anongSusunodInstruction, isNotEmpty);
        expect(strings.anongSusunodComplete, isNotEmpty);
      });
    }

    test('the Filipino prompts are not the English ones', () {
      expect(AppStrings(GameLanguage.tagalog).hintayInstruction,
          isNot(AppStrings(GameLanguage.english).hintayInstruction));
      expect(AppStrings(GameLanguage.cebuano).anongSusunodInstruction,
          isNot(AppStrings(GameLanguage.english).anongSusunodInstruction));
    });
  });
}
