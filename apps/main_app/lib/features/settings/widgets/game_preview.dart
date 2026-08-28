import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:game_core/game_core.dart';
import 'package:shared_ui/shared_ui.dart';

/// A miniature Match It round, drawn with the game's own painter.
///
/// Used by both the background picker and the object-style picker so a
/// parent sees the actual result before applying it — the earlier previews
/// were hand-drawn approximations, which meant they could disagree with the
/// game about the very thing the parent was judging.
///
/// Everything visual here comes from [ShapePainter3D]: the same card fill,
/// drop shadow, rim highlight, outline rule and shape geometry the real
/// round uses. The only thing faked is the layout — two rows of shapes
/// instead of a full board.
class GamePreview extends StatelessWidget {
  const GamePreview({
    super.key,
    required this.background,
    required this.objectStyle,
    this.height = 150,
  });

  final ChildBackground background;

  /// The style being edited, which may not be the applied one yet.
  final GameObjectStyle objectStyle;

  final double height;

  /// Five shapes spanning the legibility range: gold and yellow are the ones
  /// that disappear on a light background, purple is the one that disappears
  /// on a dark one. If a setting works for these it works for the set.
  static const _shapes = <({String name, Color colour})>[
    (name: 'star', colour: Color(0xFFFFB300)),
    (name: 'heart', colour: Color(0xFF8E24AA)),
    (name: 'circle', colour: Color(0xFF1E88E5)),
    (name: 'triangle', colour: Color(0xFFFDD835)),
    (name: 'diamond', colour: Color(0xFF43A047)),
  ];

  /// The colour of the one card drawn in its selected state, matching the
  /// selection border the games themselves use.
  static const Color selectionBorder = AppColors.primaryPurple;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          label: 'Preview: how a game round will look with these settings',
          image: true,
          excludeSemantics: true,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              height: height,
              decoration: BoxDecoration(
                gradient: background.toGradient(),
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(12),
              ),
              child: CustomPaint(
                painter: _GamePreviewPainter(style: objectStyle),
                size: Size.infinite,
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        // Without this line the purple card is just an odd one out, which is
        // precisely the reading the uniform outline exists to prevent. It is
        // labelled so a parent sees it as a demonstration of the selected
        // state rather than as "the right answer".
        Text(
          'Every object has the same outline. The purple card shows what '
          'selecting one looks like.',
          style: AppTextStyles.bodySmall
              .copyWith(color: AppColors.mutedForeground),
        ),
      ],
    );
  }
}

class _GamePreviewPainter extends CustomPainter {
  const _GamePreviewPainter({required this.style});

  final GameObjectStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    const shapes = GamePreview._shapes;
    const gap = 10.0;
    const pad = 12.0;

    // Two rows, mirroring Match It's left/right columns of cards. The second
    // row is shuffled so the preview reads as a matching game rather than a
    // colour chart.
    const order = [0, 1, 2, 3, 4];
    const shuffled = [2, 4, 0, 3, 1];

    // Floors rather than clamps: in a narrow settings column cardW can fall
    // below any sensible minimum, and `clamp(min, max)` throws outright once
    // min exceeds max. Cards stay square-ish by taking the smaller of the
    // two available dimensions.
    final available = size.width - pad * 2 - gap * (shapes.length - 1);
    final cardW = math.max(8.0, available / shapes.length);
    final rowH = math.max(8.0, (size.height - pad * 2 - gap) / 2);
    final cardH = math.min(rowH, cardW);
    final radius = (cardW * 0.22).clamp(4.0, 20.0);

    void drawRow(List<int> indices, double top, {bool selected = false}) {
      for (var i = 0; i < indices.length; i++) {
        final shape = shapes[indices[i]];
        final rect = Rect.fromLTWH(pad + i * (cardW + gap), top, cardW, cardH);

        // One card is shown selected so the state border is visible too — it
        // takes priority over the standing outline, and a parent should see
        // that it still does. The caption under the preview names it as a
        // selection so the odd card out is never mistaken for the answer.
        //
        // Every other card, whatever colour it is, gets the identical
        // standing outline; the five fills here span the range on purpose,
        // so a parent can see that they do.
        final isSelected = selected && i == 1;

        ShapePainter3D.drawCard3D(
          canvas,
          rect,
          color: shape.colour,
          cornerRadius: radius,
          showBorder: isSelected,
          borderColor: isSelected ? GamePreview.selectionBorder : null,
          borderWidth: 3,
          styleOverride: style,
        );
        ShapePainter3D.drawByName(
          canvas,
          shape.name,
          rect.center.dx,
          rect.center.dy,
          cardW * 0.26,
          shape.colour,
        );
      }
    }

    drawRow(order, pad);
    drawRow(shuffled, pad + cardH + gap, selected: true);
  }

  @override
  bool shouldRepaint(_GamePreviewPainter old) => old.style != style;
}
