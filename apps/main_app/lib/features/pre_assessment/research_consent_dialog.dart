import 'package:flutter/material.dart';

import 'package:shared_ui/shared_ui.dart';

import '../../services/research_consent_service.dart';

/// Parental research consent for the beta test (RA 10173-aligned).
///
/// Shown once per child (re-shown if the consent text version changes).
/// Both choices default to OFF — consent must be affirmative — and
/// declining never blocks the assessment or the app: it only means the
/// child's results stay private to the parent and are excluded from AI
/// training.
class ResearchConsentDialog {
  ResearchConsentDialog._();

  static Future<void> show(BuildContext context,
      {required String childId}) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ResearchConsentContent(childId: childId),
    );
  }
}

class _ResearchConsentContent extends StatefulWidget {
  const _ResearchConsentContent({required this.childId});

  final String childId;

  @override
  State<_ResearchConsentContent> createState() =>
      _ResearchConsentContentState();
}

class _ResearchConsentContentState extends State<_ResearchConsentContent> {
  bool _participate = false;
  bool _aiTraining = false;
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    await ResearchConsentService.instance.record(
      childId: widget.childId,
      participate: _participate,
      aiTraining: _aiTraining,
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          const Icon(Icons.science_rounded, color: AppColors.primaryPurple),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Research Participation (Beta)',
              style: AppTextStyles.titleLarge
                  .copyWith(color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 380),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Aumazing is part of a capstone research study. During '
                'play, the app records gameplay information only — scores, '
                'response times, taps, hints, and idle time. It never '
                'records camera, microphone, or your location. Location is '
                'used only if you ask the Therapy Directory to find centers '
                'near you, and even then it stays on your phone — it is '
                'never saved or included in the study.\n\n'
                'Your choices below are optional: the app and all its '
                'features work the same whichever you pick, and you may '
                'withdraw at any time and ask for your child\'s data to be '
                'deleted by contacting the research team.',
                style: AppTextStyles.bodySmall
                    .copyWith(color: AppColors.mutedForeground),
              ),
              const SizedBox(height: AppSpacing.sm),
              CheckboxListTile(
                value: _participate,
                onChanged: (v) =>
                    setState(() => _participate = v ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'I allow the research team and a licensed SPED '
                  'professional to review my child\'s gameplay results '
                  'for this study.',
                  style: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.textPrimary),
                ),
              ),
              CheckboxListTile(
                value: _aiTraining,
                onChanged: (v) => setState(() => _aiTraining = v ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'I allow my child\'s gameplay data (without their name) '
                  'to be used to improve and train the app\'s '
                  'recommendation AI.',
                  style: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.textPrimary),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primaryPurple,
          ),
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving…' : 'Save my choices'),
        ),
      ],
    );
  }
}
