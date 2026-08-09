/// A selectable voice-over recording set for one language.
///
/// A voice pack is *not* a language: several packs can share the same
/// [languageSlug] (e.g. a synthesized Cebuano voice and a human-recorded one).
/// Keeping the two separate means on-screen text keeps following the child's
/// language while the audio follows the parent's chosen voice.
///
/// [languageSlug] matches `GameLanguage.slug` in shared_ui — kept as a plain
/// string so shared_audio stays decoupled from shared_ui.
class VoicePack {
  /// Stable key used for persistence. Never change it for an existing pack.
  final String id;

  /// The language this pack speaks (`en`, `tl`, `ceb`).
  final String languageSlug;

  /// Label shown in the parent-facing picker.
  final String label;

  /// Folder under `assets/audio/voice_over/` holding this pack's cues.
  final String assetFolder;

  /// Age group this voice portrays: `adult`, `young`, `child`.
  ///
  /// Null for the original packs, which were recorded before voices were
  /// grouped by age. The picker lists those on their own, above the tiers.
  final String? tier;

  /// File extension this pack's cues are stored with, including the dot.
  ///
  /// The original packs are uncompressed `.wav`; generated packs ship as
  /// `.mp3` because 48 packs of WAV would be ~457 MB. Stored per pack rather
  /// than probed at playback: guessing would mean a failed asset load, and
  /// therefore an exception, before every single cue in the WAV packs.
  final String fileExtension;

  const VoicePack({
    required this.id,
    required this.languageSlug,
    required this.label,
    required this.assetFolder,
    this.tier,
    this.fileExtension = '.wav',
  });
}

/// All registered voice packs.
///
/// Adding a voice is a two-step change: drop the audio folders under
/// `assets/audio/voice_over/<assetFolder>/`, list them in `pubspec.yaml`, and
/// add one entry here. No other code needs to change. For voices produced by
/// `tools/voice_gen`, `install_packs.py` does all three.
///
/// ORDER MATTERS: the first pack listed for a language is that language's
/// default — it is what a child starts with and what alternate packs fall back
/// to for cues their voice actor never recorded. Each language therefore leads
/// with its complete `adult / woman` pack; incomplete packs go last.
///
/// The original `en` / `tl` / `ceb` packs were removed: they were stitched
/// together from several speakers, so a single session could switch voices
/// mid-cue. Every remaining pack is one consistent voice throughout.
const List<VoicePack> kVoicePacks = [
  // BEGIN generated voice packs
  // Written by tools/voice_gen/install_packs.py -- do not hand-edit.
  // Each language keeps its original pack above as the default; these
  // are additional choices offered in Settings.
  VoicePack(
    id: 'en_adult_woman',
    languageSlug: 'en',
    label: 'Woman',
    assetFolder: 'en_adult_woman',
    tier: 'adult',
    fileExtension: '.mp3',
  ),
  VoicePack(
    id: 'en_adult_man',
    languageSlug: 'en',
    label: 'Man',
    assetFolder: 'en_adult_man',
    tier: 'adult',
    fileExtension: '.mp3',
  ),
  VoicePack(
    id: 'en_young_girl',
    languageSlug: 'en',
    label: 'Girl',
    assetFolder: 'en_young_girl',
    tier: 'young',
    fileExtension: '.mp3',
  ),
  VoicePack(
    id: 'en_young_boy',
    languageSlug: 'en',
    label: 'Boy',
    assetFolder: 'en_young_boy',
    tier: 'young',
    fileExtension: '.mp3',
  ),
  VoicePack(
    id: 'en_child_girl',
    languageSlug: 'en',
    label: 'Girl',
    assetFolder: 'en_child_girl',
    tier: 'child',
    fileExtension: '.mp3',
  ),
  VoicePack(
    id: 'en_child_boy',
    languageSlug: 'en',
    label: 'Boy',
    assetFolder: 'en_child_boy',
    tier: 'child',
    fileExtension: '.mp3',
  ),
  VoicePack(
    id: 'tl_adult_woman',
    languageSlug: 'tl',
    label: 'Woman',
    assetFolder: 'tl_adult_woman',
    tier: 'adult',
    fileExtension: '.mp3',
  ),
  VoicePack(
    id: 'tl_adult_man',
    languageSlug: 'tl',
    label: 'Man',
    assetFolder: 'tl_adult_man',
    tier: 'adult',
    fileExtension: '.mp3',
  ),
  VoicePack(
    id: 'tl_young_girl',
    languageSlug: 'tl',
    label: 'Girl',
    assetFolder: 'tl_young_girl',
    tier: 'young',
    fileExtension: '.mp3',
  ),
  VoicePack(
    id: 'tl_young_boy',
    languageSlug: 'tl',
    label: 'Boy',
    assetFolder: 'tl_young_boy',
    tier: 'young',
    fileExtension: '.mp3',
  ),
  VoicePack(
    id: 'tl_child_girl',
    languageSlug: 'tl',
    label: 'Girl',
    assetFolder: 'tl_child_girl',
    tier: 'child',
    fileExtension: '.mp3',
  ),
  VoicePack(
    id: 'tl_child_boy',
    languageSlug: 'tl',
    label: 'Boy',
    assetFolder: 'tl_child_boy',
    tier: 'child',
    fileExtension: '.mp3',
  ),
  VoicePack(
    id: 'ceb_adult_woman',
    languageSlug: 'ceb',
    label: 'Woman',
    assetFolder: 'ceb_adult_woman',
    tier: 'adult',
    fileExtension: '.mp3',
  ),
  VoicePack(
    id: 'ceb_adult_man',
    languageSlug: 'ceb',
    label: 'Man',
    assetFolder: 'ceb_adult_man',
    tier: 'adult',
    fileExtension: '.mp3',
  ),
  VoicePack(
    id: 'ceb_young_girl',
    languageSlug: 'ceb',
    label: 'Girl',
    assetFolder: 'ceb_young_girl',
    tier: 'young',
    fileExtension: '.mp3',
  ),
  VoicePack(
    id: 'ceb_young_boy',
    languageSlug: 'ceb',
    label: 'Boy',
    assetFolder: 'ceb_young_boy',
    tier: 'young',
    fileExtension: '.mp3',
  ),
  VoicePack(
    id: 'ceb_child_girl',
    languageSlug: 'ceb',
    label: 'Girl',
    assetFolder: 'ceb_child_girl',
    tier: 'child',
    fileExtension: '.mp3',
  ),
  VoicePack(
    id: 'ceb_child_boy',
    languageSlug: 'ceb',
    label: 'Boy',
    assetFolder: 'ceb_child_boy',
    tier: 'child',
    fileExtension: '.mp3',
  ),
  // END generated voice packs
  // Human-recorded and incomplete, so it stays last: being a non-default keeps
  // fallbackVoiceFolder pointing its missing cues at ceb_adult_woman.
  VoicePack(
    id: 'ceb_lexianne',
    languageSlug: 'ceb',
    label: 'Lexianne',
    assetFolder: 'ceb_lexianne',
  ),
];

/// The packs available for [languageSlug], default first.
List<VoicePack> voicePacksForLanguage(String languageSlug) =>
    kVoicePacks.where((p) => p.languageSlug == languageSlug).toList();

/// The pack with [id], or null when it is unknown (e.g. a pack that was
/// removed after a parent had already selected it).
VoicePack? voicePackById(String? id) {
  if (id == null) return null;
  for (final pack in kVoicePacks) {
    if (pack.id == id) return pack;
  }
  return null;
}

/// The default pack for [languageSlug], falling back to English when the
/// language has no packs registered.
VoicePack defaultVoicePackForLanguage(String languageSlug) =>
    kVoicePacks.firstWhere(
      (p) => p.languageSlug == languageSlug,
      orElse: () => kVoicePacks.first,
    );

/// The asset folder to play [code] from.
///
/// [code] is normally a [VoicePack.assetFolder], but plenty of call sites pass
/// a bare language slug instead. That used to resolve by accident, because the
/// default packs were foldered as `en` / `tl` / `ceb`; now that those packs are
/// gone, a slug is mapped explicitly onto its language's default pack. Unknown
/// codes land on the English default rather than a folder that does not exist.
String resolveVoiceFolder(String code) {
  if (voicePackByAssetFolder(code) != null) return code;
  return defaultVoicePackForLanguage(code).assetFolder;
}

/// The pack served from [assetFolder], or null if no pack uses that folder.
VoicePack? voicePackByAssetFolder(String assetFolder) {
  for (final pack in kVoicePacks) {
    if (pack.assetFolder == assetFolder) return pack;
  }
  return null;
}

/// The file extension used by the pack in [assetFolder], defaulting to `.wav`
/// for folders that are not registered.
String voiceFileExtension(String assetFolder) =>
    voicePackByAssetFolder(assetFolder)?.fileExtension ?? '.wav';

/// The packs for [languageSlug] that belong to [tier], in registry order.
List<VoicePack> voicePacksForTier(String languageSlug, String? tier) => [
      for (final pack in kVoicePacks)
        if (pack.languageSlug == languageSlug && pack.tier == tier) pack,
    ];

/// The age tiers available for [languageSlug], in registry order.
///
/// Packs with no tier are represented by null. Only the human-recorded
/// Cebuano pack is untiered now, and it is registered last, so null sorts to
/// the bottom of the picker rather than the top.
List<String?> voiceTiersForLanguage(String languageSlug) {
  final tiers = <String?>[];
  for (final pack in kVoicePacks) {
    if (pack.languageSlug == languageSlug && !tiers.contains(pack.tier)) {
      tiers.add(pack.tier);
    }
  }
  return tiers;
}

/// The folder to retry from when a cue is missing in [assetFolder].
///
/// Alternate packs are often incomplete — a human voice actor may not have
/// recorded every cue — so playback falls back to the language's default pack
/// rather than leaving the child in silence. Returns null when [assetFolder]
/// is already the default (or unknown), i.e. there is nothing to fall back to.
String? fallbackVoiceFolder(String assetFolder) {
  final pack = voicePackByAssetFolder(assetFolder);
  if (pack == null) return null;
  final fallback = defaultVoicePackForLanguage(pack.languageSlug).assetFolder;
  return fallback == assetFolder ? null : fallback;
}
