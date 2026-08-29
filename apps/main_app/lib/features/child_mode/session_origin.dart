import 'package:flutter/widgets.dart';

/// Why a practice game was opened — the difference between "the child picked
/// this from the lobby" and "this is the next step on their recommended
/// module path".
///
/// Both look identical to a game screen: `assessmentContext` stays
/// `'practice'` in either case, because it is what gates retry, the end-of-game
/// choice dialog and a dozen other in-game behaviours that must not change
/// just because the game came from the path. So the origin travels as an
/// inherited marker around the screen instead, and only
/// [GameSessionRecording] reads it — to record `recommended_module` rather
/// than `practice` as the session's context.
///
/// The cloud already speaks this vocabulary: `game_sessions.session_type`
/// admits `recommended_module` alongside `practice`, and the beta report
/// groups its gameplay table by it.
class SessionOrigin extends InheritedWidget {
  const SessionOrigin({
    super.key,
    required this.context,
    required super.child,
  });

  /// The value to record as the session's context: `'practice'` or
  /// `'recommended_module'`.
  final String context;

  /// The recorded context for a practice game opened below [buildContext],
  /// defaulting to plain `'practice'` when no origin was declared (a game
  /// opened outside the launcher, or a test pumping a screen directly).
  static String of(BuildContext buildContext) =>
      buildContext
          .dependOnInheritedWidgetOfExactType<SessionOrigin>()
          ?.context ??
      practice;

  static const practice = 'practice';
  static const recommendedModule = 'recommended_module';

  @override
  bool updateShouldNotify(SessionOrigin oldWidget) =>
      oldWidget.context != context;
}
