/// How much of the web build the offline service worker has saved.
///
/// "Core" is the app itself (engine, code, pictures, models) and is saved in
/// full before offline play turns on; "lazy" is game audio and music, saved as
/// games are played and by the background download.
class OfflineStatus {
  const OfflineStatus({
    required this.coreCached,
    required this.coreTotal,
    required this.lazyCached,
    required this.lazyTotal,
  });

  final int coreCached;
  final int coreTotal;
  final int lazyCached;
  final int lazyTotal;

  /// The app opens and runs with no connection.
  bool get appReady => coreTotal > 0 && coreCached >= coreTotal;

  /// Every game, with all of its sound, works with no connection.
  bool get fullyReady => appReady && lazyCached >= lazyTotal;

  /// Share of all files saved, 0–1.
  double get fraction {
    final total = coreTotal + lazyTotal;
    return total == 0 ? 0 : (coreCached + lazyCached) / total;
  }
}
