import 'package:flutter_test/flutter_test.dart';

import 'package:aumazing/features/child_mode/pending_path_launch.dart';

void main() {
  tearDown(PendingPathLaunch.take);

  test('take returns null when nothing is parked', () {
    expect(PendingPathLaunch.take(), isNull);
  });

  test('set then take returns the launch exactly once', () {
    PendingPathLaunch.set('copy_me', 2);
    expect(PendingPathLaunch.take(), ('copy_me', 2));
    expect(PendingPathLaunch.take(), isNull);
  });

  test('a later set replaces the parked launch', () {
    PendingPathLaunch.set('match_it', 1);
    PendingPathLaunch.set('copy_me', 3);
    expect(PendingPathLaunch.take(), ('copy_me', 3));
  });
}
