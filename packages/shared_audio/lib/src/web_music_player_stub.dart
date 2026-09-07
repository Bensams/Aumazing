/// Native builds continue to use audioplayers in AudioService.
class WebMusicPlayer {
  bool get isPlaying => false;
  void play(String track, double volume) {}
  void setVolume(double volume) {}
  void pause() {}
  void resume() {}
  void stop() {}
  void dispose() {}
}
