import 'package:flutter/material.dart';

import 'package:shared_ui/shared_ui.dart';

import '../../../providers/child_provider.dart';

/// Parent-facing editor for the cards behind game objects.
///
/// Two controls that matter, and one that deliberately is not offered:
///
///  * **Card colour** — the tile under each shape, picture or item. Left
///    alone, the card is a faint wash of the object's own colour, which is
///    why a gold star could measure 1.00:1 against its own card. Setting a
///    fixed colour breaks that relationship.
///  * **Outline** — style and thickness, so the card is separable from the
///    screen background.
///  * **Outline colour is not offered.** It is derived from the card so it
///    always clears 3:1. A picker there would let the one element whose job
///    is guaranteeing contrast be set to something that fails.
class ObjectStylePicker extends StatefulWidget {
  const ObjectStylePicker({super.key, required this.childProv});

  final ChildProvider childProv;

  @override
  State<ObjectStylePicker> createState() => _ObjectStylePickerState();
}

class _ObjectStylePickerState extends State<ObjectStylePicker> {
  late GameObjectStyle _draft = widget.childProv.objectStyle;

  void _update(GameObjectStyle next) {
    setState(() => _draft = next);
    // Applied immediately: every control here is a discrete, reversible
    // choice with a live preview, so an extra confirm step would only add a
    // tap. The background picker keeps its Apply button because dragging a
    // wheel would otherwise write to storage on every frame.
    widget.childProv.setObjectStyle(next);
  }

  @override
  Widget build(BuildContext context) {
    final background = widget.childProv.customBackground ??
        const ChildBackground.solid(Color(0xFFEDE7F6));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Card colour behind objects', style: AppTextStyles.labelLarge),
        const SizedBox(height: AppSpacing.xs),
        _CardColourRow(
          selected: _draft.cardColour,
          onPick: (c) => _update(c == null
              ? _draft.copyWith(clearCardColour: true)
              : _draft.copyWith(cardColour: c)),
        ),
        const SizedBox(height: AppSpacing.md),

        Text('Outline', style: AppTextStyles.labelLarge),
        const SizedBox(height: AppSpacing.xs),
        SegmentedButton<ObjectOutline>(
          segments: [
            for (final o in ObjectOutline.values)
              ButtonSegment(value: o, label: Text(o.label)),
          ],
          selected: {_draft.outline},
          onSelectionChanged: (s) =>
              _update(_draft.copyWith(outline: s.first)),
        ),
        if (_draft.hasOutline) ...[
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Text('Thickness', style: AppTextStyles.bodySmall),
              Expanded(
                child: Slider(
                  value: _draft.effectiveWidth,
                  min: GameObjectStyle.minWidth,
                  max: GameObjectStyle.maxWidth,
                  divisions:
                      (GameObjectStyle.maxWidth - GameObjectStyle.minWidth)
                          .round(),
                  label: '${_draft.effectiveWidth.round()} px',
                  semanticFormatterCallback: (v) =>
                      'Outline thickness ${v.round()} pixels',
                  onChanged: (v) => _update(_draft.copyWith(outlineWidth: v)),
                ),
              ),
              SizedBox(
                width: 34,
                child: Text(
                  '${_draft.effectiveWidth.round()} px',
                  style: AppTextStyles.labelSmall
                      .copyWith(color: AppColors.mutedForeground),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.sm),

        _ObjectPreview(style: _draft, background: background),
        const SizedBox(height: AppSpacing.xs),
        Text(
          _draft.hasOutline
              ? 'The outline colour is chosen automatically so it always '
                  'stands out against the card.'
              : 'Without an outline, a card can blend into the background.',
          style: AppTextStyles.bodySmall
              .copyWith(color: AppColors.mutedForeground),
        ),
      ],
    );
  }
}

/// Card-colour circles, plus an "Auto" option that restores the original
/// tint-of-the-object behaviour.
class _CardColourRow extends StatelessWidget {
  const _CardColourRow({required this.selected, required this.onPick});

  final Color? selected;
  final ValueChanged<Color?> onPick;

  static const _options = <({String name, Color? colour})>[
    (name: 'Auto', colour: null),
    (name: 'White', colour: Color(0xFFFFFFFF)),
    (name: 'Soft white', colour: Color(0xFFFAF9F6)),
    (name: 'Light grey', colour: Color(0xFFE8E8EC)),
    (name: 'Warm sand', colour: Color(0xFFF4EDE0)),
    (name: 'Slate', colour: Color(0xFF3A4550)),
    (name: 'Charcoal', colour: Color(0xFF2E2E33)),
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final o in _options)
          Semantics(
            button: true,
            selected: o.colour == selected,
            label: o.colour == null
                ? 'Auto, card tinted with the object colour'
                : '${o.name} card',
            excludeSemantics: true,
            child: InkResponse(
              onTap: () => onPick(o.colour),
              radius: kMinInteractiveDimension / 2,
              child: SizedBox(
                width: kMinInteractiveDimension,
                height: kMinInteractiveDimension,
                child: Center(
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: o.colour ?? AppColors.muted,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: o.colour == selected
                            ? AppColors.primaryPurple
                            : AppColors.border,
                        width: o.colour == selected ? 3 : 1,
                      ),
                    ),
                    child: o.colour == null
                        ? const Icon(Icons.auto_awesome_rounded,
                            size: 17, color: AppColors.mutedForeground)
                        : (o.colour == selected
                            ? Icon(
                                Icons.check_rounded,
                                size: 18,
                                color: GameObjectStyle.outlineColourFor(
                                    o.colour!),
                              )
                            : null),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Sample object cards drawn the way the games will draw them.
class _ObjectPreview extends StatelessWidget {
  const _ObjectPreview({required this.style, required this.background});

  final GameObjectStyle style;
  final ChildBackground background;

  /// A light, a mid and a very light shape — the three cases that behave
  /// differently. Gold is the one that vanishes without help.
  static const _samples = [
    Color(0xFFFFB300), // gold — the 1.00:1 case
    Color(0xFF8E24AA), // purple — needs a light surround
    Color(0xFF1E88E5), // blue
    Color(0xFFFDD835), // yellow — needs a dark surround
  ];

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Preview of game object cards on the current background',
      image: true,
      excludeSemantics: true,
      child: Container(
        height: 96,
        decoration: BoxDecoration(
          gradient: background.toGradient(),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            for (final shape in _samples)
              CustomPaint(
                size: const Size(58, 58),
                painter: _CardPreviewPainter(shape: shape, style: style),
              ),
          ],
        ),
      ),
    );
  }
}

/// Mirrors what `ShapePainter3D.drawCard3D` does, so the preview and the game
/// cannot drift in the ways that matter: card fill, outline style, outline
/// width, and the derived outline colour.
class _CardPreviewPainter extends CustomPainter {
  const _CardPreviewPainter({required this.shape, required this.style});

  final Color shape;
  final GameObjectStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(12));

    // Same rule as the painter: a fixed card colour, or the object's own
    // colour at alpha 40 when left on Auto.
    final card = style.cardColour ?? shape.withAlpha(40);
    canvas.drawRRect(rrect, Paint()..color = card);

    if (style.hasOutline) {
      final paint = Paint()
        ..color = GameObjectStyle.outlineColourFor(card)
        ..style = PaintingStyle.stroke
        ..strokeWidth = style.effectiveWidth;
      if (style.outline == ObjectOutline.dashed) {
        final dash = (paint.strokeWidth * 2.5).clamp(6.0, 40.0);
        final gap = (paint.strokeWidth * 1.5).clamp(4.0, 40.0);
        for (final m in (Path()..addRRect(rrect)).computeMetrics()) {
          var d = 0.0;
          while (d < m.length) {
            final end = (d + dash).clamp(0.0, m.length);
            canvas.drawPath(m.extractPath(d, end), paint);
            d = end + gap;
          }
        }
      } else {
        canvas.drawRRect(rrect, paint);
      }
    }

    // The object itself.
    canvas.drawCircle(
      rect.center,
      size.width * 0.26,
      Paint()..color = shape,
    );
  }

  @override
  bool shouldRepaint(_CardPreviewPainter old) =>
      old.shape != shape || old.style != style;
}
