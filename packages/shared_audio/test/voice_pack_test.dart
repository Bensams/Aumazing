import 'package:flutter_test/flutter_test.dart';
import 'package:shared_audio/shared_audio.dart';

void main() {
  group('voice pack registry', () {
    test('ids are unique and asset folders are unique', () {
      final ids = kVoicePacks.map((p) => p.id).toList();
      final folders = kVoicePacks.map((p) => p.assetFolder).toList();

      expect(ids.toSet(), hasLength(ids.length));
      expect(folders.toSet(), hasLength(folders.length));
    });

    test('every language has a default pack listed first', () {
      for (final slug in kVoicePacks.map((p) => p.languageSlug).toSet()) {
        final packs = voicePacksForLanguage(slug);
        expect(packs, isNotEmpty);
        expect(defaultVoicePackForLanguage(slug), same(packs.first));
      }
    });

    test('every language offers a choice of voices', () {
      for (final slug in ['en', 'tl', 'ceb']) {
        expect(voicePacksForLanguage(slug).length, greaterThan(1),
            reason: '$slug should offer more than one voice');
      }
      expect(
        voicePacksForLanguage('ceb').map((p) => p.id),
        contains('ceb_lexianne'),
      );
    });

    // The multi-speaker `en` / `tl` / `ceb` packs were removed because the
    // voice could change mid-session. Nothing may reintroduce them, and every
    // language's default must now be a single-speaker generated pack.
    test('the inconsistent original packs are gone', () {
      for (final id in ['en_default', 'tl_default', 'ceb_default']) {
        expect(voicePackById(id), isNull, reason: id);
      }
      for (final folder in ['en', 'tl', 'ceb']) {
        expect(voicePackByAssetFolder(folder), isNull, reason: folder);
      }
    });

    test('each language defaults to its complete adult woman pack', () {
      expect(defaultVoicePackForLanguage('en').id, 'en_adult_woman');
      expect(defaultVoicePackForLanguage('tl').id, 'tl_adult_woman');
      expect(defaultVoicePackForLanguage('ceb').id, 'ceb_adult_woman');
    });

    test('a language slug resolves to that language default folder', () {
      expect(resolveVoiceFolder('en'), 'en_adult_woman');
      expect(resolveVoiceFolder('tl'), 'tl_adult_woman');
      expect(resolveVoiceFolder('ceb'), 'ceb_adult_woman');
      expect(resolveVoiceFolder('ceb_lexianne'), 'ceb_lexianne');
      expect(resolveVoiceFolder('nonsense'), 'en_adult_woman');
    });

    test('every generated pack declares a tier and ships as mp3', () {
      final generated = kVoicePacks.where((p) => p.tier != null);
      expect(generated, hasLength(18));
      for (final pack in generated) {
        expect(pack.fileExtension, '.mp3', reason: pack.id);
        expect(['adult', 'young', 'child'], contains(pack.tier));
        expect(pack.assetFolder, '${pack.languageSlug}_${pack.tier}_'
            '${pack.id.split('_').last}');
      }
    });

    test('the human-recorded pack stays wav and untiered', () {
      final pack = voicePackById('ceb_lexianne')!;
      expect(pack.fileExtension, '.wav');
      expect(pack.tier, isNull);
    });

    test('tiers are grouped, tiered first, and cover every pack', () {
      for (final slug in ['en', 'tl', 'ceb']) {
        final tiers = voiceTiersForLanguage(slug);
        expect(tiers.first, 'adult',
            reason: '$slug must lead with a complete default');
        expect(tiers, containsAll(<String?>['adult', 'young', 'child']));

        final grouped = [
          for (final tier in tiers) ...voicePacksForTier(slug, tier),
        ];
        expect(grouped, hasLength(voicePacksForLanguage(slug).length),
            reason: 'grouping must not drop or duplicate a pack');
      }
    });

    test('lookup by id returns null for unknown or null ids', () {
      expect(voicePackById('ceb_lexianne')?.assetFolder, 'ceb_lexianne');
      expect(voicePackById('does_not_exist'), isNull);
      expect(voicePackById(null), isNull);
    });

    test('unknown language falls back to the first registered pack', () {
      expect(defaultVoicePackForLanguage('xx'), same(kVoicePacks.first));
    });
  });

  group('fallbackVoiceFolder', () {
    test('alternate pack falls back to its language default', () {
      expect(fallbackVoiceFolder('ceb_lexianne'), 'ceb_adult_woman');
      expect(fallbackVoiceFolder('en_child_boy'), 'en_adult_woman');
    });

    test('default packs have nothing to fall back to', () {
      expect(fallbackVoiceFolder('ceb_adult_woman'), isNull);
      expect(fallbackVoiceFolder('en_adult_woman'), isNull);
      expect(fallbackVoiceFolder('tl_adult_woman'), isNull);
    });

    test('unregistered folder has no fallback', () {
      expect(fallbackVoiceFolder('ceb_someone_else'), isNull);
    });
  });

  group('VoiceOverService.assetPathCandidates', () {
    const prefix = 'packages/shared_audio/assets/audio/voice_over';

    test('default pack resolves to exactly one path', () {
      expect(
        VoiceOverService.assetPathCandidates(
            VoiceOverCue.greatJob, 'ceb_adult_woman'),
        ['$prefix/ceb_adult_woman/core_praise/GreatJob.mp3'],
      );
    });

    test('alternate pack is tried first, then the default pack', () {
      expect(
        VoiceOverService.assetPathCandidates(
          VoiceOverCue.greatJob,
          'ceb_lexianne',
        ),
        [
          '$prefix/ceb_lexianne/core_praise/GreatJob.wav',
          '$prefix/ceb_adult_woman/core_praise/GreatJob.mp3',
        ],
      );
    });

    // The Lexianne voice actor never recorded these three cues, so playback
    // must have a default-pack path to retry against rather than going silent.
    test('cues missing from the Lexianne pack still offer a default path', () {
      const missing = {
        VoiceOverCue.fantastic: 'reward_and_celebration/Fantastic.wav',
        VoiceOverCue.greatPlaying: 'reward_and_celebration/GreatPlaying.wav',
        VoiceOverCue.gameFinished: 'transition/GameFinished.wav',
      };

      for (final entry in missing.entries) {
        final candidates = VoiceOverService.assetPathCandidates(
          entry.key,
          'ceb_lexianne',
        );
        expect(candidates, hasLength(2));
        expect(candidates.last,
            '$prefix/ceb_adult_woman/${entry.value.replaceAll('.wav', '.mp3')}');
      }
    });

    test('supportedLanguages covers every registered asset folder', () {
      expect(
        VoiceOverService.supportedLanguages,
        containsAll(kVoicePacks.map((p) => p.assetFolder)),
      );
    });

    // The extension has to follow the folder, not the cue table: the wav
    // Lexianne pack falls back to an mp3 default, and vice versa.
    test('generated packs resolve to mp3 and fall back to the mp3 default', () {
      expect(
        VoiceOverService.assetPathCandidates(
          VoiceOverCue.greatJob,
          'en_child_girl',
        ),
        [
          '$prefix/en_child_girl/core_praise/GreatJob.mp3',
          '$prefix/en_adult_woman/core_praise/GreatJob.mp3',
        ],
      );
    });

    test('every registered pack yields a path with its own extension', () {
      for (final pack in kVoicePacks) {
        final first = VoiceOverService.assetPathCandidates(
          VoiceOverCue.greatJob,
          pack.assetFolder,
        ).first;
        expect(first, startsWith('$prefix/${pack.assetFolder}/'),
            reason: pack.id);
        expect(first, endsWith(pack.fileExtension), reason: pack.id);
      }
    });
  });
}
