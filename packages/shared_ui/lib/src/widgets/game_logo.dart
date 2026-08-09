import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The illustrated tile that identifies one mini-game.
///
/// Each game owns an SVG in `assets/game_logos/`: a rounded square with its own
/// colour wash and a small scene of what the game asks the child to do. A child
/// who cannot read the name still recognises the picture, which is the whole
/// point — the lobby is used by pre-readers.
///
/// The artwork already carries its own background and corner radius, so this
/// widget only sizes it. Pass [fallbackIcon] so a game without art (or an asset
/// that fails to parse) still shows something rather than a gap; the fallback
/// draws the icon on a soft tile so the layout does not shift.
class GameLogo extends StatelessWidget {
  const GameLogo({
    super.key,
    required this.asset,
    this.size = 56,
    this.fallbackIcon,
    this.fallbackColor,
    this.semanticLabel,
  });

  /// Full asset path, e.g. `packages/shared_ui/assets/game_logos/match_it.svg`.
  /// Null for a game that has no artwork yet.
  final String? asset;

  /// Width and height of the square tile.
  final double size;

  /// Drawn instead when [asset] is null, and while the SVG decodes.
  final IconData? fallbackIcon;

  /// Tint for [fallbackIcon]. Defaults to the theme's primary colour.
  final Color? fallbackColor;

  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    if (asset == null) return _fallback(context);
    return SvgPicture.asset(
      asset!,
      width: size,
      height: size,
      semanticsLabel: semanticLabel,
      // The tile is square; anything else would letterbox the scene.
      fit: BoxFit.contain,
      placeholderBuilder: (_) => _fallback(context),
    );
  }

  Widget _fallback(BuildContext context) {
    final color = fallbackColor ?? Theme.of(context).colorScheme.primary;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(size * 0.2),
      ),
      child: fallbackIcon == null
          ? null
          : Icon(fallbackIcon, size: size * 0.52, color: color),
    );
  }
}
