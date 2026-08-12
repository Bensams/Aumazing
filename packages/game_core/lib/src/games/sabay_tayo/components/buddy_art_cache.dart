import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/cache.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../shared/sprite_fit.dart';

/// Decoded mascot sprite sheets for the buddy in "Sabay Tayo!", held for the
/// lifetime of the process.
///
/// The sheets are bundled in `shared_ui`, outside Flame's default
/// `assets/images/` prefix, so this uses an [Images] cache with an empty prefix
/// and full package paths — the same arrangement as
/// `anong_susunod/routine_art_cache.dart`, which is the established way to pull
/// `shared_ui` art into a Flame game.
///
/// Why not [CharacterSprites]: that class hands back [ImageProvider]s for the
/// Flutter widget tree and slices every sheet into per-frame PNGs up front. A
/// Flame component draws to a [ui.Canvas] and needs a [ui.Image] plus a source
/// rect, so it would have to undo that work. The *grid contract* is still taken
/// from [CharacterSprites.layout] rather than copied, so a change to a sheet's
/// dimensions can never silently desync the two readers.
///
/// Loading is best-effort by design. A sheet that fails to decode is left out
/// and [BuddyPainter] covers for it; a child's session must never end because
/// an asset went missing.
class BuddyArtCache {
  BuddyArtCache._();

  /// Actions this game actually draws. Deliberately a subset of
  /// [CharacterSprites.layout] — loading all 21 sheets to use eight of them
  /// costs a visible pause on the first frame of the game.
  static const List<String> usedActions = [
    'idle',
    'point',
    'celebrate',
    'oops',
    'encourage',
    'look_left',
    'look_right',
    'look_up',
    'look_down',
    'look_up_left',
    'look_up_right',
    'look_down_left',
    'look_down_right',
  ];

  static final Images _images = Images(prefix: '');
  static final Map<String, ui.Image> _sheets = {};

  static String? _character;
  static bool _loading = false;
  static bool _loaded = false;

  /// The character whose sheets are currently loaded, or null before a load.
  static String? get character => _character;

  /// True once a load pass has finished, whatever it managed to decode.
  static bool get isLoaded => _loaded;

  /// True when enough of the gaze grid decoded for the buddy to aim at all.
  ///
  /// The horizontal pair is the floor: a buddy that can only look up and down
  /// cannot point at objects arranged around an arc, and the painted fallback
  /// is a better experience than a character staring straight ahead while the
  /// child is asked where it is looking.
  static bool get canGaze =>
      _sheets.containsKey('look_left') && _sheets.containsKey('look_right');

  /// Decodes the sheets for [character] (`'bps'` or `'reiz'`). Safe to call
  /// more than once; switching characters reloads.
  static Future<void> ensureLoaded(String character) async {
    if (_loading) return;
    if (_loaded && _character == character) return;

    _loading = true;
    _sheets.clear();
    _character = character;

    for (final action in usedActions) {
      final path =
          'packages/shared_ui/assets/characters/${character}_$action.png';
      try {
        _sheets[action] = await _images.load(path);
      } catch (e) {
        // BuddyPainter covers this one. Worth a log line: a buddy silently
        // rendering as the painted version is easy to miss in review.
        debugPrint('[SabayTayo] buddy sheet missing: $path ($e)');
      }
    }

    _loading = false;
    _loaded = true;
  }

  /// The decoded sheet for [action], or null if it isn't loaded.
  static ui.Image? sheet(String action) => _sheets[action];

  /// How many real frames [action]'s sheet holds, per the shared grid contract.
  static int frameCount(String action) =>
      CharacterSprites.layout[action]?.frames ?? 1;

  @visibleForTesting
  static void resetForTest() {
    _sheets.clear();
    _character = null;
    _loaded = false;
    _loading = false;
  }
}

/// The sheet name for a gaze aimed at ([x], [y]) — fractions of the way across
/// and down the playfield, (0,0) being the top-left corner.
///
/// Mirrors `CharacterSprites.gazeFrameFor`, including its deliberately wide
/// middle band: a full third on each axis keeps the buddy from staring off into
/// a corner for an object that is only slightly off-centre. Returns null for
/// the centre cell, where the resting pose is the correct pose.
///
/// This duplicates nine lines of banding logic rather than importing it because
/// the original returns an [ImageProvider] and its helpers are private. If that
/// ever changes, delete this and call through.
String? gazeActionFor(double x, double y) {
  final col = _band(x);
  final row = _band(y);
  if (col == 0 && row == 0) return null;
  final vertical = row < 0 ? 'up' : (row > 0 ? 'down' : '');
  final horizontal = col < 0 ? 'left' : (col > 0 ? 'right' : '');
  final parts = [vertical, horizontal].where((s) => s.isNotEmpty);
  return 'look_${parts.join('_')}';
}

/// -1 (near edge), 0 (middle third), or 1 (far edge).
int _band(double v) {
  final at = v.clamp(0.0, 1.0);
  if (at < 1 / 3) return -1;
  if (at > 2 / 3) return 1;
  return 0;
}

/// The best available sheet for a gaze at ([x], [y]), degrading the way
/// `CharacterSprites.gazeFrameFor` does: a missing corner falls back to the
/// horizontal pose, then the vertical, then rest. A buddy that drops to rest
/// the moment the target strays off-axis would look like it had stopped
/// attending, which in this game reads as part of the task.
String? resolvedGazeAction(double x, double y) {
  final exact = gazeActionFor(x, y);
  if (exact == null) return null;
  if (BuddyArtCache.sheet(exact) != null) return exact;

  final col = _band(x);
  final row = _band(y);
  for (final candidate in [
    if (col != 0) 'look_${col < 0 ? 'left' : 'right'}',
    if (row != 0) 'look_${row < 0 ? 'up' : 'down'}',
  ]) {
    if (BuddyArtCache.sheet(candidate) != null) return candidate;
  }
  return null;
}

/// Draws frame [frameIndex] of [action] into [dest], preferring the bundled
/// sheet and falling back to the painted buddy.
///
/// [gazeX] and [gazeY] are passed through to the fallback so it can aim: a
/// joint-attention game whose fallback cannot indicate direction has no
/// fallback at all, only a picture of a character.
void drawBuddy(
  ui.Canvas canvas,
  String action,
  ui.Rect dest, {
  int frameIndex = 0,
  double gazeX = 0.5,
  double gazeY = 0.5,
}) {
  final sheet = BuddyArtCache.sheet(action);
  if (sheet == null) {
    BuddyPainter.paint(canvas, dest, gazeX: gazeX, gazeY: gazeY);
    return;
  }

  final spec = CharacterSprites.layout[action];
  final cols = spec?.cols ?? 1;
  final rows = spec?.rows ?? 1;
  final frames = spec?.frames ?? 1;
  final index = frameIndex.clamp(0, frames - 1);

  final cellW = sheet.width / cols;
  final cellH = sheet.height / rows;
  final src = ui.Rect.fromLTWH(
    (index % cols) * cellW,
    (index ~/ cols) * cellH,
    cellW,
    cellH,
  );

  // Fit rather than fill. [dest] is the component's own box, whose proportions
  // are picked for the layout and are not the cell's, so filling it squashed
  // the buddy horizontally on every device — mildly, but always. The eyes are
  // the cue this entire game rests on, and a distorted face is a harder one to
  // read than an undistorted one.
  canvas.drawImageRect(
    sheet,
    src,
    fitSpriteCell(dest, cellW, cellH),
    ui.Paint()..filterQuality = ui.FilterQuality.medium,
  );
}

/// The buddy drawn from scratch, for when the sprite sheets are unavailable.
///
/// Unlike the routine cards' fallback this one is not a nicety. The child's
/// whole task is to read where the buddy is looking, so the fallback has to
/// carry a *direction* — hence offset pupils and a head tilt rather than a
/// neutral placeholder. It is plainly not the shipped art, which is the point:
/// it should be obvious in review that the sheets failed to load.
class BuddyPainter {
  BuddyPainter._();

  static const ui.Color _skin = ui.Color(0xFFF2D3B8);
  static const ui.Color _shirt = ui.Color(0xFF6C9BD2);
  static const ui.Color _ink = ui.Color(0xFF5A5A6B);

  static void paint(
    ui.Canvas canvas,
    ui.Rect dest, {
    required double gazeX,
    required double gazeY,
  }) {
    final headR = dest.width * 0.30;
    final headC = ui.Offset(dest.center.dx, dest.top + headR * 1.15);

    // Body: a simple rounded torso under the head.
    final body = ui.RRect.fromRectAndRadius(
      ui.Rect.fromLTRB(
        dest.center.dx - headR * 0.95,
        headC.dy + headR * 0.75,
        dest.center.dx + headR * 0.95,
        dest.bottom,
      ),
      ui.Radius.circular(headR * 0.45),
    );
    canvas.drawRRect(body, ui.Paint()..color = _shirt);

    // The head leans toward what it is looking at. Small — the eyes do the
    // work — but enough that the direction survives at thumbnail size.
    final leanX = (gazeX.clamp(0.0, 1.0) - 0.5) * headR * 0.30;
    final leanY = (gazeY.clamp(0.0, 1.0) - 0.5) * headR * 0.14;
    final head = headC.translate(leanX, leanY);

    canvas.drawCircle(head, headR, ui.Paint()..color = _skin);
    canvas.drawCircle(
      head,
      headR,
      ui.Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = math.max(2, headR * 0.05)
        ..color = const ui.Color(0x335A5A6B),
    );

    // Eyes, with the pupils pushed most of the way to the edge of the white.
    // This is the channel that actually carries the cue.
    final eyeDx = headR * 0.36;
    final eyeY = head.dy - headR * 0.08;
    final whiteR = headR * 0.22;
    final pupilR = whiteR * 0.52;
    final pupilOffX = (gazeX.clamp(0.0, 1.0) - 0.5) * 2 * (whiteR - pupilR);
    final pupilOffY = (gazeY.clamp(0.0, 1.0) - 0.5) * 2 * (whiteR - pupilR);

    for (final dx in [-eyeDx, eyeDx]) {
      final centre = ui.Offset(head.dx + dx, eyeY);
      canvas.drawCircle(
          centre, whiteR, ui.Paint()..color = const ui.Color(0xFFFFFFFF));
      canvas.drawCircle(
        centre.translate(pupilOffX, pupilOffY),
        pupilR,
        ui.Paint()..color = _ink,
      );
    }

    // A neutral mouth. No smile: the child should never have to read emotion
    // to work out where the buddy is attending.
    canvas.drawLine(
      ui.Offset(head.dx - headR * 0.16, head.dy + headR * 0.42),
      ui.Offset(head.dx + headR * 0.16, head.dy + headR * 0.42),
      ui.Paint()
        ..color = _ink
        ..strokeWidth = math.max(2, headR * 0.06)
        ..strokeCap = ui.StrokeCap.round,
    );
  }
}
