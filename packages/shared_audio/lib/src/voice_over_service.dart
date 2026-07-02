import 'dart:async';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Categories of voice-over audio cues, matching the asset folder structure.
enum VoiceOverCategory {
  assessmentStyle,
  attentionAndRegulation,
  corePraise,
  gentlyRetry,
  instruction,
  rewardAndCelebration,
  transition,
  turnTaking,
  dynamic,    // Action words: "Tap the", "Drag the", "Drop the"
  colors,     // Color names: "Red", "Blue", etc.
  shapes,     // Shape names: "Circle", "Star", etc.
}

/// Individual voice-over cues mapped to their .wav asset files.
///
/// Each value corresponds to a single voice-over recording stored under
/// `assets/audio/voice_over/<category>/<FileName>.wav`.
enum VoiceOverCue {
  // ── Assessment Style ──────────────────────────────────────────────
  canYouCopyMe,
  canYouMatchThis,
  findTheRightOne,
  goodListening,
  goodLooking,
  letSeeWhatYouCanDo,
  letsTryTheNextTask,
  showMe,
  whatComesNext,
  whichOneIsTheSame,

  // ── Attention and Regulation ──────────────────────────────────────
  calmBody,
  eyesHere,
  goodCalmingDown,
  itsOkay,
  letsContinue,
  letsSlowDown,
  listenCarefully,
  readyAgain,
  takeABreath,
  youAreSafe,

  // ── Core Praise ───────────────────────────────────────────────────
  aumazing,
  ausome,
  correct,
  excellent,
  goodTry,
  greatJob,
  niceWork,
  thatsRight,
  veryGood,
  wellDone,
  yayYouGotIt,
  youDidIt,

  // ── Gently Retry ──────────────────────────────────────────────────
  almostThere,
  giveItAnotherTry,
  keepGoing,
  letsDoItOneMoreTime,
  letsPracticeAgain,
  letsTryAgain,
  niceTry,
  notYet,
  tryAgain,
  youCanDoIt,

  // ── Instruction ───────────────────────────────────────────────────
  chooseOne,
  copyMe,
  countWithMe,
  dragIt,
  findTheSame,
  followMe,
  letsBegin,
  listen,
  matchIt,
  myTurnInstruction,
  pickTheColor,
  pickTheShape,
  tapHere,
  touchThePicture,
  watchCarefully,
  yourTurnInstruction,

  // ── Reward & Celebration ──────────────────────────────────────────
  awesomeWorkToday,
  bigHighFive,
  fantastic,
  greatPlaying,
  hooray,
  superJob,
  youDidSoWell,
  youFinishedIt,
  youreAmazing,

  // ── Transition ────────────────────────────────────────────────────
  gameFinished,
  getReady,
  goodJobMovingOn,
  letsGo,
  letsPlayAgain,
  levelComplete,
  newGame,
  nextActivity,
  nextOne,
  timeForTheNextOne,

  // ── Turn Taking ───────────────────────────────────────────────────
  goodWaiting,
  hereWeGo,
  letsTakeTurns,
  myTurn,
  nowYouTry,
  ready,
  thankYouForWaiting,
  wait,
  watchMeFirst,
  yourTurn,

  // ── Dynamic (action) cues ──────────────────────────────────────────
  tapThe,
  dragThe,
  dropThe,

  // ── Color cues ─────────────────────────────────────────────────────
  colorRed,
  colorBlue,
  colorGreen,
  colorYellow,
  colorPurple,
  colorOrange,

  // ── Shape cues ─────────────────────────────────────────────────────
  shapeCircle,
  shapeStar,
  shapeTriangle,
  shapeDiamond,
}

/// Maps each [VoiceOverCue] to its category.
const Map<VoiceOverCue, VoiceOverCategory> _cueCategories = {
  // Assessment Style
  VoiceOverCue.canYouCopyMe: VoiceOverCategory.assessmentStyle,
  VoiceOverCue.canYouMatchThis: VoiceOverCategory.assessmentStyle,
  VoiceOverCue.findTheRightOne: VoiceOverCategory.assessmentStyle,
  VoiceOverCue.goodListening: VoiceOverCategory.assessmentStyle,
  VoiceOverCue.goodLooking: VoiceOverCategory.assessmentStyle,
  VoiceOverCue.letSeeWhatYouCanDo: VoiceOverCategory.assessmentStyle,
  VoiceOverCue.letsTryTheNextTask: VoiceOverCategory.assessmentStyle,
  VoiceOverCue.showMe: VoiceOverCategory.assessmentStyle,
  VoiceOverCue.whatComesNext: VoiceOverCategory.assessmentStyle,
  VoiceOverCue.whichOneIsTheSame: VoiceOverCategory.assessmentStyle,

  // Attention and Regulation
  VoiceOverCue.calmBody: VoiceOverCategory.attentionAndRegulation,
  VoiceOverCue.eyesHere: VoiceOverCategory.attentionAndRegulation,
  VoiceOverCue.goodCalmingDown: VoiceOverCategory.attentionAndRegulation,
  VoiceOverCue.itsOkay: VoiceOverCategory.attentionAndRegulation,
  VoiceOverCue.letsContinue: VoiceOverCategory.attentionAndRegulation,
  VoiceOverCue.letsSlowDown: VoiceOverCategory.attentionAndRegulation,
  VoiceOverCue.listenCarefully: VoiceOverCategory.attentionAndRegulation,
  VoiceOverCue.readyAgain: VoiceOverCategory.attentionAndRegulation,
  VoiceOverCue.takeABreath: VoiceOverCategory.attentionAndRegulation,
  VoiceOverCue.youAreSafe: VoiceOverCategory.attentionAndRegulation,

  // Core Praise
  VoiceOverCue.aumazing: VoiceOverCategory.corePraise,
  VoiceOverCue.ausome: VoiceOverCategory.corePraise,
  VoiceOverCue.correct: VoiceOverCategory.corePraise,
  VoiceOverCue.excellent: VoiceOverCategory.corePraise,
  VoiceOverCue.goodTry: VoiceOverCategory.corePraise,
  VoiceOverCue.greatJob: VoiceOverCategory.corePraise,
  VoiceOverCue.niceWork: VoiceOverCategory.corePraise,
  VoiceOverCue.thatsRight: VoiceOverCategory.corePraise,
  VoiceOverCue.veryGood: VoiceOverCategory.corePraise,
  VoiceOverCue.wellDone: VoiceOverCategory.corePraise,
  VoiceOverCue.yayYouGotIt: VoiceOverCategory.corePraise,
  VoiceOverCue.youDidIt: VoiceOverCategory.corePraise,

  // Gently Retry
  VoiceOverCue.almostThere: VoiceOverCategory.gentlyRetry,
  VoiceOverCue.giveItAnotherTry: VoiceOverCategory.gentlyRetry,
  VoiceOverCue.keepGoing: VoiceOverCategory.gentlyRetry,
  VoiceOverCue.letsDoItOneMoreTime: VoiceOverCategory.gentlyRetry,
  VoiceOverCue.letsPracticeAgain: VoiceOverCategory.gentlyRetry,
  VoiceOverCue.letsTryAgain: VoiceOverCategory.gentlyRetry,
  VoiceOverCue.niceTry: VoiceOverCategory.gentlyRetry,
  VoiceOverCue.notYet: VoiceOverCategory.gentlyRetry,
  VoiceOverCue.tryAgain: VoiceOverCategory.gentlyRetry,
  VoiceOverCue.youCanDoIt: VoiceOverCategory.gentlyRetry,

  // Instruction
  VoiceOverCue.chooseOne: VoiceOverCategory.instruction,
  VoiceOverCue.copyMe: VoiceOverCategory.instruction,
  VoiceOverCue.countWithMe: VoiceOverCategory.instruction,
  VoiceOverCue.dragIt: VoiceOverCategory.instruction,
  VoiceOverCue.findTheSame: VoiceOverCategory.instruction,
  VoiceOverCue.followMe: VoiceOverCategory.instruction,
  VoiceOverCue.letsBegin: VoiceOverCategory.instruction,
  VoiceOverCue.listen: VoiceOverCategory.instruction,
  VoiceOverCue.matchIt: VoiceOverCategory.instruction,
  VoiceOverCue.myTurnInstruction: VoiceOverCategory.instruction,
  VoiceOverCue.pickTheColor: VoiceOverCategory.instruction,
  VoiceOverCue.pickTheShape: VoiceOverCategory.instruction,
  VoiceOverCue.tapHere: VoiceOverCategory.instruction,
  VoiceOverCue.touchThePicture: VoiceOverCategory.instruction,
  VoiceOverCue.watchCarefully: VoiceOverCategory.instruction,
  VoiceOverCue.yourTurnInstruction: VoiceOverCategory.instruction,

  // Reward & Celebration
  VoiceOverCue.awesomeWorkToday: VoiceOverCategory.rewardAndCelebration,
  VoiceOverCue.bigHighFive: VoiceOverCategory.rewardAndCelebration,
  VoiceOverCue.fantastic: VoiceOverCategory.rewardAndCelebration,
  VoiceOverCue.greatPlaying: VoiceOverCategory.rewardAndCelebration,
  VoiceOverCue.hooray: VoiceOverCategory.rewardAndCelebration,
  VoiceOverCue.superJob: VoiceOverCategory.rewardAndCelebration,
  VoiceOverCue.youDidSoWell: VoiceOverCategory.rewardAndCelebration,
  VoiceOverCue.youFinishedIt: VoiceOverCategory.rewardAndCelebration,
  VoiceOverCue.youreAmazing: VoiceOverCategory.rewardAndCelebration,

  // Transition
  VoiceOverCue.gameFinished: VoiceOverCategory.transition,
  VoiceOverCue.getReady: VoiceOverCategory.transition,
  VoiceOverCue.goodJobMovingOn: VoiceOverCategory.transition,
  VoiceOverCue.letsGo: VoiceOverCategory.transition,
  VoiceOverCue.letsPlayAgain: VoiceOverCategory.transition,
  VoiceOverCue.levelComplete: VoiceOverCategory.transition,
  VoiceOverCue.newGame: VoiceOverCategory.transition,
  VoiceOverCue.nextActivity: VoiceOverCategory.transition,
  VoiceOverCue.nextOne: VoiceOverCategory.transition,
  VoiceOverCue.timeForTheNextOne: VoiceOverCategory.transition,

  // Turn Taking
  VoiceOverCue.goodWaiting: VoiceOverCategory.turnTaking,
  VoiceOverCue.hereWeGo: VoiceOverCategory.turnTaking,
  VoiceOverCue.letsTakeTurns: VoiceOverCategory.turnTaking,
  VoiceOverCue.myTurn: VoiceOverCategory.turnTaking,
  VoiceOverCue.nowYouTry: VoiceOverCategory.turnTaking,
  VoiceOverCue.ready: VoiceOverCategory.turnTaking,
  VoiceOverCue.thankYouForWaiting: VoiceOverCategory.turnTaking,
  VoiceOverCue.wait: VoiceOverCategory.turnTaking,
  VoiceOverCue.watchMeFirst: VoiceOverCategory.turnTaking,
  VoiceOverCue.yourTurn: VoiceOverCategory.turnTaking,

  // Dynamic
  VoiceOverCue.tapThe: VoiceOverCategory.dynamic,
  VoiceOverCue.dragThe: VoiceOverCategory.dynamic,
  VoiceOverCue.dropThe: VoiceOverCategory.dynamic,

  // Colors
  VoiceOverCue.colorRed: VoiceOverCategory.colors,
  VoiceOverCue.colorBlue: VoiceOverCategory.colors,
  VoiceOverCue.colorGreen: VoiceOverCategory.colors,
  VoiceOverCue.colorYellow: VoiceOverCategory.colors,
  VoiceOverCue.colorPurple: VoiceOverCategory.colors,
  VoiceOverCue.colorOrange: VoiceOverCategory.colors,

  // Shapes
  VoiceOverCue.shapeCircle: VoiceOverCategory.shapes,
  VoiceOverCue.shapeStar: VoiceOverCategory.shapes,
  VoiceOverCue.shapeTriangle: VoiceOverCategory.shapes,
  VoiceOverCue.shapeDiamond: VoiceOverCategory.shapes,
};

/// Maps each [VoiceOverCue] to its asset file path (relative to the package
/// asset root, i.e. `packages/shared_audio/assets/audio/voice_over/...`).
const Map<VoiceOverCue, String> _cueAssetPaths = {
  // Assessment Style
  VoiceOverCue.canYouCopyMe: 'voice_over/assessment_style/CanYouCopyMe.wav',
  VoiceOverCue.canYouMatchThis:
      'voice_over/assessment_style/CanYouMatchThis.wav',
  VoiceOverCue.findTheRightOne:
      'voice_over/assessment_style/FindTheRightOne.wav',
  VoiceOverCue.goodListening: 'voice_over/assessment_style/GoodListening.wav',
  VoiceOverCue.goodLooking: 'voice_over/assessment_style/GoodLooking.wav',
  VoiceOverCue.letSeeWhatYouCanDo:
      'voice_over/assessment_style/LetSeeWhatYouCanDo.wav',
  VoiceOverCue.letsTryTheNextTask:
      'voice_over/assessment_style/LetsTryTheNextTask.wav',
  VoiceOverCue.showMe: 'voice_over/assessment_style/ShowMe.wav',
  VoiceOverCue.whatComesNext: 'voice_over/assessment_style/WhatComesNext.wav',
  VoiceOverCue.whichOneIsTheSame:
      'voice_over/assessment_style/WhichOneIsTheSame.wav',

  // Attention and Regulation
  VoiceOverCue.calmBody:
      'voice_over/attention_and_regulation/CalmBody.wav',
  VoiceOverCue.eyesHere:
      'voice_over/attention_and_regulation/EyesHere.wav',
  VoiceOverCue.goodCalmingDown:
      'voice_over/attention_and_regulation/GoodCalmingDown.wav',
  VoiceOverCue.itsOkay:
      'voice_over/attention_and_regulation/ItsOkay.wav',
  VoiceOverCue.letsContinue:
      'voice_over/attention_and_regulation/LetsContinue.wav',
  VoiceOverCue.letsSlowDown:
      'voice_over/attention_and_regulation/LetsSlowDown.wav',
  VoiceOverCue.listenCarefully:
      'voice_over/attention_and_regulation/ListenCarefully.wav',
  VoiceOverCue.readyAgain:
      'voice_over/attention_and_regulation/ReadyAgain.wav',
  VoiceOverCue.takeABreath:
      'voice_over/attention_and_regulation/TakeABreath.wav',
  VoiceOverCue.youAreSafe:
      'voice_over/attention_and_regulation/YouAreSafe.wav',

  // Core Praise
  VoiceOverCue.aumazing: 'voice_over/core_praise/Aumazing.wav',
  VoiceOverCue.ausome: 'voice_over/core_praise/Ausome.wav',
  VoiceOverCue.correct: 'voice_over/core_praise/Correct.wav',
  VoiceOverCue.excellent: 'voice_over/core_praise/Excellent.wav',
  VoiceOverCue.goodTry: 'voice_over/core_praise/GoodTry.wav',
  VoiceOverCue.greatJob: 'voice_over/core_praise/GreatJob.wav',
  VoiceOverCue.niceWork: 'voice_over/core_praise/NiceWork.wav',
  VoiceOverCue.thatsRight: 'voice_over/core_praise/ThatsRight.wav',
  VoiceOverCue.veryGood: 'voice_over/core_praise/VeryGood.wav',
  VoiceOverCue.wellDone: 'voice_over/core_praise/WellDone.wav',
  VoiceOverCue.yayYouGotIt: 'voice_over/core_praise/YayYouGotIt.wav',
  VoiceOverCue.youDidIt: 'voice_over/core_praise/YouDidIt.wav',

  // Gently Retry
  VoiceOverCue.almostThere: 'voice_over/gently_retry/AlmostThere.wav',
  VoiceOverCue.giveItAnotherTry:
      'voice_over/gently_retry/GiveItAnotherTry.wav',
  VoiceOverCue.keepGoing: 'voice_over/gently_retry/KeepGoing.wav',
  VoiceOverCue.letsDoItOneMoreTime:
      'voice_over/gently_retry/LetsDoItOneMoreTime.wav',
  VoiceOverCue.letsPracticeAgain:
      'voice_over/gently_retry/LetsPracticeAgain.wav',
  VoiceOverCue.letsTryAgain: 'voice_over/gently_retry/LetsTryAgain.wav',
  VoiceOverCue.niceTry: 'voice_over/gently_retry/NiceTry.wav',
  VoiceOverCue.notYet: 'voice_over/gently_retry/NotYet.wav',
  VoiceOverCue.tryAgain: 'voice_over/gently_retry/TryAgain.wav',
  VoiceOverCue.youCanDoIt: 'voice_over/gently_retry/YouCanDoIt.wav',

  // Instruction
  VoiceOverCue.chooseOne: 'voice_over/instruction/ChooseOne.wav',
  VoiceOverCue.copyMe: 'voice_over/instruction/CopyMe.wav',
  VoiceOverCue.countWithMe: 'voice_over/instruction/CountWithMe.wav',
  VoiceOverCue.dragIt: 'voice_over/instruction/DragIt.wav',
  VoiceOverCue.findTheSame: 'voice_over/instruction/FindTheSame.wav',
  VoiceOverCue.followMe: 'voice_over/instruction/FollowMe.wav',
  VoiceOverCue.letsBegin: 'voice_over/instruction/LetsBegin.wav',
  VoiceOverCue.listen: 'voice_over/instruction/Listen.wav',
  VoiceOverCue.matchIt: 'voice_over/instruction/MatchIt.wav',
  VoiceOverCue.myTurnInstruction: 'voice_over/instruction/MyTurn.wav',
  VoiceOverCue.pickTheColor: 'voice_over/instruction/PickTheColor.wav',
  VoiceOverCue.pickTheShape: 'voice_over/instruction/PickTheShape.wav',
  VoiceOverCue.tapHere: 'voice_over/instruction/TapHere.wav',
  VoiceOverCue.touchThePicture: 'voice_over/instruction/TouchThePicture.wav',
  VoiceOverCue.watchCarefully: 'voice_over/instruction/WatchCarefully.wav',
  VoiceOverCue.yourTurnInstruction: 'voice_over/instruction/YourTurn.wav',

  // Reward & Celebration
  VoiceOverCue.awesomeWorkToday:
      'voice_over/reward_and_celebration/AwesomeWorkToday.wav',
  VoiceOverCue.bigHighFive:
      'voice_over/reward_and_celebration/BigHighFive.wav',
  VoiceOverCue.fantastic: 'voice_over/reward_and_celebration/Fantastic.wav',
  VoiceOverCue.greatPlaying:
      'voice_over/reward_and_celebration/GreatPlaying.wav',
  VoiceOverCue.hooray: 'voice_over/reward_and_celebration/Hooray.wav',
  VoiceOverCue.superJob: 'voice_over/reward_and_celebration/SuperJob.wav',
  VoiceOverCue.youDidSoWell:
      'voice_over/reward_and_celebration/YouDidSoWell.wav',
  VoiceOverCue.youFinishedIt:
      'voice_over/reward_and_celebration/YouFinishedIt.wav',
  VoiceOverCue.youreAmazing:
      'voice_over/reward_and_celebration/YoureAmazing.wav',

  // Transition
  VoiceOverCue.gameFinished: 'voice_over/transition/GameFinished.wav',
  VoiceOverCue.getReady: 'voice_over/transition/GetReady.wav',
  VoiceOverCue.goodJobMovingOn: 'voice_over/transition/GoodJobMovingOn.wav',
  VoiceOverCue.letsGo: 'voice_over/transition/LetsGo.wav',
  VoiceOverCue.letsPlayAgain: 'voice_over/transition/LetsPlayAgain.wav',
  VoiceOverCue.levelComplete: 'voice_over/transition/LevelComplete.wav',
  VoiceOverCue.newGame: 'voice_over/transition/NewGame.wav',
  VoiceOverCue.nextActivity: 'voice_over/transition/NextActivity.wav',
  VoiceOverCue.nextOne: 'voice_over/transition/NextOne.wav',
  VoiceOverCue.timeForTheNextOne:
      'voice_over/transition/TimeForTheNextOne.wav',

  // Turn Taking
  VoiceOverCue.goodWaiting: 'voice_over/turn_taking/GoodWaiting.wav',
  VoiceOverCue.hereWeGo: 'voice_over/turn_taking/HereWeGo.wav',
  VoiceOverCue.letsTakeTurns: 'voice_over/turn_taking/LetsTakeTurns.wav',
  VoiceOverCue.myTurn: 'voice_over/turn_taking/MyTurn.wav',
  VoiceOverCue.nowYouTry: 'voice_over/turn_taking/NowYouTry.wav',
  VoiceOverCue.ready: 'voice_over/turn_taking/Ready.wav',
  VoiceOverCue.thankYouForWaiting:
      'voice_over/turn_taking/ThankYouForWaiting.wav',
  VoiceOverCue.wait: 'voice_over/turn_taking/Wait.wav',
  VoiceOverCue.watchMeFirst: 'voice_over/turn_taking/WatchMeFirst.wav',
  VoiceOverCue.yourTurn: 'voice_over/turn_taking/YourTurn.wav',

  // Dynamic
  VoiceOverCue.tapThe: 'voice_over/dynamic/TapThe.wav',
  VoiceOverCue.dragThe: 'voice_over/dynamic/DragThe.wav',
  VoiceOverCue.dropThe: 'voice_over/dynamic/DropThe.wav',

  // Colors
  VoiceOverCue.colorRed: 'voice_over/colors/Red.wav',
  VoiceOverCue.colorBlue: 'voice_over/colors/Blue.wav',
  VoiceOverCue.colorGreen: 'voice_over/colors/Green.wav',
  VoiceOverCue.colorYellow: 'voice_over/colors/Yellow.wav',
  VoiceOverCue.colorPurple: 'voice_over/colors/Purple.wav',
  VoiceOverCue.colorOrange: 'voice_over/colors/Orange.wav',

  // Shapes
  VoiceOverCue.shapeCircle: 'voice_over/shapes/Circle.wav',
  VoiceOverCue.shapeStar: 'voice_over/shapes/Star.wav',
  VoiceOverCue.shapeTriangle: 'voice_over/shapes/Triangle.wav',
  VoiceOverCue.shapeDiamond: 'voice_over/shapes/Diamond.wav',
};

/// Audio context for voice-over playback that mixes with background music.
final _voiceOverAudioContext = AudioContext(
  android: AudioContextAndroid(
    audioFocus: AndroidAudioFocus.none,
    contentType: AndroidContentType.speech,
    usageType: AndroidUsageType.game,
  ),
  iOS: AudioContextIOS(
    category: AVAudioSessionCategory.playback,
    options: {AVAudioSessionOptions.mixWithOthers},
  ),
);

/// Maximum number of players in the voice-over pool.
///
/// Using a pool avoids the Android MediaPlayer "reset during preparing"
/// bug that occurs when a single player is rapidly stopped and restarted.
const _kPoolSize = 3;

/// Minimum interval between consecutive [play] calls to prevent rapid
/// fire that overwhelms the audio system.
const _kDebounceInterval = Duration(milliseconds: 300);

/// Service for playing voice-over audio cues.
///
/// Uses a pool of [AudioPlayer] instances to avoid the Android MediaPlayer
/// "reset during preparing" bug. When a new cue is requested, the service
/// picks an available (stopped/completed) player from the pool and plays
/// on it. The previously active player is stopped asynchronously so its
/// native MediaPlayer has time to release without blocking the new playback.
///
/// Uses [AssetSource] for playback which works reliably on both Android and
/// iOS.
///
/// Supports multiple languages via [languageCode]. Voice-over assets are
/// loaded from language-specific subdirectories:
///   `voice_over/{languageCode}/{category}/{CueName}.wav`
///
/// Supported language codes: `'en'` (English), `'tl'` (Tagalog),
/// `'ceb'` (Cebuano/Bisaya).
///
/// Usage:
/// ```dart
/// final voiceOver = VoiceOverService(languageCode: 'tl');
/// await voiceOver.play(VoiceOverCue.greatJob);
/// await voiceOver.playCorrectPraise(); // random from Core Praise
/// await voiceOver.setLanguage('ceb');  // switch language at runtime
/// voiceOver.setEnabled(false);         // master toggle
/// ```
class VoiceOverService {
  /// Asset prefix for package-based assets.
  static const String _assetPrefix = 'packages/shared_audio/assets/audio';

  /// Supported language codes for voice-over playback.
  static const List<String> supportedLanguages = ['en', 'tl', 'ceb'];

  /// Current language code for voice-over asset resolution.
  String _languageCode;

  /// Pool of players for voice-over playback.
  final List<AudioPlayer> _players = [];

  /// Index of the player that was most recently used for playback.
  int _activePlayerIndex = 0;

  /// Master toggle for voice-over playback.
  bool _enabled;

  /// Volume level for voice-over playback (0.0 – 1.0).
  double _volume;

  /// Random number generator for category-based random playback.
  final Random _random;

  /// Lazily built lookup: category → list of cues in that category.
  late final Map<VoiceOverCategory, List<VoiceOverCue>> _cuesByCategory;

  /// Timestamp of the last successful [play] call, used for debouncing.
  DateTime? _lastPlayTime;

  /// Flag to cancel an in-progress [playSequence] call.
  bool _sequenceCancelled = false;

  VoiceOverService({
    String languageCode = 'en',
    bool enabled = true,
    double volume = 1.0,
    Random? random,
  })  : _languageCode = supportedLanguages.contains(languageCode)
            ? languageCode
            : 'en',
        _enabled = enabled,
        _volume = volume.clamp(0.0, 1.0),
        _random = random ?? Random() {
    // Create the player pool.
    for (int i = 0; i < _kPoolSize; i++) {
      final player = AudioPlayer()..setAudioContext(_voiceOverAudioContext);
      player.audioCache = AudioCache(prefix: '');
      _players.add(player);
    }

    // Build the category → cues lookup once.
    _cuesByCategory = {};
    for (final entry in _cueCategories.entries) {
      _cuesByCategory.putIfAbsent(entry.value, () => []).add(entry.key);
    }
  }

  // ── State Queries ───────────────────────────────────────────────────

  /// Whether a voice-over cue is currently playing on any pool player.
  bool get isPlaying =>
      _players.any((p) => p.state == PlayerState.playing);

  /// Whether voice-over playback is enabled.
  bool get isEnabled => _enabled;

  /// Current language code for voice-over playback.
  String get languageCode => _languageCode;

  /// Current volume level (0.0 – 1.0).
  double get volume => _volume;

  // ── Configuration ───────────────────────────────────────────────────

  /// Set the master volume for voice-over playback.
  ///
  /// [volume] is clamped to the range 0.0 – 1.0.
  void setVolume(double volume) {
    _volume = volume.clamp(0.0, 1.0);
    for (final player in _players) {
      player.setVolume(_enabled ? _volume : 0.0);
    }
  }

  /// Change the voice-over language at runtime.
  ///
  /// Stops any currently playing cue and updates the language.
  /// Falls back to `'en'` if [languageCode] is not in
  /// [supportedLanguages].
  Future<void> setLanguage(String languageCode) async {
    if (!supportedLanguages.contains(languageCode)) {
      debugPrint(
          '[VoiceOverService] ⚠ Unsupported language: $languageCode, '
          'falling back to en');
      languageCode = 'en';
    }
    if (_languageCode != languageCode) {
      await stop();
      _languageCode = languageCode;
      debugPrint(
          '[VoiceOverService] 🌐 Language changed to: $_languageCode');
    }
  }

  /// Enable or disable voice-over playback globally.
  ///
  /// When disabled, calls to [play] and convenience methods are no-ops.
  void setEnabled(bool enabled) {
    _enabled = enabled;
    if (!enabled) {
      for (final player in _players) {
        player.stop();
      }
    }
  }

  // ── Playback ────────────────────────────────────────────────────────

  /// Find an available player from the pool.
  ///
  /// Prefers a player that is stopped or completed. If all players are
  /// busy, returns the oldest one (round-robin) so it can be reused.
  AudioPlayer _getAvailablePlayer() {
    // First pass: find a player that's not playing.
    for (int i = 0; i < _players.length; i++) {
      final idx = (i + _activePlayerIndex + 1) % _players.length;
      final player = _players[idx];
      if (player.state == PlayerState.stopped ||
          player.state == PlayerState.completed) {
        _activePlayerIndex = idx;
        return player;
      }
    }
    // All players are busy — use round-robin to pick the next one.
    _activePlayerIndex = (_activePlayerIndex + 1) % _players.length;
    return _players[_activePlayerIndex];
  }

  /// Play a specific voice-over [cue].
  ///
  /// Uses a pool of players to avoid the Android MediaPlayer "reset during
  /// preparing" bug. The previously active player is stopped asynchronously
  /// while the new cue starts on a different player.
  ///
  /// When [awaitCompletion] is true (default: false), the returned Future
  /// completes only after the audio clip finishes playing. This is used by
  /// [playSequence] to chain clips.
  ///
  /// Rapid calls within [_kDebounceInterval] are silently ignored unless
  /// [skipDebounce] is true (used internally by [playSequence]).
  Future<void> play(
    VoiceOverCue cue, {
    bool awaitCompletion = false,
    bool skipDebounce = false,
  }) async {
    if (!_enabled) return;

    // Debounce: ignore rapid calls (unless skipped for sequence playback).
    if (!skipDebounce) {
      final now = DateTime.now();
      if (_lastPlayTime != null &&
          now.difference(_lastPlayTime!) < _kDebounceInterval) {
        debugPrint(
            '[VoiceOverService] ⏭ Debounced (${now.difference(_lastPlayTime!).inMilliseconds}ms): ${cue.name}');
        return;
      }
      _lastPlayTime = now;
    }

    final relativePath = _cueAssetPaths[cue];
    if (relativePath == null) {
      debugPrint('[VoiceOverService] ✖ No asset path for cue: ${cue.name}');
      return;
    }

    // Insert language folder: voice_over/{lang}/category/File.wav
    final langPath = relativePath.replaceFirst(
      'voice_over/',
      'voice_over/$_languageCode/',
    );
    final assetPath = '$_assetPrefix/$langPath';

    try {
      // Stop all currently playing players (fire-and-forget).
      for (final player in _players) {
        if (player.state == PlayerState.playing) {
          player.stop(); // intentionally not awaited
        }
      }

      // Pick an available player from the pool.
      final player = _getAvailablePlayer();

      player.setReleaseMode(ReleaseMode.stop);
      await player.setVolume(_volume);

      debugPrint('[VoiceOverService] 🗣 Playing: ${cue.name} '
          '(lang=$_languageCode, vol=$_volume)');

      if (awaitCompletion) {
        // Wait for the clip to finish playing before returning.
        final completer = Completer<void>();
        StreamSubscription<void>? subscription;
        subscription = player.onPlayerComplete.listen((_) {
          if (!completer.isCompleted) completer.complete();
          subscription?.cancel();
        });
        await player.play(AssetSource(assetPath));
        await completer.future;
      } else {
        await player.play(AssetSource(assetPath));
      }
    } catch (e) {
      debugPrint('[VoiceOverService] ✖ Error playing "${cue.name}": $e');
    }
  }

  /// Plays a sequence of voice-over cues one after another.
  /// Each cue waits for the previous one to finish before playing.
  /// Returns when the entire sequence has finished or been cancelled.
  Future<void> playSequence(
    List<VoiceOverCue> cues, {
    Duration gap = const Duration(milliseconds: 80),
  }) async {
    // Cancel any currently playing sequence or single cue
    await stop();
    _sequenceCancelled = false;

    for (final cue in cues) {
      if (_sequenceCancelled) break;
      await play(cue, awaitCompletion: true, skipDebounce: true);
      if (_sequenceCancelled) break;
      if (cue != cues.last) {
        await Future.delayed(gap);
      }
    }
  }

  /// Play a random voice-over cue from the given [category].
  ///
  /// Useful for varied praise, encouragement, or transitions so the child
  /// hears different phrases each time.
  Future<void> playRandom(VoiceOverCategory category) async {
    final cues = _cuesByCategory[category];
    if (cues == null || cues.isEmpty) return;
    final cue = cues[_random.nextInt(cues.length)];
    debugPrint(
        '[VoiceOverService] 🎲 Random from ${category.name}: ${cue.name}');
    await play(cue);
  }

  // ── Convenience Methods ─────────────────────────────────────────────

  /// Play a random praise cue from [VoiceOverCategory.corePraise].
  Future<void> playCorrectPraise() =>
      playRandom(VoiceOverCategory.corePraise);

  /// Play a random encouragement cue from [VoiceOverCategory.gentlyRetry].
  Future<void> playWrongEncouragement() =>
      playRandom(VoiceOverCategory.gentlyRetry);

  /// Play a random transition cue from [VoiceOverCategory.transition].
  Future<void> playTransition() =>
      playRandom(VoiceOverCategory.transition);

  /// Play a random celebration cue from
  /// [VoiceOverCategory.rewardAndCelebration].
  Future<void> playRewardCelebration() =>
      playRandom(VoiceOverCategory.rewardAndCelebration);

  // ── Playback Control ────────────────────────────────────────────────

  /// Stop the currently playing voice-over cue, if any.
  /// Also cancels any in-progress [playSequence] call.
  Future<void> stop() async {
    _sequenceCancelled = true;
    for (final player in _players) {
      await player.stop();
    }
  }

  // ── Lifecycle ───────────────────────────────────────────────────────

  /// Release audio resources. Call when the service is no longer needed.
  Future<void> dispose() async {
    _sequenceCancelled = true;
    for (final player in _players) {
      await player.dispose();
    }
    _players.clear();
  }

  // ── Composite Instruction Helpers ──────────────────────────────────

  /// Composes a list of [VoiceOverCue]s for a game instruction.
  /// [action] is 'tap', 'drag', or 'drop'
  /// [color] is the color name (lowercase)
  /// [shape] is the shape type (lowercase)
  static List<VoiceOverCue> composeInstruction({
    required String action,
    required String color,
    required String shape,
  }) {
    final actionCue = _actionMap[action.toLowerCase()];
    final colorCue = _colorMap[color.toLowerCase()];
    final shapeCue = _shapeMap[shape.toLowerCase()];

    return [
      if (actionCue != null) actionCue,
      if (colorCue != null) colorCue,
      if (shapeCue != null) shapeCue,
    ];
  }

  static const _actionMap = {
    'tap': VoiceOverCue.tapThe,
    'drag': VoiceOverCue.dragThe,
    'drop': VoiceOverCue.dropThe,
  };

  static const _colorMap = {
    'red': VoiceOverCue.colorRed,
    'blue': VoiceOverCue.colorBlue,
    'green': VoiceOverCue.colorGreen,
    'yellow': VoiceOverCue.colorYellow,
    'purple': VoiceOverCue.colorPurple,
    'orange': VoiceOverCue.colorOrange,
  };

  static const _shapeMap = {
    'circle': VoiceOverCue.shapeCircle,
    'star': VoiceOverCue.shapeStar,
    'triangle': VoiceOverCue.shapeTriangle,
    'diamond': VoiceOverCue.shapeDiamond,
  };
}
