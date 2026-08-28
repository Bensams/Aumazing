import 'package:aumazing/model/child_profile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_audio/shared_audio.dart';

void main() {
  test('fromMap keeps legacy child rows readable without a birth date', () {
    final profile = ChildProfile.fromMap({
      'id': 'legacy-child',
      'user_id': 'parent-1',
      'name': 'Legacy Child',
      'age': 5,
      'avatar': 'lion',
      'music_enabled': 1,
      'vibration_enabled': 0,
      'created_at': '2026-04-21T00:00:00.000',
      'updated_at': '2026-04-21T00:00:00.000',
    });

    expect(profile.displayName, 'Legacy Child');
    expect(profile.name, 'Legacy Child');
    expect(profile.birthDate, isNull);
    expect(profile.age, 5);
    expect(profile.musicEnabled, isTrue);
    expect(profile.vibrationEnabled, isFalse);
  });

  test('age getter derives years for canonical birth-date records', () {
    final now = DateTime.now();
    final profile = ChildProfile(
      id: 'child-1',
      userId: 'parent-1',
      displayName: 'Mika',
      birthDate: DateTime(now.year - 4, now.month, now.day),
      avatar: 'lion',
      createdAt: DateTime(2026, 4, 21),
      updatedAt: DateTime(2026, 4, 21),
    );

    expect(profile.age, 4);
  });

  test(
    'fromSupabase decodes a minimal public.children row with local defaults',
    () {
      final profile = ChildProfile.fromSupabase({
        'id': 'child-1',
        'parent_user_id': 'parent-1',
        'display_name': 'Mika',
        'birth_date': '2022-04-20',
        'created_at': '2026-04-21T00:00:00Z',
        'updated_at': '2026-04-21T00:00:00Z',
      });

      expect(profile.id, 'child-1');
      expect(profile.userId, 'parent-1');
      expect(profile.displayName, 'Mika');
      expect(profile.birthDate, DateTime(2022, 4, 20));
      expect(profile.avatar, isNotEmpty);
      expect(profile.musicEnabled, isTrue);
      expect(profile.vibrationEnabled, isTrue);
    },
  );

  group('music category', () {
    test('a row written before v16 reads as the default category', () {
      // The v16 migration backfills with a column DEFAULT, but rows can also
      // reach fromMap from other paths — either way the child gets the calmest
      // category rather than an empty string or a crash.
      final profile = ChildProfile.fromMap({
        'id': 'legacy-child',
        'user_id': 'parent-1',
        'display_name': 'Legacy Child',
        'avatar': 'lion',
        'created_at': '2026-04-21T00:00:00.000',
        'updated_at': '2026-04-21T00:00:00.000',
      });

      expect(profile.musicCategory, kDefaultBgmCategory);
    });

    test('survives a toMap/fromMap round trip', () {
      final profile = ChildProfile(
        id: 'child-1',
        userId: 'parent-1',
        displayName: 'Mika',
        birthDate: DateTime(2022, 4, 20),
        avatar: 'lion',
        musicCategory: 'filipino_calm',
        createdAt: DateTime(2026, 4, 21),
        updatedAt: DateTime(2026, 4, 21),
      );

      expect(ChildProfile.fromMap(profile.toMap()).musicCategory,
          'filipino_calm');
    });

    test('copyWith leaves the category alone when not passed', () {
      final profile = ChildProfile(
        id: 'child-1',
        userId: 'parent-1',
        displayName: 'Mika',
        birthDate: DateTime(2022, 4, 20),
        avatar: 'lion',
        musicCategory: 'focus_minimal',
        createdAt: DateTime(2026, 4, 21),
        updatedAt: DateTime(2026, 4, 21),
      );

      expect(profile.copyWith(musicVolume: 0.9).musicCategory,
          'focus_minimal');
    });
  });
}
