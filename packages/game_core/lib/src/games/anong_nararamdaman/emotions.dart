import 'package:shared_ui/shared_ui.dart' show GameLanguage;

/// The five emotions this game asks a child to recognise.
///
/// Deliberately small and deliberately unambiguous. The states a two-to-six
/// year old can name reliably are the basic ones, and every subtle addition
/// (proud, embarrassed, confused, jealous) costs twice: the target face becomes
/// arguable, and — worse — it enters the distractor pool, so a *different*
/// trial's answer stops being defensible too. A child who taps "sad" for a
/// scared face has told us something clinically real; a child who taps "sad"
/// for an "embarrassed" face has told us only that the card was unfair.
///
/// Subtle states are a later target. When they arrive they should arrive as
/// their own tier with their own distractor rules, not as five more cards here.
enum Emotion {
  happy('happy', FaceArt.happy, 'Happy', 'Masaya', 'Malipayon'),
  sad('sad', FaceArt.sad, 'Sad', 'Malungkot', 'Masulub-on'),
  scared('scared', FaceArt.scared, 'Scared', 'Takot', 'Nahadlok'),
  surprised('surprised', FaceArt.surprised, 'Surprised', 'Gulat', 'Natingala'),
  angry('angry', FaceArt.angry, 'Angry', 'Galit', 'Nasuko');

  const Emotion(this.slug, this.face, this.en, this.tl, this.ceb);

  /// Stable identifier used in analytics and as the voice-over lookup key.
  /// Language-independent on purpose: the recording under `'sad'` is Tagalog in
  /// a Tagalog pack, so the game never has to know the translation.
  final String slug;

  /// The face picture this emotion is drawn with.
  final FaceArt face;

  final String en;
  final String tl;
  final String ceb;

  String label(GameLanguage language) {
    switch (language) {
      case GameLanguage.tagalog:
        return tl;
      case GameLanguage.cebuano:
        return ceb;
      case GameLanguage.english:
        return en;
    }
  }

  /// The emotion with this [slug], or null.
  static Emotion? bySlug(String slug) {
    for (final e in Emotion.values) {
      if (e.slug == slug) return e;
    }
    return null;
  }
}

/// The face pictures: the five emotions plus the neutral rest pose.
///
/// Neutral is not a playable answer and never appears on a card. It exists
/// because the buddy's face *transitions* into the emotion rather than holding
/// it: a still face is a puzzle to be decoded, while a face changing in front of
/// you is the same information delivered as movement, which is markedly easier
/// to read. That transition is also the first rung of the prompt hierarchy —
/// replaying it is the cheapest help this game can give.
enum FaceArt {
  neutral('neutral'),
  happy('happy'),
  sad('sad'),
  scared('scared'),
  surprised('surprised'),
  angry('angry');

  const FaceArt(this.assetName);

  /// Basename of the face picture, without extension.
  final String assetName;

  /// The generic (character-agnostic) face path — the original BPS-styled set,
  /// kept as the fallback when a chosen character has no art for this face.
  String get assetPath =>
      'packages/shared_ui/assets/emotion_cards/face_$assetName.png';

  /// The path to [character]'s own drawing of this face (bps / reiz /
  /// lexianne), so the buddy the child reads is the character they picked. The
  /// cache tries this first and falls back to [assetPath].
  String assetPathFor(String character) =>
      'packages/shared_ui/assets/emotion_cards/face_${character}_$assetName.png';
}

/// The pairs of emotions children actually confuse.
///
/// These are the discriminations that matter clinically, and they are the ones
/// tier 2 is built to force. `sad`/`scared` and `scared`/`surprised` are the
/// classic errors — a wide mouth and raised brows read as both. `happy`/
/// `surprised` share the open mouth, and `angry`/`sad` share the downturned one
/// and the general negative valence.
///
/// The set does double duty. Tier 1 uses it as a *ban list* so the two cards a
/// beginner sees are never a hard pair, and tier 2 uses it as a *requirement*
/// so the near-miss is present exactly once. Both readings depend on it being
/// the same list, which is why it lives here rather than inside the game.
const Set<Set<Emotion>> kNearMissPairs = {
  {Emotion.sad, Emotion.scared},
  {Emotion.scared, Emotion.surprised},
  {Emotion.happy, Emotion.surprised},
  {Emotion.angry, Emotion.sad},
};

/// Whether [a] and [b] are one of the confusable pairs above.
bool isNearMiss(Emotion a, Emotion b) {
  if (a == b) return false;
  for (final pair in kNearMissPairs) {
    if (pair.contains(a) && pair.contains(b)) return true;
  }
  return false;
}

/// The emotions that are *not* confusable with [e] — tier 1's safe distractors.
List<Emotion> farFrom(Emotion e) =>
    Emotion.values.where((o) => o != e && !isNearMiss(o, e)).toList();

/// The emotions that ARE confusable with [e] — tier 2's required distractor.
List<Emotion> nearTo(Emotion e) =>
    Emotion.values.where((o) => o != e && isNearMiss(o, e)).toList();

/// A caring thing the child can do about how their friend feels.
///
/// Tier 3's second question. Kept to four, all of them things a preschooler can
/// actually perform, and none of them requiring speech beyond a single word —
/// a response step a non-speaking child cannot answer would measure their
/// speech, not their social understanding.
enum CaringResponse {
  hug('hug', ResponseArt.hug, 'Give a hug', 'Yakapin', 'Gakson'),
  share('share', ResponseArt.share, 'Share a toy', 'Magbahagi ng laruan',
      'Pakigbahin ang dulaan'),
  sorry('sorry', ResponseArt.sorry, 'Say sorry', 'Magsorry', 'Mangayo og pasaylo'),
  clap('clap', ResponseArt.clap, 'Clap for them', 'Pumalakpak', 'Mopakpak');

  const CaringResponse(this.slug, this.art, this.en, this.tl, this.ceb);

  final String slug;
  final ResponseArt art;
  final String en;
  final String tl;
  final String ceb;

  String label(GameLanguage language) {
    switch (language) {
      case GameLanguage.tagalog:
        return tl;
      case GameLanguage.cebuano:
        return ceb;
      case GameLanguage.english:
        return en;
    }
  }
}

/// The pictures for the caring-response cards.
enum ResponseArt {
  hug('hug'),
  share('share'),
  sorry('sorry'),
  clap('clap');

  const ResponseArt(this.assetName);

  final String assetName;

  String get assetPath =>
      'packages/shared_ui/assets/emotion_cards/do_$assetName.png';
}

/// The pictures for the situation cards.
enum SceneArt {
  gift('gift'),
  finishedDrawing('finished_drawing'),
  iceCreamFell('ice_cream_fell'),
  spilledDrink('spilled_drink'),
  dogBarked('dog_barked'),
  loudThunder('loud_thunder'),
  jackInBox('jack_in_box'),
  surpriseBalloons('surprise_balloons'),
  towerFell('tower_fell'),
  puzzleStuck('puzzle_stuck');

  const SceneArt(this.assetName);

  final String assetName;

  String get assetPath =>
      'packages/shared_ui/assets/emotion_cards/scene_$assetName.png';
}

/// One situation: a picture of something that happened, the emotion it causes,
/// and the caring thing to do about it.
///
/// The caring response hangs off the *scene*, not off the emotion, and that is
/// the whole reason tier 3's second step is worth scoring. "Sad" does not imply
/// one correct action: a friend whose ice cream fell wants you to share yours,
/// and a friend whose drink you knocked over wants you to say sorry. Deriving
/// the response from the emotion alone would have taught a lookup table, which
/// is precisely the social-scripting failure mode this game should not produce.
class EmotionScene {
  const EmotionScene(
    this.id,
    this.art,
    this.emotion,
    this.response,
    this.en,
    this.tl,
    this.ceb,
  );

  /// Stable identifier, also used in analytics round data.
  final String id;

  final SceneArt art;

  /// What the buddy feels about it — the answer to the first question.
  final Emotion emotion;

  /// What a friend could do about it — the answer to tier 3's second question.
  final CaringResponse response;

  /// A short caption, printed under the scene picture in the child's language.
  final String en;
  final String tl;
  final String ceb;

  String caption(GameLanguage language) {
    switch (language) {
      case GameLanguage.tagalog:
        return tl;
      case GameLanguage.cebuano:
        return ceb;
      case GameLanguage.english:
        return en;
    }
  }
}

/// The situations the game draws from.
///
/// Two per emotion, so no emotion is carried by a single picture that a child
/// might simply memorise, and so a session of twelve trials rarely repeats.
///
/// **Every one of these is deliberately mild.** A dropped ice cream is the
/// ceiling for a negative event: nothing here frightens, nothing depicts a
/// child being hurt, and nothing shows a child left out. That is not squeamish-
/// ness. Emotion-recognition material shown to autistic children doubles as
/// exposure, and a distressing card teaches the distress alongside the label.
/// The two scary scenes are a dog barking behind a fence and thunder heard from
/// indoors — both at a safe distance, with the buddy safe in the picture.
///
/// Translations are drafts pending native-speaker review, as elsewhere in the
/// app; see the note in docs/ before these ship to a child.
const List<EmotionScene> kEmotionScenes = [
  // ── Happy ────────────────────────────────────────────────────────────
  EmotionScene('gift', SceneArt.gift, Emotion.happy, CaringResponse.clap,
      'His friend gave him a present.', 'Binigyan siya ng regalo ng kaibigan.',
      'Gihatagan siya og regalo sa iyang higala.'),
  EmotionScene(
      'finished_drawing',
      SceneArt.finishedDrawing,
      Emotion.happy,
      CaringResponse.clap,
      'He finished his drawing.',
      'Natapos niya ang kanyang drawing.',
      'Nahuman niya ang iyang drowing.'),
  // ── Sad ──────────────────────────────────────────────────────────────
  EmotionScene(
      'ice_cream_fell',
      SceneArt.iceCreamFell,
      Emotion.sad,
      CaringResponse.share,
      'His ice cream fell down.',
      'Nahulog ang kanyang ice cream.',
      'Nahulog ang iyang ice cream.'),
  EmotionScene(
      'spilled_drink',
      SceneArt.spilledDrink,
      Emotion.sad,
      CaringResponse.sorry,
      'You bumped his drink over.',
      'Nabangga mo ang kanyang inumin.',
      'Nabangga nimo ang iyang ilimnon.'),
  // ── Scared ───────────────────────────────────────────────────────────
  EmotionScene(
      'dog_barked',
      SceneArt.dogBarked,
      Emotion.scared,
      CaringResponse.hug,
      'A dog barked behind the gate.',
      'May asong tumahol sa likod ng gate.',
      'Adunay iro nga miusig sa luyo sa ganghaan.'),
  EmotionScene(
      'loud_thunder',
      SceneArt.loudThunder,
      Emotion.scared,
      CaringResponse.hug,
      'The thunder was very loud.',
      'Napakalakas ng kulog.',
      'Kusog kaayo ang dalugdog.'),
  // ── Surprised ────────────────────────────────────────────────────────
  EmotionScene(
      'jack_in_box',
      SceneArt.jackInBox,
      Emotion.surprised,
      CaringResponse.clap,
      'The toy popped out of the box!',
      'Biglang lumabas ang laruan sa kahon!',
      'Kalit nga migawas ang dulaan sa kahon!'),
  EmotionScene(
      'surprise_balloons',
      SceneArt.surpriseBalloons,
      Emotion.surprised,
      CaringResponse.clap,
      'Balloons appeared all at once!',
      'Biglang sumulpot ang mga lobo!',
      'Kalit nga mitungha ang mga lobo!'),
  // ── Angry ────────────────────────────────────────────────────────────
  EmotionScene(
      'tower_fell',
      SceneArt.towerFell,
      Emotion.angry,
      CaringResponse.sorry,
      'His block tower got knocked over.',
      'Natumba ang tore niyang blocks.',
      'Natumba ang iyang tore nga blocks.'),
  EmotionScene(
      'puzzle_stuck',
      SceneArt.puzzleStuck,
      Emotion.angry,
      CaringResponse.share,
      'The puzzle piece will not fit.',
      'Ayaw pumasok ng piyesa ng puzzle.',
      'Dili mosulod ang piraso sa puzzle.'),
];
