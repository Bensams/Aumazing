import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../assessment_result_data.dart';
import 'assessment_section_card.dart';

/// Recommended Settings — the settings finalized with this assessment run.
///
/// Never regenerated from the child's current settings: reopening an older
/// summary shows what was recommended then.
///
/// With [onApply] the card also *does* something about them. Reading a list
/// of recommendations and then reproducing each one by hand in Settings is
/// the kind of errand that quietly does not get run, so the card offers to
/// write the ones the app can write. It is deliberately a button and not an
/// automatic write: these are the child's settings and the parent is the one
/// who decides they change.
class AssessmentRecommendationsCard extends StatefulWidget {
  const AssessmentRecommendationsCard({
    super.key,
    required this.recommendations,
    this.dense = false,
    this.onApply,
  });

  final List<ResultRecommendation> recommendations;
  final bool dense;

  /// Writes these recommendations to the child's settings. Returns false if
  /// nothing could be saved, which the card reports inline rather than
  /// pretending the settings changed.
  ///
  /// Null hides the button entirely — the game-lab preview and any host with
  /// no child to write to.
  final Future<bool> Function()? onApply;

  @override
  State<AssessmentRecommendationsCard> createState() =>
      _AssessmentRecommendationsCardState();
}

enum _ApplyState { idle, applying, applied, failed }

class _AssessmentRecommendationsCardState
    extends State<AssessmentRecommendationsCard> {
  _ApplyState _state = _ApplyState.idle;

  /// The rows an apply would actually change, and the rows it would not.
  List<ResultRecommendation> get _appliable =>
      widget.recommendations.where((r) => r.appliesToSetting).toList();

  List<ResultRecommendation> get _recordedOnly =>
      widget.recommendations.where((r) => !r.appliesToSetting).toList();

  Future<void> _apply() async {
    final onApply = widget.onApply;
    if (onApply == null) return;
    setState(() => _state = _ApplyState.applying);
    final ok = await onApply();
    if (!mounted) return;
    setState(() => _state = ok ? _ApplyState.applied : _ApplyState.failed);
  }

  @override
  Widget build(BuildContext context) {
    return AssessmentSectionCard(
      label: AssessmentLabels.recommendedSettings,
      emoji: '💡',
      dense: widget.dense,
      children: [
        ...assessmentWithDividers([
          for (final recommendation in widget.recommendations)
            AssessmentKeyValueRow(
              icon: recommendation.icon,
              label: recommendation.label,
              value: recommendation.value,
            ),
        ]),
        if (widget.onApply != null && _appliable.isNotEmpty) ...[
          const SizedBox(height: 12),
          _ApplyButton(
            state: _state,
            onPressed: _apply,
          ),
          const SizedBox(height: 6),
          Text(
            _applyNote(),
            style: AppTextStyles.bodySmall.copyWith(
              color: _state == _ApplyState.failed
                  ? AppColors.destructiveRed
                  : AppColors.mutedForeground,
            ),
          ),
        ],
      ],
    );
  }

  /// The line under the button. It names what will change — and, when some
  /// recommendations have no setting behind them, says so plainly instead of
  /// letting "Applied" imply the whole list was written.
  String _applyNote() {
    if (_state == _ApplyState.failed) {
      return 'Nothing was changed. Please try again.';
    }
    final changes = _appliable.map((r) => r.label.toLowerCase()).join(', ');
    final applied = _state == _ApplyState.applied;
    final head = applied
        ? 'Saved to this child\'s settings: $changes.'
        : 'Changes $changes in this child\'s settings.';
    final rest = _recordedOnly;
    if (rest.isEmpty) return head;
    final names = rest.map((r) => r.label.toLowerCase()).join(', ');
    final one = rest.length == 1;
    return '$head The $names ${one ? 'recommendation has' : 'recommendations '
        'have'} no matching setting yet, so ${one ? 'it is' : 'they are'} '
        'recorded with this assessment only.';
  }
}

class _ApplyButton extends StatelessWidget {
  const _ApplyButton({required this.state, required this.onPressed});

  final _ApplyState state;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final applied = state == _ApplyState.applied;
    final applying = state == _ApplyState.applying;

    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        // Disabled once done: the same settings written twice is harmless,
        // but a button that stays live invites a parent to wonder whether
        // the first press worked.
        onPressed: applied || applying ? null : onPressed,
        icon: applying
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(
                applied ? Icons.check_rounded : Icons.tune_rounded,
                size: 18,
              ),
        label: Text(
          applied
              ? 'Settings updated'
              : applying
                  ? 'Applying…'
                  : 'Use these settings',
        ),
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(kMinInteractiveDimension),
        ),
      ),
    );
  }
}
