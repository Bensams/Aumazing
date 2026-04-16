import 'package:flutter/services.dart';

/// Parent-facing screens use landscape to match the login experience.
void lockParentLandscape() {
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
}

/// Call when leaving a parent screen — keeps landscape since the entire
/// app is landscape-only.
void unlockParentOrientation() {
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
}
