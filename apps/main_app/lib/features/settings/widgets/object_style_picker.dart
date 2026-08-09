import 'package:flutter/material.dart';

import 'package:shared_ui/shared_ui.dart';

import 'game_preview.dart';

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

        GamePreview(background: background, objectStyle: _draft),
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
