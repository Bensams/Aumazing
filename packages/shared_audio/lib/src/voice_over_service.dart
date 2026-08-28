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
  emotions,   // Ano'ng Nararamdaman emotion names: "Masaya", "Takot"
  milestone,  // Whole-milestone victory lines: pre/post assessment, learning path
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

  /// "Look where your friend is looking, then tap it." — the Sabay Tayo!
  /// instruction.
  ///
  /// A dedicated line for the same reason [waitForTheStar] is one. The closest
  /// existing cues each describe a different task: `eyesHere` pulls the child's
  /// attention *to the speaker*, which is the opposite of following it away;
  /// `watchCarefully` and `findTheSame` name a watching and a matching task
  /// respectively, and a child who follows either instruction literally can
  /// answer this game wrong. Nothing in the library says *someone else is
  /// looking at something — find it*, which is the entire skill.
  lookWhereImLooking,

  /// "Look over there!" — the escalated verbal prompt in Sabay Tayo!, spoken
  /// alongside the pointing arm.
  ///
  /// Deliberately still a direction rather than an answer: it tells the child
  /// to follow the cue, not which object to tap. Never spoken as the gaze
  /// settles — a word landing inside the response window would be measured as
  /// part of the gaze-following latency, the one number this game exists for.
  lookOverThere,
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
  /// The four Kumusta! greetings, named aloud as the buddy offers each one.
  ///
  /// Kept in `instruction/` rather than a `greetings/` folder of their own.
  /// A new folder has to be declared in pubspec.yaml for all eighteen packs,
  /// and a folder that is missing there fails only on device, as silence —
  /// which is what voice_asset_bundle_test exists to catch. `instruction/` is
  /// already declared everywhere and already holds [sayHelloBack], so the
  /// failure mode simply cannot happen.
  ///
  /// These replaced four borrowed cues that named the wrong thing: fistBump
  /// played "Now you try" and thumbsUp played "Very good" — praise, spoken
  /// before the child had done anything. Naming the gesture is also what makes
  /// the bid answerable for a child who cannot yet read the hand.
  greetingWave,
  greetingHighFive,
  greetingFistBump,
  greetingThumbsUp,
  touchThePicture,
  watchCarefully,
  yourTurnInstruction,

  /// The reward overlay's "here is what to do with this" line, one per reward
  /// kind: "Pop the balloons!", "Tap the rockets!", "Pop the bubbles!",
  /// "Collect the candy!".
  ///
  /// These replace the written hint that used to sit at the top of the reward.
  /// A pre-reader could not use it, and the reward is the one screen in the app
  /// where nothing else is being measured — so the instruction is spoken and
  /// the screen is left as pure play.
  ///
  /// Whole recorded lines rather than a composed "Pop the" + noun: the verb
  /// differs per reward (rockets are tapped, candy is collected), and a single
  /// utterance keeps the phrase's intonation instead of stitching two clips.
  ///
  /// They live in Instruction because that is what they are; the category is
  /// never drawn at random outside the game_lab audio tester, so one surfacing
  /// on its own is not possible in the app.
  rewardHintBalloons,
  rewardHintFireworks,
  rewardHintBubbles,
  rewardHintCandy,

  // ── Reward & Celebration ──────────────────────────────────────────
  //
  // The end of a session, not the end of a round. Every line here is safe to
  // hear once, after the last question, and would be wrong in the middle.
  awesomeWorkToday,
  bigHighFive,
  fantastic,

  /// "Game finished!" — the neutral statement of what just happened, paired
  /// with [youFinishedIt], which celebrates the same moment.
  ///
  /// It sits here rather than in Transition because Transition is drawn at
  /// random by [VoiceOverService.playTransition] between rounds, and a child
  /// told the game is finished while it is still running is being given false
  /// information by the one voice in the app they are meant to trust.
  gameFinished,
  greatPlaying,
  hooray,
  superJob,
  youDidSoWell,
  youFinishedIt,
  youreAmazing,

  // ── Milestone (major completions) ─────────────────────────────────
  //
  // Spoken once, on the full-screen victory scene, when a child finishes a
  // *whole* milestone — the entire pre-assessment, every game on their
  // recommended learning path, or the entire post-assessment. Bigger than the
  // per-game reward lines above, and never heard mid-session. On the scene the
  // written title is deliberately not shown (it overflows and a pre-reader
  // cannot use it), so this line carries the message. Each falls back to
  // [youFinishedIt] where its own recording is not yet in a pack.
  milestonePreAssessmentComplete,
  milestoneLearningPathComplete,
  milestonePostAssessmentComplete,

  // ── Transition ────────────────────────────────────────────────────
  //
  // Drawn at random between activities, so every line has to still be true
  // whenever it happens to surface. That is the whole entry requirement.
  getReady,
  goodJobMovingOn,
  letsGo,
  letsPlayAgain,
  levelComplete,

  /// "New round!" — replaces the old `newGame`, which announced a new *game*
  /// on a transition between two rounds of the same one.
  newRound,
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
  /// A direct social reinforcer after the child shares the requested item.
  /// `thankYouForWaiting` is intentionally not reused: it praises waiting,
  /// which is a different behaviour from responding to another person's need.
  thankYouFriend,
  thankYouForWaiting,
  wait,
  watchMeFirst,
  yourTurn,

  // ── Dynamic (action) cues ──────────────────────────────────────────
  /// Opening of the composed request "Can I have the" + item name.
  /// Kept separate so every existing localized item recording can be reused.
  canIHaveThe,
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
  shapeSquare,
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

  // ── Ano'ng Nararamdaman emotion cues ────────────────────────────────
  //
  // The instruction and the five emotion names, spoken back when the child
  // finds the matching face.
  //
  // Every one of these must be read **warmly and neutrally — never acted out
  // in the emotion it names**. A sad-sounding "Malungkot" delivers the answer
  // in the tone of voice, so a child can score full marks by listening to the
  // narrator instead of looking at the face, which is precisely the skill the
  // card is there to test. It also models emotional contagion where the game
  // is trying to model labelling.
  howIsHeFeeling,
  emotionHappy,
  emotionSad,
  emotionScared,
  emotionSurprised,
  emotionAngry,

  // The narration of each situation picture — "His ice cream fell down."
  //
  // Read the same warm, neutral way as the emotion names above, and for the
  // same reason: a sentence performed in the feeling it describes hands the
  // child the answer through the tone, so the card stops testing the face.
  // These say only what happened, never how the buddy feels about it.
  sceneGift,
  sceneFinishedDrawing,
  sceneIceCreamFell,
  sceneSpilledDrink,
  sceneDogBarked,
  sceneLoudThunder,
  sceneJackInBox,
  sceneSurpriseBalloons,
  sceneTowerFell,
  scenePuzzleStuck,
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
  VoiceOverCue.lookWhereImLooking: VoiceOverCategory.instruction,
  VoiceOverCue.lookOverThere: VoiceOverCategory.instruction,
  VoiceOverCue.sayHelloBack: VoiceOverCategory.instruction,
  VoiceOverCue.greetingWave: VoiceOverCategory.instruction,
  VoiceOverCue.greetingHighFive: VoiceOverCategory.instruction,
  VoiceOverCue.greetingFistBump: VoiceOverCategory.instruction,
  VoiceOverCue.greetingThumbsUp: VoiceOverCategory.instruction,
  VoiceOverCue.touchThePicture: VoiceOverCategory.instruction,
  VoiceOverCue.watchCarefully: VoiceOverCategory.instruction,
  VoiceOverCue.yourTurnInstruction: VoiceOverCategory.instruction,
  VoiceOverCue.rewardHintBalloons: VoiceOverCategory.instruction,
  VoiceOverCue.rewardHintFireworks: VoiceOverCategory.instruction,
  VoiceOverCue.rewardHintBubbles: VoiceOverCategory.instruction,
  VoiceOverCue.rewardHintCandy: VoiceOverCategory.instruction,

  // Reward & Celebration
  VoiceOverCue.awesomeWorkToday: VoiceOverCategory.rewardAndCelebration,
  VoiceOverCue.bigHighFive: VoiceOverCategory.rewardAndCelebration,
  VoiceOverCue.fantastic: VoiceOverCategory.rewardAndCelebration,
  VoiceOverCue.gameFinished: VoiceOverCategory.rewardAndCelebration,
  VoiceOverCue.greatPlaying: VoiceOverCategory.rewardAndCelebration,
  VoiceOverCue.hooray: VoiceOverCategory.rewardAndCelebration,
  VoiceOverCue.superJob: VoiceOverCategory.rewardAndCelebration,
  VoiceOverCue.youDidSoWell: VoiceOverCategory.rewardAndCelebration,
  VoiceOverCue.youFinishedIt: VoiceOverCategory.rewardAndCelebration,
  VoiceOverCue.youreAmazing: VoiceOverCategory.rewardAndCelebration,

  // Milestone — a dedicated category so these whole-milestone lines are never
  // drawn by the random end-of-game praise picker (which only ever draws from
  // corePraise and rewardAndCelebration).
  VoiceOverCue.milestonePreAssessmentComplete: VoiceOverCategory.milestone,
  VoiceOverCue.milestoneLearningPathComplete: VoiceOverCategory.milestone,
  VoiceOverCue.milestonePostAssessmentComplete: VoiceOverCategory.milestone,

  // Transition
  VoiceOverCue.getReady: VoiceOverCategory.transition,
  VoiceOverCue.goodJobMovingOn: VoiceOverCategory.transition,
  VoiceOverCue.letsGo: VoiceOverCategory.transition,
  VoiceOverCue.letsPlayAgain: VoiceOverCategory.transition,
  VoiceOverCue.levelComplete: VoiceOverCategory.transition,
  VoiceOverCue.newRound: VoiceOverCategory.transition,
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
  VoiceOverCue.thankYouFriend: VoiceOverCategory.turnTaking,
  VoiceOverCue.thankYouForWaiting: VoiceOverCategory.turnTaking,
  VoiceOverCue.wait: VoiceOverCategory.turnTaking,
  VoiceOverCue.watchMeFirst: VoiceOverCategory.turnTaking,
  VoiceOverCue.yourTurn: VoiceOverCategory.turnTaking,

  // Dynamic
  VoiceOverCue.canIHaveThe: VoiceOverCategory.dynamic,
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
  VoiceOverCue.shapeSquare: VoiceOverCategory.shapes,
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

  // Emotions
  VoiceOverCue.howIsHeFeeling: VoiceOverCategory.emotions,
  VoiceOverCue.emotionHappy: VoiceOverCategory.emotions,
  VoiceOverCue.emotionSad: VoiceOverCategory.emotions,
  VoiceOverCue.emotionScared: VoiceOverCategory.emotions,
  VoiceOverCue.emotionSurprised: VoiceOverCategory.emotions,
  VoiceOverCue.emotionAngry: VoiceOverCategory.emotions,

  // Emotion scenes
  VoiceOverCue.sceneGift: VoiceOverCategory.emotions,
  VoiceOverCue.sceneFinishedDrawing: VoiceOverCategory.emotions,
  VoiceOverCue.sceneIceCreamFell: VoiceOverCategory.emotions,
  VoiceOverCue.sceneSpilledDrink: VoiceOverCategory.emotions,
  VoiceOverCue.sceneDogBarked: VoiceOverCategory.emotions,
  VoiceOverCue.sceneLoudThunder: VoiceOverCategory.emotions,
  VoiceOverCue.sceneJackInBox: VoiceOverCategory.emotions,
  VoiceOverCue.sceneSurpriseBalloons: VoiceOverCategory.emotions,
  VoiceOverCue.sceneTowerFell: VoiceOverCategory.emotions,
  VoiceOverCue.scenePuzzleStuck: VoiceOverCategory.emotions,
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
  VoiceOverCue.lookWhereImLooking:
      'voice_over/instruction/LookWhereImLooking.wav',
  VoiceOverCue.lookOverThere: 'voice_over/instruction/LookOverThere.wav',
  VoiceOverCue.sayHelloBack: 'voice_over/instruction/SayHelloBack.wav',
  VoiceOverCue.greetingWave: 'voice_over/instruction/GreetWave.wav',
  VoiceOverCue.greetingHighFive: 'voice_over/instruction/GreetHighFive.wav',
  VoiceOverCue.greetingFistBump: 'voice_over/instruction/GreetFistBump.wav',
  VoiceOverCue.greetingThumbsUp: 'voice_over/instruction/GreetThumbsUp.wav',
  VoiceOverCue.touchThePicture: 'voice_over/instruction/TouchThePicture.wav',
  VoiceOverCue.watchCarefully: 'voice_over/instruction/WatchCarefully.wav',
  VoiceOverCue.yourTurnInstruction: 'voice_over/instruction/YourTurn.wav',
  VoiceOverCue.rewardHintBalloons:
      'voice_over/instruction/PopTheBalloons.wav',
  VoiceOverCue.rewardHintFireworks:
      'voice_over/instruction/TapTheRockets.wav',
  VoiceOverCue.rewardHintBubbles: 'voice_over/instruction/PopTheBubbles.wav',
  VoiceOverCue.rewardHintCandy: 'voice_over/instruction/CollectTheCandy.wav',

  // Reward & Celebration
  VoiceOverCue.awesomeWorkToday:
      'voice_over/reward_and_celebration/AwesomeWorkToday.wav',
  VoiceOverCue.bigHighFive:
      'voice_over/reward_and_celebration/BigHighFive.wav',
  VoiceOverCue.fantastic: 'voice_over/reward_and_celebration/Fantastic.wav',
  VoiceOverCue.gameFinished:
      'voice_over/reward_and_celebration/GameFinished.wav',
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

  // Milestone
  VoiceOverCue.milestonePreAssessmentComplete:
      'voice_over/milestone/MilestonePreComplete.wav',
  VoiceOverCue.milestoneLearningPathComplete:
      'voice_over/milestone/MilestonePathComplete.wav',
  VoiceOverCue.milestonePostAssessmentComplete:
      'voice_over/milestone/MilestonePostComplete.wav',

  // Transition
  VoiceOverCue.getReady: 'voice_over/transition/GetReady.wav',
  VoiceOverCue.goodJobMovingOn: 'voice_over/transition/GoodJobMovingOn.wav',
  VoiceOverCue.letsGo: 'voice_over/transition/LetsGo.wav',
  VoiceOverCue.letsPlayAgain: 'voice_over/transition/LetsPlayAgain.wav',
  VoiceOverCue.levelComplete: 'voice_over/transition/LevelComplete.wav',
  VoiceOverCue.newRound: 'voice_over/transition/NewRound.wav',
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
  VoiceOverCue.thankYouFriend:
      'voice_over/turn_taking/ThankYouFriend.wav',
  VoiceOverCue.thankYouForWaiting:
      'voice_over/turn_taking/ThankYouForWaiting.wav',
  VoiceOverCue.wait: 'voice_over/turn_taking/Wait.wav',
  VoiceOverCue.watchMeFirst: 'voice_over/turn_taking/WatchMeFirst.wav',
  VoiceOverCue.yourTurn: 'voice_over/turn_taking/YourTurn.wav',

  // Dynamic
  VoiceOverCue.canIHaveThe: 'voice_over/dynamic/CanIHaveThe.wav',
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
  VoiceOverCue.shapeSquare: 'voice_over/shapes/Square.wav',
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

  // Emotions
  VoiceOverCue.howIsHeFeeling: 'voice_over/emotions/HowIsHeFeeling.wav',
  VoiceOverCue.emotionHappy: 'voice_over/emotions/Happy.wav',
  VoiceOverCue.emotionSad: 'voice_over/emotions/Sad.wav',
  VoiceOverCue.emotionScared: 'voice_over/emotions/Scared.wav',
  VoiceOverCue.emotionSurprised: 'voice_over/emotions/Surprised.wav',
  VoiceOverCue.emotionAngry: 'voice_over/emotions/Angry.wav',

  // Emotion scenes
  VoiceOverCue.sceneGift: 'voice_over/emotions/scenes/Gift.wav',
  VoiceOverCue.sceneFinishedDrawing:
      'voice_over/emotions/scenes/FinishedDrawing.wav',
  VoiceOverCue.sceneIceCreamFell: 'voice_over/emotions/scenes/IceCreamFell.wav',
  VoiceOverCue.sceneSpilledDrink: 'voice_over/emotions/scenes/SpilledDrink.wav',
  VoiceOverCue.sceneDogBarked: 'voice_over/emotions/scenes/DogBarked.wav',
  VoiceOverCue.sceneLoudThunder: 'voice_over/emotions/scenes/LoudThunder.wav',
  VoiceOverCue.sceneJackInBox: 'voice_over/emotions/scenes/JackInBox.wav',
  VoiceOverCue.sceneSurpriseBalloons:
      'voice_over/emotions/scenes/SurpriseBalloons.wav',
  VoiceOverCue.sceneTowerFell: 'voice_over/emotions/scenes/TowerFell.wav',
  VoiceOverCue.scenePuzzleStuck: 'voice_over/emotions/scenes/PuzzleStuck.wav',
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

/// Longest a caller waiting on a clip will wait for the platform to say it
/// finished.
///
/// Completion is an event, and an event can be missed — a player released
/// under memory pressure, an app resumed from the background. Anything gating
/// game flow on a clip ending has to come back even then: the cost of waiting
/// too long is a child sitting in front of a game that has stopped, which is
/// worse than a line being talked over. Comfortably longer than the longest
/// recording in the library (~2 s) even at the slowest prompt speed.
const _kClipCompletionBackstop = Duration(seconds: 6);

/// Native player calls can outlive a route transition on Android. A bounded
/// wait keeps a game from holding its input phase open forever when the plugin
/// never resolves a stop, prepare, or play request.
const _kNativeOperationBackstop = Duration(seconds: 4);

/// How long an interrupted clip takes to fade out before it is stopped.
///
/// Cutting a waveform mid-cycle steps the signal straight to zero, and that
/// discontinuity is the click a child hears whenever one line takes the floor
/// from another. Ramping the amplitude down first removes the edge.
///
/// 150 ms is short enough that the incoming line is not audibly late — it
/// starts immediately on its own player, so the two briefly cross-fade — and
/// long enough to be inaudible as a fade rather than a clip.
const _kFadeOutDuration = Duration(milliseconds: 150);

/// Volume steps in a fade-out.
///
/// 15 steps puts one every 10 ms, which is below the ~20 ms the ear resolves
/// as separate events, so the ramp is heard as smooth rather than as a
/// staircase. More steps buy nothing and cost a platform call each.
const _kFadeOutSteps = 15;

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
  bool _disposed = false;
  int _generation = 0;
  Future<void>? _disposeFuture;
  Future<void> _languageChange = Future<void>.value();

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

  /// Serialize native calls per pooled player. A stale call may still be
  /// unwinding after its Dart await is abandoned; queueing prevents a newer
  /// source/stop/resume from racing that same Android MediaPlayer instance.
  final Map<AudioPlayer, Future<void>> _playerOperations = {};

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

  /// Stops every live instance's players.
  ///
  /// Called from the app lifecycle handler when the app loses focus or goes to
  /// the background, so narration (which is contextual and per-screen) does not
  /// keep talking under backgrounded BGM. Instances are per-screen and not
  /// lifecycle-observed, so instance-level [stop] cannot reach them from the
  /// BGM pause path. Safe no-op when [_live] is empty.
  static Future<void> stopAll() async {
    for (final service in List<VoiceOverService>.from(_live)) {
      await service.stop();
    }
  }

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

  /// Cue names that actually reached the speaker, in order. Test-only: with no
  /// audio device in a unit test, this is the only deterministic witness of
  /// what a line sequence produced. Records only in debug builds: the adds
  /// sit inside `assert`s so release devices never grow this list.
  @visibleForTesting
  final List<String> spokenCues = [];

  /// When the current immediate-feedback line claimed the floor, or null when
  /// the last claim was something else.
  DateTime? _immediateStartedAt;

  /// The floor ticket that immediate-feedback line took.
  int _immediateTicket = 0;

  /// Set by [playAnswerLabel] for the length of one synchronous claim, so
  /// [_takeFloor] can tag the ticket it is about to hand out as immediate
  /// feedback. Consumed there.
  bool _claimingImmediate = false;

  /// The single pending-narration slot.
  ///
  /// A non-immediate line that arrives while immediate feedback owns the
  /// narrator — the round-transition line, the next round's instruction, a
  /// retry prompt — is not allowed to cut the label, so it parks here instead.
  /// Newest-wins: a newer line replaces whatever is parked, so two lines queued
  /// behind one label never both speak (that was the doubled voice).
  ///
  /// The slot is discarded when the service stops, is disabled, or is disposed,
  /// and when the floor moves while the label is still finishing: something
  /// newer spoke first, so this narration is stale.
  Future<void> Function()? _queuedNarration;

  /// Monotonic id for [_runQueuedNarration] ordering: a newer queued line
  /// invalidates an older one still waiting to speak.
  int _queuedNarrationId = 0;

  /// Set for the moment a queued line fires, so the very immediate-feedback
  /// hold window that parked it does not re-queue it into the same slot.
  bool _suppressNarrationGuard = false;

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

  /// Completes when the phrase [playSequence] is speaking has finished, or
  /// null when no phrase is in flight.
  ///
  /// A phrase is spread across the pool — one word per player — so "is any
  /// player playing?" goes false in the gap between two words and true again a
  /// moment later. Anything waiting for the current line to finish has to wait
  int get _token => _generation;
  bool _valid(int token) => !_disposed && token == _generation;
  bool _holdsFloorFor(int ticket, int token) => _valid(token) &&
      _myTicket == ticket && ticket == _floorTicket;

  Future<void> _enqueuePlayerOperation(
    AudioPlayer player,
    Future<void> Function() operation,
  ) {
    final previous = _playerOperations[player] ?? Future<void>.value();
    final run = previous.then<void>(
      (_) => operation(),
      onError: (_, __) => operation(),
    );
    _playerOperations[player] = run.catchError((_) {});
    return run;
  }

  void _quarantinePlayer(AudioPlayer player) {
    if (!_players.remove(player)) return;
    _playerOperations.remove(player);
    _fadeGeneration.remove(player);
    final replacement = AudioPlayer()..setAudioContext(_voiceOverAudioContext);
    replacement.audioCache = AudioCache(prefix: '');
    _players.add(replacement);
    unawaited(player.dispose().catchError((_) {}));
  }

  Future<bool> _awaitNative(
    AudioPlayer player,
    Future<void> Function() operation,
    String operationName,
    int token, {
    int? ticket,
    bool Function()? canRun,
  }) async {
    bool allowed() => _valid(token) &&
        (ticket == null || _holdsFloorFor(ticket, token)) &&
        (canRun?.call() ?? true);
    if (!allowed()) return false;
    final queued = _enqueuePlayerOperation(player, () async {
      if (!allowed()) return;
      await operation();
    });
    try {
      await queued.timeout(_kNativeOperationBackstop);
      return allowed();
    } on TimeoutException {
      _quarantinePlayer(player);
      if (allowed()) {
        debugPrint(
            '[VoiceOverService] ⏱ Timed out waiting for $operationName');
      }
      return false;
    }
  }
  /// for the *phrase*: waiting per clip returned between "purple" and "circle"
  /// and let the next line start on top of the second word.
  Completer<void>? _phrase;

  /// Publishes a phrase as in flight and returns what ends it.
  ///
  /// Visible for testing because holding a phrase open is otherwise only
  /// possible with a platform that actually plays audio, which a unit test does
  /// not have. [playSequence] goes through here too, so a test that holds one
  /// open is holding the same thing a real phrase does.
  @visibleForTesting
  Completer<void> beginPhrase() => _phrase = Completer<void>();

  /// Release whatever is waiting on the phrase in flight.
  ///
  /// Called wherever a sequence is cancelled. Its remaining words will never be
  /// spoken, and a waiter left on the completer would otherwise sit out the
  /// full backstop timeout waiting for a phrase that has already stopped.
  void _abandonPhrase() {
    final phrase = _phrase;
    _phrase = null;
    if (phrase != null && !phrase.isCompleted) phrase.complete();
  }

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
    if (_disposed) return;
    _volume = volume.clamp(0.0, 1.0);
    final token = _token;
    for (final player in _players) {
      unawaited(_awaitNative(
        player,
        () => player.setVolume(_enabled ? _volume : 0.0),
        'set volume',
        token,
      ).then<void>((_) {}, onError: (_, __) {}));
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
  Future<void> setLanguage(String languageCode) {
    final request = _languageChange.then<void>((_) async {
      final folder = resolveVoiceFolder(languageCode);
      if (folder != languageCode) {
        debugPrint(
            '[VoiceOverService] ⚠ Not a voice pack folder: $languageCode, '
            'using $folder');
      }
      if (_languageCode != folder) {
        await stop();
        if (_disposed) return;
        _languageCode = folder;
        debugPrint('[VoiceOverService] 🌐 Language changed to: $_languageCode');
      }
    });
    _languageChange = request.catchError((_) {});
    return request;
  }

  /// Enable or disable voice-over playback globally.
  ///
  /// When disabled, calls to [play] and convenience methods are no-ops.
  void setEnabled(bool enabled) {
    if (_disposed) return;
    _enabled = enabled;
    if (!enabled) {
      ++_generation;
      _sequenceCancelled = true;
      _myTicket = 0;
      _immediateStartedAt = null;
      _immediateTicket = 0;
      _abandonPhrase();
      _queuedNarration = null;
      _queuedNarrationId++;
      for (final player in List<AudioPlayer>.from(_players)) {
        _fadeGeneration[player] = (_fadeGeneration[player] ?? 0) + 1;
        unawaited(_enqueuePlayerOperation(player, () => player.stop()).catchError((_) {}));
      }
    }
  }

  // ── Playback ────────────────────────────────────────────────────────
  /// The volume a clip should play at right now.
  double get _effectiveVolume => _enabled ? _volume : 0.0;

  /// Fade generation per player, bumped every time a fade is started or a
  /// player is claimed for a new clip.
  ///
  /// A fade is a loop of awaits, so the player under it can be stopped,
  /// reclaimed and speaking a different line before the loop's next step. The
  /// generation is what that loop checks to notice it is no longer the current
  /// owner and stop touching the player — without it, a fade would ramp the
  /// *next* line down to silence and stop it mid-word.
  final Map<AudioPlayer, int> _fadeGeneration = {};

  Future<bool> _claimPlayer(
    AudioPlayer player, {
    required int token,
    required int ticket,
  }) async {
    if (!_holdsFloorFor(ticket, token)) return false;
    final generation = (_fadeGeneration[player] ?? 0) + 1;
    _fadeGeneration[player] = generation;
    try {
      if (!await _awaitNative(
        player,
        () => player.setVolume(_effectiveVolume),
        'set volume',
        token,
        ticket: ticket,
        canRun: () => _fadeGeneration[player] == generation,
      )) {
        return false;
      }
    } catch (e) {
      if (_holdsFloorFor(ticket, token)) {
        debugPrint('[VoiceOverService] ⚠ Could not set player volume: $e');
      }
      return false;
    }
    return _holdsFloorFor(ticket, token) &&
        _fadeGeneration[player] == generation;
  }

  /// The volume levels of a fade starting from [from], in order.
  ///
  /// Linear in amplitude, which over 150 ms is indistinguishable from any
  /// fancier curve and is one multiplication. The ramp stops one step short of
  /// zero because the stop that follows it is what reaches silence.
  @visibleForTesting
  static List<double> fadeRamp(double from) => [
        for (var remaining = _kFadeOutSteps - 1; remaining > 0; remaining--)
          from * remaining / _kFadeOutSteps,
      ];
  /// Ramp [player] down over [_kFadeOutDuration], then stop it.
  ///
  /// Deliberately not awaited by callers: the incoming line starts on another
  /// player while this one is released in the background.
  Future<void> _fadeOutAndStop(AudioPlayer player) async {
    if (_disposed) return;
    final token = _token;
    final generation = (_fadeGeneration[player] ?? 0) + 1;
    _fadeGeneration[player] = generation;
    bool current() => _valid(token) && _fadeGeneration[player] == generation;

    try {
      if (player.state != PlayerState.playing) {
        await _awaitNative(
          player,
          () => player.stop(),
          'stop',
          token,
          canRun: current,
        );
        return;
      }
      final step = _kFadeOutDuration ~/ _kFadeOutSteps;
      final from = _effectiveVolume;
      for (final level in fadeRamp(from)) {
        await Future<void>.delayed(step);
        if (!current()) return;
        if (!await _awaitNative(
          player,
          () => player.setVolume(level),
          'fade volume',
          token,
          canRun: current,
        )) {
          await _enqueuePlayerOperation(player, () => player.stop()).catchError((_) {});
          return;
        }
      }
      if (!current()) return;
      if (!await _awaitNative(
        player,
        () => player.stop(),
        'stop',
        token,
        canRun: current,
      )) {
        await _enqueuePlayerOperation(player, () => player.stop()).catchError((_) {});
        return;
      }
      if (!current()) return;
      await _awaitNative(
        player,
        () => player.setVolume(_effectiveVolume),
        'restore volume',
        token,
        canRun: current,
      );
    } catch (e) {
      if (!current()) return;
      debugPrint('[VoiceOverService] ⚠ Fade-out failed, stopping outright: $e');
      try {
        await _awaitNative(
          player,
          () => player.stop(),
          'stop after fade failure',
          token,
          canRun: current,
        );
      } catch (_) {}
    }
  }

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
    final token = _token;
    if (!_valid(token) || !_enabled) return;
    // Immediate feedback owns the narrator: the child is hearing what they
    // just got right. Do not cut it — park this line as the pending narration
    // and let it speak when the label finishes, if it is still relevant then.
    // Lines called to take the floor ([skipDebounce]), the label itself
    // ([_claimingImmediate]) and the queued line firing are exempt from the
    // park.
    if (!skipDebounce &&
        !_claimingImmediate &&
        !_suppressNarrationGuard &&
        isImmediateFeedbackActive) {
      return _enqueueNarration(
        () => play(cue,
            awaitCompletion: awaitCompletion, skipDebounce: true),
      );
    }
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
    if (candidates.isEmpty || !_valid(token)) return;
    final ticket = _takeFloor();
    if (!_holdsFloorFor(ticket, token)) return;
    try {
      for (final player in _players) {
        if (!_holdsFloorFor(ticket, token)) return;
        if (player.state == PlayerState.playing) _fadeOutAndStop(player);
      }
      final player = _getAvailablePlayer();
      // Dart state can still be `stopped` while the native player is preparing.
      // Queue an unconditional stop barrier before reusing the player so a
      // stale native play cannot overlap the incoming cue.
      if (!await _awaitNative(
        player,
        () => player.stop(),
        'reuse stop',
        token,
        ticket: ticket,
      )) {
        return;
      }
      if (!await _awaitNative(
        player,
        () => player.setReleaseMode(ReleaseMode.stop),
        'set release mode',
        token,
        ticket: ticket,
      )) {
        return;
      }
      if (!await _claimPlayer(player, token: token, ticket: ticket)) return;
      if (!await _applySpeed(player, token: token, ticket: ticket)) return;
      debugPrint(
          '[VoiceOverService] 🗣 Playing: ${cue.name} (pack=$_languageCode, vol=$_volume, speed=$_speed)');
      assert(() {
        spokenCues.add(cue.name);
        return true;
      }());
      for (var i = 0; i < candidates.length; i++) {
        if (!_holdsFloorFor(ticket, token)) return;
        try {
          await _playAsset(
            player,
            candidates[i],
            awaitCompletion: awaitCompletion,
            token: token,
            ticket: ticket,
          );
          if (!_holdsFloorFor(ticket, token)) return;
          return;
        } catch (e) {
          if (i == candidates.length - 1) rethrow;
          debugPrint(
              '[VoiceOverService] ↩ "${cue.name}" unavailable in $_languageCode, retrying default pack: $e');
        }
      }
    } catch (e) {
      if (_holdsFloorFor(ticket, token)) {
        debugPrint('[VoiceOverService] ✖ Error playing "${cue.name}": $e');
      }
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

    // A pack generated before the milestone lines existed says "You finished
    // it!" instead of leaving the victory scene silent — the same celebratory
    // truth, just less specific about which whole thing was finished.
    VoiceOverCue.milestonePreAssessmentComplete: VoiceOverCue.youFinishedIt,
    VoiceOverCue.milestoneLearningPathComplete: VoiceOverCue.youFinishedIt,
    VoiceOverCue.milestonePostAssessmentComplete: VoiceOverCue.youFinishedIt,

    // The reward hints replaced a written line, so a pack without them yet must
    // not leave the reward with no instruction at all. "Tap here." is the one
    // thing that is true of all four rewards — every one of them is played by
    // touching what is on screen — and it is already in every pack.
    VoiceOverCue.rewardHintBalloons: VoiceOverCue.tapHere,
    VoiceOverCue.rewardHintFireworks: VoiceOverCue.tapHere,
    VoiceOverCue.rewardHintBubbles: VoiceOverCue.tapHere,
    VoiceOverCue.rewardHintCandy: VoiceOverCue.tapHere,
  };

  /// Applies the current [speed] to [player] before it starts a clip.
  ///
  /// A platform that does not support rate changes must not cost the child the
  /// cue itself, so a failure here is logged and the clip plays at its
  /// recorded pace.
  Future<bool> _applySpeed(
    AudioPlayer player, {
    required int token,
    required int ticket,
  }) async {
    if (!_holdsFloorFor(ticket, token)) return false;
    try {
      final applied = await _awaitNative(
        player,
        () => player.setPlaybackRate(_speed),
        'playback rate',
        token,
        ticket: ticket,
      );
      // A timeout leaves an unresolved native operation in the queue. Do not
      // start another operation on this player behind it.
      return applied;
    } catch (e) {
      if (_holdsFloorFor(ticket, token)) {
        debugPrint(
            '[VoiceOverService] ⚠ Playback rate $_speed unavailable: $e');
      }
      return _holdsFloorFor(ticket, token);
    }
  }

  /// Plays [assetPath] on [player], optionally waiting for it to finish.
  Future<void> _playAsset(
    AudioPlayer player,
    String assetPath, {
    required bool awaitCompletion,
    required int token,
    required int ticket,
  }) async {
    if (!_holdsFloorFor(ticket, token)) return;
    if (!awaitCompletion) {
      await _awaitNative(
        player,
        () => player.play(AssetSource(assetPath)),
        'play',
        token,
        ticket: ticket,
      );
      return;
    }

    final completer = Completer<void>();
    final subscription = player.onPlayerComplete.listen((_) {
      if (!completer.isCompleted) completer.complete();
    });
    try {
      final started = await _awaitNative(
        player,
        () => player.play(AssetSource(assetPath)),
        'play',
        token,
        ticket: ticket,
      );
      if (!started || !_holdsFloorFor(ticket, token)) return;
      await completer.future.timeout(
        _kClipCompletionBackstop,
        onTimeout: () => debugPrint(
            '[VoiceOverService] ⏱ No completion reported for $assetPath'),
      );
    } finally {
      await subscription.cancel();
    }
  }

  Future<bool> _prepare(
    AudioPlayer player,
    VoiceOverCue cue, {
    required int token,
    required int ticket,
  }) async {
    if (!_holdsFloorFor(ticket, token)) return false;
    final candidates = assetPathCandidates(cue, _languageCode);
    for (var i = 0; i < candidates.length; i++) {
      try {
        if (!_holdsFloorFor(ticket, token)) return false;
        if (!await _awaitNative(
          player,
          () => player.setReleaseMode(ReleaseMode.stop),
          'set release mode',
          token,
          ticket: ticket,
        )) {
          return false;
        }
        if (!await _claimPlayer(player, token: token, ticket: ticket)) {
          return false;
        }
        if (!await _applySpeed(player, token: token, ticket: ticket)) {
          return false;
        }
        if (!await _awaitNative(
          player,
          () => player.setSource(AssetSource(candidates[i])),
          'prepare source',
          token,
          ticket: ticket,
        )) {
          return false;
        }
        return _holdsFloorFor(ticket, token);
      } catch (e) {
        if (i == candidates.length - 1 && _holdsFloorFor(ticket, token)) {
          debugPrint(
              '[VoiceOverService] ✖ Could not prepare "${cue.name}": $e');
        }
      }
    }
    return false;
  }

  Future<bool> _playPrepared(
    AudioPlayer player, {
    required int token,
    required int ticket,
  }) async {
    if (!_holdsFloorFor(ticket, token)) return false;
    final completer = Completer<void>();
    final subscription = player.onPlayerComplete.listen((_) {
      if (!completer.isCompleted) completer.complete();
    });
    try {
      final started = await _awaitNative(
        player,
        () => player.resume(),
        'resume',
        token,
        ticket: ticket,
      );
      if (!started || !_holdsFloorFor(ticket, token)) return false;
      await completer.future.timeout(
        _kClipCompletionBackstop,
        onTimeout: () => debugPrint(
            '[VoiceOverService] ⏱ No completion reported for word'),
      );
      return _holdsFloorFor(ticket, token);
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
  Future<bool> _stopPlayersForSequence(int token, int ticket) async {
    if (!_holdsFloorFor(ticket, token)) return false;
    _sequenceCancelled = true;
    _abandonPhrase();
    for (final player in List<AudioPlayer>.from(_players)) {
      if (!_holdsFloorFor(ticket, token)) return false;
      _fadeGeneration[player] = (_fadeGeneration[player] ?? 0) + 1;
      if (!await _awaitNative(
        player,
        () => player.stop(),
        'stop before sequence',
        token,
        ticket: ticket,
      )) {
        return false;
      }
    }
    return _holdsFloorFor(ticket, token);
  }

  Future<void> playSequence(
    List<VoiceOverCue> cues, {
    Duration gap = Duration.zero,
  }) async {
    if (!_enabled || _disposed) return;
    final token = _token;
    if (!_valid(token)) return;
    // Same arbitration as [play]: a sequence arriving while immediate
    // feedback owns the narrator parks behind it instead of cutting it.
    if (!_claimingImmediate &&
        !_suppressNarrationGuard &&
        isImmediateFeedbackActive) {
      return _enqueueNarration(() => playSequence(cues, gap: gap));
    }
    final ticket = _takeFloor();
    if (!_holdsFloorFor(ticket, token)) return;
    if (!await _stopPlayersForSequence(token, ticket)) return;
    if (!_holdsFloorFor(ticket, token)) return;
    _sequenceCancelled = false;
    if (cues.isEmpty || _players.isEmpty) return;
    final phrase = beginPhrase();
    try {
      AudioPlayer playerFor(int i) => _players[i % _players.length];
      final ready = List<bool>.filled(cues.length, false);
      final preload = min(cues.length, _players.length);
      await Future.wait([
        for (var i = 0; i < preload; i++)
          _prepare(
            playerFor(i),
            cues[i],
            token: token,
            ticket: ticket,
          ).then((ok) => ready[i] = ok),
      ]);
      var resumeFrom = -1;
      for (var i = 0; i < cues.length; i++) {
        if (!_valid(token) || _sequenceCancelled) break;
        if (!_holdsFloorFor(ticket, token)) {
          // The floor was claimed before cue i could speak; everything from i
          // on is unspoken.
          resumeFrom = i;
          break;
        }
        final player = playerFor(i);
        if (ready[i]) {
          _activePlayerIndex = i % _players.length;
          assert(() {
            spokenCues.add(cues[i].name);
            return true;
          }());
          try {
            await _playPrepared(
              player,
              token: token,
              ticket: ticket,
            );
          } catch (e) {
            if (_valid(token)) debugPrint('[VoiceOverService] ✖ Error playing "${cues[i].name}": $e');
          }
        }
        if (!_valid(token) || _sequenceCancelled) break;
        final next = i + _players.length;
        if (next < cues.length) {
          ready[next] = await _prepare(
            playerFor(next),
            cues[next],
            token: token,
            ticket: ticket,
          );
          if (!_holdsFloorFor(ticket, token)) {
            resumeFrom = i + 1;
            break;
          }
        }
        if (i != cues.length - 1) {
          await Future<void>.delayed(gap);
          if (!_holdsFloorFor(ticket, token)) {
            resumeFrom = i + 1;
            break;
          }
        }
      }
      if (resumeFrom >= 0) {
        return _resurrectSequenceTail(cues, resumeFrom, gap: gap,
            token: token);
      }
    } finally {
      if (identical(_phrase, phrase)) _phrase = null;
      if (!phrase.isCompleted) phrase.complete();
    }
  }

  /// Re-queues the unspoken tail of an interrupted [playSequence] behind the
  /// immediate-feedback line that grabbed the floor mid-sequence (AUM-316).
  ///
  /// In Anong Nararamdaman the sequence tail is the "How is he feeling?"
  /// instruction that follows every scene caption; a fast tap's correct/wrong
  /// label used to swallow it. The tail parks in the single narration slot —
  /// it waits the feedback episode out and speaks after it, unless a newer
  /// line supersedes it: the usual last-wins rule from the instant of the
  /// re-queue. A floor claim by a full narration is NOT healed — that line is
  /// the child's current context and the tail is stale by design, exactly
  /// like a parked sequence displaced in the slot.
  ///
  /// The guard is CLAIM-based, not [isImmediateFeedbackActive]: the windowed
  /// getter also requires the label to still be speaking or inside its
  /// three-second hold, but the interrupted sequence only notices the floor
  /// change when its player await settles — a label's fade-out never
  /// completes the caption's player, so the clip-completion backstop does,
  /// typically past the hold. What matters is that the floor was claimed AS
  /// feedback and no newer claim superseded it; the slot then yields behind
  /// whatever episode is live.
  Future<void> _resurrectSequenceTail(
    List<VoiceOverCue> cues,
    int from, {
    required Duration gap,
    required int token,
  }) {
    final feedbackOwnsFloor = _immediateStartedAt != null &&
        _immediateTicket == _floorTicket &&
        _valid(token);
    if (from >= cues.length ||
        !_enabled ||
        _disposed ||
        _sequenceCancelled ||
        !feedbackOwnsFloor) {
      return Future<void>.value();
    }
    return _enqueueNarration(() => playSequence(cues.sublist(from), gap: gap));
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
  /// Yields to immediate feedback — see [_playPraise] — and never interrupts:
  /// when it plays it is exempt from the debounce and waits for anything
  /// mid-word to finish, because a game fires it in the same synchronous breath
  /// as the round's last line rather than in response to a fresh tap. A line
  /// is still dropped when immediate feedback owns the floor, and a line that
  /// got past that yield parks as pending narration, so it can be discarded as
  /// stale before it speaks if the floor moves to something newer.
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

  /// Park [speak] as the pending narration, or let it run when nothing has to
  /// finish first.
  ///
  /// One slot: a newer line displaces the older, so a child answering rapidly
  /// or a round advancing past one transition can never stack two lines.
  ///
  /// Returns the settlement of the parked line: it completes when the line has
  /// either spoken or been discarded as stale, so a caller awaiting its
  /// playback is never left believing a line is playing that will never be
  /// heard.
  Future<void> _enqueueNarration(Future<void> Function() speak) {
    final floor = _floorTicket;
    final id = ++_queuedNarrationId;
    _queuedNarration = speak;
    return _runQueuedNarration(id, floor);
  }

  /// Wait for the current line to finish, then decide whether the queued
  /// narration is still worth speaking.
  ///
  /// Discard, do not play, when the service stopped/disabled/disposed, when a
  /// newer narration replaced this one, or when the floor moved — anything new
  /// that spoke while the label was finishing is now the child's current
  /// context, and this line would arrive late twice over.
  Future<void> _runQueuedNarration(int id, int floor) async {
    await _awaitCurrentSpeech();
    if (!_enabled) return;
    if (id != _queuedNarrationId) return;
    // The label can own the episode while no player reports playing: a
    // single-cue label has no phrase, and its native preparation window
    // reports nothing. Waiting only on speech state would cut the label in
    // precisely that window — the overlap this queue exists to prevent. Wait
    // the immediate-feedback episode out instead: the hold covers
    // preparation and the last word's tail, and a line outliving the hold
    // (slow prompt speed, slow device) is waited on directly once its last
    // word is audible.
    if (isImmediateFeedbackActive) {
      if (isPlaying) await _awaitCurrentSpeech();
      final startedAt = _immediateStartedAt;
      if (startedAt != null) {
        final remaining =
            _kImmediateFeedbackHold - DateTime.now().difference(startedAt);
        if (remaining > Duration.zero) {
          await Future.delayed(remaining);
        }
      }
      if (isPlaying) await _awaitCurrentSpeech();
    }
    if (!_enabled) return;
    if (id != _queuedNarrationId) return;
    if (floor != _floorTicket) return;
    final speak = _queuedNarration;
    _queuedNarration = null;
    if (speak == null) return;
    // The bypass covers only the synchronous re-entry into [speak]: the
    // queued line must not re-park itself into the slot it just vacated. It
    // must not outlive that re-entry either - a queued line takes the floor
    // and can sit in native preparation or clip playback for a while, and a
    // bypass held across all of it would let any genuinely new line skip the
    // immediate-feedback guard and cut a fresh label.
    _suppressNarrationGuard = true;
    final Future<void> spoke;
    try {
      spoke = speak();
    } finally {
      _suppressNarrationGuard = false;
    }
    await spoke;
  }

  /// Play a random cue from [category] once anything speaking has finished,
  ///
  /// For lines a game fires as a *consequence* of the answer it just narrated,
  /// rather than in response to a fresh tap. The debounce exists to stop a
  /// child's rapid tapping from stacking up speech; these are not taps, and
  /// dropping them loses the line entirely. They must not cut immediate
  /// feedback either: a line parked behind the label speaks after it, and only
  /// if nothing newer superseded it while the label was still speaking.
  Future<void> _playRandomAfterCurrent(VoiceOverCategory category) async {
    if (!_enabled) return;
    final cues = _cuesByCategory[category];
    if (cues == null || cues.isEmpty) return;
    final cue = cues[_random.nextInt(cues.length)];
    if (isImmediateFeedbackActive) {
      return _enqueueNarration(() => play(cue, skipDebounce: true));
    }
    final floor = _floorTicket;
    await _awaitCurrentSpeech();
    // Anything that took the floor while we waited is now what the child is
    // hearing; this line would either cut it or arrive after the moment it
    // belonged to, so it is stale and is discarded.
    if (!_enabled || floor != _floorTicket) return;
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
    // A phrase in flight comes first. Its words are on different players, so
    // the per-player wait below would return in the silence between two of
    // them — which is precisely where a second voice used to come in. The
    // backstop scales with the pool because a phrase is that many words long.
    //
    // A phrase completes when its last word *starts*, so the players are
    // still checked afterwards: that last word is audible and the caller
    // must not begin on top of it.
    final phrase = _phrase;
    if (phrase != null) {
      try {
        await phrase.future.timeout(timeout * _kPoolSize);
      } on TimeoutException {
        debugPrint('[VoiceOverService] ⏱ Gave up waiting for current phrase');
      }
    }
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
    if (_disposed) return _myTicket;
    // AUM-316: an immediate-feedback label does not CANCEL a running
    // sequence — it takes the floor, and the sequence's own floor checks
    // notice and re-queue the unspoken tail behind the label. Cancelling
    // here would drop that tail (the "How is he feeling?" question) as if a
    // newer narration had superseded it, which is not what a tap label is.
    // A full narration claim (label not claiming) supersedes: the sequence
    // is cancelled outright, as before.
    if (!_claimingImmediate) _sequenceCancelled = true;
    _abandonPhrase();
    _myTicket = ++_floorTicket;
    if (_claimingImmediate) {
      _claimingImmediate = false;
      _immediateStartedAt = DateTime.now();
      _immediateTicket = _myTicket;
    } else {
      _immediateStartedAt = null;
    }
    for (final other in List<VoiceOverService>.from(_live)) {
      if (identical(other, this) || other._disposed) continue;
      other._sequenceCancelled = true;
      other._abandonPhrase();
      other.yieldedCount++;
      for (final player in other._players) {
        other._fadeOutAndStop(player);
      }
    }
    return _myTicket;
  }


  Future<void> stop() async {
    if (_disposed) return;
    _generation++;
    _sequenceCancelled = true;
    _abandonPhrase();
    _myTicket = 0;
    _immediateStartedAt = null;
    _immediateTicket = 0;
    // A stashed narration belongs to the moment that just ended.
    _queuedNarration = null;
    _queuedNarrationId++;
    for (final player in List<AudioPlayer>.from(_players)) {
      _fadeGeneration[player] = (_fadeGeneration[player] ?? 0) + 1;
      try {
        await _enqueuePlayerOperation(player, () => player.stop());
      } catch (_) {
        // A failed stop must not prevent the remaining players from stopping.
      }
    }
  }

  Future<void> dispose() {
    if (_disposeFuture != null) return _disposeFuture!;
    _disposed = true;
    _generation++;
    _myTicket = 0;
    _immediateStartedAt = null;
    _immediateTicket = 0;
    _live.remove(this);
    _sequenceCancelled = true;
    _abandonPhrase();
    _queuedNarration = null;
    _queuedNarrationId++;
    final future = () async {
      for (final player in List<AudioPlayer>.from(_players)) {
        _fadeGeneration[player] = (_fadeGeneration[player] ?? 0) + 1;
        try {
          await _enqueuePlayerOperation(player, () => player.dispose());
        } catch (_) {
          // Continue disposing the rest of the pool.
        }
      }
      _fadeGeneration.clear();
      _players.clear();
    }();
    _disposeFuture = future;
    return future;
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
    'square': VoiceOverCue.shapeSquare,
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

  /// Ano'ng Nararamdaman emotion slugs → the recording that names the emotion.
  ///
  /// Keyed on `Emotion.slug`, which is language-independent, exactly as
  /// [_routineStepMap] is: the recording under `'sad'` is Tagalog in a Tagalog
  /// pack, so the game never has to know the translation.
  static const _emotionMap = {
    'happy': VoiceOverCue.emotionHappy,
    'sad': VoiceOverCue.emotionSad,
    'scared': VoiceOverCue.emotionScared,
    'surprised': VoiceOverCue.emotionSurprised,
    'angry': VoiceOverCue.emotionAngry,
  };

  /// Ano'ng Nararamdaman scene ids → the recording that narrates the picture.
  ///
  /// Keyed on `EmotionScene.id`, language-independent for the same reason
  /// [_emotionMap] is: the recording under `'ice_cream_fell'` is Tagalog in a
  /// Tagalog pack, so the game never has to know the translation.
  static const _sceneMap = {
    'gift': VoiceOverCue.sceneGift,
    'finished_drawing': VoiceOverCue.sceneFinishedDrawing,
    'ice_cream_fell': VoiceOverCue.sceneIceCreamFell,
    'spilled_drink': VoiceOverCue.sceneSpilledDrink,
    'dog_barked': VoiceOverCue.sceneDogBarked,
    'loud_thunder': VoiceOverCue.sceneLoudThunder,
    'jack_in_box': VoiceOverCue.sceneJackInBox,
    'surprise_balloons': VoiceOverCue.sceneSurpriseBalloons,
    'tower_fell': VoiceOverCue.sceneTowerFell,
    'puzzle_stuck': VoiceOverCue.scenePuzzleStuck,
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
    String? emotion,
  }) {
    VoiceOverCue? lookup(Map<String, VoiceOverCue> table, String? value) =>
        value == null ? null : table[value.trim().toLowerCase()];

    // A routine step is a whole phrase ("Maghugas ng kamay"), never combined
    // with a colour or shape, so it answers on its own.
    if (lookup(_routineStepMap, routineStep) case final cue?) return [cue];

    // An emotion name answers on its own for the same reason.
    if (lookup(_emotionMap, emotion) case final cue?) return [cue];

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
    String? emotion,
  }) async {
    final cues = answerLabelCues(
      color: color,
      shape: shape,
      letter: letter,
      item: item,
      routineStep: routineStep,
      emotion: emotion,
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

  /// Ask Ano'ng Nararamdaman's question: "How is he feeling?"
  ///
  /// Its own method rather than a bare [play] call so the game does not have to
  /// import the cue set, matching how [playRoutineTitle] serves Ano'ng Susunod.
  Future<void> playEmotionQuestion() => play(VoiceOverCue.howIsHeFeeling);

  /// The recording that narrates the situation with [sceneId], or null when the
  /// library has none for it.
  @visibleForTesting
  static VoiceOverCue? sceneCue(String sceneId) =>
      _sceneMap[sceneId.trim().toLowerCase()];

  /// Narrate the situation on screen — "His ice cream fell down." — from the
  /// `EmotionScene.id` the game is showing.
  ///
  /// This is the round's opening line, and it is what makes the question
  /// answerable for a child who cannot yet read the caption printed under the
  /// picture: the event arrives as speech, and only the feeling is left to be
  /// read off the face.
  ///
  /// With [alsoAsk], the question follows in the same breath ("His ice cream
  /// fell down. How is he feeling?"). One sequence rather than two calls, for
  /// the reason [playRoutineTitle] documents: the floor is last-claim-wins, so
  /// two calls in the same moment would drop the narration and leave the child
  /// with a question about a picture nobody described.
  ///
  /// Silent for an unknown id rather than substituting anything — a scene with
  /// no recording should pass without a word, not with the wrong one.
  Future<void> playSceneCaption(String sceneId, {bool alsoAsk = false}) async {
    final cue = sceneCue(sceneId);
    final cues = [
      if (cue != null) cue,
      if (alsoAsk) VoiceOverCue.howIsHeFeeling,
    ];
    if (cues.isEmpty) return;
    if (cues.length == 1) {
      await play(cues.first);
      return;
    }
    await playSequence(cues);
  }
  /// Speak a friend's request for [item] — "Can I have the … bola?" — as one
  /// utterance, from the item's stable Filipino name.
  ///
  /// Composed here rather than in the game layer for the same reason
  /// [playRoutineTitle] is: the game knows *what* was asked for, the audio
  /// layer knows how to say it, and only this side knows the phrase has to go
  /// out as a single [playSequence]. Two separate calls would lose the first
  /// half to the last-claim-wins floor, and the child would hear a dangling
  /// "can I have the" with no object.
  ///
  /// Silent for an item the library cannot name. "Can I have the" alone is not
  /// a shorter version of the request, it is an unfinished sentence — and this
  /// is also what keeps [answerLabelCues] inside the audio layer, where its
  /// `@visibleForTesting` contract says it belongs.
  Future<void> playItemRequest(String? item) async {
    final itemCues = answerLabelCues(item: item);
    if (itemCues.isEmpty) return;
    await playSequence([VoiceOverCue.canIHaveThe, ...itemCues]);
  }
}
