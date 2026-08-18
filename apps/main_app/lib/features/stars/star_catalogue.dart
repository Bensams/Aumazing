/// The Star Shop's fixed catalogue and earning rules (AUM-246, phase 02.0).
///
/// Everything a child can earn or spend is declared here as `const`, and that
/// is the point rather than a convenience: this is a *digital token board*, not
/// a game shop. A token economy works because the child can predict it. The
/// moment a price moves, a payout varies, or an item appears only sometimes,
/// the thing stops being a token board and becomes the kind of variable-reward
/// loop this app exists to be the opposite of.
///
/// So the invariants below are load-bearing, and `star_rules_test.dart` asserts
/// each one:
///
///  * every game pays [kStarsPerGame], whatever happened in it;
///  * prices are compile-time constants — no sales, no dynamic pricing, no
///    randomised or "mystery" items, no loot boxes;
///  * every costume is available to every character (see [Costume.assetFor]);
///  * nothing is ever taken away except a purchase the child chose.
///
/// See `.planning/phases/02.0-star-rewards/BACKLOG.md` for the reasoning, and
/// STAR-B1 / STAR-C5 / STAR-D3 for the specific acceptance criteria.
library;

import 'package:flutter/foundation.dart';

/// Stars awarded for finishing any activity, whatever the score.
///
/// Deliberately not a function of accuracy, errors, hints, retries or time.
/// Accuracy-contingent points punish exactly the children this app exists for,
/// and they corrupt the assessment: a child optimising for stars stops
/// answering honestly, which is the signal `gameplay_session` collects.
const int kStarsPerGame = 3;

/// The most stars a child can earn in one day.
///
/// Five games' worth. Past this, games stay fully playable and still celebrate
/// normally — they simply stop paying. The shop must never become a reason to
/// keep a child on the tablet longer, which is also why this coordinates with
/// `ScreenTimeService` rather than competing with it.
const int kDailyStarCap = kStarsPerGame * 5;

/// Which character guides the child through the app.
///
/// The parent picks this during setup and can change it at any time. It is
/// **never** derived from [ChildSex] — see STAR-A3 and the test that pins it.
/// A child's recorded sex is assessment data; it is not a costume rack.
enum ChildCharacter {
  bps('bps', 'BPS'),
  lexianne('lexianne', 'Lexianne'),
  reiz('reiz', 'Reiz');

  const ChildCharacter(this.id, this.displayName);

  /// Stable key stored on the profile and synced. Never renumber these.
  final String id;

  /// Shown under the character's portrait and spoken aloud on tap.
  final String displayName;

  static ChildCharacter fromId(String? id) => ChildCharacter.values.firstWhere(
        (c) => c.id == id,
        orElse: () => ChildCharacter.bps,
      );

  /// The character's own artwork, with no costume on.
  String get baseArtAsset => Costume.none.assetFor(this);
}

/// A costume a child can unlock and wear.
///
/// [none] is not a purchasable item — it is the character's own clothes, always
/// owned and always equippable, so a child can always undo a change of mind.
enum Costume {
  none('none', 'No costume', 0, hasSpriteSheets: true),
  teddy('teddy', 'Teddy', 9, hasSpriteSheets: true),
  panda('panda', 'Panda', 9, hasSpriteSheets: true),
  rabbit('rabbit', 'Rabbit', 12),
  pig('pig', 'Pig', 12, hasSpriteSheets: true),
  frog('frog', 'Frog', 15),
  fox('fox', 'Fox', 15),
  koala('koala', 'Koala', 18),
  octopus('octopus', 'Octopus', 21),
  unicorn('unicorn', 'Unicorn', 21);

  const Costume(
    this.id,
    this.displayName,
    this.priceStars, {
    this.hasSpriteSheets = false,
  });

  /// Stable key stored in `child_unlocks` and on the profile. Never rename.
  final String id;

  /// Shown on the shop card and spoken on tap.
  final String displayName;

  /// Price in stars. `const`, and asserted immutable by test — a shop whose
  /// prices can move is a shop that can pressure a child.
  final int priceStars;

  /// Whether this costume has its 21 sprite sheets cut for every character.
  ///
  /// The still art in `assets/costumes/` exists for all nine; the *animated*
  /// sheets in `assets/characters/` do not, because each costume is ~63 files
  /// and thousands of generation credits. Without them the mascot silently
  /// falls back to the character's own clothes in-game
  /// (`CharacterSprites.costumed`), so a child spends stars and then sees no
  /// change where it matters most — during play.
  ///
  /// That is why this gates [inStock] rather than merely being recorded:
  /// selling a costume that does not appear on the mascot breaks the promise
  /// the shop makes. Flip a costume to `true` in the same change that lands
  /// its sheets (STAR-F3 / AUM-275), and `star_rules_test.dart` will hold the
  /// declaration and the files on disk together.
  final bool hasSpriteSheets;

  static Costume fromId(String? id) => Costume.values.firstWhere(
        (c) => c.id == id,
        orElse: () => Costume.none,
      );

  /// Everything except [none], in the order the shop shows them: cheapest
  /// first, so the nearest goal is the one a child sees at the top.
  ///
  /// This is the *catalogue* — every costume that has a price and artwork,
  /// including ones the shop is not selling yet. Prices and asset paths are
  /// asserted against this. What a child can actually buy is [inStock].
  static List<Costume> get purchasable =>
      Costume.values.where((c) => c != Costume.none).toList()
        ..sort((a, b) => a.priceStars.compareTo(b.priceStars));

  /// What the shop actually offers today: the costumes whose sprite sheets
  /// exist, so buying one changes the mascot during play.
  ///
  /// A costume already owned is shown regardless of this list — see
  /// `StarRepository.offersFor`. Nothing a child has bought is ever taken
  /// away (STAR-D4), including by a later decision to stop selling it.
  static List<Costume> get inStock =>
      purchasable.where((c) => c.hasSpriteSheets).toList();

  /// Artwork of [character] wearing this costume.
  ///
  /// Every costume resolves for every character — there is no gating by
  /// character and none by the child's recorded sex (STAR-D3). A panda has no
  /// gender, which is precisely why the shop is built out of animals.
  ///
  /// Reads from `shared_ui`'s bundled copies, NOT from `packages/assets/`:
  /// that folder has no pubspec, so nothing in it ships with the app. The
  /// bundled set is written by `scripts/bundle_costume_art.py`, which resizes
  /// the 43 MB of source art down to about 2.5 MB.
  String assetFor(ChildCharacter character) =>
      'packages/shared_ui/assets/costumes/${character.id}_$id.png';
}

/// How the shop should present one costume to one child.
///
/// Deliberately has no "locked" state. An unaffordable costume renders in full
/// colour with a progress ring — never greyed out, never behind a padlock,
/// never accompanied by a disappointed mascot. This mirrors the rule already
/// written into `MascotGesture.oops`: the app does not model distress at a
/// child. "Not yet" is a progress bar, not a rejection.
@immutable
class CostumeOffer {
  const CostumeOffer({
    required this.costume,
    required this.owned,
    required this.balance,
  });

  final Costume costume;
  final bool owned;
  final int balance;

  bool get affordable => balance >= costume.priceStars;

  /// How far along the child is, 0–1. Full when owned.
  double get progress {
    if (owned || costume.priceStars == 0) return 1;
    return (balance / costume.priceStars).clamp(0, 1).toDouble();
  }

  /// Stars still needed. Zero when owned or affordable.
  int get remaining =>
      owned ? 0 : (costume.priceStars - balance).clamp(0, costume.priceStars);

  /// Spoken on tap, phrased as a countdown of *games* rather than stars —
  /// many users cannot read numerals, and "two more games" is a unit a child
  /// experiences directly.
  String get spokenProgress {
    if (owned) return 'You have ${costume.displayName}.';
    final games = (remaining / kStarsPerGame).ceil();
    if (games <= 0) return 'You can get ${costume.displayName} now!';
    if (games == 1) return 'One more game until ${costume.displayName}.';
    return '$games more games until ${costume.displayName}.';
  }
}
