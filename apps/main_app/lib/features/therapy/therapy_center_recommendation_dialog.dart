import 'package:flutter/material.dart';

import 'package:shared_ui/shared_ui.dart';

import 'therapy_directory_screen.dart';

/// Offers an optional, non-clinical route to the therapy-center directory.
///
/// The directory reads the active child from [ChildProvider]; this action only
/// pushes its existing route and never changes the selected child.
Future<void> showTherapyCenterRecommendation(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => PopScope(
      canPop: false,
      child: AlertDialog(
        backgroundColor: AppColors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Text(
          'Explore Therapy Center support',
          style: AppTextStyles.titleLarge.copyWith(
            color: AppColors.textPrimary,
          ),
        ),
        content: Text(
          'These results suggest that extra support may be helpful. This '
          'assessment is based on game performance only and is not a medical '
          'diagnosis. You can browse Therapy Centers for consultation and '
          'support options.',
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.mutedForeground,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Maybe Later'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const TherapyDirectoryScreen(),
                ),
              );
            },
            child: const Text('Browse Therapy Centers'),
          ),
        ],
      ),
    ),
  );
}

class TherapyCenterRecommendationTrigger extends StatefulWidget {
  const TherapyCenterRecommendationTrigger({
    super.key,
    required this.child,
    required this.shouldShow,
  });

  final Widget child;
  final bool shouldShow;

  @override
  State<TherapyCenterRecommendationTrigger> createState() =>
      _TherapyCenterRecommendationTriggerState();
}

class _TherapyCenterRecommendationTriggerState
    extends State<TherapyCenterRecommendationTrigger> {
  @override
  void initState() {
    super.initState();
    if (widget.shouldShow) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showTherapyCenterRecommendation(context);
      });
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
