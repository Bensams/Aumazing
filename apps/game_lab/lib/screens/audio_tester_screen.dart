import 'package:flutter/material.dart';
import 'package:shared_audio/shared_audio.dart';
import 'package:shared_ui/shared_ui.dart';

import '../services/game_lab_services.dart';

/// A dedicated screen for testing all audio features in Game Lab.
///
/// Provides controls to:
/// - Play any [VoiceOverCue] from a categorized list
/// - Play each SFX type (correct, wrong, tap, drag, drop, level complete, game complete)
/// - Toggle BG music on/off
/// - Adjust volumes in real-time
/// - See playback status
class AudioTesterScreen extends StatefulWidget {
  const AudioTesterScreen({super.key});

  @override
  State<AudioTesterScreen> createState() => _AudioTesterScreenState();
}

class _AudioTesterScreenState extends State<AudioTesterScreen> {
  final _services = GameLabServices.instance;
  AudioService get _audio => _services.audioService;
  VoiceOverService get _vo => _services.voiceOverService;

  VoiceOverCategory _selectedCategory = VoiceOverCategory.corePraise;
  String _lastAction = 'None';
  bool _musicPlaying = false;

  /// Filename of the track currently auditioning, or null when stopped.
  String? _playingTrack;

  // Group cues by category for display
  static final Map<VoiceOverCategory, List<VoiceOverCue>> _cuesByCategory = () {
    final map = <VoiceOverCategory, List<VoiceOverCue>>{};
    for (final cue in VoiceOverCue.values) {
      final cat = _getCueCategory(cue);
      map.putIfAbsent(cat, () => []).add(cue);
    }
    return map;
  }();

  static VoiceOverCategory _getCueCategory(VoiceOverCue cue) {
    // Map cues to categories based on their enum position
    final name = cue.name;
    // The naming-feedback families are prefixed, so they need no roster here —
    // and unlike the lists below, a new colour or item stays classified.
    if (name.startsWith('phrase')) return VoiceOverCategory.phrases;
    if (name.startsWith('color')) return VoiceOverCategory.colors;
    if (name.startsWith('shape')) return VoiceOverCategory.shapes;
    if (name.startsWith('letter')) return VoiceOverCategory.letters;
    if (name.startsWith('number')) return VoiceOverCategory.numbers;
    if (name.startsWith('item')) return VoiceOverCategory.items;
    if (['tapThe', 'dragThe', 'dropThe'].contains(name)) {
      return VoiceOverCategory.dynamic;
    }
    if (['canYouCopyMe', 'canYouMatchThis', 'findTheRightOne', 'goodListening',
         'goodLooking', 'letSeeWhatYouCanDo', 'letsTryTheNextTask', 'showMe',
         'whatComesNext', 'whichOneIsTheSame'].contains(name)) {
      return VoiceOverCategory.assessmentStyle;
    }
    if (['calmBody', 'eyesHere', 'goodCalmingDown', 'itsOkay', 'letsContinue',
         'letsSlowDown', 'listenCarefully', 'readyAgain', 'takeABreath',
         'youAreSafe'].contains(name)) {
      return VoiceOverCategory.attentionAndRegulation;
    }
    if (['aumazing', 'ausome', 'correct', 'excellent', 'greatJob',
         'niceWork', 'thatsRight', 'veryGood', 'wellDone', 'yayYouGotIt',
         'youDidIt'].contains(name)) {
      return VoiceOverCategory.corePraise;
    }
    if (['almostThere', 'giveItAnotherTry', 'keepGoing', 'letsDoItOneMoreTime',
         'letsPracticeAgain', 'letsTryAgain', 'niceTry', 'notYet', 'tryAgain',
         'youCanDoIt'].contains(name)) {
      return VoiceOverCategory.gentlyRetry;
    }
    if (['chooseOne', 'copyMe', 'countWithMe', 'dragIt', 'findTheSame',
         'followMe', 'letsBegin', 'listen', 'matchIt', 'myTurnInstruction',
         'pickTheColor', 'pickTheShape', 'tapHere', 'touchThePicture',
         'watchCarefully', 'yourTurnInstruction'].contains(name)) {
      return VoiceOverCategory.instruction;
    }
    if (['awesomeWorkToday', 'bigHighFive', 'fantastic', 'gameFinished',
         'greatPlaying', 'hooray', 'superJob', 'youDidSoWell', 'youFinishedIt',
         'youreAmazing'].contains(name)) {
      return VoiceOverCategory.rewardAndCelebration;
    }
    if (['getReady', 'goodJobMovingOn', 'letsGo',
         'letsPlayAgain', 'levelComplete', 'newRound', 'nextActivity',
         'nextOne', 'timeForTheNextOne'].contains(name)) {
      return VoiceOverCategory.transition;
    }
    // Default: turn taking
    return VoiceOverCategory.turnTaking;
  }

  String _categoryLabel(VoiceOverCategory cat) {
    switch (cat) {
      case VoiceOverCategory.assessmentStyle:
        return '📋 Assessment';
      case VoiceOverCategory.attentionAndRegulation:
        return '🧘 Attention';
      case VoiceOverCategory.corePraise:
        return '⭐ Praise';
      case VoiceOverCategory.gentlyRetry:
        return '🔄 Retry';
      case VoiceOverCategory.instruction:
        return '📝 Instruction';
      case VoiceOverCategory.rewardAndCelebration:
        return '🎉 Celebration';
      case VoiceOverCategory.transition:
        return '➡️ Transition';
      case VoiceOverCategory.turnTaking:
        return '🤝 Turn Taking';
      case VoiceOverCategory.dynamic:
        return '🎬 Dynamic';
      case VoiceOverCategory.colors:
        return '🎨 Colors';
      case VoiceOverCategory.shapes:
        return '🔷 Shapes';
      case VoiceOverCategory.phrases:
        return '🗣 Phrases';
      case VoiceOverCategory.letters:
        return '🔤 Letters';
      case VoiceOverCategory.numbers:
        return '🔢 Numbers';
      case VoiceOverCategory.items:
        return '🛒 Items';
      case VoiceOverCategory.routines:
        return '🗓 Routines';
      case VoiceOverCategory.emotions:
        return '🙂 Emotions';
      case VoiceOverCategory.milestone:
        return '🏆 Milestone';
    }
  }

  String _cueFriendlyName(VoiceOverCue cue) {
    // Convert camelCase to Title Case with spaces
    final name = cue.name;
    final buffer = StringBuffer();
    for (int i = 0; i < name.length; i++) {
      if (i > 0 && name[i].toUpperCase() == name[i] && name[i] != name[i].toLowerCase()) {
        buffer.write(' ');
      }
      buffer.write(i == 0 ? name[i].toUpperCase() : name[i]);
    }
    return buffer.toString();
  }

  void _playCue(VoiceOverCue cue) {
    _vo.play(cue);
    setState(() {
      _lastAction = 'VO: ${cue.name}';
      _services.lastPlayedVo = cue.name;
    });
  }

  void _playSfx(String name, Future<void> Function() playFn) {
    playFn();
    setState(() {
      _lastAction = 'SFX: $name';
      _services.lastPlayedSfx = name;
    });
  }

  /// Play one specific track, so the whole library can be auditioned.
  ///
  /// This deliberately bypasses [AudioService.playCategoryMusic] — that method
  /// picks at random and no-ops on a repeat call, which is right for the app
  /// and useless for checking a particular file.
  void _playTrack(BgmCategory category, BgmTrack track) {
    _audio.playMusic(category.trackPath(track));
    setState(() {
      _playingTrack = track.file;
      _musicPlaying = true;
      _lastAction = 'Music: ${category.key}/${track.file}';
    });
  }

  void _stopMusic() {
    _audio.stopMusic();
    setState(() {
      _playingTrack = null;
      _musicPlaying = false;
    });
  }

  @override
  void dispose() {
    // Stop music if it was started in this screen
    if (_musicPlaying) {
      _audio.stopMusic();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration:
            const BoxDecoration(gradient: AppGradients.parentLavenderMint),
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '🎧 Audio Tester',
                      style: AppTextStyles.headlineMedium.copyWith(
                        color: AppColors.primaryPurple,
                      ),
                    ),
                    const Spacer(),
                    // Status chip
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Last: $_lastAction',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Main content
              Expanded(
                child: Row(
                  children: [
                    // ── Left: SFX + Music Controls ─────────────────
                    SizedBox(
                      width: 260,
                      child: _buildSfxPanel(),
                    ),

                    // ── Right: Voice-Over Cues ─────────────────────
                    Expanded(
                      child: _buildVoiceOverPanel(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSfxPanel() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 6, 12),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(230),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // SFX Section
            Text('🔊 Sound Effects',
                style: AppTextStyles.titleMedium
                    .copyWith(color: AppColors.primaryPurple)),
            const SizedBox(height: 12),

            _buildSfxButton('✅ Correct', 'correct', _audio.playCorrectSfx),
            _buildSfxButton('❌ Wrong', 'wrong', _audio.playWrongSfx),
            _buildSfxButton('👆 Game Tap', 'game_tap', _audio.playGameTapSfx),
            _buildSfxButton('🫳 Drag', 'drag', _audio.playDragSfx),
            _buildSfxButton('📥 Drop', 'drop', _audio.playDropSfx),
            _buildSfxButton(
                '🏆 Level Complete', 'level_complete', _audio.playLevelCompleteSfx),
            _buildSfxButton(
                '🎊 Game Complete', 'game_complete', _audio.playGameCompleteSfx),
            _buildSfxButton('🔘 UI Tap', 'ui_tap', _audio.playButtonTap),

            const Divider(height: 24),

            // Music Section
            Text('🎵 Background Music',
                style: AppTextStyles.titleMedium
                    .copyWith(color: AppColors.primaryPurple)),
            const SizedBox(height: 12),

            Text(
              'Every track the app can play, grouped by the style a parent '
              'picks in Settings. Tracks loop, so leave one running to hear '
              'whether the loop join is audible.',
              style: AppTextStyles.bodySmall
                  .copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _musicPlaying ? _stopMusic : null,
                icon: const Icon(Icons.stop, size: 20),
                label: const Text('Stop Music'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade400,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppColors.lavenderLight,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
            const SizedBox(height: 12),

            for (final category in kBgmCategories) ...[
              Text(
                '${category.label}  (${category.tracks.length})',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              for (final track in category.tracks)
                _buildTrackButton(category, track),
              const SizedBox(height: 10),
            ],

            const Divider(height: 24),

            // Status Section
            Text('📊 Status',
                style: AppTextStyles.titleMedium
                    .copyWith(color: AppColors.primaryPurple)),
            const SizedBox(height: 8),

            _buildStatusRow('SFX Enabled', _audio.config.sfxEnabled),
            _buildStatusRow('Music Enabled', _audio.config.musicEnabled),
            _buildStatusRow('VO Enabled', _vo.isEnabled),
            _buildStatusRow('VO Playing', _vo.isPlaying),
            _buildStatusRow('Music Playing', _audio.isMusicPlaying),

            const SizedBox(height: 8),
            _buildInfoRow('SFX Vol',
                '${(_audio.config.sfxVolume * 100).round()}%'),
            _buildInfoRow('Music Vol',
                '${(_audio.config.musicVolume * 100).round()}%'),
            _buildInfoRow('VO Vol', '${(_vo.volume * 100).round()}%'),
            _buildInfoRow('Last SFX', _services.lastPlayedSfx),
            _buildInfoRow('Last VO', _services.lastPlayedVo),
          ],
        ),
      ),
    );
  }

  /// One track row. Highlights while it is the one playing, so it is obvious
  /// which file you are hearing when you are working through a category.
  Widget _buildTrackButton(BgmCategory category, BgmTrack track) {
    final playing = _playingTrack == track.file;
    final label = track.title;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: SizedBox(
        width: double.infinity,
        height: 32,
        child: ElevatedButton(
          onPressed: () => _playTrack(category, track),
          style: ElevatedButton.styleFrom(
            backgroundColor:
                playing ? AppColors.primaryPurple : AppColors.lavenderLight,
            foregroundColor: playing ? Colors.white : AppColors.primaryPurple,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: Row(
            children: [
              Icon(playing ? Icons.volume_up : Icons.play_arrow, size: 15),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSfxButton(
      String label, String name, Future<void> Function() playFn) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: SizedBox(
        width: double.infinity,
        height: 36,
        child: ElevatedButton(
          onPressed: () => _playSfx(name, playFn),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.lavenderLight,
            foregroundColor: AppColors.primaryPurple,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: Text(label,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }

  Widget _buildStatusRow(String label, bool value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: AppTextStyles.labelSmall
                  .copyWith(color: AppColors.mutedForeground)),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: value ? Colors.green : Colors.red.shade300,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: AppTextStyles.labelSmall
                  .copyWith(color: AppColors.mutedForeground)),
          Flexible(
            child: Text(
              value.isEmpty ? '—' : value,
              style: AppTextStyles.labelSmall.copyWith(
                color: AppColors.primaryPurple,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVoiceOverPanel() {
    final cues = _cuesByCategory[_selectedCategory] ?? [];

    return Container(
      margin: const EdgeInsets.fromLTRB(6, 0, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(230),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Category selector
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('🗣 Voice-Over Cues',
                    style: AppTextStyles.titleMedium
                        .copyWith(color: AppColors.primaryPurple)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: VoiceOverCategory.values.map((cat) {
                    final isSelected = cat == _selectedCategory;
                    return ChoiceChip(
                      selected: isSelected,
                      onSelected: (_) =>
                          setState(() => _selectedCategory = cat),
                      label: Text(
                        _categoryLabel(cat),
                        style: TextStyle(fontSize: 11),
                      ),
                      selectedColor: AppColors.primaryPurple,
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.white : AppColors.foreground,
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                      ),
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 8),
                // Play random from category
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      _vo.playRandom(_selectedCategory);
                      setState(() {
                        _lastAction =
                            'VO: random ${_selectedCategory.name}';
                        _services.lastPlayedVo =
                            'random (${_selectedCategory.name})';
                      });
                    },
                    icon: const Icon(Icons.shuffle, size: 16),
                    label: Text(
                        'Play Random ${_categoryLabel(_selectedCategory)}'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primaryPurple,
                      side: BorderSide(color: AppColors.primaryPurple),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Cue list
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
                childAspectRatio: 3.5,
              ),
              itemCount: cues.length,
              itemBuilder: (context, index) {
                final cue = cues[index];
                return ElevatedButton(
                  onPressed: () => _playCue(cue),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.lavenderLight,
                    foregroundColor: AppColors.primaryPurple,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    _cueFriendlyName(cue),
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w600),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
