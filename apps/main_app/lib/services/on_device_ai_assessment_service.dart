import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:onnxruntime/onnxruntime.dart';

import '../model/ai_assessment_response.dart';
import '../model/area_level.dart';
import '../model/gameplay_session.dart';
import 'on_device_feature_aggregator.dart';

/// Runs the XGBoost developmental classifier **on-device** via ONNX Runtime
/// Mobile — no network required (true offline-first inference), matching the
/// architecture stated in the manuscript.
///
/// Model artifacts live in `assets/models/` and are generated from the trained
/// scikit-learn / XGBoost model by `ai_assessment/training/export_onnx.py`:
///   - `communication.onnx`, `social.onnx`, `play.onnx`, `attention.onnx`
///     — one per-area binary XGBoost classifier (3 classes, zipmap=False)
///   - `feature_names.json` — canonical feature order
///   - `level_names.json`   — {"0":"Needs Support","1":"Emerging","2":"Strength"}
///
/// If the assets are missing (e.g. before the model is exported), [predict]
/// returns null so the caller can fall back to the cloud API / rubric scoring.
class OnDeviceAiAssessmentService {
  OnDeviceAiAssessmentService({this.aggregator = const OnDeviceFeatureAggregator()});

  final OnDeviceFeatureAggregator aggregator;

  static bool _envInitialised = false;

  /// area key → asset filename
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

  final Map<String, OrtSession> _sessions = {};
  List<String> _featureNames = const [];
  Map<int, String> _levelNames = const {};
  bool _loaded = false;
  bool _unavailable = false;

  /// Whether the on-device model is loaded and ready.
  bool get isReady => _loaded;

  /// Loads the ONNX sessions + metadata from assets (once). Returns false if
  /// the artifacts aren't bundled yet.
  Future<bool> _ensureLoaded() async {
    if (_loaded) return true;
    if (_unavailable) return false;
    try {
      if (!_envInitialised) {
        OrtEnv.instance.init();
        _envInitialised = true;
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

      final options = OrtSessionOptions();
      for (final entry in _areaModels.entries) {
        final bytes = await rootBundle.load(entry.value);
        _sessions[entry.key] = OrtSession.fromBuffer(
          bytes.buffer.asUint8List(),
          options,
        );
      }

      _loaded = true;
      debugPrint('[OnDeviceAI] Loaded ${_sessions.length} area models, '
          '${_featureNames.length} features.');
      return true;
    } catch (e) {
      debugPrint('[OnDeviceAI] Model assets unavailable — '
          'on-device inference disabled ($e)');
      _unavailable = true;
      return false;
    }
  }

  /// Predicts per-area developmental levels from [sessions], fully on-device.
  /// Returns null when the model isn't bundled (caller should fall back).
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
    final runOptions = OrtRunOptions();
    try {
      for (final area in _areaModels.keys) {
        final session = _sessions[area];
        if (session == null) continue;
        final inputName = session.inputNames.first;
        final tensor = OrtValueTensor.createTensorWithDataList(
          input,
          [1, _featureNames.length],
        );
        try {
          final outputs = session.run(runOptions, {inputName: tensor});
          final probs = _extractProbabilities(outputs);
          for (final o in outputs) {
            o?.release();
          }
          if (probs == null) continue;
          final levelInt = _argMax(probs);
          areaLevels[area] = AreaLevel(
            level: _levelToApi[levelInt] ?? '$levelInt',
            levelInt: levelInt,
            levelName: _levelNames[levelInt] ?? '$levelInt',
            confidence: double.parse(probs[levelInt].toStringAsFixed(4)),
          );
        } finally {
          tensor.release();
        }
      }
    } finally {
      runOptions.release();
    }

    if (areaLevels.length < _areaModels.length) {
      debugPrint('[OnDeviceAI] Incomplete prediction '
          '(${areaLevels.length}/${_areaModels.length}) — falling back.');
      return null;
    }

    return _buildResponse(areaLevels, features);
  }

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

    return AiAssessmentResponse(
      predictedProfile: predictedProfile,
      confidence: avgConfidence,
      summary: 'On-device assessment complete.',
      supportLevel: supportLevel,
      recommendedModules: const [], // module selection handled by local rules
      featureValues: features,
      skillAreas: areaLevels.keys.toList(),
      areaLevels: areaLevels,
    );
  }

  /// Finds the probabilities tensor among the model outputs (the one with
  /// ≥2 values), robust to output ordering/naming across exporters.
  List<double>? _extractProbabilities(List<OrtValue?> outputs) {
    for (final o in outputs) {
      final v = o?.value;
      if (v is List && v.isNotEmpty) {
        // Shape [1, C] → List<List<num>>
        if (v.first is List) {
          final row = (v.first as List);
          if (row.length >= 2) {
            return row.map((e) => (e as num).toDouble()).toList();
          }
        }
        // Shape [C] → List<num>
        if (v.first is num && v.length >= 2) {
          return v.map((e) => (e as num).toDouble()).toList();
        }
      }
    }
    return null;
  }

  int _argMax(List<double> values) {
    var best = 0;
    for (var i = 1; i < values.length; i++) {
      if (values[i] > values[best]) best = i;
    }
    return best;
  }

  void dispose() {
    for (final s in _sessions.values) {
      s.release();
    }
    _sessions.clear();
    _loaded = false;
  }
}
