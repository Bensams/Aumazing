/// Process-wide reduced-motion flag for in-game visuals.
///
/// The host app sets [reduced] before launching a game (from the child's
/// graphics-quality / reduced-motion preference). Game components read it to
/// replace continuous animations — e.g. pulsing hint rings — with a static
/// highlight, which is calmer for motion-sensitive children.
class GameMotion {
  GameMotion._();

  /// When true, components render hints statically instead of animating them.
  static bool reduced = false;
}
