import 'dart:async';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'voice_pack.dart';

/// How much claim a line has on the narrator when two want to speak.
///
/// The layers are not about loudness or order in a queue — they decide which
/// line the child hears *at all*. A higher layer speaking means the lower one
/// is dropped, not deferred, because two voices in the same breath is the thing
/// being avoided and a queued line arrives after the moment it referred to.
///
/// Applies to every game: the arbitration lives here, in the one service all of
/// them speak through, so no game has to reason about it.
enum VoiceOverPriority {
  /// Naming back what the child just did — "red circle", "Gatas", "A".
  ///
  /// Outranks praise. It is tied to the thing on screen the child is looking at
  /// right now, and it teaches the label; praise teaches nothing about *what*
  /// was right.
  immediateFeedback,

  /// "Great job!", "Well done!" — core praise and the end-of-game celebration.
  ///
  /// Fills the gap when there was nothing to name, so a correct answer is never
  /// met with silence.
  praise,
}

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
  phrases,    // Whole colour+shape phrases: "Purple circle" 
  shapes,     // Shape names: "Circle", "Star", etc.
  letters,    // Letter names: "A", "C", etc. (Trace It)
  numbers,    // Numeral names: "One", "Two", etc. (Trace It)
  items,      // Sari-sari store item names: "Tinapay", "Gatas", etc.
  routines,   // Ano'ng Susunod routine titles and step names: "Umaga", "Maligo"
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
  //
  // Every line here must read as *you got it right*, with no second meaning.
  // "Good try!" used to sit in this set and does not: it praises the attempt,
  // so one correct answer in twelve was answered with consolation. For a child
  // working out which sounds mean success, that is the one channel that cannot
  // be ambiguous. It says the same thing as gently_retry/NiceTry — in Cebuano,
  // the same words — so it was retired rather than moved.
  aumazing,
  ausome,
  correct,
  excellent,
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
  /// "Please give the device to your parent." — spoken once the child has
  /// finished every assessment game and the screen is waiting on a grown-up.
  ///
  /// It lives in Instruction rather than Transition because Transition is drawn
  /// at random by [VoiceOverService.playTransition]; a hand-the-device line
  /// surfacing between two rounds of a game would be nonsense.
  giveTheDeviceToYourParent,
  letsBegin,
  listen,
  matchIt,
  myTurnInstruction,
  pickTheColor,
  pickTheShape,
  tapHere,

  /// "Wait for the star to wake up, then tap it." — the Hintay! instruction.
  ///
  /// A dedicated line rather than the reused `eyesHere`: that cue orients
  /// attention but never says the task is to *wait*, which is the whole of
  /// what this game measures.
  waitForTheStar,

  /// "Tap the star!" — spoken only as the escalated prompt when the child has
  /// missed the cue and the pointing hand alone was not enough. Never on the
  /// cue itself, which would put a spoken word inside the response-time
  /// measurement.
  tapTheStar,

  /// "Say hello back!" — the Kumusta! instruction.
  ///
  /// A dedicated line for the same reason [waitForTheStar] is one. `showMe`
  /// stood in here first and asks for the wrong thing: it is the assessment
  /// library's "demonstrate something for me", which describes the child
  /// performing for an adult rather than answering another person's greeting.
  /// The whole skill is that a social bid arrived and it is now the child's
  /// turn to return it — the word "back" is doing the work, and nothing else
  /// in the library says it.
  sayHelloBack,
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
  colorGold,
  colorPink,
  colorMagenta,
  colorTeal,


  // ── Colour+shape phrase cues ───────────────────────────────────────
  // Recorded as one utterance so the colour leads into the shape instead of
  // ending like a sentence. Derived from the games' own palettes.
  phraseBlueCircle,
  phraseBlueDiamond,
  phraseBlueStar,
  phraseBlueTriangle,
  phraseGoldStar,
  phraseGreenCircle,
  phraseGreenDiamond,
  phraseGreenStar,
  phraseGreenTriangle,
  phraseMagentaDiamond,
  phraseOrangeCircle,
  phraseOrangeDiamond,
  phraseOrangeStar,
  phraseOrangeTriangle,
  phrasePinkHeart,
  phrasePurpleCircle,
  phrasePurpleDiamond,
  phrasePurpleHeart,
  phrasePurpleStar,
  phrasePurpleTriangle,
  phraseRedCircle,
  phraseRedDiamond,
  phraseRedHeart,
  phraseRedStar,
  phraseRedTriangle,
  phraseTealTriangle,
  phraseYellowCircle,
  phraseYellowDiamond,
  phraseYellowStar,
  phraseYellowTriangle,

  // ── Shape cues ─────────────────────────────────────────────────────
  shapeCircle,
  shapeStar,
  shapeTriangle,
  shapeDiamond,
  shapeHeart,

  // ── Letter cues (Trace It glyphs) ───────────────────────────────────
  letterA,
  letterC,
  letterE,
  letterH,
  letterL,
  letterT,
  letterU,
  letterV,

  // ── Numeral cues (Trace It glyphs) ──────────────────────────────────
  numberOne,
  numberTwo,
  numberThree,
  numberFour,
  numberFive,
  numberSeven,

  // ── Sari-Sari Sort item cues ────────────────────────────────────────
  itemTinapay,
  itemBiskwit,
  itemKendi,
  itemSaging,
  itemMansanas,
  itemTubig,
  itemGatas,
  itemJuice,
  itemSoftdrink,
  itemKape,
  itemSabon,
  itemSipilyo,
  itemTisyu,
  itemSyampu,
  // Toys. The sari-sari sort gained a toys category on the SPED teacher's
  // advice; these four are the only item names in it.
  itemBola,
  itemManika,
  itemKotse,
  itemTeddy,

  // ── Ano'ng Susunod routine cues ─────────────────────────────────────
  //
  // The four routine names, spoken as each round opens, and the fourteen step
  // names, spoken back when the child seats a card correctly. Naming the step
  // is what turns a correct placement into another exposure to the word for it
  // — the same reason the sari-sari items are named back.
  routineMorning,
  routineMealtime,
  routineBedtime,
  routinePlaytime,
  stepWakeUp,
  stepBrushTeeth,
  stepBreakfast,
  stepSchool,
  stepWashHands,
  stepSitAtTable,
  stepEat,
  stepClearPlate,
  stepBath,
  stepPajamas,
  stepSleep,
  stepGetToy,
  stepPlay,
  stepPutAway,
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
  VoiceOverCue.giveTheDeviceToYourParent: VoiceOverCategory.instruction,
  VoiceOverCue.letsBegin: VoiceOverCategory.instruction,
  VoiceOverCue.listen: VoiceOverCategory.instruction,
  VoiceOverCue.matchIt: VoiceOverCategory.instruction,
  VoiceOverCue.myTurnInstruction: VoiceOverCategory.instruction,
  VoiceOverCue.pickTheColor: VoiceOverCategory.instruction,
  VoiceOverCue.pickTheShape: VoiceOverCategory.instruction,
  VoiceOverCue.tapHere: VoiceOverCategory.instruction,
  VoiceOverCue.waitForTheStar: VoiceOverCategory.instruction,
  VoiceOverCue.tapTheStar: VoiceOverCategory.instruction,
  VoiceOverCue.sayHelloBack: VoiceOverCategory.instruction,
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
  VoiceOverCue.colorGold: VoiceOverCategory.colors,
  VoiceOverCue.colorPink: VoiceOverCategory.colors,
  VoiceOverCue.colorMagenta: VoiceOverCategory.colors,
  VoiceOverCue.colorTeal: VoiceOverCategory.colors,


  // Colour+shape phrases
  VoiceOverCue.phraseBlueCircle: VoiceOverCategory.phrases,
  VoiceOverCue.phraseBlueDiamond: VoiceOverCategory.phrases,
  VoiceOverCue.phraseBlueStar: VoiceOverCategory.phrases,
  VoiceOverCue.phraseBlueTriangle: VoiceOverCategory.phrases,
  VoiceOverCue.phraseGoldStar: VoiceOverCategory.phrases,
  VoiceOverCue.phraseGreenCircle: VoiceOverCategory.phrases,
  VoiceOverCue.phraseGreenDiamond: VoiceOverCategory.phrases,
  VoiceOverCue.phraseGreenStar: VoiceOverCategory.phrases,
  VoiceOverCue.phraseGreenTriangle: VoiceOverCategory.phrases,
  VoiceOverCue.phraseMagentaDiamond: VoiceOverCategory.phrases,
  VoiceOverCue.phraseOrangeCircle: VoiceOverCategory.phrases,
  VoiceOverCue.phraseOrangeDiamond: VoiceOverCategory.phrases,
  VoiceOverCue.phraseOrangeStar: VoiceOverCategory.phrases,
  VoiceOverCue.phraseOrangeTriangle: VoiceOverCategory.phrases,
  VoiceOverCue.phrasePinkHeart: VoiceOverCategory.phrases,
  VoiceOverCue.phrasePurpleCircle: VoiceOverCategory.phrases,
  VoiceOverCue.phrasePurpleDiamond: VoiceOverCategory.phrases,
  VoiceOverCue.phrasePurpleHeart: VoiceOverCategory.phrases,
  VoiceOverCue.phrasePurpleStar: VoiceOverCategory.phrases,
  VoiceOverCue.phrasePurpleTriangle: VoiceOverCategory.phrases,
  VoiceOverCue.phraseRedCircle: VoiceOverCategory.phrases,
  VoiceOverCue.phraseRedDiamond: VoiceOverCategory.phrases,
  VoiceOverCue.phraseRedHeart: VoiceOverCategory.phrases,
  VoiceOverCue.phraseRedStar: VoiceOverCategory.phrases,
  VoiceOverCue.phraseRedTriangle: VoiceOverCategory.phrases,
  VoiceOverCue.phraseTealTriangle: VoiceOverCategory.phrases,
  VoiceOverCue.phraseYellowCircle: VoiceOverCategory.phrases,
  VoiceOverCue.phraseYellowDiamond: VoiceOverCategory.phrases,
  VoiceOverCue.phraseYellowStar: VoiceOverCategory.phrases,
  VoiceOverCue.phraseYellowTriangle: VoiceOverCategory.phrases,

  // Shapes
  VoiceOverCue.shapeCircle: VoiceOverCategory.shapes,
  VoiceOverCue.shapeStar: VoiceOverCategory.shapes,
  VoiceOverCue.shapeTriangle: VoiceOverCategory.shapes,
  VoiceOverCue.shapeDiamond: VoiceOverCategory.shapes,
  VoiceOverCue.shapeHeart: VoiceOverCategory.shapes,

  // Letters
  VoiceOverCue.letterA: VoiceOverCategory.letters,
  VoiceOverCue.letterC: VoiceOverCategory.letters,
  VoiceOverCue.letterE: VoiceOverCategory.letters,
  VoiceOverCue.letterH: VoiceOverCategory.letters,
  VoiceOverCue.letterL: VoiceOverCategory.letters,
  VoiceOverCue.letterT: VoiceOverCategory.letters,
  VoiceOverCue.letterU: VoiceOverCategory.letters,
  VoiceOverCue.letterV: VoiceOverCategory.letters,

  // Numbers
  VoiceOverCue.numberOne: VoiceOverCategory.numbers,
  VoiceOverCue.numberTwo: VoiceOverCategory.numbers,
  VoiceOverCue.numberThree: VoiceOverCategory.numbers,
  VoiceOverCue.numberFour: VoiceOverCategory.numbers,
  VoiceOverCue.numberFive: VoiceOverCategory.numbers,
  VoiceOverCue.numberSeven: VoiceOverCategory.numbers,

  // Items
  VoiceOverCue.itemTinapay: VoiceOverCategory.items,
  VoiceOverCue.itemBiskwit: VoiceOverCategory.items,
  VoiceOverCue.itemKendi: VoiceOverCategory.items,
  VoiceOverCue.itemSaging: VoiceOverCategory.items,
  VoiceOverCue.itemMansanas: VoiceOverCategory.items,
  VoiceOverCue.itemTubig: VoiceOverCategory.items,
  VoiceOverCue.itemGatas: VoiceOverCategory.items,
  VoiceOverCue.itemJuice: VoiceOverCategory.items,
  VoiceOverCue.itemSoftdrink: VoiceOverCategory.items,
  VoiceOverCue.itemKape: VoiceOverCategory.items,
  VoiceOverCue.itemSabon: VoiceOverCategory.items,
  VoiceOverCue.itemSipilyo: VoiceOverCategory.items,
  VoiceOverCue.itemTisyu: VoiceOverCategory.items,
  VoiceOverCue.itemSyampu: VoiceOverCategory.items,
  VoiceOverCue.itemBola: VoiceOverCategory.items,
  VoiceOverCue.itemManika: VoiceOverCategory.items,
  VoiceOverCue.itemKotse: VoiceOverCategory.items,
  VoiceOverCue.itemTeddy: VoiceOverCategory.items,

  // Routines
  VoiceOverCue.routineMorning: VoiceOverCategory.routines,
  VoiceOverCue.routineMealtime: VoiceOverCategory.routines,
  VoiceOverCue.routineBedtime: VoiceOverCategory.routines,
  VoiceOverCue.routinePlaytime: VoiceOverCategory.routines,
  VoiceOverCue.stepWakeUp: VoiceOverCategory.routines,
  VoiceOverCue.stepBrushTeeth: VoiceOverCategory.routines,
  VoiceOverCue.stepBreakfast: VoiceOverCategory.routines,
  VoiceOverCue.stepSchool: VoiceOverCategory.routines,
  VoiceOverCue.stepWashHands: VoiceOverCategory.routines,
  VoiceOverCue.stepSitAtTable: VoiceOverCategory.routines,
  VoiceOverCue.stepEat: VoiceOverCategory.routines,
  VoiceOverCue.stepClearPlate: VoiceOverCategory.routines,
  VoiceOverCue.stepBath: VoiceOverCategory.routines,
  VoiceOverCue.stepPajamas: VoiceOverCategory.routines,
  VoiceOverCue.stepSleep: VoiceOverCategory.routines,
  VoiceOverCue.stepGetToy: VoiceOverCategory.routines,
  VoiceOverCue.stepPlay: VoiceOverCategory.routines,
  VoiceOverCue.stepPutAway: VoiceOverCategory.routines,
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
  VoiceOverCue.giveTheDeviceToYourParent:
      'voice_over/instruction/GiveTheDeviceToYourParent.wav',
  VoiceOverCue.letsBegin: 'voice_over/instruction/LetsBegin.wav',
  VoiceOverCue.listen: 'voice_over/instruction/Listen.wav',
  VoiceOverCue.matchIt: 'voice_over/instruction/MatchIt.wav',
  VoiceOverCue.myTurnInstruction: 'voice_over/instruction/MyTurn.wav',
  VoiceOverCue.pickTheColor: 'voice_over/instruction/PickTheColor.wav',
  VoiceOverCue.pickTheShape: 'voice_over/instruction/PickTheShape.wav',
  VoiceOverCue.tapHere: 'voice_over/instruction/TapHere.wav',
  VoiceOverCue.waitForTheStar: 'voice_over/instruction/WaitForTheStar.wav',
  VoiceOverCue.tapTheStar: 'voice_over/instruction/TapTheStar.wav',
  VoiceOverCue.sayHelloBack: 'voice_over/instruction/SayHelloBack.wav',
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
  VoiceOverCue.colorGold: 'voice_over/colors/Gold.wav',
  VoiceOverCue.colorPink: 'voice_over/colors/Pink.wav',
  VoiceOverCue.colorMagenta: 'voice_over/colors/Magenta.wav',
  VoiceOverCue.colorTeal: 'voice_over/colors/Teal.wav',


  // Colour+shape phrases
  VoiceOverCue.phraseBlueCircle: 'voice_over/phrases/BlueCircle.wav',
  VoiceOverCue.phraseBlueDiamond: 'voice_over/phrases/BlueDiamond.wav',
  VoiceOverCue.phraseBlueStar: 'voice_over/phrases/BlueStar.wav',
  VoiceOverCue.phraseBlueTriangle: 'voice_over/phrases/BlueTriangle.wav',
  VoiceOverCue.phraseGoldStar: 'voice_over/phrases/GoldStar.wav',
  VoiceOverCue.phraseGreenCircle: 'voice_over/phrases/GreenCircle.wav',
  VoiceOverCue.phraseGreenDiamond: 'voice_over/phrases/GreenDiamond.wav',
  VoiceOverCue.phraseGreenStar: 'voice_over/phrases/GreenStar.wav',
  VoiceOverCue.phraseGreenTriangle: 'voice_over/phrases/GreenTriangle.wav',
  VoiceOverCue.phraseMagentaDiamond: 'voice_over/phrases/MagentaDiamond.wav',
  VoiceOverCue.phraseOrangeCircle: 'voice_over/phrases/OrangeCircle.wav',
  VoiceOverCue.phraseOrangeDiamond: 'voice_over/phrases/OrangeDiamond.wav',
  VoiceOverCue.phraseOrangeStar: 'voice_over/phrases/OrangeStar.wav',
  VoiceOverCue.phraseOrangeTriangle: 'voice_over/phrases/OrangeTriangle.wav',
  VoiceOverCue.phrasePinkHeart: 'voice_over/phrases/PinkHeart.wav',
  VoiceOverCue.phrasePurpleCircle: 'voice_over/phrases/PurpleCircle.wav',
  VoiceOverCue.phrasePurpleDiamond: 'voice_over/phrases/PurpleDiamond.wav',
  VoiceOverCue.phrasePurpleHeart: 'voice_over/phrases/PurpleHeart.wav',
  VoiceOverCue.phrasePurpleStar: 'voice_over/phrases/PurpleStar.wav',
  VoiceOverCue.phrasePurpleTriangle: 'voice_over/phrases/PurpleTriangle.wav',
  VoiceOverCue.phraseRedCircle: 'voice_over/phrases/RedCircle.wav',
  VoiceOverCue.phraseRedDiamond: 'voice_over/phrases/RedDiamond.wav',
  VoiceOverCue.phraseRedHeart: 'voice_over/phrases/RedHeart.wav',
  VoiceOverCue.phraseRedStar: 'voice_over/phrases/RedStar.wav',
  VoiceOverCue.phraseRedTriangle: 'voice_over/phrases/RedTriangle.wav',
  VoiceOverCue.phraseTealTriangle: 'voice_over/phrases/TealTriangle.wav',
  VoiceOverCue.phraseYellowCircle: 'voice_over/phrases/YellowCircle.wav',
  VoiceOverCue.phraseYellowDiamond: 'voice_over/phrases/YellowDiamond.wav',
  VoiceOverCue.phraseYellowStar: 'voice_over/phrases/YellowStar.wav',
  VoiceOverCue.phraseYellowTriangle: 'voice_over/phrases/YellowTriangle.wav',

  // Shapes
  VoiceOverCue.shapeCircle: 'voice_over/shapes/Circle.wav',
  VoiceOverCue.shapeStar: 'voice_over/shapes/Star.wav',
  VoiceOverCue.shapeTriangle: 'voice_over/shapes/Triangle.wav',
  VoiceOverCue.shapeDiamond: 'voice_over/shapes/Diamond.wav',
  VoiceOverCue.shapeHeart: 'voice_over/shapes/Heart.wav',

  // Letters
  VoiceOverCue.letterA: 'voice_over/letters/A.wav',
  VoiceOverCue.letterC: 'voice_over/letters/C.wav',
  VoiceOverCue.letterE: 'voice_over/letters/E.wav',
  VoiceOverCue.letterH: 'voice_over/letters/H.wav',
  VoiceOverCue.letterL: 'voice_over/letters/L.wav',
  VoiceOverCue.letterT: 'voice_over/letters/T.wav',
  VoiceOverCue.letterU: 'voice_over/letters/U.wav',
  VoiceOverCue.letterV: 'voice_over/letters/V.wav',

  // Numbers
  VoiceOverCue.numberOne: 'voice_over/numbers/One.wav',
  VoiceOverCue.numberTwo: 'voice_over/numbers/Two.wav',
  VoiceOverCue.numberThree: 'voice_over/numbers/Three.wav',
  VoiceOverCue.numberFour: 'voice_over/numbers/Four.wav',
  VoiceOverCue.numberFive: 'voice_over/numbers/Five.wav',
  VoiceOverCue.numberSeven: 'voice_over/numbers/Seven.wav',

  // Items
  VoiceOverCue.itemTinapay: 'voice_over/items/Tinapay.wav',
  VoiceOverCue.itemBiskwit: 'voice_over/items/Biskwit.wav',
  VoiceOverCue.itemKendi: 'voice_over/items/Kendi.wav',
  VoiceOverCue.itemSaging: 'voice_over/items/Saging.wav',
  VoiceOverCue.itemMansanas: 'voice_over/items/Mansanas.wav',
  VoiceOverCue.itemTubig: 'voice_over/items/Tubig.wav',
  VoiceOverCue.itemGatas: 'voice_over/items/Gatas.wav',
  VoiceOverCue.itemJuice: 'voice_over/items/Juice.wav',
  VoiceOverCue.itemSoftdrink: 'voice_over/items/Softdrink.wav',
  VoiceOverCue.itemKape: 'voice_over/items/Kape.wav',
  VoiceOverCue.itemSabon: 'voice_over/items/Sabon.wav',
  VoiceOverCue.itemSipilyo: 'voice_over/items/Sipilyo.wav',
  VoiceOverCue.itemTisyu: 'voice_over/items/Tisyu.wav',
  VoiceOverCue.itemSyampu: 'voice_over/items/Syampu.wav',
  VoiceOverCue.itemBola: 'voice_over/items/Bola.wav',
  VoiceOverCue.itemManika: 'voice_over/items/Manika.wav',
  VoiceOverCue.itemKotse: 'voice_over/items/Kotse.wav',
  VoiceOverCue.itemTeddy: 'voice_over/items/Teddy.wav',

  // Routines
  VoiceOverCue.routineMorning: 'voice_over/routines/Morning.wav',
  VoiceOverCue.routineMealtime: 'voice_over/routines/Mealtime.wav',
  VoiceOverCue.routineBedtime: 'voice_over/routines/Bedtime.wav',
  VoiceOverCue.routinePlaytime: 'voice_over/routines/Playtime.wav',
  VoiceOverCue.stepWakeUp: 'voice_over/routines/WakeUp.wav',
  VoiceOverCue.stepBrushTeeth: 'voice_over/routines/BrushTeeth.wav',
  VoiceOverCue.stepBreakfast: 'voice_over/routines/Breakfast.wav',
  VoiceOverCue.stepSchool: 'voice_over/routines/School.wav',
  VoiceOverCue.stepWashHands: 'voice_over/routines/WashHands.wav',
  VoiceOverCue.stepSitAtTable: 'voice_over/routines/SitAtTable.wav',
  VoiceOverCue.stepEat: 'voice_over/routines/Eat.wav',
  VoiceOverCue.stepClearPlate: 'voice_over/routines/ClearPlate.wav',
  VoiceOverCue.stepBath: 'voice_over/routines/Bath.wav',
  VoiceOverCue.stepPajamas: 'voice_over/routines/Pajamas.wav',
  VoiceOverCue.stepSleep: 'voice_over/routines/Sleep.wav',
  VoiceOverCue.stepGetToy: 'voice_over/routines/GetToy.wav',
  VoiceOverCue.stepPlay: 'voice_over/routines/Play.wav',
  VoiceOverCue.stepPutAway: 'voice_over/routines/PutAway.wav',
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
/// Assets are loaded from the voice pack folder named by [languageCode]:
///   `voice_over/{languageCode}/{category}/{CueName}.wav`
///
/// [languageCode] is a [VoicePack.assetFolder] (`'en_adult_woman'`,
/// `'ceb_lexianne'`, …). A bare language slug is accepted too and resolves to
/// that language's default pack — see [resolveVoiceFolder]. Alternate packs
/// fall back to their language's default pack for any cue they are missing —
/// see [fallbackVoiceFolder].
///
/// Usage:
/// ```dart
/// final voiceOver = VoiceOverService(languageCode: 'tl');
/// await voiceOver.play(VoiceOverCue.greatJob);
/// await voiceOver.playCorrectPraise(); // random from Core Praise
/// await voiceOver.setLanguage('ceb');  // switch voice pack at runtime
/// voiceOver.setEnabled(false);         // master toggle
/// ```
/// Converts the parent-facing "prompt speed" setting into a playback rate.
///
/// The setting runs 0–1 where 1 is the recording's own pace; the bottom of
/// the range stretches speech to 0.6x for children who need longer to process
/// each word. Speaking *faster* than recorded is deliberately not offered.
double voiceRateForPromptSpeed(double promptSpeed) =>
    0.6 + 0.4 * promptSpeed.clamp(0.0, 1.0);

class VoiceOverService {
  /// Asset prefix for package-based assets.
  static const String _assetPrefix = 'packages/shared_audio/assets/audio';

  /// Voice pack asset folders that can be played.
  static final List<String> supportedLanguages = [
    for (final pack in kVoicePacks) pack.assetFolder,
  ];

  /// Current voice pack asset folder for voice-over asset resolution.
  String _languageCode;

  /// Pool of players for voice-over playback.
  final List<AudioPlayer> _players = [];

  /// Index of the player that was most recently used for playback.
  int _activePlayerIndex = 0;

  /// Master toggle for voice-over playback.
  bool _enabled;

  /// Volume level for voice-over playback (0.0 – 1.0).
  double _volume;

  /// Playback rate applied to every cue, where 1.0 is the recording's own
  /// pace.
  ///
  /// Below 1.0 stretches speech without lowering its pitch, which is what a
  /// child who needs longer to process each word actually benefits from —
  /// the parent's "prompt speed" setting feeds this.
  double _speed;

  /// Random number generator for category-based random playback.
  final Random _random;

  /// Lazily built lookup: category → list of cues in that category.
  late final Map<VoiceOverCategory, List<VoiceOverCue>> _cuesByCategory;

  /// Timestamp of the last successful [play] call, used for debouncing.
  DateTime? _lastPlayTime;

  /// How many times another service has taken the floor from this one.
  /// Test-only: yielding is otherwise invisible.
  @visibleForTesting
  int yieldedCount = 0;

  /// Every service that exists and has not been disposed.
  ///
  /// A screen builds its own service, and screens outlive each other: the
  /// child-mode lobby is still mounted underneath an open game, so its service
  /// is still alive and still holds three audio players. Two services speaking
  /// at once is always wrong — there is one narrator, and a child hearing two
  /// overlapping voices cannot follow either. Instance-level stopping cannot
  /// see across that boundary, so the floor is arbitrated here.
  static final Set<VoiceOverService> _live = <VoiceOverService>{};

  /// Monotonic ticket identifying whoever most recently claimed the floor.
  ///
  /// Stopping other players is not enough on its own. Starting a cue is
  /// asynchronous — the asset is loaded and the platform player prepared, which
  /// takes 100–400 ms on Android — and during that window the player is not yet
  /// `playing`, so a service scanning for something to silence finds nothing
  /// and the pending cue starts afterwards anyway. That is the game-launch
  /// overlap exactly: the lobby says "Let's go" as the game screen says "Match
  /// it", each too early for the other to see.
  ///
  /// So the floor is a ticket, not a scan. Every claim takes the next number,
  /// and a call that no longer holds the current one abandons itself at its
  /// next await rather than reaching the speaker. Last claim wins, whatever
  /// order the platform happens to get around to.
  static int _floorTicket = 0;

  /// The ticket this service last claimed.
  int _myTicket = 0;

  /// Whether this service still holds the floor. Test-only.
  @visibleForTesting
  bool get holdsFloor => _myTicket == _floorTicket;

  /// How many cues the debounce has dropped. Test-only: the debounce is
  /// otherwise invisible, and a silently dropped cue is exactly the failure
  /// mode this guards against.
  @visibleForTesting
  int debouncedCount = 0;

  /// How many praise lines were dropped in favour of immediate feedback.
  /// Test-only: the whole point of the layer is that nothing is heard.
  @visibleForTesting
  int praiseSuppressedCount = 0;

  /// When the current immediate-feedback line claimed the floor, or null when
  /// the last claim was something else.
  DateTime? _immediateStartedAt;

  /// The floor ticket that immediate-feedback line took.
  int _immediateTicket = 0;

  /// Set by [playAnswerLabel] for the length of one synchronous claim, so
  /// [_takeFloor] can tag the ticket it is about to hand out as immediate
  /// feedback. Consumed there.
  bool _claimingImmediate = false;

  /// How long an immediate-feedback line keeps praise off the air after it
  /// starts.
  ///
  /// The same-breath case — a game naming the final answer and celebrating on
  /// the next line — is what this exists for, and there the gap is microseconds.
  /// The window only matters when playback state is unknown (a platform that
  /// never reports completion); it is long enough to cover a spoken label and
  /// short enough that a celebration fired later in the session, on its own,
  /// still gets through.
  static const _kImmediateFeedbackHold = Duration(seconds: 3);

  /// Flag to cancel an in-progress [playSequence] call.
  bool _sequenceCancelled = false;

  VoiceOverService({
    String languageCode = 'en',
    bool enabled = true,
    double volume = 1.0,
    double speed = 1.0,
    Random? random,
  })  : _languageCode = resolveVoiceFolder(languageCode),
        _enabled = enabled,
        _volume = volume.clamp(0.0, 1.0),
        _speed = speed.clamp(_kMinSpeed, _kMaxSpeed),
        _random = random ?? Random() {
    // Create the player pool.
    for (int i = 0; i < _kPoolSize; i++) {
      final player = AudioPlayer()..setAudioContext(_voiceOverAudioContext);
      player.audioCache = AudioCache(prefix: '');
      _players.add(player);
    }

    _live.add(this);

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

  /// Current voice pack asset folder for voice-over playback.
  String get languageCode => _languageCode;

  /// Current volume level (0.0 – 1.0).
  double get volume => _volume;

  /// Current playback rate (1.0 = the recording's own pace).
  double get speed => _speed;

  /// Slowest and fastest rates a cue may be played at.
  ///
  /// Below ~0.5x the recordings smear into something harder to follow than
  /// the normal pace, which defeats the point of slowing them down.
  static const double _kMinSpeed = 0.5;
  static const double _kMaxSpeed = 1.5;

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

  /// Set the pace cues are spoken at, clamped to 0.5x – 1.5x.
  ///
  /// Takes effect on the next cue rather than mid-word: changing the rate of
  /// a clip already speaking would be its own startling event.
  void setSpeed(double speed) {
    _speed = speed.clamp(_kMinSpeed, _kMaxSpeed);
  }

  /// Change the voice pack at runtime.
  ///
  /// Stops any currently playing cue and updates the pack. [languageCode] is
  /// a [VoicePack.assetFolder] or a language slug — see [resolveVoiceFolder].
  Future<void> setLanguage(String languageCode) async {
    final folder = resolveVoiceFolder(languageCode);
    if (folder != languageCode) {
      debugPrint(
          '[VoiceOverService] ⚠ Not a voice pack folder: $languageCode, '
          'using $folder');
    }
    if (_languageCode != folder) {
      await stop();
      _languageCode = folder;
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
        debouncedCount++;
        debugPrint(
            '[VoiceOverService] ⏭ Debounced (${now.difference(_lastPlayTime!).inMilliseconds}ms): ${cue.name}');
        return;
      }
      _lastPlayTime = now;
    }

    final candidates = assetPathCandidates(cue, _languageCode);
    if (candidates.isEmpty) {
      debugPrint('[VoiceOverService] ✖ No asset path for cue: ${cue.name}');
      return;
    }

    final ticket = _takeFloor();

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
      await _applySpeed(player);
      // Someone else claimed the floor while the platform was busy; drop this
      // cue rather than adding a second voice.
      if (!_holdsFloor(ticket)) return;

      debugPrint('[VoiceOverService] 🗣 Playing: ${cue.name} '
          '(pack=$_languageCode, vol=$_volume, speed=$_speed)');

      for (var i = 0; i < candidates.length; i++) {
        if (!_holdsFloor(ticket)) return;
        try {
          await _playAsset(player, candidates[i],
              awaitCompletion: awaitCompletion);
          return;
        } catch (e) {
          if (i == candidates.length - 1) rethrow;
          debugPrint('[VoiceOverService] ↩ "${cue.name}" unavailable in '
              '$_languageCode, retrying default pack: $e');
        }
      }
    } catch (e) {
      debugPrint('[VoiceOverService] ✖ Error playing "${cue.name}": $e');
    }
  }

  /// Asset paths to try for [cue], most preferred first.
  ///
  /// An alternate voice pack that is missing a cue yields a second candidate
  /// pointing at its language's default pack, so the child hears the default
  /// voice rather than silence.
  ///
  /// [_cueAssetPaths] names every cue with a `.wav` suffix; the extension
  /// actually used is whatever the target pack declares, so a `.mp3` pack and
  /// a `.wav` pack can sit side by side without the cue table caring.
  @visibleForTesting
  static List<String> assetPathCandidates(VoiceOverCue cue, String voiceFolder) {
    final paths = <String>[];
    for (final c in [cue, if (_cueFallbacks[cue] case final f?) f]) {
      final relativePath = _cueAssetPaths[c];
      if (relativePath == null) continue;
      final withoutExtension =
          relativePath.substring(0, relativePath.length - '.wav'.length);

      String pathFor(String folder) =>
          '$_assetPrefix/'
          '${withoutExtension.replaceFirst('voice_over/', 'voice_over/$folder/')}'
          '${voiceFileExtension(folder)}';

      final fallback = fallbackVoiceFolder(voiceFolder);
      paths.add(pathFor(voiceFolder));
      if (fallback != null) paths.add(pathFor(fallback));
    }
    return paths;
  }

  /// Cues that degrade to a different cue when their own audio is absent.
  ///
  /// A linking colour is only an intonation variant of the plain one. A pack
  /// that has not been regenerated since they were introduced simply falls back
  /// to its sentence-final recording: the phrase sounds less connected, which
  /// is what it sounded like before, rather than dropping the colour entirely.
  static const Map<VoiceOverCue, VoiceOverCue> _cueFallbacks = {
    // "Wait." is the shorter truth of the same moment: the child has finished
    // and a grown-up is coming. Packs generated before this line existed say
    // that instead of leaving the hand-off screen silent, which is the one
    // outcome the screen cannot afford — the child would sit there with no
    // idea what is being asked of them.
    VoiceOverCue.giveTheDeviceToYourParent: VoiceOverCue.wait,
  };

  /// Applies the current [speed] to [player] before it starts a clip.
  ///
  /// A platform that does not support rate changes must not cost the child the
  /// cue itself, so a failure here is logged and the clip plays at its
  /// recorded pace.
  Future<void> _applySpeed(AudioPlayer player) async {
    try {
      await player.setPlaybackRate(_speed);
    } catch (e) {
      debugPrint('[VoiceOverService] ⚠ Playback rate $_speed unavailable: $e');
    }
  }

  /// Plays [assetPath] on [player], optionally waiting for it to finish.
  Future<void> _playAsset(
    AudioPlayer player,
    String assetPath, {
    required bool awaitCompletion,
  }) async {
    if (!awaitCompletion) {
      await player.play(AssetSource(assetPath));
      return;
    }

    final completer = Completer<void>();
    StreamSubscription<void>? subscription;
    subscription = player.onPlayerComplete.listen((_) {
      if (!completer.isCompleted) completer.complete();
      subscription?.cancel();
    });
    try {
      await player.play(AssetSource(assetPath));
    } catch (_) {
      await subscription.cancel();
      rethrow;
    }
    await completer.future;
  }

  /// Loads [cue] onto [player] and leaves it prepared, ready for `resume()`.
  ///
  /// Returns false when no candidate path could be loaded, so the caller can
  /// skip that word instead of stalling the phrase on it.
  Future<bool> _prepare(AudioPlayer player, VoiceOverCue cue) async {
    final candidates = assetPathCandidates(cue, _languageCode);
    for (var i = 0; i < candidates.length; i++) {
      try {
        player.setReleaseMode(ReleaseMode.stop);
        await player.setVolume(_volume);
        await _applySpeed(player);
        await player.setSource(AssetSource(candidates[i]));
        return true;
      } catch (e) {
        if (i == candidates.length - 1) {
          debugPrint('[VoiceOverService] ✖ Could not prepare "${cue.name}": $e');
        }
      }
    }
    return false;
  }

  /// Plays an already-prepared [player] and waits for the clip to finish.
  ///
  /// The completion listener is attached before `resume()`, so a very short
  /// clip cannot finish in the window before anyone is listening, and it is
  /// cancelled in a `finally` so a failed resume does not leak it.
  Future<void> _playPrepared(AudioPlayer player) async {
    final completer = Completer<void>();
    final subscription = player.onPlayerComplete.listen((_) {
      if (!completer.isCompleted) completer.complete();
    });
    try {
      await player.resume();
      await completer.future;
    } finally {
      await subscription.cancel();
    }
  }

  /// Plays a sequence of cues as one phrase — "Tap the" · "Yellow" · "Star".
  ///
  /// Every clip is **loaded before the first word plays**. Preparing an audio
  /// source is a platform round trip (asset extraction, then an Android
  /// MediaPlayer prepare), and doing it lazily per word put that cost *between*
  /// the words, where it read as a long unexplained pause mid-phrase. Paying it
  /// up front costs the same total time but moves it before the phrase starts,
  /// where it is just onset latency.
  ///
  /// The pool holds [_kPoolSize] players and phrases are at most three words,
  /// so in practice the whole phrase is resident before it starts. Longer
  /// sequences fall back to preparing each remaining word on the player freed
  /// by the word that just finished.
  ///
  /// [gap] is the deliberate pause between words, on top of the ~90 ms tail and
  /// ~40 ms lead the clips themselves carry. Keep it small: the silence a child
  /// hears is the sum of all three.
  Future<void> playSequence(
    List<VoiceOverCue> cues, {
    Duration gap = Duration.zero,
  }) async {
    // Cancel any currently playing sequence or single cue, here and anywhere
    // else in the app that is speaking.
    final ticket = _takeFloor();
    await stop();
    if (!_holdsFloor(ticket)) return;
    _sequenceCancelled = false;
    if (cues.isEmpty) return;

    // One player per word, cycling through the pool.
    AudioPlayer playerFor(int i) => _players[i % _players.length];
    final ready = List<bool>.filled(cues.length, false);

    final preload = min(cues.length, _players.length);
    await Future.wait([
      for (var i = 0; i < preload; i++)
        _prepare(playerFor(i), cues[i]).then((ok) => ready[i] = ok),
    ]);

    for (var i = 0; i < cues.length; i++) {
      if (_sequenceCancelled || !_holdsFloor(ticket)) break;
      final player = playerFor(i);

      if (ready[i]) {
        _activePlayerIndex = i % _players.length;
        try {
          await _playPrepared(player);
        } catch (e) {
          debugPrint(
              '[VoiceOverService] ✖ Error playing "${cues[i].name}": $e');
        }
      }

      if (_sequenceCancelled) break;

      // This player is free again; load the word that will reuse it. Only
      // reached for sequences longer than the pool.
      final next = i + _players.length;
      if (next < cues.length) {
        ready[next] = await _prepare(playerFor(next), cues[next]);
      }

      if (i != cues.length - 1) {
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
  ///
  /// Yields to immediate feedback — see [_playPraise].
  Future<void> playCorrectPraise() =>
      _playPraise(VoiceOverCategory.corePraise);

  /// Play a random encouragement cue from [VoiceOverCategory.gentlyRetry].
  Future<void> playWrongEncouragement() =>
      playRandom(VoiceOverCategory.gentlyRetry);

  /// Play a random transition cue from [VoiceOverCategory.transition].
  ///
  /// Follows the answer's naming cue in the same synchronous block when a round
  /// ends, so like the celebration it waits its turn rather than being dropped
  /// by the debounce. See [_playRandomAfterCurrent].
  Future<void> playTransition() =>
      _playRandomAfterCurrent(VoiceOverCategory.transition);

  /// Play a random celebration cue from
  /// [VoiceOverCategory.rewardAndCelebration].
  ///
  /// Yields to immediate feedback — see [_playPraise]. When it does play it is
  /// **never dropped and never interrupts**: it is exempt from the debounce and
  /// waits for anything mid-word to finish, because a game fires it in the same
  /// synchronous breath as the round's last line rather than in response to a
  /// fresh tap.
  Future<void> playRewardCelebration() =>
      _playPraise(VoiceOverCategory.rewardAndCelebration);

  /// Play a praise line from [category], unless immediate feedback has the
  /// floor.
  ///
  /// This is the priority layer. A game names what the child just answered and
  /// then, on the next line with nothing awaited between, praises them. Both
  /// lines reaching the speaker means either two voices at once or a "Great
  /// job!" landing after the moment it belonged to, and of the two the label is
  /// the one worth keeping: it is tied to what the child is looking at and it
  /// teaches the word. So praise is dropped here rather than queued.
  ///
  /// Praise still plays whenever the answer had no recorded name — an
  /// unlabelled correct answer is met with "Well done!" instead of silence.
  Future<void> _playPraise(VoiceOverCategory category) async {
    if (!_enabled) return;
    if (isImmediateFeedbackActive) {
      praiseSuppressedCount++;
      debugPrint('[VoiceOverService] 🤫 ${category.name} yields to immediate '
          'feedback');
      return;
    }
    await _playRandomAfterCurrent(category);
  }

  /// Whether an immediate-feedback line currently owns the narrator.
  ///
  /// True while that line is still speaking, and for [_kImmediateFeedbackHold]
  /// after it starts on platforms that never report completion. False as soon
  /// as any other line takes the floor, here or in another service.
  bool get isImmediateFeedbackActive {
    final startedAt = _immediateStartedAt;
    if (startedAt == null) return false;
    if (_immediateTicket != _floorTicket) return false;
    if (isPlaying) return true;
    return DateTime.now().difference(startedAt) < _kImmediateFeedbackHold;
  }

  /// Play a random cue from [category] once anything speaking has finished,
  /// exempt from the debounce.
  ///
  /// For lines a game fires as a *consequence* of the answer it just narrated,
  /// rather than in response to a fresh tap. The debounce exists to stop a
  /// child's rapid tapping from stacking up speech; these are not taps, and
  /// dropping them loses the line entirely.
  Future<void> _playRandomAfterCurrent(VoiceOverCategory category) async {
    if (!_enabled) return;
    final cues = _cuesByCategory[category];
    if (cues == null || cues.isEmpty) return;
    final cue = cues[_random.nextInt(cues.length)];
    await _awaitCurrentSpeech();
    debugPrint('[VoiceOverService] ▶ ${category.name}: ${cue.name}');
    await play(cue, skipDebounce: true);
  }

  /// Waits for any cue that is currently speaking to finish.
  ///
  /// The timeout is a backstop, not a schedule: if a completion event is missed
  /// the caller still speaks rather than staying silent forever.
  Future<void> _awaitCurrentSpeech({
    Duration timeout = const Duration(seconds: 4),
  }) async {
    for (final player in _players) {
      if (player.state == PlayerState.playing) {
        try {
          await player.onPlayerComplete.first.timeout(timeout);
        } on TimeoutException {
          debugPrint('[VoiceOverService] ⏱ Gave up waiting for current cue');
        } catch (_) {
          // A player that errors is not going to complete; carry on.
        }
        return;
      }
    }
  }

  // ── Playback Control ────────────────────────────────────────────────

  /// Silence every *other* live service, and cancel this one's own sequence.
  ///
  /// Called immediately before this service speaks. A sequence in flight is
  /// cancelled rather than left running, because it would otherwise keep
  /// producing words underneath whatever is starting now — the pooled players
  /// mean stopping the current clip does not stop the phrase it belongs to.
  int _takeFloor() {
    _sequenceCancelled = true;
    _myTicket = ++_floorTicket;

    // Tag this claim's layer. Anything that is not immediate feedback ends the
    // feedback episode: whatever spoke last is now what the child is hearing,
    // so a praise line arriving after it is no longer competing with a label.
    if (_claimingImmediate) {
      _claimingImmediate = false;
      _immediateStartedAt = DateTime.now();
      _immediateTicket = _myTicket;
    } else {
      _immediateStartedAt = null;
    }

    for (final other in _live) {
      if (identical(other, this)) continue;
      other._sequenceCancelled = true;
      other.yieldedCount++;
      for (final player in other._players) {
        // Unconditionally, not only when `playing`: a player still preparing
        // is precisely the one that would otherwise surface later.
        player.stop(); // intentionally not awaited
      }
    }
    return _myTicket;
  }

  /// Whether [ticket] is still the current claim on the floor.
  static bool _holdsFloor(int ticket) => ticket == _floorTicket;

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
    _live.remove(this);
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
    final phraseCue = _phraseMap[_phraseKey(color, shape)];
    // "Tap the" + one recording of "purple circle" beats three separate words:
    // the phrase carries its own internal prosody, so only the seam after the
    // action word is left. See [answerLabelCues].
    if (phraseCue != null) {
      return [if (actionCue != null) actionCue, phraseCue];
    }
    return [
      if (actionCue != null) actionCue,
      if (_colorMap[color.toLowerCase()] case final cue?) cue,
      if (_shapeMap[shape.toLowerCase()] case final cue?) cue,
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
    'gold': VoiceOverCue.colorGold,
    'pink': VoiceOverCue.colorPink,
    'magenta': VoiceOverCue.colorMagenta,
    'teal': VoiceOverCue.colorTeal,
  };

  /// Colour+shape phrases recorded as a single utterance, keyed
  /// `<colour>_<shape>`. Generated from the games' palettes by
  /// `tools/voice_gen`; a pair with no entry falls back to two separate words.
  static const _phraseMap = {
    'blue_circle': VoiceOverCue.phraseBlueCircle,
    'blue_diamond': VoiceOverCue.phraseBlueDiamond,
    'blue_star': VoiceOverCue.phraseBlueStar,
    'blue_triangle': VoiceOverCue.phraseBlueTriangle,
    'gold_star': VoiceOverCue.phraseGoldStar,
    'green_circle': VoiceOverCue.phraseGreenCircle,
    'green_diamond': VoiceOverCue.phraseGreenDiamond,
    'green_star': VoiceOverCue.phraseGreenStar,
    'green_triangle': VoiceOverCue.phraseGreenTriangle,
    'magenta_diamond': VoiceOverCue.phraseMagentaDiamond,
    'orange_circle': VoiceOverCue.phraseOrangeCircle,
    'orange_diamond': VoiceOverCue.phraseOrangeDiamond,
    'orange_star': VoiceOverCue.phraseOrangeStar,
    'orange_triangle': VoiceOverCue.phraseOrangeTriangle,
    'pink_heart': VoiceOverCue.phrasePinkHeart,
    'purple_circle': VoiceOverCue.phrasePurpleCircle,
    'purple_diamond': VoiceOverCue.phrasePurpleDiamond,
    'purple_heart': VoiceOverCue.phrasePurpleHeart,
    'purple_star': VoiceOverCue.phrasePurpleStar,
    'purple_triangle': VoiceOverCue.phrasePurpleTriangle,
    'red_circle': VoiceOverCue.phraseRedCircle,
    'red_diamond': VoiceOverCue.phraseRedDiamond,
    'red_heart': VoiceOverCue.phraseRedHeart,
    'red_star': VoiceOverCue.phraseRedStar,
    'red_triangle': VoiceOverCue.phraseRedTriangle,
    'teal_triangle': VoiceOverCue.phraseTealTriangle,
    'yellow_circle': VoiceOverCue.phraseYellowCircle,
    'yellow_diamond': VoiceOverCue.phraseYellowDiamond,
    'yellow_star': VoiceOverCue.phraseYellowStar,
    'yellow_triangle': VoiceOverCue.phraseYellowTriangle,
  };

  /// Lookup key for a colour+shape phrase, or null when either is missing.
  static String? _phraseKey(String? color, String? shape) {
    if (color == null || shape == null) return null;
    return '${color.trim().toLowerCase()}_${shape.trim().toLowerCase()}';
  }

  static const _shapeMap = {
    'circle': VoiceOverCue.shapeCircle,
    'star': VoiceOverCue.shapeStar,
    'triangle': VoiceOverCue.shapeTriangle,
    'diamond': VoiceOverCue.shapeDiamond,
    'heart': VoiceOverCue.shapeHeart,
  };

  static const _letterMap = {
    'a': VoiceOverCue.letterA,
    'c': VoiceOverCue.letterC,
    'e': VoiceOverCue.letterE,
    'h': VoiceOverCue.letterH,
    'l': VoiceOverCue.letterL,
    't': VoiceOverCue.letterT,
    'u': VoiceOverCue.letterU,
    'v': VoiceOverCue.letterV,
  };

  static const _numberMap = {
    '1': VoiceOverCue.numberOne,
    '2': VoiceOverCue.numberTwo,
    '3': VoiceOverCue.numberThree,
    '4': VoiceOverCue.numberFour,
    '5': VoiceOverCue.numberFive,
    '7': VoiceOverCue.numberSeven,
  };

  static const _itemMap = {
    'tinapay': VoiceOverCue.itemTinapay,
    'biskwit': VoiceOverCue.itemBiskwit,
    'kendi': VoiceOverCue.itemKendi,
    'saging': VoiceOverCue.itemSaging,
    'mansanas': VoiceOverCue.itemMansanas,
    'tubig': VoiceOverCue.itemTubig,
    'gatas': VoiceOverCue.itemGatas,
    'juice': VoiceOverCue.itemJuice,
    'softdrink': VoiceOverCue.itemSoftdrink,
    'kape': VoiceOverCue.itemKape,
    'sabon': VoiceOverCue.itemSabon,
    'sipilyo': VoiceOverCue.itemSipilyo,
    'tisyu': VoiceOverCue.itemTisyu,
    'syampu': VoiceOverCue.itemSyampu,
    'bola': VoiceOverCue.itemBola,
    'manika': VoiceOverCue.itemManika,
    'kotse': VoiceOverCue.itemKotse,
    'teddy': VoiceOverCue.itemTeddy,
  };

  /// Ano'ng Susunod step ids → the recording that names that step.
  ///
  /// Keyed on `RoutineStep.id`, which is language-independent: the recording
  /// under it is Tagalog in a Tagalog pack and Cebuano in a Cebuano one, so the
  /// spoken label follows the child's language without the game knowing.
  static const _routineStepMap = {
    'wake': VoiceOverCue.stepWakeUp,
    'brush': VoiceOverCue.stepBrushTeeth,
    'breakfast': VoiceOverCue.stepBreakfast,
    'school': VoiceOverCue.stepSchool,
    'wash': VoiceOverCue.stepWashHands,
    'sit': VoiceOverCue.stepSitAtTable,
    'eat': VoiceOverCue.stepEat,
    'clear': VoiceOverCue.stepClearPlate,
    'bath': VoiceOverCue.stepBath,
    'pajamas': VoiceOverCue.stepPajamas,
    'sleep': VoiceOverCue.stepSleep,
    'toy': VoiceOverCue.stepGetToy,
    'play': VoiceOverCue.stepPlay,
    'away': VoiceOverCue.stepPutAway,
  };

  /// Ano'ng Susunod routine ids → the recording that names the routine.
  static const _routineTitleMap = {
    'umaga': VoiceOverCue.routineMorning,
    'kainan': VoiceOverCue.routineMealtime,
    'gabi': VoiceOverCue.routineBedtime,
    'laro': VoiceOverCue.routinePlaytime,
  };

  // ── Immediate Answer Feedback ───────────────────────────────────────

  /// Cues that name back what the child just got right, in spoken order.
  ///
  /// Colour precedes shape ("red circle"), which is the order all three
  /// languages take and the order the instruction cues are already composed in,
  /// so the confirmation echoes the prompt rather than reversing it.
  ///
  /// Returns an empty list when nothing in the answer has a recorded name —
  /// the caller then stays silent rather than substituting praise, because
  /// praise is reserved for the end-of-game reward.
  @visibleForTesting
  static List<VoiceOverCue> answerLabelCues({
    String? color,
    String? shape,
    String? letter,
    String? item,
    String? routineStep,
  }) {
    VoiceOverCue? lookup(Map<String, VoiceOverCue> table, String? value) =>
        value == null ? null : table[value.trim().toLowerCase()];

    // A routine step is a whole phrase ("Maghugas ng kamay"), never combined
    // with a colour or shape, so it answers on its own.
    if (lookup(_routineStepMap, routineStep) case final cue?) return [cue];

    // A glyph label is either a letter or a numeral; try both tables.
    final glyphCue =
        lookup(_letterMap, letter) ?? lookup(_numberMap, letter);

    // "Purple circle" is one phrase, not two statements. Played as two clips it
    // never sounds like one: an isolated word has no following context, so the
    // model renders it sentence-final and the pitch drops hard at the end --
    // measured at -39% to -69% across the colour set. Neither a trailing comma
    // nor an explicit "keep the pitch lifted" instruction changed that, because
    // the model has nothing to lift *towards*. A phrase recorded whole does
    // have it: the colour rises into the shape and only the shape falls.
    //
    // So a colour-plus-shape answer resolves to a single phrase recording when
    // one exists, and falls back to the two separate words when it does not.
    final shapeCue = lookup(_shapeMap, shape);
    final phraseCue = _phraseMap[_phraseKey(color, shape)];
    if (phraseCue != null) return [phraseCue];

    return [
      if (lookup(_itemMap, item) case final cue?) cue,
      if (lookup(_colorMap, color) case final cue?) cue,
      if (shapeCue case final cue?) cue,
      if (glyphCue case final cue?) cue,
    ];
  }

  /// Name back what the child just answered correctly — "red circle", "Gatas",
  /// "A" — as immediate feedback on a correct response.
  ///
  /// Speaks at [VoiceOverPriority.immediateFeedback], which outranks praise:
  /// any praise line a game fires alongside this one is dropped rather than
  /// stacked behind it. Labelling a success turns it into another exposure to
  /// the target vocabulary, while praise on the same trial both dilutes the
  /// reinforcer and tells the child nothing about *what* they got right.
  ///
  /// Silent when the answer has no recorded name — and it takes no floor in
  /// that case either, so the game's praise line is heard instead of nothing.
  Future<void> playAnswerLabel({
    String? color,
    String? shape,
    String? letter,
    String? item,
    String? routineStep,
  }) async {
    final cues = answerLabelCues(
      color: color,
      shape: shape,
      letter: letter,
      item: item,
      routineStep: routineStep,
    );
    if (cues.isEmpty) return;
    // Claim the immediate-feedback layer for the ticket this call is about to
    // take. Both paths reach [_takeFloor] synchronously, before the game's next
    // line runs, which is what lets praise fired in the same breath see it.
    _claimingImmediate = true;
    try {
      if (cues.length == 1) {
        await play(cues.first);
        return;
      }
      await playSequence(cues);
    } finally {
      // Only set if the debounce turned the label away before it claimed
      // anything; leaving it armed would mislabel the next line.
      _claimingImmediate = false;
    }
  }

  /// The recording that names the routine with [routineId], or null when the
  /// library has none for it.
  @visibleForTesting
  static VoiceOverCue? routineTitleCue(String routineId) =>
      _routineTitleMap[routineId.trim().toLowerCase()];

  /// Say which routine the round is about — "Umaga", "Pagkaon" — from the
  /// `Routine.id` the game is running.
  ///
  /// With [alsoAsk], the question follows in the same breath ("Umaga. What
  /// comes next?"). It is one sequence rather than two calls because the floor
  /// is last-claim-wins: two separate calls in the same moment would silence
  /// the first, and the child would hear only half the opening.
  ///
  /// Silent for an unknown id rather than substituting anything: a routine the
  /// library has no recording for should pass without a word, not with the
  /// wrong one.
  Future<void> playRoutineTitle(String routineId,
      {bool alsoAsk = false}) async {
    final cue = routineTitleCue(routineId);
    final cues = [
      if (cue != null) cue,
      if (alsoAsk) VoiceOverCue.whatComesNext,
    ];
    if (cues.isEmpty) return;
    if (cues.length == 1) {
      await play(cues.first);
      return;
    }
    await playSequence(cues);
  }
}
