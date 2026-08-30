import 'package:flutter/material.dart';

import 'package:shared_ui/shared_ui.dart';

import 'child_mode_lobby_screen.dart';

/// Opens Child Mode directly on the "My Path" view.
///
/// One entry point for every parent surface that offers it — the dashboard's
/// Recommended Module card and the assessment result's Recommended Activities
/// card — so the child always lands in the same place.
///
/// Child Mode may lock landscape, and the parent screen underneath does not
/// rebuild on pop, so the parent orientation is re-applied on the way back.
Future<void> openMyPath(BuildContext context) async {
  final navigator = Navigator.of(context);
  await navigator.push(
    MaterialPageRoute(
      builder: (_) => const ChildModeLobbyScreen(openPath: true),
    ),
  );
  lockParentAdaptive();
}
