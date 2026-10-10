import 'package:flutter/material.dart';
import 'package:questionnaire_core/questionnaire_core.dart';
import 'package:shared_ui/shared_ui.dart';

import 'observation_choice_row.dart';

/// One practitioner-authored question (AUM-352): chips for choose-one and
/// choose-any, a text box for a written answer.
///
/// Keys: chips are `<keyPrefix>.<question id>.<option id>`, the text box is
/// `<keyPrefix>.<question id>`.
class TemplateQuestionField extends StatefulWidget {
  const TemplateQuestionField({
    super.key,
    required this.keyPrefix,
    required this.question,
    required this.value,
    required this.onChanged,
  });

  final String keyPrefix;
  final TemplateQuestion question;
  final Object? value;
  final ValueChanged<Object?> onChanged;

  @override
  State<TemplateQuestionField> createState() => _TemplateQuestionFieldState();
}

class _TemplateQuestionFieldState extends State<TemplateQuestionField> {
  late final TextEditingController _text = TextEditingController(
    text: widget.value is String ? widget.value as String : '',
  );

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  TemplateQuestion get _q => widget.question;

  void _toggle(ChoiceOption o) {
    final current = [
      if (widget.value is List)
        for (final v in widget.value as List)
          if (v is String) v,
    ];
    List<String> next;
    if (current.contains(o.id)) {
      next = [...current]..remove(o.id);
    } else if (o.exclusive) {
      next = [o.id];
    } else {
      next = [
        for (final id in current)
          if (_q.option(id)?.exclusive != true) id,
        o.id,
      ];
    }
    widget.onChanged(next.isEmpty ? null : next);
  }

  @override
  Widget build(BuildContext context) {
    final prefix = '${widget.keyPrefix}.${_q.id}';
    switch (_q.type) {
      case QuestionType.text:
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: TextField(
            key: Key(prefix),
            controller: _text,
            maxLines: 3,
            maxLength: 500,
            onChanged: (v) => widget.onChanged(v.trim().isEmpty ? null : v),
            decoration: InputDecoration(
              labelText: _q.text,
              border: const OutlineInputBorder(),
            ),
          ),
        );
      case QuestionType.single:
        return ObservationChoiceRow<ChoiceOption>(
          keyPrefix: prefix,
          question: _q.text,
          values: _q.options,
          label: (o) => o.label,
          id: (o) => o.id,
          isSelected: (o) => widget.value == o.id,
          // Tapping the chosen answer again clears an optional question.
          onSelected:
              (o) => widget.onChanged(
                widget.value == o.id && !_q.required ? null : o.id,
              ),
        );
      case QuestionType.multi:
        return ObservationChoiceRow<ChoiceOption>(
          keyPrefix: prefix,
          question: _q.text,
          values: _q.options,
          label: (o) => o.label,
          id: (o) => o.id,
          isSelected:
              (o) => widget.value is List && (widget.value as List).contains(o.id),
          onSelected: _toggle,
        );
    }
  }
}
