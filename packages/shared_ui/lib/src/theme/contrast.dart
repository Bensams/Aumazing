import 'dart:math' as math;
import 'dart:ui';

/// WCAG 2.2 contrast maths, used to keep parent-chosen backgrounds from
/// making the game art unreadable.
///
/// The formulas here are the ones the WCAG success criteria — and
/// Accessibility Scanner — are defined in terms of, so a ratio from
/// [contrastRatio] is directly comparable to the 3:1 and 4.5:1 thresholds
/// quoted in the manuscript.
abstract final class Contrast {
  /// Minimum contrast for a meaningful graphical object (WCAG 2.2, 1.4.11
  /// Non-text Contrast). Game shapes are graphical objects, not text.
  static const double graphicalObjectMinimum = 3.0;

  /// Minimum contrast for normal-size body text (WCAG 2.2, 1.4.3 at AA).
  static const double textMinimum = 4.5;

  /// Relative luminance per the WCAG definition.
  static double relativeLuminance(Color c) {
    double channel(double v) =>
        v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * channel(c.r) +
        0.7152 * channel(c.g) +
        0.0722 * channel(c.b);
  }

  /// Contrast ratio between two opaque colours, from 1.0 (identical
  /// luminance) to 21.0 (black on white). Order does not matter.
  static double contrastRatio(Color a, Color b) {
    final la = relativeLuminance(a);
    final lb = relativeLuminance(b);
    final hi = math.max(la, lb);
    final lo = math.min(la, lb);
    return (hi + 0.05) / (lo + 0.05);
  }

  /// Flattens [fg] at [alpha] (0–1) over [bg].
  ///
  /// Needed because the game cards are drawn translucent over the
  /// background, so the colour a shape is actually seen against is a
  /// composite rather than either source colour.
  static Color compositeOver(Color fg, Color bg, double alpha) {
    double mix(double f, double b) => f * alpha + b * (1 - alpha);
    return Color.from(
      alpha: 1,
      red: mix(fg.r, bg.r),
      green: mix(fg.g, bg.g),
      blue: mix(fg.b, bg.b),
    );
  }

  /// The worst contrast any colour in [foregrounds] achieves against any
  /// colour in [backgrounds].
  ///
  /// A background is only as good as its weakest pairing — a parent picking
  /// a colour needs the worst case, not the average, because the child will
  /// meet every shape in the set.
  static double worstCase({
    required Iterable<Color> foregrounds,
    required Iterable<Color> backgrounds,
  }) {
    var worst = double.infinity;
    for (final f in foregrounds) {
      for (final b in backgrounds) {
        final r = contrastRatio(f, b);
        if (r < worst) worst = r;
      }
    }
    return worst.isFinite ? worst : 1.0;
  }
}
