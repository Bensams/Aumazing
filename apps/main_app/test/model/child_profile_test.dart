import 'package:aumazing/model/child_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
}
