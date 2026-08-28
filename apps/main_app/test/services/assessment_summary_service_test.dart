import 'package:flutter_test/flutter_test.dart';

import 'package:aumazing/services/assessment_summary_service.dart';

void main() {
  group('AssessmentSummaryService cache key', () {
    final areas = [
      {'name': 'Communication', 'level': 'Emerging'},
      {'name': 'Play Skills', 'level': 'Strength'},
    ];

    test('is stable for identical inputs', () {
      final a = AssessmentSummaryService.debugCacheKey(areas, 72, 'moderate');
      final b = AssessmentSummaryService.debugCacheKey(areas, 72, 'moderate');
      expect(a, b);
    });

    test('changes when a level changes', () {
      final base =
          AssessmentSummaryService.debugCacheKey(areas, 72, 'moderate');
      final changed = AssessmentSummaryService.debugCacheKey(
        [
          {'name': 'Communication', 'level': 'Strength'}, // was Emerging
          {'name': 'Play Skills', 'level': 'Strength'},
        ],
        72,
        'moderate',
      );
      expect(base, isNot(changed));
    });

    test('changes when the overall percent changes', () {
      final a = AssessmentSummaryService.debugCacheKey(areas, 72, 'moderate');
      final b = AssessmentSummaryService.debugCacheKey(areas, 80, 'moderate');
      expect(a, isNot(b));
    });

    test('a progress key (with previous areas) differs from a snapshot',
        () {
      final snapshot =
          AssessmentSummaryService.debugCacheKey(areas, 72, 'moderate');
      final progress = AssessmentSummaryService.debugCacheKey(
        areas,
        72,
        'moderate',
        [
          {'name': 'Communication', 'level': 'Needs Support'},
          {'name': 'Play Skills', 'level': 'Emerging'},
        ],
      );
      expect(snapshot, isNot(progress));
    });
  });
}
