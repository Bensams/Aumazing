import 'bgm_library.dart';

/// A parent-created style containing tracks from any bundled category.
const kMinCustomMixTracks = 3;
const kMaxCustomMixTracks = 5;

/// Resolve a canonical asset path against the current bundled library.
(BgmCategory, BgmTrack)? bgmTrackByPath(String path) {
  for (final category in kBgmCategories) {
    for (final track in category.tracks) {
      if (category.trackPath(track) == path) return (category, track);
    }
  }
  return null;
}

/// Remove duplicate or retired assets before choosing a session track.
List<String> validBgmTrackPaths(Iterable<String>? paths) => [
  for (final path in {...?paths})
    if (bgmTrackByPath(path) != null) path,
];
