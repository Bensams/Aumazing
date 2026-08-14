import 'package:flutter/material.dart';

import '../../model/area_level.dart';
import '../../widgets/assessment_handoff.dart';
import 'post_assessment_result_screen.dart';

/// Screen shown to the child after all post-assessment games are complete.
///
/// The post-assessment used to drop straight from the last game into
/// [PostAssessmentResultScreen], which is parent-facing — so the child was
/// handed the comparison of their own before/after levels, and no verification
/// stood between them and it. This puts the same child hand-off the
/// pre-assessment has in front of it.
///
/// The finished run's numbers are carried through verbatim rather than
/// recomputed: they were produced by the run that just ended, and re-deriving
/// them here could only disagree with it.
class PostAssessmentHandoffScreen extends StatelessWidget {
  const PostAssessmentHandoffScreen({
    super.key,
    required this.improvement,
    required this.preAreaLevels,
    required this.postAreaLevels,
    this.voiceOverFactory,
  });

  /// Output of AssessmentService.compareAssessments for the completed run.
  final Map<String, dynamic> improvement;

  /// Area levels from the pre-assessment (the frozen baseline).
  final Map<String, AreaLevel> preAreaLevels;

  /// Area levels from the post-assessment prediction just captured.
  final Map<String, AreaLevel> postAreaLevels;

  /// Test seam, forwarded to [AssessmentHandoffScreen].
  final HandoffVoiceOverFactory? voiceOverFactory;

  @override
  Widget build(BuildContext context) {
    return AssessmentHandoffScreen(
      voiceOverFactory: voiceOverFactory,
      onParentVerified: _showResults,
    );
  }

  void _showResults(BuildContext context) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => PostAssessmentResultScreen(
          improvement: improvement,
          preAreaLevels: preAreaLevels,
          postAreaLevels: postAreaLevels,
        ),
      ),
    );
  }
}
