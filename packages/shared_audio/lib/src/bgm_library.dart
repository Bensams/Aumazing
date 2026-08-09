// GENERATED FILE — do not edit by hand.
// Written by tools/bgm_gen/install_bgm.py. Re-run that script to
// change which tracks ship. See docs/asd-friendly-bgm.md.

/// One background-music track.
///
/// [title] is parent-facing — it is what the settings preview lists —
/// while [file] is the asset on disk.
class BgmTrack {
  const BgmTrack({required this.file, required this.title});

  /// Filename within the category folder.
  final String file;

  /// Human-readable name shown to the parent.
  final String title;
}

/// A parent-selectable background-music category.
///
/// Every track in every category is instrumental, loudness-matched to
/// -20 LUFS and loops seamlessly, so switching category changes the
/// character of the music but never how loud or how startling it is.
class BgmCategory {
  const BgmCategory({
    required this.key,
    required this.label,
    required this.description,
    required this.tracks,
  });

  /// Stable identifier persisted in the child's profile.
  final String key;

  /// Short name shown to the parent.
  final String label;

  /// One-line guidance shown under the label in the picker.
  final String description;

  /// The tracks in this category, in the order the picker lists them.
  final List<BgmTrack> tracks;

  /// Path accepted by [AudioService.playMusic].
  String trackPath(BgmTrack track) => 'bgm/$key/${track.file}';
}

/// The category used when a child has no stored preference.
const String kDefaultBgmCategory = 'soft_relaxing';

/// Every category available to the parent picker.
const List<BgmCategory> kBgmCategories = <BgmCategory>[
  BgmCategory(
    key: 'soft_relaxing',
    label: 'Soft & Relaxing',
    description: 'Lowest-arousal category. Sustained, slow, almost motionless. For children who are easily over-stimulated, or for winding down after a session.',
    tracks: <BgmTrack>[
      BgmTrack(file: 'breathing_pad.ogg', title: 'Breathing Pad'),
      BgmTrack(file: 'felt_piano_rest.ogg', title: 'Felt Piano Rest'),
      BgmTrack(file: 'quiet_guitar_room.ogg', title: 'Quiet Guitar Room'),
      BgmTrack(file: 'soft_harp_drift.ogg', title: 'Soft Harp Drift'),
      BgmTrack(file: 'warm_strings_haze.ogg', title: 'Warm Strings Haze'),
    ],
  ),
  BgmCategory(
    key: 'nature_ambient',
    label: 'Nature & Ambient',
    description: 'Soft tonal music layered with steady natural texture. The constant broadband texture masks unpredictable household noise, which many sound-sensitive children find easier than silence.',
    tracks: <BgmTrack>[
      BgmTrack(file: 'forest_light.ogg', title: 'Forest Light'),
      BgmTrack(file: 'gentle_rainfall.ogg', title: 'Gentle Rainfall'),
      BgmTrack(file: 'morning_garden.ogg', title: 'Morning Garden'),
      BgmTrack(file: 'slow_ocean.ogg', title: 'Slow Ocean'),
      BgmTrack(file: 'small_stream.ogg', title: 'Small Stream'),
    ],
  ),
  BgmCategory(
    key: 'gentle_playful',
    label: 'Gentle Playful',
    description: 'Mildly energising without becoming stimulating. Slightly brighter and more rhythmic, for children who disengage when music is too still. Still no percussive transients.',
    tracks: <BgmTrack>[
      BgmTrack(file: 'bouncy_pizzicato.ogg', title: 'Bouncy Pizzicato'),
      BgmTrack(file: 'happy_marimba.ogg', title: 'Happy Marimba'),
      BgmTrack(file: 'little_whistle_tune.ogg', title: 'Little Whistle Tune'),
      BgmTrack(file: 'sunny_ukulele.ogg', title: 'Sunny Ukulele'),
      BgmTrack(file: 'toy_xylophone_walk.ogg', title: 'Toy Xylophone Walk'),
    ],
  ),
  BgmCategory(
    key: 'lullaby_music_box',
    label: 'Lullaby & Music Box',
    description: 'Familiar, highly predictable nursery timbres. Strongest cue for \'settle down\' — useful for transitions, calm corners and the end of a play session.',
    tracks: <BgmTrack>[
      BgmTrack(file: 'celesta_cradle.ogg', title: 'Celesta Cradle'),
      BgmTrack(file: 'cradle_piano.ogg', title: 'Cradle Piano'),
      BgmTrack(file: 'humming_bells.ogg', title: 'Humming Bells'),
      BgmTrack(file: 'kalimba_sleep.ogg', title: 'Kalimba Sleep'),
      BgmTrack(file: 'music_box_circle.ogg', title: 'Music Box Circle'),
    ],
  ),
  BgmCategory(
    key: 'focus_minimal',
    label: 'Focus & Minimal',
    description: 'Deliberately uneventful. A steady, near-static bed with almost no melodic \'events\' to capture attention, so it supports on-task attention during matching, tracing and sorting activities.',
    tracks: <BgmTrack>[
      BgmTrack(file: 'even_ground.ogg', title: 'Even Ground'),
      BgmTrack(file: 'patient_keys.ogg', title: 'Patient Keys'),
      BgmTrack(file: 'quiet_ostinato.ogg', title: 'Quiet Ostinato'),
      BgmTrack(file: 'soft_pulse.ogg', title: 'Soft Pulse'),
      BgmTrack(file: 'steady_loop_one.ogg', title: 'Steady Loop One'),
    ],
  ),
  BgmCategory(
    key: 'filipino_calm',
    label: 'Filipino Calm',
    description: 'Culturally familiar tone colours for Filipino families, kept within the same calm envelope as the other categories. Pairs with the app\'s Tagalog and Cebuano voice-overs.',
    tracks: <BgmTrack>[
      BgmTrack(file: 'bamboo_breeze.ogg', title: 'Bamboo Breeze'),
      BgmTrack(file: 'harana_evening.ogg', title: 'Harana Evening'),
      BgmTrack(file: 'kulintang_calm.ogg', title: 'Kulintang Calm'),
      BgmTrack(file: 'kundiman_hush.ogg', title: 'Kundiman Hush'),
      BgmTrack(file: 'soft_rondalla.ogg', title: 'Soft Rondalla'),
    ],
  ),
];

/// Look up a category by its persisted [key].
///
/// Returns null when the key is unknown, which happens if a profile was
/// written by a build that shipped a category this build does not have.
BgmCategory? bgmCategoryByKey(String? key) {
  for (final category in kBgmCategories) {
    if (category.key == key) return category;
  }
  return null;
}

/// The category for [key], falling back to the default when unknown.
BgmCategory bgmCategoryOrDefault(String? key) =>
    bgmCategoryByKey(key) ?? bgmCategoryByKey(kDefaultBgmCategory)!;
