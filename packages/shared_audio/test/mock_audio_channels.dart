import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-memory native side of the audioplayers channels.
///
/// The service under test keeps running against the real
/// [AudioplayersPlatform] adapter - method channel `xyz.luan/audioplayers`,
/// per-player `EventChannel('xyz.luan/audioplayers/events/<id>')`; only the
/// native side is faked. The adapter subscribes to each player's event
/// channel inside [AudioplayersPlatform.create], which [AudioPlayer._create]
/// awaits before its own `getEventStream(playerId).listen(...)`, so a stream
/// handler installed synchronously in the mock `create` call is live before
/// any event can be delivered. `setSourceUrl` even awaits the `prepared`
/// event through `_completePrepared`, so this mock feeds the exact native
/// contract the production adapter parses.
class MockAudioChannels {
  MockAudioChannels(this._messenger) {
    _messenger.setMockMethodCallHandler(_channel, _handleCall);
  }

  final TestDefaultBinaryMessenger _messenger;

  static const MethodChannel _channel = MethodChannel('xyz.luan/audioplayers');

  /// Ordered witness of native traffic: `resume:<id>`, `complete:<id>`,
  /// `stop:<id>`. Tests use it to prove a line was never cut - that no stop
  /// reached a player between its resume and its completed playback.
  final List<String> eventLog = [];

  /// The player of the line that most recently resumed, i.e. the one that
  /// just started.
  String? lastResumedPlayer;

  final Map<String, int> _stopCalls = {};
  final Map<String, MockStreamHandlerEventSink?> _sinks = {};

  /// When set, the next resume blocks until [releaseResume] - it holds a line
  /// in playback across an assertion window, the exact "slow device" frame a
  /// cut can hide inside.
  Completer<void>? _resumeGate;

  void holdNextResume() {
    _resumeGate = Completer<void>();
  }

  void releaseResume() {
    final gate = _resumeGate;
    _resumeGate = null;
    gate?.complete();
  }

  int stopCallsFor(String playerId) => _stopCalls[playerId] ?? 0;

  int totalStopCalls() => _stopCalls.values.fold(0, (a, b) => a + b);

  Future<Object?> _handleCall(MethodCall call) async {
    final arguments = call.arguments as Map<Object?, Object?>;
    final playerId = arguments['playerId'] as String;
    switch (call.method) {
      case 'create':
        // Synchronously, before this call returns: the adapter's
        // createEventStream runs after `create` and the AudioPlayer
        // subscribes after that, so no event can race ahead of the handler.
        _messenger.setMockStreamHandler(
          EventChannel('xyz.luan/audioplayers/events/$playerId'),
          MockStreamHandler.inline(
            onListen: (arguments, events) => _sinks[playerId] = events,
            onCancel: (arguments) => _sinks[playerId] = null,
          ),
        );
        return null;
      case 'setSourceUrl':
      case 'setSourceBytes':
        _emit(playerId, {'event': 'audio.onPrepared', 'value': true});
        return null;
      case 'resume':
        final gate = _resumeGate;
        if (gate != null) {
          _resumeGate = null;
          await gate.future;
        }
        lastResumedPlayer = playerId;
        eventLog.add('resume:$playerId');
        // After the call returns: the backend would deliver the event on its
        // own schedule, and the service subscribes to the completion after
        // resume returns - a synchronous event would be lost to that
        // subscription and stall every wait into the timeout backstop.
        scheduleMicrotask(() {
          eventLog.add('complete:$playerId');
          _emit(playerId, {'event': 'audio.onComplete'});
        });
        return null;
      case 'stop':
        _stopCalls[playerId] = (_stopCalls[playerId] ?? 0) + 1;
        eventLog.add('stop:$playerId');
        return null;
      case 'dispose':
        _sinks[playerId] = null;
        return null;
      default:
        return null;
    }
  }

  void _emit(String playerId, Map<String, Object?> event) {
    // No sink yet (stream cancelled or not yet listened): the event is
    // dropped, exactly like an event racing a not-yet-listening native
    // channel.
    _sinks[playerId]?.success(event);
  }
}
