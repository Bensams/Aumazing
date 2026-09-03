import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../model/ai_assessment_response.dart';
import '../model/area_level.dart';
import '../model/gameplay_session.dart';
import 'local_recommendation_rules.dart';
import 'on_device_feature_aggregator.dart';

// ── JS bridge (see web/ort_bridge.mjs) ──────────────────────────────────────
@JS('aumazingAI.createSession')
external JSPromise<JSString> _createSession(JSString key, JSUint8Array bytes);

@JS('aumazingAI.run')
external JSPromise<JSArray<JSNumber>?> _runSession(
  JSString key,
  JSFloat32Array input,
  JSNumber cols,
);

/// Null until `web/ort_bridge.mjs` finishes loading and defines the global.
@JS('aumazingAI')
external JSObject? get _aumazingAIGlobal;

/// Web build of the on-device AI service.
///
/// ONNX Runtime's Dart package uses `dart:ffi` and cannot run on the web, so
/// here inference is driven through onnxruntime-web (WASM) via the
/// `window.aumazingAI` bridge. It runs the same models as the native/Android
/// build, entirely in the browser — no server. The public API mirrors
/// [on_device_ai_assessment_service_native.dart]; only the session execution
/// differs, so [AiPredictionFallbackService] behaves identically across
/// platforms. Selected by the conditional export in
/// `on_device_ai_assessment_service.dart`.
class OnDeviceAiAssessmentService {
  OnDeviceAiAssessmentService({
    this.aggregator = const OnDeviceFeatureAggregator(),
  });

  final OnDeviceFeatureAggregator aggregator;

  /// area key → asset filename (same set as native).
  static const _areaModels = {
    'communication': 'assets/models/communication.onnx',
    'social': 'assets/models/social.onnx',
    'play': 'assets/models/play.onnx',
    'attention': 'assets/models/attention.onnx',
  };

  static const _levelToApi = {0: 'needs_support', 1: 'emerging', 2: 'strength'};
  static const _defaultLevelNames = {
    0: 'Needs Support',
    1: 'Emerging',
    2: 'Strength',
  };

  final Set<String> _createdSessions = {};
  List<String> _featureNames = const [];
  Map<int, String> _levelNames = const {};
  bool _loaded = false;
  bool _unavailable = false;

  /// Whether the on-device (in-browser) model is loaded and ready.
  bool get isReady => _loaded;

  /// Wait for the onnxruntime-web bridge module to finish loading.
  Future<bool> _waitForBridge() async {
    for (var i = 0; i < 100; i++) {
      if (_aumazingAIGlobal != null) return true;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return false;
  }

  /// Loads the ONNX sessions (via WASM) + metadata once. Returns false if the
  /// runtime or model artifacts aren't available.
  Future<bool> _ensureLoaded() async {
    if (_loaded) return true;
    if (_unavailable) return false;
    try {
      if (!await _waitForBridge()) {
        throw StateError('onnxruntime-web bridge did not load');
      }

      // Feature order is required to build the input vector correctly.
      final featuresJson =
          await rootBundle.loadString('assets/models/feature_names.json');
      _featureNames =
          (jsonDecode(featuresJson) as List).map((e) => e.toString()).toList();

      // Level names (optional — fall back to defaults).
      try {
        final levelsJson =
            await rootBundle.loadString('assets/models/level_names.json');
        final raw = jsonDecode(levelsJson) as Map<String, dynamic>;
        _levelNames = {
          for (final e in raw.entries) int.parse(e.key): e.value.toString(),
        };
      } catch (_) {
        _levelNames = Map.of(_defaultLevelNames);
      }

      for (final entry in _areaModels.entries) {
        final data = await rootBundle.load(entry.value);
        final bytes = data.buffer
            .asUint8List(data.offsetInBytes, data.lengthInBytes);
        await _createSession(entry.key.toJS, bytes.toJS).toDart;
        _createdSessions.add(entry.key);
      }

      _loaded = true;
      debugPrint('[OnDeviceAI/web] Loaded ${_createdSessions.length} models, '
          '${_featureNames.length} features (onnxruntime-web).');
      return true;
    } catch (e) {
      debugPrint('[OnDeviceAI/web] In-browser inference unavailable ($e)');
      _unavailable = true;
      return false;
    }
  }

  /// Predicts per-area developmental levels from [sessions], fully in-browser.
  /// Returns null when the model isn't available (caller should fall back).
  Future<AiAssessmentResponse?> predictFromSessions({
    required String childId,
    required List<GameplaySession> sessions,
  }) async {
    if (sessions.isEmpty) return null;
    if (!await _ensureLoaded()) return null;

    final features = aggregator.aggregate(sessions);
    final input = Float32List.fromList(
      _featureNames.map((name) => (features[name] ?? 0.0).toDouble()).toList(),
    );

    final areaLevels = <String, AreaLevel>{};
    for (final area in _areaModels.keys) {
      if (!_createdSessions.contains(area)) continue;
      final result = await _runSession(
        area.toJS,
        input.toJS,
        _featureNames.length.toJS,
      ).toDart;
      if (result == null) continue;
      final probs =
          result.toDart.map((e) => e.toDartDouble).toList(growable: false);
      if (probs.length < 2) continue;
      final levelInt = _argMax(probs);
      areaLevels[area] = AreaLevel(
        level: _levelToApi[levelInt] ?? '$levelInt',
        levelInt: levelInt,
        levelName: _levelNames[levelInt] ?? '$levelInt',
        confidence: double.parse(probs[levelInt].toStringAsFixed(4)),
      );
    }

    if (areaLevels.length < _areaModels.length) {
      debugPrint('[OnDeviceAI/web] Incomplete prediction '
          '(${areaLevels.length}/${_areaModels.length}) — falling back.');
      return null;
    }

    return _buildResponse(areaLevels, features);
  }

  // ── Pure helpers (mirrors the native service) ─────────────────────────────

  AiAssessmentResponse _buildResponse(
    Map<String, AreaLevel> areaLevels,
    Map<String, double> features,
  ) {
    // Lowest-level area drives the "support" profile; ties favour the order
    // communication → social → play → attention.
    String focusArea = 'communication';
    var minLevel = 3;
    for (final area in ['communication', 'social', 'play', 'attention']) {
      final lvl = areaLevels[area]?.levelInt ?? 2;
      if (lvl < minLevel) {
        minLevel = lvl;
        focusArea = area;
      }
    }

    final needsSupportCount =
        areaLevels.values.where((a) => a.levelInt == 0).length;
    final supportLevel = needsSupportCount >= 2
        ? 'high'
        : (needsSupportCount == 1 || minLevel <= 1 ? 'moderate' : 'low');

    final predictedProfile =
        minLevel >= 2 ? 'balanced_profile' : '${focusArea}_support';

    final avgConfidence = areaLevels.values.isEmpty
        ? 0.0
        : areaLevels.values.map((a) => a.confidence).reduce((a, b) => a + b) /
            areaLevels.length;

    final moduleDetails = LocalRecommendationRules.deriveModuleDetails(
      areaLevels,
      featureValues: features,
    );

    return AiAssessmentResponse(
      predictedProfile: predictedProfile,
      confidence: avgConfidence,
      summary: LocalRecommendationRules.buildSummaryText(areaLevels),
      supportLevel: supportLevel,
      recommendedModules: moduleDetails.map((m) => m.name).toList(),
      moduleDetails: moduleDetails,
      featureValues: features,
      skillAreas: areaLevels.keys.toList(),
      areaLevels: areaLevels,
      onDevice: true,
    );
  }

  int _argMax(List<double> values) {
    var best = 0;
    for (var i = 1; i < values.length; i++) {
      if (values[i] > values[best]) best = i;
    }
    return best;
  }

  void dispose() {
    _createdSessions.clear();
    _loaded = false;
  }
}
