import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

/// Keeps the actual music element and context alive across tracks and taps.
/// Browser activation is used synchronously, before any loading/await boundary.
class WebMusicPlayer {
  final _element = web.HTMLAudioElement();
  late final web.AudioContext _context;
  late final web.GainNode _gain;
  late final JSFunction _gestureListener;
  bool _wantsPlayback = false;
  bool _disposed = false;
  String? _track;

  WebMusicPlayer() {
    _element.loop = true;
    _element.preload = 'auto';
    _context = web.AudioContext();
    _gain = _context.createGain();
    _context.createMediaElementSource(_element).connect(_gain);
    _gain.connect(_context.destination);
    _gestureListener =
        ((web.Event event) {
          if (!event.isTrusted) return;
          if (event.type == 'keydown') {
            final key = (event as web.KeyboardEvent).key;
            if (key != 'Enter' && key != ' ') return;
          }
          _tryPlay();
        }).toJS;
    // Touch becomes activating on release; pointer-down only covers a mouse.
    for (final type in ['pointerup', 'touchend', 'click', 'keydown']) {
      web.document.addEventListener(type, _gestureListener, true.toJS);
    }
  }

  bool get isPlaying =>
      !_disposed && !_element.paused && _context.state == 'running';

  void setVolume(double volume) {
    if (!_disposed) _gain.gain.value = volume.clamp(0.0, 1.0);
  }

  void play(String track, double volume) {
    if (_disposed) return;
    setVolume(volume);
    if (_track != track) {
      _track = track;
      final supportsOgg =
          _element.canPlayType('audio/ogg; codecs="vorbis"').isNotEmpty;
      final path =
          track.endsWith('.ogg') && !supportsOgg
              ? 'audio_fallback/${track.replaceFirst(RegExp(r'\.ogg$'), '.mp3')}'
              : 'assets/packages/shared_audio/assets/audio/$track';
      _element.src = Uri.parse(web.document.baseURI).resolve(path).toString();
      _element.load();
    }
    _wantsPlayback = true;
    _tryPlay();
  }

  void _tryPlay() {
    if (_disposed || !_wantsPlayback || _track == null || isPlaying) return;
    // Issue BOTH calls now. Awaiting resume or a media-loaded event first can
    // lose Safari's user activation before HTMLMediaElement.play is reached.
    if (_context.state == 'suspended') {
      _context.resume().toDart.then<void>(
        (_) {},
        onError: (Object error) {
          debugPrint('[WebMusicPlayer] Context waiting for a tap: $error');
        },
      );
    }
    _element.play().toDart.then<void>(
      (_) {},
      onError: (Object error) {
        // Keep the requested track and retry on the next real gesture. A blocked
        // autoplay request must never become a permanent "already unlocked" flag.
        debugPrint('[WebMusicPlayer] Playback waiting for a tap: $error');
      },
    );
  }

  void pause() {
    if (_disposed) return;
    _wantsPlayback = false;
    _element.pause();
  }

  void resume() {
    if (_disposed || _track == null) return;
    _wantsPlayback = true;
    _tryPlay();
  }

  void stop() {
    if (_disposed) return;
    pause();
    _track = null;
    _element.removeAttribute('src');
    _element.load();
  }

  void dispose() {
    if (_disposed) return;
    stop();
    _disposed = true;
    for (final type in ['pointerup', 'touchend', 'click', 'keydown']) {
      web.document.removeEventListener(type, _gestureListener, true.toJS);
    }
    _context.close().toDart.then<void>((_) {}, onError: (Object _) {});
  }
}
