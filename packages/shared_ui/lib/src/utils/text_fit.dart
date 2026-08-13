import 'package:flutter/material.dart';

/// Smallest width at which [text] still lays out within [maxLines] using
/// [style], at the text scale in effect at [context].
///
/// Responsive layouts use this to reserve space for a label instead of
/// guessing a constant: a guess that is too small silently truncates the
/// label, which is how the parent dashboard ended up showing
/// "Start Pre-Assessm…".
///
/// The style is merged onto the ambient [DefaultTextStyle] the same way a
/// [Text] widget merges it, so the measurement matches what will render.
double minWidthToFitLines(
  BuildContext context, {
  required String text,
  required TextStyle style,
  int maxLines = 2,
}) {
  final textScaler =
      MediaQuery.maybeOf(context)?.textScaler ?? TextScaler.noScaling;
  final effective = DefaultTextStyle.of(context).style.merge(style);
  final painter = TextPainter(
    text: TextSpan(text: text, style: effective),
    textDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
    textScaler: textScaler,
    maxLines: maxLines,
  )..layout();

  // One line always fits; the longest single word is the hard floor.
  var fits = painter.maxIntrinsicWidth;
  var tooNarrow = painter.minIntrinsicWidth;

  // Binary search the narrowest width that still fits, so a label that can
  // wrap is not given a full single-line column.
  if (maxLines > 1) {
    for (var i = 0; i < 12 && fits - tooNarrow > 1; i++) {
      final mid = (fits + tooNarrow) / 2;
      painter.layout(maxWidth: mid);
      if (painter.didExceedMaxLines) {
        tooNarrow = mid;
      } else {
        fits = mid;
      }
    }
  }
  painter.dispose();

  // A pixel of slack, so sub-pixel differences against the real layout
  // cannot push a word onto one line too many.
  return fits.ceilToDouble() + 1;
}
