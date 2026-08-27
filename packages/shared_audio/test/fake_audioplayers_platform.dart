import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers_platform_interface/audioplayers_platform_interface.dart';
import 'package:audioplayers_platform_interface/src/audioplayers_platform.dart';
import 'package:flutter/foundation.dart';

/// In-memory audioplayers backend used by the queue tests.
///
/// The real method-channel backend never receives the native 'prepared' event
/// in a headless test, which makes every [setSource] block until the service's
/// 4-second backstop times out — so a phrase never registers its first word
/// and a queue that should advance never does. This fake answers every call
/// immediately and feeds the prepared/complete events the real platform would
/// emit, so labels, praise and sequences run end to end without wall-clock
/// stalls and the queue tests exercise real timing instead of backstops.
class FakeAudioplayersPlatform extends AudioplayersPlatform {
  final Map<String, StreamController<AudioEvent>> _streams = {};
  final Map<String, int> _stopCalls = {};

  /// When set, the next [resume] waits for [releaseResume] - used to hold a
  /// line in playback across an assertion window, which is the exact "slow
  /// device" frame a cut can hide inside.
  Completer<void>? _resumeGate;

  /// Hold the next resume.
  void holdNextResume() {
    _resumeGate = Completer<void>();
  }

  /// Release a held resume.
  void releaseResume() {
    final gate = _resumeGate;
    _resumeGate = null;
    gate?.complete();
  }

  int stopCallsFor(String playerId) => _stopCalls[playerId] ?? 0;
  int totalStopCalls() => _stopCalls.values.fold(0, (a, b) => a + b);

  /// Ordered witness of what happened in what order: `resume:<id>`,
  /// `complete:<id>` (the microtask the native backend would deliver), and
  /// `stop:<id>`. Tests use this to prove a line was never cut - that no stop
  /// reached its player between its resume and its complete.
  final List<String> eventLog = [];

  /// The player that most recently resumed, i.e. the line that just started.
  String? lastResumedPlayer;

  @override
  Future<void> create(String playerId) async {
    _streams.putIfAbsent(
        playerId, () => StreamController<AudioEvent>.broadcast());
  }

  @override
  Future<void> dispose(String playerId) async {
    final controller = _streams.remove(playerId);
    await controller?.close();
  }

  @override
  Stream<AudioEvent> getEventStream(String playerId) =>
      _streams[playerId]!.stream;

  @override
  Future<void> setSourceUrl(String playerId, String url,
      {bool? isLocal, String? mimeType}) async {
    _emit(playerId,
        const AudioEvent(eventType: AudioEventType.prepared, isPrepared: true));
  }

  @override
  Future<void> setSourceBytes(String playerId, Uint8List bytes,
      {String? mimeType}) async {
    _emit(playerId,
        const AudioEvent(eventType: AudioEventType.prepared, isPrepared: true));
  }

  @override
  Future<void> resume(String playerId) async {
    final gate = _resumeGate;
    if (gate != null) {
      _resumeGate = null;
      await gate.future;
    }
    lastResumedPlayer = playerId;
    eventLog.add('resume:$playerId');
    // Emit on a microtask: the service awaits the event with onPlayerComplete
    // .first *after* resume returns, and a synchronous emission would be lost
    // to that subscription and stall every wait into the 4s backstop.
    scheduleMicrotask(() {
      eventLog.add('complete:$playerId');
      _emit(playerId,
          const AudioEvent(eventType: AudioEventType.complete));
    });
  }

  @override
  Future<void> stop(String playerId) async {
    _stopCalls[playerId] = (_stopCalls[playerId] ?? 0) + 1;
    eventLog.add('stop:$playerId');
  }

  @override
  Future<void> pause(String playerId) async {}

  @override
  Future<void> release(String playerId) async {}

  @override
  Future<void> seek(String playerId, Duration position) async {}

  @override
  Future<void> setVolume(String playerId, double volume) async {}

  @override
  Future<void> setBalance(String playerId, double balance) async {}

  @override
  Future<void> setPlaybackRate(String playerId, double playbackRate) async {}

  @override
  Future<void> setPlayerMode(String playerId, PlayerMode playerMode) async {}

  @override
  Future<void> setReleaseMode(String playerId, ReleaseMode releaseMode) async {}

  @override
  Future<void> setAudioContext(String playerId, AudioContext context) async {}

  @override
  Future<int?> getCurrentPosition(String playerId) async => 0;

  @override
  Future<int?> getDuration(String playerId) async => null;

  void _emit(String playerId, AudioEvent event) {
    // No listener yet (create still in flight): the event is dropped, exactly
    // like an event racing a not-yet-subscribed native channel.
    _streams[playerId]?.add(event);
  }
}
