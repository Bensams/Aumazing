import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../services/overall_gameplay_summary_service.dart';
import '../../../services/rubric/rubric.dart';

/// The parent dashboard's overall gameplay summary: one narrative across the
/// pre-assessment, the recommended activities (with the tries each My Path
/// game took to reach Strength), the post-assessment and any later cycle —
/// free practice is left out — followed by questions to bring to a
/// therapist or practitioner.
///
/// Always says who wrote it: Gemini, Groq (when Gemini is at its limit), or
/// the on-device summarizer when neither answered. A saved AI summary is
/// reused until a new game record arrives; [refreshToken] changing is what
/// asks the service to look again.
class OverallGameplaySummaryCard extends StatefulWidget {
  const OverallGameplaySummaryCard({
    super.key,
    required this.childId,
    required this.pathGameIds,
    required this.pathAttempts,
    required this.refreshToken,
    this.languageCode = 'en',
    this.service,
  });

  final String childId;
  final List<String> pathGameIds;
  final Map<String, PathAttemptRecord> pathAttempts;

  /// Any value that changes when new game records may exist.
  final Object refreshToken;
  final String languageCode;

  /// Injected in tests; defaults to [OverallGameplaySummaryService.instance].
  final OverallGameplaySummaryService? service;

  @override
  State<OverallGameplaySummaryCard> createState() =>
      _OverallGameplaySummaryCardState();
}

class _OverallGameplaySummaryCardState
    extends State<OverallGameplaySummaryCard> {
  GameplaySummaryInput? _input;
  OverallGameplaySummary? _summary;
  bool _loading = true;
  int _generation = 0;

  OverallGameplaySummaryService get _service =>
      widget.service ?? OverallGameplaySummaryService.instance;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(OverallGameplaySummaryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.childId != widget.childId ||
        oldWidget.refreshToken != widget.refreshToken ||
        oldWidget.languageCode != widget.languageCode) {
      _load();
    }
  }

  Future<void> _load({bool forceRefresh = false}) async {
    final generation = ++_generation;
    if (!_loading) setState(() => _loading = true);
    GameplaySummaryInput? input;
    OverallGameplaySummary? summary;
    try {
      input = await _service.buildInput(
        childId: widget.childId,
        pathGameIds: widget.pathGameIds,
        pathAttempts: widget.pathAttempts,
      );
      summary = await _service.summarize(
        childId: widget.childId,
        input: input,
        languageCode: widget.languageCode,
        forceRefresh: forceRefresh,
      );
    } catch (e) {
      debugPrint('[OverallGameplaySummaryCard] load failed: $e');
    }
    // A newer load (child switch, new record) owns the card now.
    if (!mounted || generation != _generation) return;
    setState(() {
      _input = input;
      _summary = summary;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;
    final input = _input;

    return AppCard(
      key: const ValueKey('overallGameplaySummaryCard'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Overall Gameplay Summary',
                style: AppTextStyles.titleMedium.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
              if (summary != null) _SourceChip(source: summary.source),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Pre-assessment, recommended activities and post-assessment. '
            'Free practice is not included.',
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.mutedForeground,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (_loading && summary == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ),
            )
          else if (summary == null)
            Text(
              'Once your child finishes the first assessment, an overall '
              'summary of their games will appear here.',
              key: const ValueKey('overallSummaryEmpty'),
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            )
          else ...[
            if (summary.fromCache)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Text(
                  'Saved summary · no new games since '
                  '${_date(summary.generatedAt)}',
                  key: const ValueKey('overallSummaryCached'),
                  style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.mutedForeground,
                  ),
                ),
              ),
            Text(
              summary.summary,
              key: const ValueKey('overallSummaryText'),
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textPrimary,
                height: 1.45,
              ),
            ),
            if (input != null && input.pathGames.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                'My Path: tries to reach Strength',
                style: AppTextStyles.bodySmallStrong.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              for (final game in input.pathGames) _PathTriesRow(game: game),
            ],
            if (summary.questions.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                'Questions to ask your therapist',
                style: AppTextStyles.bodySmallStrong.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              for (var i = 0; i < summary.questions.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 22,
                        child: Text(
                          '${i + 1}.',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.primaryPurple,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          summary.questions[i],
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: AppSpacing.sm),
            Text(
              switch (summary.source) {
                GameplaySummarySource.gemini =>
                  'Written by Gemini AI from game results only. It '
                      'describes play, not a diagnosis.',
                GameplaySummarySource.groq =>
                  'Gemini AI was at its limit, so Groq AI wrote this '
                      'summary from game results only. It describes play, '
                      'not a diagnosis.',
                GameplaySummarySource.onDevice =>
                  'The AI summarizers were unavailable, so this summary was '
                      'written on this device from game results only. It '
                      'describes play, not a diagnosis.',
              },
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.mutedForeground,
                fontSize: 11,
              ),
            ),
            if (!summary.isAi)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  key: const ValueKey('overallSummaryRetryAi'),
                  onPressed: _loading ? null : () => _load(forceRefresh: true),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Try AI again'),
                ),
              ),
          ],
        ],
      ),
    );
  }

  static String _date(DateTime d) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }
}

/// "AI · Gemini", "AI · Groq" or "On-device summary" — which summarizer
/// wrote the text.
class _SourceChip extends StatelessWidget {
  const _SourceChip({required this.source});

  final GameplaySummarySource source;

  @override
  Widget build(BuildContext context) {
    final (
      String key,
      String label,
      IconData icon,
      Color fg,
      Color bg,
    ) = switch (source) {
      GameplaySummarySource.gemini => (
        'overallSummarySourceAi',
        'AI · Gemini',
        Icons.auto_awesome_rounded,
        AppColors.primaryPurple,
        AppColors.lavenderLight,
      ),
      GameplaySummarySource.groq => (
        'overallSummarySourceGroq',
        'AI · Groq',
        Icons.auto_awesome_rounded,
        AppColors.statusSuccessDark,
        AppColors.statusSuccessBg,
      ),
      GameplaySummarySource.onDevice => (
        'overallSummarySourceDevice',
        'On-device summary',
        Icons.phone_android_rounded,
        AppColors.statusInfoDark,
        AppColors.statusInfoBg,
      ),
    };
    return Container(
      key: ValueKey(key),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppTextStyles.labelSmall.copyWith(
              color: fg,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _PathTriesRow extends StatelessWidget {
  const _PathTriesRow({required this.game});

  final SummaryPathGame game;

  @override
  Widget build(BuildContext context) {
    final String status;
    final Color color;
    final IconData icon;
    if (game.reachedStrength) {
      status =
          'Strength after ${game.tries} ${game.tries == 1 ? 'try' : 'tries'}'
          '${game.retries > 0 ? ' (${game.retries} ${game.retries == 1 ? 'retry' : 'retries'})' : ''}';
      color = AppColors.statusSuccessDark;
      icon = Icons.star_rounded;
    } else if (game.tries > 0) {
      status =
          'Practising · ${game.tries} ${game.tries == 1 ? 'try' : 'tries'} so far';
      color = AppColors.statusWarningDark;
      icon = Icons.replay_rounded;
    } else {
      status = 'Not played yet';
      color = AppColors.mutedForeground;
      icon = Icons.lock_outline_rounded;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              game.name,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Text(
              status,
              textAlign: TextAlign.end,
              style: AppTextStyles.bodySmall.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
