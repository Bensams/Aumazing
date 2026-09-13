import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_audio/shared_audio.dart';
import 'package:shared_haptic/shared_haptic.dart';
import 'package:shared_ui/shared_ui.dart';

/// The language, voice, music and prompt choices a parent makes while
/// creating the child's first profile.
///
/// Held as one immutable value so the setup screen carries a single field
/// around its multi-step flow instead of nine loose ones. Every choice here is
/// also reachable later from Settings — capturing them up front means the very
/// first session already sounds the way the parent wants, which matters most
/// for the sound-sensitive children this app is built for.
@immutable
class SoundPreferences {
  const SoundPreferences({
    required this.language,
    required this.voicePackId,
    this.musicEnabled = true,
    this.musicVolume = 0.5,
    this.musicCategory = kDefaultBgmCategory,
    this.musicTrack,
    this.musicTracks,
    this.sfxVolume = 0.7,
    this.vibrationEnabled = true,
    this.promptSpeed = 1.0,
    this.showTextPrompts = true,
  });

  /// English defaults, matching [ChildProfile]'s own defaults.
  factory SoundPreferences.initial() => SoundPreferences(
    language: GameLanguage.english,
    voicePackId: defaultVoicePackForLanguage(GameLanguage.english.slug).id,
  );

  final GameLanguage language;
  final String voicePackId;
  final bool musicEnabled;
  final double musicVolume;
  final String musicCategory;
  final String? musicTrack;
  final List<String>? musicTracks;
  final double sfxVolume;
  final bool vibrationEnabled;
  final double promptSpeed;
  final bool showTextPrompts;

  /// The chosen pack, falling back to the language default if the stored id
  /// is not one this build ships.
  VoicePack get voicePack =>
      voicePackById(voicePackId) ?? defaultVoicePackForLanguage(language.slug);

  SoundPreferences copyWith({
    GameLanguage? language,
    String? voicePackId,
    bool? musicEnabled,
    double? musicVolume,
    String? musicCategory,
    String? musicTrack,
    bool clearMusicTrack = false,
    List<String>? musicTracks,
    bool clearMusicTracks = false,
    double? sfxVolume,
    bool? vibrationEnabled,
    double? promptSpeed,
    bool? showTextPrompts,
  }) {
    return SoundPreferences(
      language: language ?? this.language,
      voicePackId: voicePackId ?? this.voicePackId,
      musicEnabled: musicEnabled ?? this.musicEnabled,
      musicVolume: musicVolume ?? this.musicVolume,
      musicCategory: musicCategory ?? this.musicCategory,
      musicTrack: clearMusicTrack ? null : musicTrack ?? this.musicTrack,
      musicTracks: clearMusicTracks ? null : musicTracks ?? this.musicTracks,
      sfxVolume: sfxVolume ?? this.sfxVolume,
      vibrationEnabled: vibrationEnabled ?? this.vibrationEnabled,
      promptSpeed: promptSpeed ?? this.promptSpeed,
      showTextPrompts: showTextPrompts ?? this.showTextPrompts,
    );
  }
}

/// Setup step where the parent picks how the app sounds and speaks.
///
/// Choices are auditioned as they are made — tapping a voice speaks a sample,
/// tapping a music style starts it playing — because a parent cannot judge
/// "Gentle Playful" from its name alone. Nothing is written to the profile
/// here; the setup screen persists the value once the child record exists.
class SoundPreferencesStep extends StatefulWidget {
  const SoundPreferencesStep({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final SoundPreferences value;
  final ValueChanged<SoundPreferences> onChanged;

  @override
  State<SoundPreferencesStep> createState() => _SoundPreferencesStepState();
}

class _SoundPreferencesStepState extends State<SoundPreferencesStep> {
  /// Throwaway player used only for auditioning voices; the games build
  /// their own.
  VoiceOverService? _voicePreview;
  String? _voicePreviewFolder;

  /// Which style is expanded to show its individual tracks. Defaults to none,
  /// so the list opens as six calm choices rather than thirty.
  String? _expandedKey;

  /// Path of the track being auditioned, so the row can show it is playing.
  String? _previewPath;
  final Set<String> _mixDraft = <String>{};
  String _mixFallbackCategory = kDefaultBgmCategory;

  SoundPreferences get _value => widget.value;

  static const _tierHeadings = {
    'adult': 'Grown-up voices',
    'young': 'Teen voices',
    'child': 'Child voices',
  };

  @override
  void initState() {
    super.initState();
    _syncMixDraft(widget.value);
  }

  @override
  void didUpdateWidget(covariant SoundPreferencesStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value.musicTracks != widget.value.musicTracks ||
        (oldWidget.value.musicCategory != widget.value.musicCategory &&
            widget.value.musicCategory != kCustomMixBgmCategory)) {
      _syncMixDraft(widget.value);
    }
  }

  void _syncMixDraft(SoundPreferences value) {
    final tracks = value.musicTracks;
    if (tracks == null) {
      _mixDraft.clear();
      if (value.musicCategory != kCustomMixBgmCategory) {
        _mixFallbackCategory = value.musicCategory;
      }
      return;
    }
    _mixDraft
      ..clear()
      ..addAll(validBgmTrackPaths(tracks));
  }

  @override
  void dispose() {
    _voicePreview?.dispose();
    super.dispose();
  }

  Future<void> _playVoicePreview(VoicePack pack) async {
    // Rebuild the throwaway player whenever the audition target changes.
    if (_voicePreviewFolder != pack.assetFolder) {
      final previous = _voicePreview;
      _voicePreview = VoiceOverService(languageCode: pack.assetFolder);
      _voicePreviewFolder = pack.assetFolder;
      await previous?.dispose();
    }
    // Audition at the pace the child will actually hear: the same voice sounds
    // quite different stretched towards 0.6x.
    _voicePreview?.setSpeed(voiceRateForPromptSpeed(_value.promptSpeed));
    await _voicePreview?.play(VoiceOverCue.greatJob);
  }

  /// Speaks a sample at the pace the slider was just released at.
  Future<void> _playPromptSpeedSample() => _playVoicePreview(_value.voicePack);

  /// Switching language moves the voice to that language's default, so audio
  /// and on-screen text can never drift apart.
  void _selectLanguage(GameLanguage language) {
    final current = voicePackById(_value.voicePackId);
    final voicePackId =
        current != null && current.languageSlug == language.slug
            ? current.id
            : defaultVoicePackForLanguage(language.slug).id;
    widget.onChanged(
      _value.copyWith(language: language, voicePackId: voicePackId),
    );
  }

  Future<void> _selectVoicePack(VoicePack pack) async {
    widget.onChanged(_value.copyWith(voicePackId: pack.id));
    await _playVoicePreview(pack);
  }

  void _setMusicEnabled(bool enabled) {
    widget.onChanged(_value.copyWith(musicEnabled: enabled));
    final audio = context.read<AudioService>();
    audio.updateConfig(
      audio.config.copyWith(
        musicEnabled: enabled,
        musicVolume: _value.musicVolume,
      ),
    );
    if (enabled) {
      if (_value.musicTracks != null) {
        audio.playConfiguredMix(_value.musicTracks!, restart: true);
      } else if (_value.musicTrack != null) {
        try {
          audio.playConfiguredMusic(
            categoryKey: _value.musicCategory,
            trackPath: _value.musicTrack,
            restart: true,
          );
        } on NoSuchMethodError {
          final match = bgmTrackByPath(_value.musicTrack!);
          if (match != null) audio.playCategoryTrack(match.$1, match.$2);
        }
      } else {
        audio.playCategoryMusic(_value.musicCategory, restart: true);
      }
    } else {
      audio.stopMusic();
      setState(() => _previewPath = null);
    }
  }

  void _setMusicVolume(double volume) {
    widget.onChanged(_value.copyWith(musicVolume: volume));
    final audio = context.read<AudioService>();
    audio.updateConfig(audio.config.copyWith(musicVolume: volume));
  }

  Future<void> _selectMusicCategory(BgmCategory category) async {
    _mixDraft.clear();
    _mixFallbackCategory = category.key;
    widget.onChanged(
      _value.copyWith(
        musicCategory: category.key,
        clearMusicTrack: true,
        clearMusicTracks: true,
      ),
    );
    if (!_value.musicEnabled) return;
    final audio = context.read<AudioService>();
    audio.updateConfig(
      audio.config.copyWith(
        musicEnabled: _value.musicEnabled,
        musicVolume: _value.musicVolume,
      ),
    );
    // restart: true so the parent hears the style they just tapped rather
    // than whatever is already looping.
    await audio.playCategoryMusic(category.key, restart: true);
    if (!mounted) return;
    setState(() => _previewPath = audio.currentTrack);
  }

  Future<void> _toggleMixTrack(BgmCategory category, BgmTrack track) async {
    final path = category.trackPath(track);
    if (!_mixDraft.contains(path) && _mixDraft.length >= kMaxCustomMixTracks) {
      return;
    }
    if (_mixDraft.isEmpty && _value.musicCategory != kCustomMixBgmCategory) {
      _mixFallbackCategory = _value.musicCategory;
    }
    setState(() {
      if (_mixDraft.contains(path)) {
        _mixDraft.remove(path);
      } else {
        _mixDraft.add(path);
      }
    });
    if (_mixDraft.length < kMinCustomMixTracks) {
      // A partial draft is kept in the picker, but never persisted as a
      // playable mix. Returning to the previous category keeps the profile
      // valid while the parent is still choosing.
      widget.onChanged(
        _value.copyWith(
          musicCategory: _mixFallbackCategory,
          clearMusicTrack: true,
          clearMusicTracks: true,
        ),
      );
      return;
    }
    widget.onChanged(
      _value.copyWith(
        musicCategory: kCustomMixBgmCategory,
        musicTracks: List.unmodifiable(_mixDraft.toList()),
        clearMusicTrack: true,
      ),
    );
    if (_value.musicEnabled) {
      final audio = context.read<AudioService>();
      await audio.playConfiguredMix(_mixDraft.toList(), restart: true);
      if (mounted) setState(() => _previewPath = audio.currentTrack);
    }
  }

  Future<void> _selectMusicTrack(BgmCategory category, BgmTrack track) async {
    final path = category.trackPath(track);
    _mixDraft.clear();
    _mixFallbackCategory = category.key;
    widget.onChanged(
      _value.copyWith(
        musicCategory: category.key,
        musicTrack: path,
        clearMusicTracks: true,
      ),
    );
    if (!_value.musicEnabled) return;
    final audio = context.read<AudioService>();
    try {
      await audio.playConfiguredMusic(
        categoryKey: category.key,
        trackPath: path,
        restart: true,
      );
    } on NoSuchMethodError {
      // Keep older test hosts and embedders source-compatible while the
      // concrete service gains exact-track playback.
      await audio.playCategoryTrack(category, track);
    }
    if (mounted) setState(() => _previewPath = path);
  }

  /// Auditions one named track. Previewing deliberately does not change which
  /// style is selected, so a parent can listen through everything before
  /// committing their child to one.
  Future<void> _previewTrack(BgmCategory category, BgmTrack track) async {
    if (!_value.musicEnabled) return;
    final audio = context.read<AudioService>();
    audio.updateConfig(
      audio.config.copyWith(
        musicEnabled: _value.musicEnabled,
        musicVolume: _value.musicVolume,
      ),
    );
    await audio.playCategoryTrack(category, track);
    if (!mounted) return;
    setState(() => _previewPath = audio.currentTrack);
  }

  void _setSfxVolume(double volume) {
    widget.onChanged(_value.copyWith(sfxVolume: volume));
    final audio = context.read<AudioService>();
    audio.updateConfig(audio.config.copyWith(sfxVolume: volume));
  }

  void _setVibrationEnabled(bool enabled) {
    widget.onChanged(_value.copyWith(vibrationEnabled: enabled));
    final haptic = context.read<HapticService>();
    haptic.updateConfig(haptic.config.copyWith(enabled: enabled));
    // Let the parent feel what they just switched on.
    if (enabled) haptic.lightImpact();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PrefsCard(
          children: [
            const _SectionLabel('Background Music'),
            const _HintText(
              'Choose from six music styles. Tap a style to select it and '
              'hear a preview. Turn music off for quiet play. You can change '
              'your choice later in Settings → Audio.',
            ),
            const SizedBox(height: AppSpacing.xs),
            _ToggleRow(
              icon: Icons.music_note_rounded,
              label: 'Play background music',
              value: _value.musicEnabled,
              onChanged: _setMusicEnabled,
            ),
            if (_value.musicEnabled) ...[
              _SliderRow(
                label: 'Music volume',
                value: _value.musicVolume,
                onChanged: _setMusicVolume,
              ),
              const SizedBox(height: AppSpacing.xs),
            ] else
              const _HintText(
                'Music is muted. Your chosen style is kept. Turn music on '
                'to hear previews.',
              ),
            _buildMusicStylePicker(),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        _PrefsCard(
          children: [
            const _SectionLabel('Language'),
            const _HintText(
              'Sets the on-screen words and the language the app speaks in.',
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final language in GameLanguage.values)
                  ChoiceChip(
                    label: Text(language.label),
                    selected: _value.language == language,
                    selectedColor: AppColors.primaryPurple,
                    labelStyle: AppTextStyles.bodySmall.copyWith(
                      color:
                          _value.language == language
                              ? AppColors.white
                              : AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                    onSelected: (_) => _selectLanguage(language),
                  ),
              ],
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        _PrefsCard(
          children: [
            const _SectionLabel('Voice'),
            const _HintText(
              'Who reads the prompts aloud. Tap a voice to hear a sample — '
              'many children settle faster with a voice close to their own '
              'age.',
            ),
            _buildVoicePicker(),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        _PrefsCard(
          children: [
            const _SectionLabel('Sound & Touch'),
            const SizedBox(height: AppSpacing.xs),
            _SliderRow(
              label: 'Sound effects',
              value: _value.sfxVolume,
              onChanged: _setSfxVolume,
              // Play a sample only once the parent lets go, so dragging does
              // not fire a burst of clicks.
              onChangeEnd: (_) => context.read<AudioService>().playButtonTap(),
            ),
            _ToggleRow(
              icon: Icons.vibration_rounded,
              label: 'Vibration',
              value: _value.vibrationEnabled,
              onChanged: _setVibrationEnabled,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        _PrefsCard(
          children: [
            const _SectionLabel('Prompts'),
            const SizedBox(height: AppSpacing.xs),
            _SliderRow(
              label: 'Prompt speed',
              value: _value.promptSpeed,
              onChanged:
                  (val) => widget.onChanged(_value.copyWith(promptSpeed: val)),
              // Dragging is silent; the sample plays on release so a drag does
              // not stutter out ten half-cues.
              onChangeEnd: (_) => _playPromptSpeedSample(),
            ),
            const _HintText(
              'How quickly the chosen voice speaks its instructions. Slower '
              'stretches the words without changing the voice, giving more '
              'time to process each one. Release the slider to hear it.',
            ),
            const SizedBox(height: AppSpacing.sm),
            _ToggleRow(
              icon: Icons.chat_bubble_outline_rounded,
              label: 'Show instruction text',
              value: _value.showTextPrompts,
              onChanged:
                  (val) =>
                      widget.onChanged(_value.copyWith(showTextPrompts: val)),
            ),
            const _HintText(
              'Turn off for pre-readers or children who find text busy. The '
              'spoken instruction still plays either way.',
            ),
          ],
        ),
      ],
    );
  }

  /// Voice chips grouped by age tier. A flat list of six or seven voices per
  /// language would be a wall of chips; the headings give the parent a way to
  /// narrow down before auditioning.
  Widget _buildVoicePicker() {
    final languageSlug = _value.language.slug;
    final selectedId = _value.voicePack.id;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final tier in voiceTiersForLanguage(languageSlug)) ...[
          if (tier != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              _tierHeadings[tier] ?? tier,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
          ],
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              for (final pack in voicePacksForTier(languageSlug, tier))
                _buildVoiceChip(
                  pack,
                  pack.id == selectedId,
                  tier == null ? null : _tierHeadings[tier],
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildVoiceChip(VoicePack pack, bool selected, String? tierHeading) {
    // Every tier offers a "Girl" and a "Boy", so the visible label alone is
    // ambiguous once the heading has scrolled out of view. Screen readers get
    // the heading folded in; sighted parents still read the short label.
    final spokenName =
        tierHeading == null ? pack.label : '$tierHeading: ${pack.label}';

    // The preview button sits outside the chip: nesting it in the chip's
    // label lets the chip's own InkWell swallow the tap.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ChoiceChip(
          selected: selected,
          selectedColor: AppColors.primaryPurple,
          label: Text(pack.label, semanticsLabel: spokenName),
          labelStyle: AppTextStyles.bodySmall.copyWith(
            color: selected ? AppColors.white : AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
          onSelected: (_) => _selectVoicePack(pack),
        ),
        const SizedBox(width: 2),
        IconButton(
          onPressed: () => _playVoicePreview(pack),
          icon: const Icon(Icons.volume_up_rounded, size: 22),
          color: AppColors.primaryPurple,
          tooltip: 'Hear $spokenName',
          constraints: const BoxConstraints(
            minWidth: kMinInteractiveDimension,
            minHeight: kMinInteractiveDimension,
          ),
        ),
      ],
    );
  }

  /// The style list keeps the first screen calm: each category is collapsed,
  /// while the optional custom mix opens a second list containing all bundled
  /// tracks. A track row has two deliberately separate actions — selecting
  /// the row persists it, and the speaker button only auditions it.
  Widget _buildMusicStylePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Music Style',
          style: AppTextStyles.bodySmall.copyWith(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        const _HintText(
          'Choose a style for category shuffle, or select one track. '
          'Custom Mix lets you choose 3–5 tracks from any style.',
        ),
        const SizedBox(height: AppSpacing.xs),
        for (final category in kBgmCategories) ...[
          _MusicStyleOption(
            category: category,
            selected:
                category.key == _value.musicCategory &&
                _value.musicTracks == null,
            selectedTrack:
                _value.musicCategory == category.key
                    ? _value.musicTrack == null
                        ? null
                        : bgmTrackByPath(_value.musicTrack!)?.$2.title
                    : null,
            expanded: _expandedKey == category.key,
            onTap: () => _selectMusicCategory(category),
            onToggleExpand:
                () => setState(() {
                  _customMixExpanded = false;
                  _expandedKey =
                      _expandedKey == category.key ? null : category.key;
                }),
          ),
          if (_expandedKey == category.key)
            Padding(
              padding: const EdgeInsets.only(
                left: AppSpacing.md,
                bottom: AppSpacing.xs,
              ),
              child: Column(
                children: [
                  for (final track in category.tracks)
                    _MusicTrackRow(
                      key: ValueKey('bgm-track-${category.key}-${track.file}'),
                      title: track.title,
                      selected:
                          _value.musicCategory == category.key &&
                          _value.musicTrack == category.trackPath(track),
                      playing:
                          _value.musicEnabled &&
                          _previewPath == category.trackPath(track),
                      onSelect: () => _selectMusicTrack(category, track),
                      onPreview:
                          _value.musicEnabled
                              ? () => _previewTrack(category, track)
                              : null,
                    ),
                ],
              ),
            ),
        ],
        const SizedBox(height: AppSpacing.sm),
        _CustomMixOption(
          selected: _value.musicTracks != null,
          expanded: _customMixExpanded,
          count: _mixDraft.length,
          onToggleExpand:
              () => setState(() {
                _expandedKey = null;
                _customMixExpanded = !_customMixExpanded;
              }),
        ),
        if (_customMixExpanded)
          Padding(
            padding: const EdgeInsets.only(left: AppSpacing.md, bottom: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_mixDraft.length} of $kMaxCustomMixTracks selected',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (_mixDraft.length < kMinCustomMixTracks)
                  const _HintText('Select at least 3 tracks to save this mix.'),
                for (final category in kBgmCategories) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 2),
                    child: Text(
                      '${category.label} tracks',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  for (final track in category.tracks)
                    _MusicTrackRow(
                      key: ValueKey(
                        'bgm-mix-track-${category.key}-${track.file}',
                      ),
                      title: track.title,
                      selected: _mixDraft.contains(category.trackPath(track)),
                      playing:
                          _value.musicEnabled &&
                          _previewPath == category.trackPath(track),
                      onSelect: () => _toggleMixTrack(category, track),
                      onPreview:
                          _value.musicEnabled
                              ? () => _previewTrack(category, track)
                              : null,
                    ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  bool _customMixExpanded = false;
}

/// One track row has a selection action and a separate audition action.
class _MusicTrackRow extends StatelessWidget {
  const _MusicTrackRow({
    super.key,
    required this.title,
    required this.selected,
    required this.playing,
    required this.onSelect,
    required this.onPreview,
  });

  final String title;
  final bool selected;
  final bool playing;
  final VoidCallback onSelect;
  final VoidCallback? onPreview;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: title,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: onSelect,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 7,
                    horizontal: 8,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        selected
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked_rounded,
                        size: 18,
                        color:
                            selected
                                ? AppColors.primaryPurple
                                : AppColors.textSecondary,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          title,
                          style: AppTextStyles.bodySmall.copyWith(
                            color:
                                selected || playing
                                    ? AppColors.primaryPurple
                                    : AppColors.textPrimary,
                            fontWeight:
                                selected || playing
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            IconButton(
              key: ValueKey('bgm-preview-$title'),
              onPressed: onPreview,
              icon: Icon(
                playing ? Icons.volume_up_rounded : Icons.play_circle_outline,
                size: 20,
              ),
              color: AppColors.primaryPurple,
              tooltip: onPreview == null ? 'Music is muted' : 'Preview $title',
              constraints: const BoxConstraints(
                minWidth: kMinInteractiveDimension,
                minHeight: kMinInteractiveDimension,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One selectable music style: its name, the guidance for when it suits, and
/// a check when it is the active choice.
class _MusicStyleOption extends StatelessWidget {
  const _MusicStyleOption({
    required this.category,
    required this.selected,
    required this.selectedTrack,
    required this.expanded,
    required this.onTap,
    required this.onToggleExpand,
  });

  final BgmCategory category;
  final bool selected;
  final String? selectedTrack;
  final bool expanded;
  final VoidCallback onTap;
  final VoidCallback onToggleExpand;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: ValueKey('bgm-category-${category.key}'),
      inMutuallyExclusiveGroup: true,
      selected: selected,
      button: true,
      label: category.label,
      hint: category.description,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: selected ? AppColors.lavenderLight : AppColors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color:
                  selected ? AppColors.primaryPurple : AppColors.lavenderLight,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category.label,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      category.description,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      selectedTrack == null
                          ? 'Category shuffle: one track each session'
                          : 'Selected track: $selectedTrack',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                const Icon(
                  Icons.check_circle_rounded,
                  size: 20,
                  color: AppColors.primaryPurple,
                ),
              // Separate hit target: expanding to audition the tracks must not
              // change which style the child gets.
              IconButton(
                key: ValueKey('bgm-expand-${category.key}'),
                onPressed: onToggleExpand,
                visualDensity: VisualDensity.compact,
                iconSize: 20,
                tooltip:
                    expanded
                        ? 'Hide ${category.label} tracks'
                        : 'Show ${category.label} tracks',
                icon: Icon(
                  expanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Collapsed entry point for the cross-category custom mix picker.
class _CustomMixOption extends StatelessWidget {
  const _CustomMixOption({
    required this.selected,
    required this.expanded,
    required this.count,
    required this.onToggleExpand,
  });

  final bool selected;
  final bool expanded;
  final int count;
  final VoidCallback onToggleExpand;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: 'Custom Mix, 3 to 5 tracks',
      key: const ValueKey('bgm-custom-mix-expand'),
      child: GestureDetector(
        onTap: onToggleExpand,
        behavior: HitTestBehavior.opaque,
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: selected ? AppColors.lavenderLight : AppColors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color:
                  selected ? AppColors.primaryPurple : AppColors.lavenderLight,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Custom Mix (3–5 tracks)',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      selected
                          ? '$count tracks selected; one plays each session'
                          : 'Choose 3–5 tracks from any music style',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                const Icon(
                  Icons.check_circle_rounded,
                  size: 20,
                  color: AppColors.primaryPurple,
                ),
              Icon(
                expanded
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded,
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// White rounded card wrapping one group of setup choices.
class _PrefsCard extends StatelessWidget {
  const _PrefsCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.white.withAlpha(240),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppTextStyles.titleMedium.copyWith(color: AppColors.foreground),
    );
  }
}

class _HintText extends StatelessWidget {
  const _HintText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(
        text,
        style: AppTextStyles.bodySmall.copyWith(
          color: AppColors.mutedForeground,
        ),
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppColors.lavender, size: 20),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(label, style: AppTextStyles.bodyMedium)),
        Switch(
          value: value,
          onChanged: onChanged,
          activeTrackColor: AppColors.primaryPurple,
        ),
      ],
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.onChanged,
    this.onChangeEnd,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 120,
          child: Text(label, style: AppTextStyles.bodySmall),
        ),
        Expanded(
          child: Slider(
            value: value,
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
            activeColor: AppColors.primaryPurple,
            inactiveColor: AppColors.lavenderLight,
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(
            '${(value * 100).round()}%',
            style: AppTextStyles.bodySmall,
          ),
        ),
      ],
    );
  }
}
