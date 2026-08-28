import 'package:flutter/material.dart';

/// Supported in-app languages.
///
/// Curated (human-translated) localization — not runtime machine translation —
/// so wording stays correct and the app remains offline-first. Matches the
/// `en` / `tl` / `ceb` voice-over folders in shared_audio.
enum GameLanguage {
  english('en', 'English'),
  tagalog('tl', 'Tagalog'),
  cebuano('ceb', 'Cebuano');

  const GameLanguage(this.slug, this.label);

  /// Code used for asset folders / persistence (en, tl, ceb).
  final String slug;

  /// Human-readable name shown in the picker.
  final String label;

  static GameLanguage fromSlug(String? slug) {
    if (slug == null) return GameLanguage.english;
    return GameLanguage.values.firstWhere(
      (l) => l.slug == slug,
      orElse: () => GameLanguage.english,
    );
  }
}

/// Typed access to all localized strings for one [GameLanguage].
///
/// Each getter returns the string for the active language, falling back to
/// English when a Tagalog/Cebuano value is still empty — so the UI never shows
/// a blank while translations are being filled in.
///
/// NOTE: Tagalog/Cebuano values are starter translations and should be
/// reviewed by a SpEd/Filipino-language consultant before release. Empty
/// strings ('') are intentional TODO slots that fall back to English.
class AppStrings {
  const AppStrings(this.language);

  final GameLanguage language;

  String _pick(Map<GameLanguage, String> m) {
    final v = m[language];
    if (v != null && v.isNotEmpty) return v;
    return m[GameLanguage.english] ?? '';
  }

  // ── Praise / feedback ────────────────────────────────────────────────
  String get greatJob => _pick(const {
        GameLanguage.english: 'Great job!',
        GameLanguage.tagalog: 'Magaling!',
        GameLanguage.cebuano: 'Maayo kaayo!',
      });

  String get wellDone => _pick(const {
        GameLanguage.english: 'Well done!',
        GameLanguage.tagalog: 'Mahusay!',
        GameLanguage.cebuano: 'Maayo!',
      });

  String get tryAgain => _pick(const {
        GameLanguage.english: 'Try again',
        GameLanguage.tagalog: 'Subukan ulit',
        GameLanguage.cebuano: 'Sulayi pag-usab',
      });

  String get letsPlay => _pick(const {
        GameLanguage.english: "Let's play!",
        GameLanguage.tagalog: 'Maglaro tayo!',
        GameLanguage.cebuano: 'Magdula ta!',
      });

  // ── Sari-Sari Store Sorting ──────────────────────────────────────────
  /// Names the object and the action, rather than the bare verb "Sort".
  ///
  /// A one-word instruction assumes the child already knows what is being
  /// sorted and into what. This phrasing is modelled on how the SPED teacher
  /// actually gives the task aloud — "move the picture to its proper places" —
  /// so the on-screen prompt, the spoken cue and the adult in the room are all
  /// saying the same sentence.
  String get sortInstruction => _pick(const {
        GameLanguage.english: 'Move the picture to the right basket!',
        GameLanguage.tagalog: 'Ilipat ang larawan sa tamang basket!',
        GameLanguage.cebuano: 'Ibalhin ang hulagway sa saktong basket!',
      });

  String get binToys => _pick(const {
        GameLanguage.english: 'Toys',
        GameLanguage.tagalog: 'Laruan',
        GameLanguage.cebuano: 'Dulaan',
      });

  String get binFood => _pick(const {
        GameLanguage.english: 'Food',
        GameLanguage.tagalog: 'Pagkain',
        GameLanguage.cebuano: 'Pagkaon',
      });

  /// Everything a household needs that is neither a toy nor food — soap,
  /// toothbrush, tissue, shampoo. "Gamit" / "Galamiton" is the word a Filipino
  /// child hears for this at home, and is wider than "toiletries", which is
  /// what this category used to be called before it was allowed to grow.
  String get binEssentials => _pick(const {
        GameLanguage.english: 'Things',
        GameLanguage.tagalog: 'Gamit',
        GameLanguage.cebuano: 'Galamiton',
      });

  // ── Hintay! (Wait For It) ────────────────────────────────────────────
  /// Names both halves of the task — the waiting *and* the tap — because the
  /// game scores a tap that came too early. An instruction that said only
  /// "tap the star" would describe the error as the goal.
  String get hintayInstruction => _pick(const {
        GameLanguage.english: 'Wait for the star to wake up, then tap it!',
        GameLanguage.tagalog:
            'Hintayin mong magising ang bituin, tapos pindutin mo!',
        GameLanguage.cebuano:
            'Hulata nga momata ang bitoon, dayon tapika kini!',
      });

  /// Praises the waiting rather than the score: waiting is the skill the game
  /// exists to build, and the child cannot see their own premature-tap count.
  String get hintayComplete => _pick(const {
        GameLanguage.english: 'Well done! You waited so well!',
        GameLanguage.tagalog: 'Magaling! Ang galing mong maghintay!',
        GameLanguage.cebuano: 'Maayo kaayo! Maayo ka kaayo mohulat!',
      });

  // ── Kumusta! (Greet Back) ────────────────────────────────────────────
  /// Names the buddy's action first, then the child's, in that order: the
  /// child's job is a *reply*, and an instruction that opened with "wave" would
  /// describe a solo action instead of an exchange.
  String get kumustaInstruction => _pick(const {
        GameLanguage.english: 'Your friend is greeting you. Greet back!',
        GameLanguage.tagalog: 'Binabati ka ng kaibigan mo. Batiin mo rin siya!',
        GameLanguage.cebuano: 'Gitimbaya ka sa imong higala. Timbayaa pod siya!',
      });

  /// Praises the greeting, not the count. The child cannot see how many they
  /// got wrong, and the thing worth naming is that the exchange happened.
  String get kumustaComplete => _pick(const {
        GameLanguage.english: 'Well done! You are a great friend!',
        GameLanguage.tagalog: 'Magaling! Ang bait mong kaibigan!',
        GameLanguage.cebuano: 'Maayo kaayo! Maayo ka nga higala!',
      });

  // ── Ano'ng Susunod? (What's Next?) ───────────────────────────────────
  String get anongSusunodInstruction => _pick(const {
        GameLanguage.english: 'Which picture comes next?',
        GameLanguage.tagalog: 'Aling larawan ang susunod?',
        GameLanguage.cebuano: 'Unsang hulagway ang sunod?',
      });

  String get anongSusunodComplete => _pick(const {
        GameLanguage.english: 'Well done! You put them all in order!',
        GameLanguage.tagalog: 'Magaling! Naisaayos mo lahat!',
        GameLanguage.cebuano: 'Maayo kaayo! Nahan-ay nimo silang tanan!',
      });

  // ── Sabay Tayo! (joint attention) ────────────────────────────────────
  /// Names the *looking* before the tapping, and in that order. The tap is
  /// only how the child answers; what the game asks is that they find where
  /// someone else's attention has gone. An instruction that led with "tap the
  /// toy" would describe a different task, and one the child could pass
  /// without ever looking at the buddy.
  String get sabayTayoInstruction => _pick(const {
        GameLanguage.english: 'Look where your friend is looking, then tap it!',
        GameLanguage.tagalog:
            'Tingnan mo kung saan nakatingin ang kaibigan mo, tapos pindutin mo!',
        GameLanguage.cebuano:
            'Tan-awa kung asa nagtan-aw ang imong higala, dayon tapika kini!',
      });

  /// Praises the looking-together rather than the count of correct taps —
  /// sharing attention with someone is the thing that was practised.
  String get sabayTayoComplete => _pick(const {
        GameLanguage.english: 'Well done! You looked together!',
        GameLanguage.tagalog: 'Magaling! Sabay kayong tumingin!',
        GameLanguage.cebuano: 'Maayo kaayo! Dungan mong nagtan-aw!',
      });

  // ── Ano'ng Nararamdaman? (How does he feel?) ─────────────────────────
  /// Asks about the friend in the picture, not about the child. "How does *he*
  /// feel?" is a question with a findable answer on screen; "how would you
  /// feel?" is a question about the child's own interior, which this game
  /// neither asks nor scores.
  String get anongNararamdamanInstruction => _pick(const {
        GameLanguage.english: 'How is your friend feeling?',
        GameLanguage.tagalog: "Ano'ng nararamdaman ng kaibigan mo?",
        GameLanguage.cebuano: 'Unsay gibati sa imong higala?',
      });

  /// Tier 3's second question. Phrased as an offer of help rather than a duty
  /// ("what *should* you do"), so a child who picks a different kindness has
  /// answered a question, not failed a rule.
  String get anongNararamdamanResponse => _pick(const {
        GameLanguage.english: 'What could you do to help?',
        GameLanguage.tagalog: 'Ano ang pwede mong gawin para tumulong?',
        GameLanguage.cebuano: 'Unsay mahimo nimo aron makatabang?',
      });

  /// Praises the looking, which is the skill, rather than the number right.
  String get anongNararamdamanComplete => _pick(const {
        GameLanguage.english: 'Well done! You looked so carefully!',
        GameLanguage.tagalog: 'Magaling! Ang husay mong tumingin!',
        GameLanguage.cebuano: 'Maayo kaayo! Maayo ka kaayo motan-aw!',
      });

  // ── Tulong, Kaibigan! (sharing & requesting) ─────────────────────────
  /// Names the person before the object. The task is not "move the banana",
  /// it is "give it to the one who asked" — and on the hardest tier, where two
  /// friends ask in turn, a child who only heard the object would have no way
  /// to know they had been told the harder half of the question.
  String get tulongKaibiganInstruction => _pick(const {
        GameLanguage.english: 'Give your friend what they asked for!',
        GameLanguage.tagalog: 'Ibigay mo sa kaibigan mo ang hiningi niya!',
        GameLanguage.cebuano: 'Ihatag sa imong higala ang iyang gipangayo!',
      });

  /// Praises the helping rather than the count. Sharing on request is the
  /// behaviour being built; how many items were handed over is not something
  /// the child can see or should be scored on out loud.
  String get tulongKaibiganComplete => _pick(const {
        GameLanguage.english: 'Well done! You helped your friends!',
        GameLanguage.tagalog: 'Magaling! Natulungan mo ang mga kaibigan mo!',
        GameLanguage.cebuano: 'Maayo kaayo! Natabangan nimo ang imong mga higala!',
      });

  // ── Settings ─────────────────────────────────────────────────────────
  String get settingsTitle => _pick(const {
        GameLanguage.english: 'Settings',
        GameLanguage.tagalog: 'Mga Setting',
        GameLanguage.cebuano: 'Mga Setting',
      });

  String get languageLabel => _pick(const {
        GameLanguage.english: 'Language',
        GameLanguage.tagalog: 'Wika',
        GameLanguage.cebuano: 'Pinulongan',
      });

  String get backgroundThemeLabel => _pick(const {
        GameLanguage.english: 'Background Theme',
        GameLanguage.tagalog: 'Tema ng Background',
        GameLanguage.cebuano: 'Tema sa Background',
      });

  // ── Generic actions ──────────────────────────────────────────────────
  String get close => _pick(const {
        GameLanguage.english: 'Close',
        GameLanguage.tagalog: 'Isara',
        GameLanguage.cebuano: 'Sirad-i',
      });

  String get continueLabel => _pick(const {
        GameLanguage.english: 'Continue',
        GameLanguage.tagalog: 'Magpatuloy',
        GameLanguage.cebuano: 'Padayon',
      });
}

/// Holds the selected [GameLanguage] and notifies on change.
///
/// Mirrors AppThemeController. Create near the app root and expose via
/// [AppLanguageScope]; or drive it from a provider (e.g. ChildProvider).
class AppLanguageController extends ChangeNotifier {
  AppLanguageController([GameLanguage initial = GameLanguage.english])
      : _language = initial;

  GameLanguage _language;

  GameLanguage get language => _language;

  /// Localized strings for the current language.
  AppStrings get strings => AppStrings(_language);

  void setLanguage(GameLanguage language) {
    if (language == _language) return;
    _language = language;
    notifyListeners();
  }
}

/// Inherited access to the active [AppLanguageController] / [AppStrings].
class AppLanguageScope extends InheritedNotifier<AppLanguageController> {
  const AppLanguageScope({
    super.key,
    required AppLanguageController controller,
    required super.child,
  }) : super(notifier: controller);

  static AppLanguageController controllerOf(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<AppLanguageScope>();
    assert(scope != null, 'No AppLanguageScope found in the widget tree.');
    return scope!.notifier!;
  }

  static AppStrings stringsOf(BuildContext context) =>
      controllerOf(context).strings;
}
