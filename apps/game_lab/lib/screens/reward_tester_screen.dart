import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

/// A screen for testing individual reward types.
///
/// Allows developers to select and preview each reward animation
/// to verify behavior.
class RewardTesterScreen extends StatefulWidget {
  const RewardTesterScreen({super.key});

  @override
  State<RewardTesterScreen> createState() => _RewardTesterScreenState();
}

class _RewardTesterScreenState extends State<RewardTesterScreen> {
  String _selectedReward = 'balloons';
  bool _showingReward = false;

  void _showReward() {
    setState(() => _showingReward = true);
  }

  void _hideReward() {
    setState(() => _showingReward = false);
  }

  Widget _buildRewardWidget() {
    switch (_selectedReward) {
      case 'balloons':
        return BalloonsReward(
          balloonCount: 8,
          duration: const Duration(seconds: 15),
          onComplete: () {},
          onAllPopped: () {},
        );
      case 'fireworks':
        return FireworksReward(
          rocketCount: 6,
          duration: const Duration(seconds: 10),
          onComplete: () {},
          onAllExploded: () {},
        );
      case 'bubbles':
        return BubblesReward(
          bubbleCount: 12,
          duration: const Duration(seconds: 10),
          onComplete: () {},
          onAllPopped: () {},
        );
      case 'candy':
        return CandyReward(
          candyCount: 15,
          duration: const Duration(seconds: 8),
          onComplete: () {},
          onAllCollected: () {},
        );
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppGradients.parentLavenderMint),
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '🎁 Reward Tester',
                      style: AppTextStyles.headlineMedium.copyWith(
                        color: AppColors.primaryPurple,
                      ),
                    ),
                  ],
                ),
              ),

              // Reward Selector
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Select Reward Type',
                          style: AppTextStyles.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _buildRewardChip('balloons', '🎈 Balloons'),
                            _buildRewardChip('fireworks', '🎆 Fireworks'),
                            _buildRewardChip('bubbles', '🫧 Bubbles'),
                            _buildRewardChip('candy', '🍬 Candy'),
                          ],
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _showingReward ? _hideReward : _showReward,
                            icon: Icon(_showingReward ? Icons.stop : Icons.play_arrow),
                            label: Text(_showingReward ? 'Stop Reward' : 'Show Reward'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF9B82C4),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Reward Display Area
              Expanded(
                child: Container(
                  margin: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(200),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppColors.primaryPurple.withAlpha(100),
                      width: 2,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: _showingReward
                        ? Stack(
                            fit: StackFit.expand,
                            children: [
                              _buildRewardWidget(),
                              // Instructions overlay
                              Positioned(
                                top: 16,
                                left: 0,
                                right: 0,
                                child: Center(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withAlpha(220),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      _getInstructions(),
                                      style: AppTextStyles.bodyMedium.copyWith(
                                        color: AppColors.primaryPurple,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          )
                        : Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.touch_app,
                                  size: 48,
                                  color: AppColors.primaryPurple.withAlpha(100),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'Select a reward type and tap "Show Reward"',
                                  style: AppTextStyles.bodyLarge.copyWith(
                                    color: AppColors.mutedForeground,
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRewardChip(String value, String label) {
    final isSelected = _selectedReward == value;
    return ChoiceChip(
      selected: isSelected,
      onSelected: (_) => setState(() => _selectedReward = value),
      label: Text(label),
      selectedColor: const Color(0xFF9B82C4),
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : AppColors.primaryPurple,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  String _getInstructions() {
    switch (_selectedReward) {
      case 'balloons':
        return '🎈 Tap balloons to pop them! They float up from bottom.';
      case 'fireworks':
        return '🎆 Tap rockets to make them explode!';
      case 'bubbles':
        return '🫧 Tap bubbles to pop them!';
      case 'candy':
        return '🍬 Tap candy to collect them!';
      default:
        return '';
    }
  }
}
