import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../model/child_profile.dart';

/// Widget for selecting reward preferences
/// Shows visual previews of each reward type
class RewardPreferenceSelector extends StatelessWidget {
  final RewardPreference selectedPreference;
  final bool useRandomReward;
  final ValueChanged<RewardPreference> onPreferenceChanged;
  final ValueChanged<bool> onRandomChanged;
  final bool showSkipOption;
  final VoidCallback? onSkip;

  const RewardPreferenceSelector({
    super.key,
    required this.selectedPreference,
    required this.useRandomReward,
    required this.onPreferenceChanged,
    required this.onRandomChanged,
    this.showSkipOption = true,
    this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        Text(
          'Choose a Reward Style',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: const Color(0xFF9B82C4),
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'This celebration will show when your child completes games!',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Colors.grey.shade600,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),

        // Reward options grid
        LayoutBuilder(
          builder: (context, constraints) {
            final crossAxisCount = constraints.maxWidth > 500 ? 3 : 2;
            final spacing = 12.0;
            final itemWidth = (constraints.maxWidth - spacing * (crossAxisCount - 1)) / crossAxisCount;
            // Cards share one fixed size so the grid stays even. The height
            // has to clear the tallest card content — 60px icon, title, two
            // description lines and the selection tick every card reserves
            // room for — and grow with the text scale so large-font users
            // don't overflow it on narrow phones.
            final textScale = MediaQuery.textScalerOf(context).scale(1);
            final itemHeight = math.max(itemWidth * 1.25, 116 + 60 * textScale);

            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              alignment: WrapAlignment.center,
              children: [
                // Regular reward types
                ...RewardPreference.values.where((p) => p != RewardPreference.random).map((preference) {
                  final isSelected = !useRandomReward && selectedPreference == preference;
                  return SizedBox(
                    width: itemWidth,
                    height: itemHeight,
                    child: _RewardOptionCard(
                      preference: preference,
                      isSelected: isSelected,
                      onTap: () {
                        onRandomChanged(false);
                        onPreferenceChanged(preference);
                      },
                    ),
                  );
                }),

                // Random option
                SizedBox(
                  width: itemWidth,
                  height: itemHeight,
                  child: _RewardOptionCard(
                    preference: RewardPreference.random,
                    isSelected: useRandomReward || selectedPreference == RewardPreference.random,
                    onTap: () => onRandomChanged(true),
                  ),
                ),
              ],
            );
          },
        ),

        const SizedBox(height: 24),

        // Skip option
        if (showSkipOption && onSkip != null)
          Center(
            child: TextButton(
              onPressed: onSkip,
              child: Text(
                'Skip for now (use default)',
                style: TextStyle(
                  color: Colors.grey.shade500,
                  fontSize: 14,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Individual reward option card
class _RewardOptionCard extends StatelessWidget {
  final RewardPreference preference;
  final bool isSelected;
  final VoidCallback onTap;

  const _RewardOptionCard({
    required this.preference,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final displayName = _getDisplayName();
    final emoji = _getEmoji();
    final description = _getDescription();
    final bgColor = _getBackgroundColor();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: isSelected ? bgColor.withAlpha(150) : Colors.grey.shade50,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? const Color(0xFF9B82C4) : Colors.grey.shade300,
              width: isSelected ? 3 : 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: const Color(0xFF9B82C4).withAlpha(50),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Emoji/icon
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: bgColor.withAlpha(100),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    emoji,
                    style: const TextStyle(fontSize: 32),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Name
              Text(
                displayName,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? const Color(0xFF9B82C4) : Colors.grey.shade700,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 4),

              // Description
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  description,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade500,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              // Selection indicator. Its space is reserved on every card so
              // selecting one doesn't make it taller than the others — that
              // mismatch is what used to overflow the fixed-height card.
              Visibility(
                visible: isSelected,
                maintainSize: true,
                maintainAnimation: true,
                maintainState: true,
                child: const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Icon(
                    Icons.check_circle,
                    color: Color(0xFF9B82C4),
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getDisplayName() {
    switch (preference) {
      case RewardPreference.balloons:
        return 'Balloons';
      case RewardPreference.fireworks:
        return 'Fireworks';
      case RewardPreference.bubbles:
        return 'Bubbles';
      case RewardPreference.candy:
        return 'Candy';
      case RewardPreference.random:
        return 'Surprise!';
    }
  }

  String _getEmoji() {
    switch (preference) {
      case RewardPreference.balloons:
        return '🎈';
      case RewardPreference.fireworks:
        return '🎆';
      case RewardPreference.bubbles:
        return '🫧';
      case RewardPreference.candy:
        return '🍬';
      case RewardPreference.random:
        return '🎲';
    }
  }

  String _getDescription() {
    switch (preference) {
      case RewardPreference.balloons:
        return 'Colorful balloons to pop';
      case RewardPreference.fireworks:
        return 'Rockets and stars';
      case RewardPreference.bubbles:
        return 'Gentle floating bubbles';
      case RewardPreference.candy:
        return 'Sweet treats to collect';
      case RewardPreference.random:
        return 'Different surprise each time';
    }
  }

  Color _getBackgroundColor() {
    switch (preference) {
      case RewardPreference.balloons:
        return const Color(0xFFFFB6C1); // Light pink
      case RewardPreference.fireworks:
        return const Color(0xFFFFE4B5); // Moccasin
      case RewardPreference.bubbles:
        return const Color(0xFFB0E0E6); // Powder blue
      case RewardPreference.candy:
        return const Color(0xFFDDA0DD); // Plum
      case RewardPreference.random:
        return const Color(0xFF98FB98); // Pale green
    }
  }
}

/// Compact reward preference dropdown for settings
class RewardPreferenceDropdown extends StatelessWidget {
  final RewardPreference selectedPreference;
  final bool useRandomReward;
  final ValueChanged<RewardPreference> onPreferenceChanged;
  final ValueChanged<bool> onRandomChanged;

  const RewardPreferenceDropdown({
    super.key,
    required this.selectedPreference,
    required this.useRandomReward,
    required this.onPreferenceChanged,
    required this.onRandomChanged,
  });

  @override
  Widget build(BuildContext context) {
    final currentDisplay = useRandomReward || selectedPreference == RewardPreference.random
        ? '🎲 Surprise!'
        : '${_getEmoji(selectedPreference)} ${_getDisplayName(selectedPreference)}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: PopupMenuButton<RewardPreference?>(
        onSelected: (preference) {
          if (preference == null) {
            // Random selected
            onRandomChanged(true);
          } else {
            onRandomChanged(false);
            onPreferenceChanged(preference);
          }
        },
        itemBuilder: (context) => [
          // Regular preferences
          ...RewardPreference.values.where((p) => p != RewardPreference.random).map((preference) {
            return PopupMenuItem(
              value: preference,
              child: Row(
                children: [
                  Text(_getEmoji(preference), style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 12),
                  Text(_getDisplayName(preference)),
                  if (!useRandomReward && selectedPreference == preference)
                    const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: Icon(Icons.check, size: 18, color: Color(0xFF9B82C4)),
                    ),
                ],
              ),
            );
          }),

          const PopupMenuDivider(),

          // Random option
          PopupMenuItem(
            value: null, // null represents random
            child: Row(
              children: [
                const Text('🎲', style: TextStyle(fontSize: 20)),
                const SizedBox(width: 12),
                const Text('Surprise Me!'),
                if (useRandomReward || selectedPreference == RewardPreference.random)
                  const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Icon(Icons.check, size: 18, color: Color(0xFF9B82C4)),
                  ),
              ],
            ),
          ),
        ],
        child: Row(
          children: [
            Text(
              currentDisplay,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            Icon(Icons.arrow_drop_down, color: Colors.grey.shade500),
          ],
        ),
      ),
    );
  }

  String _getDisplayName(RewardPreference preference) {
    switch (preference) {
      case RewardPreference.balloons:
        return 'Balloons';
      case RewardPreference.fireworks:
        return 'Fireworks';
      case RewardPreference.bubbles:
        return 'Bubbles';
      case RewardPreference.candy:
        return 'Candy';
      case RewardPreference.random:
        return 'Surprise!';
    }
  }

  String _getEmoji(RewardPreference preference) {
    switch (preference) {
      case RewardPreference.balloons:
        return '🎈';
      case RewardPreference.fireworks:
        return '🎆';
      case RewardPreference.bubbles:
        return '🫧';
      case RewardPreference.candy:
        return '🍬';
      case RewardPreference.random:
        return '🎲';
    }
  }
}
