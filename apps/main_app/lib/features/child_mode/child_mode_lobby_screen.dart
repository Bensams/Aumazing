import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:game_core/game_core.dart';
import 'package:shared_audio/shared_audio.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../providers/assessment_provider.dart';
import '../../providers/child_provider.dart';
import '../../services/active_games_service.dart';
import '../../services/learning_path_service.dart';
import '../../services/screen_time_service.dart';
import '../../widgets/mascot.dart';
import '../../widgets/mascot_host.dart';
import '../stars/star_shop_screen.dart';
import 'game_launcher.dart';
import 'path_map_view.dart';
import 'time_up_dialog.dart';

/// Size of a game card in step 2 — the row on a phone, the grid on a tablet.
/// A portrait-ish tile: room for the 104pt logo above the name strip, and
/// nothing like the full-height column the cards used to stretch into.
const double _kGameCardWidth = 186;
const double _kGameCardHeight = 240;

/// Child Mode Lobby.
///
/// Reached from the parent dashboard's "Enter Child Mode". The child first
/// picks a skill category (Play, Communication, Social Interaction), then sees
/// that category's games in a single horizontally-scrolling row. Games are
/// non-assessment (practice) mode, but difficulty follows the child's current
/// level from the latest assessment.
class ChildModeLobbyScreen extends StatefulWidget {
  const ChildModeLobbyScreen({super.key, this.openPath = false});

  /// When true, opens directly on the "My Path" view (used by the parent
  /// dashboard's Recommended Module card).
  final bool openPath;

  @override
  State<ChildModeLobbyScreen> createState() => _ChildModeLobbyScreenState();
}

class _ChildModeLobbyScreenState extends State<ChildModeLobbyScreen>
    with TickerProviderStateMixin {
  static const _categoryOrder = [
    SkillCategory.playSkills,
    SkillCategory.communication,
    SkillCategory.socialInteraction,
  ];

  // ── Category card sizing (step 1) ──────────────────────────────────────
  // Bounds, not fixed sizes: a card takes its share of the available width
  // between these, and its height follows. Big enough for a child to aim at,
  // never so big that it becomes a full-height column on a large tablet.
  static const _categoryCardMinWidth = 168.0;
  static const _categoryCardMaxWidth = 260.0;
  static const _categoryCardMinHeight = 260.0;
  static const _categoryCardMaxHeight = 360.0;

  /// Height as a multiple of width — portrait-ish, so the icon, label and
  /// game count stack comfortably without the card going square.
  static const _categoryCardHeightRatio = 1.25;

  /// The category the child tapped, or null while showing the buttons.
  SkillCategory? _selected;

  /// True when the child tapped "All" (show every game).
  bool _viewingAll = false;

  /// True when the child tapped "My Path" (AI-recommended order).
  bool _viewingPath = false;

  bool get _inView => _selected != null || _viewingAll || _viewingPath;

  /// Admin-enabled game ids; null until loaded (path shown once known).
  Set<String>? _activeGameIds;

  /// Screen-time usage ticker — runs for the whole child-mode session
  /// (this lobby stays mounted underneath the game screens).
  Timer? _screenTimeTicker;
  static const _tickSeconds = 15;

  /// Ownership token for the play session this lobby started (AUM-162).
  /// dispose ends the session *by token*, so a dispose that lands after
  /// the service has loaded another child cannot touch that child's
  /// session.
  int? _screenTimeToken;

  /// One-shot pre-limit warning (AUM-162): shown once per lobby visit when
  /// the stricter remaining budget first dips under the warning window.
  bool _warnedNearLimit = false;
  OverlayEntry? _breakSoonEntry;
  Timer? _breakSoonTimer;

  // ── Guided start (ABA-style lobby prompting) ─────────────────────────
  // On entry with a recommendation: voice welcome + a pointing hand at
  // "My Path". After 30s idle: the hand appears at the next tap target
  // and a guiding voice line repeats every ~7s until the child taps.
  late final VoiceOverService _lobbyVo;

  /// The hand's four motions, kept separate so they can overlap: the resting
  /// bob, the fade/scale as it arrives and leaves, the glide when it moves to
  /// a new target, and the press it plays back when the child taps.
  late final AnimationController _bobController;
  late final AnimationController _fadeController;
  late final AnimationController _travelController;
  late final AnimationController _pressController;

  /// Opens My Path as a door: the path view is revealed through a window that
  /// grows out of the "My Path" button until it fills the screen, and closes
  /// back into that same button on the way out.
  ///
  /// The lobby keeps rendering underneath for the whole animation, so the child
  /// sees the world open *on* the place they tapped rather than the screen
  /// swapping under them. This is the one piece of motion the lobby allows
  /// itself: it only ever runs because the child tapped, and it explains a
  /// change instead of decorating one.
  ///
  /// Everything about how it moves is chosen for an ASD child rather than for
  /// polish:
  ///
  /// * **Slow enough to follow.** [_doorDuration] is well past the ~300ms of a
  ///   typical UI flourish. A fast transition is *finished* before a child who
  ///   processes visual change slowly has located what moved, which turns the
  ///   new screen into a surprise. This one can be tracked from start to end.
  /// * **No sudden onset.** [_doorCurve] eases in as well as out, so the motion
  ///   starts from rest instead of snapping away on the first frame. Abrupt
  ///   onsets are the startling part of an animation, not the speed.
  /// * **Nothing overshoots, bounces, spins or flashes.** The window only ever
  ///   grows, at a steady rate, in one direction.
  /// * **Reversible and symmetric.** Going back closes the same window along
  ///   the same path at the same speed, so the child is shown where My Path
  ///   *lives* — the transition doubles as a map instead of teleporting them.
  /// * **Nothing inside moves.** The path view is laid out at full size the
  ///   whole time and only the window over it changes, so there is no scaling
  ///   text or reflowing layout to track.
  /// * **Opt-out honoured.** With reduced motion on, the same change is made as
  ///   a plain cross-fade ([_doorFadeOnly]) — announced just as clearly, with
  ///   nothing travelling across the screen.
  late final AnimationController _doorController;

  /// Root-stack rect the door grows from; null when no door is running.
  Rect? _doorFromRect;
  bool _doorActive = false;

  /// True while the door is closing (path → lobby) rather than opening.
  bool _doorClosing = false;

  /// Reduced motion: hold the window at full screen and cross-fade instead.
  bool _doorFadeOnly = false;

  static const _doorDuration = Duration(milliseconds: 600);
  static const _doorCurve = Curves.easeInOutCubic;

  /// Fraction of the door spent fading the path view in over the button, so the
  /// window's first frame dissolves out of what the child tapped rather than
  /// replacing it between one frame and the next.
  static const _doorFadeFraction = 0.3;

  /// The full-screen stack the door is drawn in. The door's clip is sized to
  /// this box, so its start rect has to be measured against it too — measuring
  /// against [_stackKey] (which sits inside the SafeArea) would start the
  /// window offset by the safe-area insets, which in child-mode landscape is
  /// the notch/gesture inset on the very edge the button sits near.
  final GlobalKey _rootStackKey = GlobalKey();
  final GlobalKey _stackKey = GlobalKey();
  final GlobalKey _pathButtonKey = GlobalKey();
  final GlobalKey _allButtonKey = GlobalKey();
  final GlobalKey _guideCardKey = GlobalKey();
  Timer? _idleGuideTimer;
  Timer? _voRepeatTimer;
  Timer? _entryHideTimer;
  bool _guideVisible = false;
  Offset? _guideAnchor; // stack-local center of the target
  Offset? _fromAnchor; // where a glide started, null when not travelling
  bool _dismissing = false; // playing the press-and-ripple goodbye
  bool _voAlternate = false;
  static const _idleGuideDelay = Duration(seconds: 30);
  static const _voRepeatInterval = Duration(seconds: 7); // within 5–8s

  /// Prompts spoken in the current idle burst. Repeating indefinitely turns
  /// help into nagging, which for an ASD child is aversive rather than
  /// supportive — so a burst stops after [_maxIdlePrompts] and the lobby
  /// waits [_idleBackoffDelay] (quietly) before offering help again.
  int _idlePrompts = 0;
  static const _maxIdlePrompts = 3;
  static const _idleBackoffDelay = Duration(seconds: 90);

  /// Bumped whenever the guidance voice speaks so BPS waves along with it.
  /// Drives BPS in the corner: greets on entry, points alongside the guidance
  /// hand, and nods back when the child chooses.
  final MascotController _mascot = MascotController();

  @override
  void initState() {
    super.initState();
    // Child mode is landscape on every device — the parent screen we came
    // from is portrait on phones, so the lock has to be re-applied here.
    lockParentLandscape();
    _viewingPath = widget.openPath;
    ActiveGamesService.instance.activeGameIds.then((ids) {
      if (mounted) setState(() => _activeGameIds = ids);
    });
    _startScreenTimeTracking();

    _lobbyVo = VoiceOverService(
      languageCode: context.read<ChildProvider>().voiceAssetFolder,
      speed: context.read<ChildProvider>().voicePlaybackRate,
    );
    _bobController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
      reverseDuration: const Duration(milliseconds: 220),
    )..addStatusListener((status) {
      // Fully faded out — drop the hand from the tree.
      if (status == AnimationStatus.dismissed && mounted) {
        setState(() => _guideVisible = false);
      }
    });
    _travelController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 430),
    )..addStatusListener((status) {
      if (status == AnimationStatus.completed) _fromAnchor = null;
    });
    _pressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    )..addStatusListener((status) {
      // The goodbye finished playing — now the hand is really gone.
      if (status == AnimationStatus.completed && mounted) {
        _fadeController.value = 0;
        setState(() {
          _dismissing = false;
          _guideVisible = false;
        });
      }
    });
    _doorController = AnimationController(vsync: this, duration: _doorDuration)
      ..addStatusListener((status) {
        if (!mounted) return;
        // Both ends of the door hand over to a view that is already
        // pixel-identical to the last frame drawn, so the state swap itself is
        // invisible: opening finishes with the window covering the screen and
        // the real path view underneath it, closing finishes with the window
        // shrunk into the button the lobby is already drawing.
        //
        // The direction has to be checked because seeding a controller
        // (`forward(from: 0)`, `value = 1`) reports dismissed/completed before
        // the animation itself runs.
        if (status == AnimationStatus.completed && !_doorClosing) {
          setState(() {
            _doorActive = false;
            _doorFromRect = null;
            _viewingPath = true;
          });
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_lobbyActive) _showGuide();
          });
        } else if (status == AnimationStatus.dismissed && _doorClosing) {
          setState(() {
            _doorActive = false;
            _doorClosing = false;
            _doorFromRect = null;
          });
        }
      });
    WidgetsBinding.instance.addPostFrameCallback((_) => _startEntryGuidance());
    _restartIdleTimer();
  }

  Future<void> _startScreenTimeTracking() async {
    final childId = context.read<ChildProvider>().profile?.id;
    if (childId == null) return;
    final screenTime = ScreenTimeService.instance;
    await screenTime.load(childId);
    if (!mounted) return;
    // Entering child mode begins the play session (AUM-162). A session
    // suspended by an app restart moments ago resumes instead of resetting —
    // see ScreenTimeService.startSession for the full lifecycle. The token
    // makes this lobby the session's owner.
    _screenTimeToken = await screenTime.startSession();
    if (!mounted) return;

    // Already out of time when entering child mode → gentle goodbye now.
    if (screenTime.isExhausted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) TimeUpDialog.show(context);
      });
    }

    _screenTimeTicker = Timer.periodic(const Duration(seconds: _tickSeconds), (
      _,
    ) async {
      if (!mounted) return;
      // The lock screen is up — stop counting until the parent unlocks.
      if (TimeUpDialog.isShowing) return;
      await screenTime.addUsage(_tickSeconds);
      if (!mounted) return;
      if (screenTime.isExhausted) {
        // Never interrupt a game in progress — a mid-activity cutoff is
        // distressing for ASD children. Only enforce while the lobby itself
        // is visible; game endings are handled by GameEndChoiceDialog.
        if (ModalRoute.of(context)?.isCurrent ?? true) {
          TimeUpDialog.show(context);
        }
      } else if (screenTime.isNearLimit && !_warnedNearLimit) {
        // One gentle heads-up before the rest screen (AUM-162). Shown over
        // whatever the child is doing — lobby or game — because its whole
        // point is to make the coming stop unsurprising.
        _warnedNearLimit = true;
        _showBreakSoonNotice();
      }
    });
  }

  /// Shows the pre-limit notice on the root overlay, above the lobby or any
  /// open game, and withdraws it again a few seconds later.
  void _showBreakSoonNotice() {
    if (_breakSoonEntry != null) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    final reduced = context.read<ChildProvider>().reducedMotion;
    final entry = OverlayEntry(
      builder: (_) => _BreakSoonNotice(reduced: reduced),
    );
    _breakSoonEntry = entry;
    overlay.insert(entry);
    _breakSoonTimer = Timer(const Duration(seconds: 6), _removeBreakSoonNotice);
  }

  void _removeBreakSoonNotice() {
    _breakSoonTimer?.cancel();
    _breakSoonTimer = null;
    _breakSoonEntry?.remove();
    _breakSoonEntry = null;
  }

  @override
  void dispose() {
    _screenTimeTicker?.cancel();
    _removeBreakSoonNotice();
    // Leaving child mode — parent exit, child switch, sign-out and the lock
    // screen's "Exit Child Mode" all pop this route — ends the play session
    // (AUM-162). Ended by token: if the service has since loaded another
    // child, this dispose is stale and must not touch that child's session.
    // An app kill skips this, which is exactly what lets the persisted
    // session resume after a quick restart.
    ScreenTimeService.instance.endSessionOwned(_screenTimeToken);
    _idleGuideTimer?.cancel();
    _voRepeatTimer?.cancel();
    _entryHideTimer?.cancel();
    _bobController.dispose();
    _fadeController.dispose();
    _travelController.dispose();
    _pressController.dispose();
    _doorController.dispose();
    _lobbyVo.dispose();
    _mascot.dispose();
    super.dispose();
  }

  // ── Guided start ───────────────────────────────────────────────────────

  /// Guidance only runs while the lobby itself is what the child sees.
  bool get _lobbyActive =>
      mounted &&
      !TimeUpDialog.isShowing &&
      (ModalRoute.of(context)?.isCurrent ?? true);

  /// Entry guidance: the voice welcomes the child and the hand shows where to
  /// start. Every child gets this — a child with no assessment yet has no
  /// learning path, but is exactly the child least able to work out where to
  /// tap, so [_currentGuideKey] points at "All" for them instead.
  Future<void> _startEntryGuidance() async {
    await Future.delayed(const Duration(milliseconds: 900));
    if (!_lobbyActive) return;
    _lobbyVo.play(VoiceOverCue.letsBegin);
    _mascot.play(MascotGesture.wave);
    _showGuide();
    // The entry pointer is a short nudge, not a fixture.
    _entryHideTimer = Timer(const Duration(seconds: 6), () {
      if (mounted) _hideGuide(restartIdle: false);
    });
  }

  /// The widget the hand should point at right now.
  GlobalKey _currentGuideKey() {
    if (!_inView) {
      return _learningPath().isNotEmpty ? _pathButtonKey : _allButtonKey;
    }
    return _guideCardKey; // set on the recommended card in the visible row
  }

  /// Stack-local centre of the widget the hand should point at, or null if
  /// that widget is not laid out right now.
  Offset? _anchorForCurrentTarget() {
    final targetContext = _currentGuideKey().currentContext;
    final stackContext = _stackKey.currentContext;
    if (targetContext == null || stackContext == null) return null;
    final targetBox = targetContext.findRenderObject() as RenderBox?;
    final stackBox = stackContext.findRenderObject() as RenderBox?;
    if (targetBox == null || stackBox == null || !targetBox.attached) {
      return null;
    }
    final centerGlobal = targetBox.localToGlobal(
      Offset(targetBox.size.width / 2, targetBox.size.height / 2),
    );
    return stackBox.globalToLocal(centerGlobal);
  }

  /// Positions (or repositions) the pointing hand over the current target.
  ///
  /// A hand that is already on screen glides to its new target rather than
  /// teleporting — the travel itself is the cue, since the child's eye follows
  /// the movement to the thing they should tap.
  void _showGuide() {
    final anchor = _anchorForCurrentTarget();
    if (anchor == null) return;
    final reduced = context.read<ChildProvider>().reducedMotion;
    final wasOnScreen = _guideVisible && !_dismissing && _guideAnchor != null;

    // A tap-dismiss already in flight is stale now — start clean.
    if (_dismissing) {
      _pressController.stop();
      _pressController.value = 0;
      _dismissing = false;
    }

    setState(() {
      if (wasOnScreen && !reduced && (_guideAnchor! - anchor).distance > 4) {
        _fromAnchor = _renderedAnchor();
        _travelController.forward(from: 0);
      } else {
        _fromAnchor = null;
      }
      _guideAnchor = anchor;
      _guideVisible = true;
    });
    _fadeController.forward();
  }

  /// Keeps the hand on its card while the games row scrolls under it, so the
  /// pointer never ends up aimed at empty space or the wrong game.
  ///
  /// Runs during the tap-dismiss too. A drag begins with the pointer-down that
  /// starts the goodbye, so this is mostly what it is here for: the fading
  /// hand and its ripple ride along with the card instead of being left
  /// behind in the space the card used to occupy.
  void _reanchorGuide() {
    if (!_guideVisible) return;
    final anchor = _anchorForCurrentTarget();
    if (anchor == null || anchor == _guideAnchor) return;
    setState(() {
      _fromAnchor = null; // track the card directly, no glide
      _guideAnchor = anchor;
    });
  }

  /// Withdraws the hand quietly (timer expiry, launching a game). The child
  /// did not act on it, so there is nothing to acknowledge — it just fades.
  void _hideGuide({required bool restartIdle}) {
    _entryHideTimer?.cancel();
    _voRepeatTimer?.cancel();
    _voRepeatTimer = null;
    if (_guideVisible && !_dismissing) _fadeController.reverse();
    if (restartIdle) _restartIdleTimer();
  }

  /// Any touch means the child is engaged — hide guidance, rearm the timer.
  ///
  /// When the hand is up, the touch gets answered: it presses down and throws
  /// a ripple before fading, so the child sees that the prompt registered what
  /// they did rather than watching it blink out.
  void _onUserInteraction(PointerDownEvent _) {
    _idlePrompts = 0; // engagement ends the burst; next one starts fresh
    final acknowledge =
        _guideVisible &&
        !_dismissing &&
        _fadeController.value > 0 &&
        !context.read<ChildProvider>().reducedMotion;
    if (acknowledge) {
      _entryHideTimer?.cancel();
      _voRepeatTimer?.cancel();
      _voRepeatTimer = null;
      setState(() => _dismissing = true);
      _pressController.forward(from: 0);
      _restartIdleTimer();
      return;
    }
    _hideGuide(restartIdle: true);
  }

  void _restartIdleTimer({Duration delay = _idleGuideDelay}) {
    _idleGuideTimer?.cancel();
    _idleGuideTimer = Timer(delay, _onIdle);
  }

  /// 30s without a tap: point at the next place to tap and repeat a short
  /// guiding voice line every ~7s — up to [_maxIdlePrompts] times, then go
  /// quiet for [_idleBackoffDelay] rather than prompting forever.
  void _onIdle() {
    if (!_lobbyActive) {
      // Mid-game or locked — check again later instead of talking over it.
      _restartIdleTimer();
      return;
    }
    _idlePrompts = 0;
    _showGuide();
    _speakGuidance();
    _voRepeatTimer = Timer.periodic(_voRepeatInterval, (_) {
      if (!_lobbyActive) return;
      if (_idlePrompts >= _maxIdlePrompts) {
        // Said our piece. Withdraw the pointer and leave the child in peace
        // until the longer backoff elapses.
        _hideGuide(restartIdle: false);
        _restartIdleTimer(delay: _idleBackoffDelay);
        return;
      }
      _showGuide(); // re-anchor in case the view changed
      _speakGuidance();
    });
  }

  /// Alternates two short cues so the repetition stays gentle, and matches
  /// the cue to what the child is actually looking at: the category buttons
  /// ("let's begin") or a row of game cards ("choose one").
  void _speakGuidance() {
    _voAlternate = !_voAlternate;
    final settled = _inView ? VoiceOverCue.chooseOne : VoiceOverCue.letsBegin;
    _lobbyVo.play(_voAlternate ? VoiceOverCue.tapHere : settled);
    _idlePrompts++;
    _mascot.play(MascotGesture.point);
  }

  /// Speaks a short confirmation when the child makes a choice, so the lobby
  /// answers back instead of going silent at the moment of the tap.
  void _speakChoice(VoiceOverCue cue) {
    if (!mounted) return;
    _lobbyVo.play(cue);
    _mascot.play(MascotGesture.nod);
  }

  /// Rect of a keyed widget in the coordinate space of [within] (the guidance
  /// stack by default), or null when either is not laid out.
  Rect? _rectForKey(GlobalKey key, {GlobalKey? within}) {
    final targetContext = key.currentContext;
    final stackContext = (within ?? _stackKey).currentContext;
    if (targetContext == null || stackContext == null) return null;
    final targetBox = targetContext.findRenderObject() as RenderBox?;
    final stackBox = stackContext.findRenderObject() as RenderBox?;
    if (targetBox == null || stackBox == null || !targetBox.attached) {
      return null;
    }
    final topLeft = stackBox.globalToLocal(
      targetBox.localToGlobal(Offset.zero),
    );
    return Rect.fromLTWH(
      topLeft.dx,
      topLeft.dy,
      targetBox.size.width,
      targetBox.size.height,
    );
  }

  /// Enters My Path through the door animation — growing out of the button when
  /// motion is allowed, cross-fading when it is not, and falling back to a
  /// plain swap only when the button's rect cannot be measured at all.
  void _enterPath() {
    final reduced = context.read<ChildProvider>().reducedMotion;
    final rect =
        reduced
            ? Rect.zero
            : _rectForKey(_pathButtonKey, within: _rootStackKey);
    if (rect == null) {
      _enterView(() => _viewingPath = true);
      return;
    }
    _speakChoice(VoiceOverCue.hereWeGo);
    _hideGuide(restartIdle: false);
    _doorClosing = false;
    // Seeded before mounting so the door's first frame is the button's rect and
    // not wherever the last run left the controller.
    _doorController.value = 0;
    setState(() {
      _doorFadeOnly = reduced;
      _doorFromRect = rect;
      _doorActive = true;
    });
    // The frame that mounts the door is the frame that builds the path view for
    // the first time — backdrop, level map and all. Starting the animation on
    // that same frame spends the build on frame one and drops it, so the door
    // appears to jump. Wait for the view to exist, then move it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _doorActive && !_doorClosing) _doorController.forward();
    });
  }

  /// Leaves My Path by running the same door backwards, so the world the child
  /// was in visibly folds back into the button that opened it. Seeing where a
  /// screen *went* is what makes the lobby stay one place instead of becoming a
  /// series of unrelated screens.
  ///
  /// The lobby is switched back on the same frame the door is pinned open, so
  /// the button is laid out and measurable by the next frame while the child
  /// still sees only the path view.
  void _exitPath() {
    final reduced = context.read<ChildProvider>().reducedMotion;
    _doorClosing = true;
    _doorController.value = 1;
    setState(() {
      _doorFadeOnly = reduced;
      // Only read at progress < 1, and the next frame replaces it with the
      // measured button. Pinned at 1 the clip is the whole canvas regardless.
      _doorFromRect = Rect.zero;
      _doorActive = true;
      _viewingPath = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_doorClosing) return;
      final rect =
          reduced
              ? Rect.zero
              : _rectForKey(_pathButtonKey, within: _rootStackKey);
      if (rect == null) {
        // Nothing to shrink into — drop the cover and let the lobby stand.
        setState(() {
          _doorActive = false;
          _doorClosing = false;
          _doorFromRect = null;
        });
        return;
      }
      setState(() => _doorFromRect = rect);
      _doorController.reverse(from: 1);
    });
  }

  /// Opens a category / All / My Path view: acknowledge the tap out loud, then
  /// move the pointing hand onto the card the child should try first.
  void _enterView(VoidCallback apply) {
    setState(apply);
    _speakChoice(VoiceOverCue.hereWeGo);
    // The cards do not exist until this frame is laid out.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_lobbyActive) _showGuide();
    });
  }

  /// True while any part of the hand — arrival, rest, or goodbye — is on
  /// screen.
  ///
  /// Deliberately keyed off [_guideVisible] and not the fade value: the
  /// controllers tick without rebuilding this widget (only the inner
  /// [ListenableBuilder] listens), so a value-based test would never see the
  /// hand fade in. [_guideVisible] is cleared by the fade and press status
  /// listeners once the exit has finished playing.
  bool get _guideOnScreen => _guideAnchor != null && _guideVisible;

  /// Where the hand sits this frame: its target, or a point along the glide
  /// if it is still travelling there.
  Offset _renderedAnchor() {
    final to = _guideAnchor!;
    final from = _fromAnchor;
    if (from == null) return to;
    final t = Curves.easeInOutCubic.transform(_travelController.value);
    return Offset.lerp(from, to, t)!;
  }

  /// The pointing hand and the ripple it leaves when the child taps.
  ///
  /// Returned as a list so the ripple can sit exactly on the target centre
  /// while the hand hangs just below it. Both ignore pointers: the hand is a
  /// cue, never the thing to tap — the game card underneath is.
  List<Widget> _buildGuideLayer() {
    final reduced = context.read<ChildProvider>().reducedMotion;
    return [
      ListenableBuilder(
        listenable: Listenable.merge([
          _fadeController,
          _travelController,
          _pressController,
          _bobController,
        ]),
        builder: (context, _) {
          final anchor = _renderedAnchor();
          final press = _pressController.value;

          // Arrival overshoots a little so the hand lands rather than
          // materialises; departure is a plain fade.
          final appear =
              reduced
                  ? 1.0
                  : Curves.easeOutBack.transform(_fadeController.value);
          // The press: a dip that holds while the hand fades away.
          final pressDip =
              1 -
              0.16 *
                  Curves.easeOutCubic.transform((press / 0.35).clamp(0.0, 1.0));
          final pressFade = press <= 0.35 ? 1.0 : 1 - ((press - 0.35) / 0.65);
          final opacity = (_fadeController.value * pressFade).clamp(0.0, 1.0);

          // Each unanswered prompt bobs a little wider — an unheeded cue
          // should grow, but only to a gentle ceiling.
          final bobHeight = (6.0 + 2.5 * _idlePrompts).clamp(6.0, 13.0);
          final bob = reduced ? 0.0 : bobHeight * _bobController.value;

          return Positioned(
            left: anchor.dx - 36,
            top: anchor.dy - 12,
            child: IgnorePointer(
              child: Opacity(
                opacity: opacity,
                child: Transform.translate(
                  offset: Offset(0, bob),
                  child: Transform.scale(
                    scale: appear * pressDip,
                    // No halo behind the hand: the emoji sits directly on the
                    // lobby. The 72x72 box keeps the anchor offsets centred.
                    child: const SizedBox(
                      width: 72,
                      height: 72,
                      child: Center(
                        child: Text('👆', style: TextStyle(fontSize: 40)),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
      if (_dismissing)
        ListenableBuilder(
          listenable: _pressController,
          builder: (context, _) {
            final t = Curves.easeOutCubic.transform(_pressController.value);
            final radius = 30 + 42 * t;
            final anchor = _renderedAnchor();
            return Positioned(
              left: anchor.dx - radius,
              top: anchor.dy - radius,
              child: IgnorePointer(
                child: Container(
                  width: radius * 2,
                  height: radius * 2,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.white.withValues(
                        alpha: (0.5 * (1 - t)).clamp(0.0, 1.0),
                      ),
                      width: 3,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
    ];
  }

  /// The AI-recommended learning path (empty when no assessment yet, all
  /// areas are at Strength, or active games are still loading).
  List<LearningPathEntry> _learningPath() =>
      LearningPathService.fromContext(context, activeGameIds: _activeGameIds);

  /// All supported games, deduplicated (used by the "All" view/button).
  List<GameEntry> _allGames() => GameLauncher.supportedGames();

  Future<void> _launch(String gameId, int difficulty) async {
    final screen = GameLauncher.screenFor(gameId, difficulty);
    if (screen == null) return;
    _speakChoice(VoiceOverCue.letsGo);
    _hideGuide(restartIdle: false); // the game speaks for itself from here
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    // Back in the lobby: pick the child up again rather than dropping them
    // into silence, and re-arm the idle guidance.
    if (!_lobbyActive) return;
    _speakChoice(VoiceOverCue.chooseOne);
    _idlePrompts = 0;
    _restartIdleTimer();
  }

  /// Opens the Star Shop. Child mode stays locked — the shop is the child's
  /// own screen, not a parent one, so it needs no verification.
  void _openStarShop() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const StarShopScreen()),
    );
  }

  Future<void> _exitToParent() async {
    final verified = await ParentVerificationDialog.show(context);
    if (verified && mounted) {
      Navigator.of(context).pop();
    }
  }

  IconData _iconForCategory(SkillCategory cat) {
    switch (cat) {
      case SkillCategory.playSkills:
        return Icons.extension_rounded;
      case SkillCategory.communication:
        return Icons.record_voice_over_rounded;
      case SkillCategory.socialInteraction:
        return Icons.people_rounded;
    }
  }

  List<Color> _gradientForCategory(SkillCategory cat) {
    switch (cat) {
      case SkillCategory.playSkills:
        return const [Color(0xFF9FD3B8), Color(0xFFABD2F0)]; // sage → sky
      case SkillCategory.communication:
        return const [
          Color(0xFFC7B4EC),
          Color(0xFFFBE49A),
        ]; // lavender → butter
      case SkillCategory.socialInteraction:
        return const [Color(0xFFABD2F0), Color(0xFFF6C6B4)]; // sky → peach
    }
  }

  List<GameEntry> _gamesFor(SkillCategory cat) =>
      GameRegistry.gamesForCategory(
        cat,
      ).where((g) => GameLauncher.supportedGameIds.contains(g.id)).toList();

  @override
  Widget build(BuildContext context) {
    final palette = context.watch<ChildProvider>().activePalette;
    // Watched so difficulty chips refresh when the AI result or the parent's
    // override changes.
    final level = context.watch<AssessmentProvider>().recommendedLevel;
    context.watch<ChildProvider>().difficultyOverride;

    // My Path is a scene, not a row on the lobby: when it is open the world
    // fills the whole body so the header and mascot sit on the same sky. The
    // scene is decoration, so the lowest graphics tier — which exists to cut
    // GPU and sensory load — drops it and falls back to the lobby gradient.
    final world = context.watch<ChildProvider>().activeWorldStyle;
    final showScene =
        _viewingPath &&
        world.hasBackdrop &&
        context.watch<ChildProvider>().graphicsQuality != GraphicsQuality.low;

    return Scaffold(
      body: Container(
        decoration:
            showScene ? null : BoxDecoration(gradient: palette.gameBackground),
        child: Stack(
          key: _rootStackKey,
          fit: StackFit.expand,
          children: [
            if (showScene) WorldBackdrop(style: world),
            SafeArea(
              // Any touch counts as engagement for the guided-start idle timer.
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: _onUserInteraction,
                child: Stack(
                  key: _stackKey,
                  children: [
                    // The games row scrolls horizontally; if it moves while the
                    // hand is up, the hand moves with its card.
                    NotificationListener<ScrollNotification>(
                      onNotification: (_) {
                        _reanchorGuide();
                        return false;
                      },
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildHeader(palette, level),
                          Expanded(
                            child:
                                !_inView
                                    ? _buildCategoryButtons(palette)
                                    : _buildGamesRow(level, palette),
                          ),
                        ],
                      ),
                    ),
                    _buildMascotCorner(),
                    if (_guideOnScreen) ..._buildGuideLayer(),
                  ],
                ),
              ),
            ),
            // The door: the path view revealed through a window growing out of
            // the button. Drawn last so it covers the lobby beneath it.
            if (_doorActive && _doorFromRect != null) ...[
              // Taps are swallowed for the whole animation. The clip means the
              // lobby is still reachable *outside* the window, and a second
              // button pressed mid-transition would leave the view in a state
              // the door never accounted for.
              const Positioned.fill(
                child: AbsorbPointer(child: SizedBox.expand()),
              ),
              Positioned.fill(
                child: ListenableBuilder(
                  listenable: _doorController,
                  // The path view is built **once** per lobby build and handed
                  // to the builder, not rebuilt inside it. Building it per
                  // frame meant re-running the backdrop, header and the whole
                  // level map sixty times a second, which is what made the
                  // door stutter. The RepaintBoundary takes the rest: the
                  // finished scene is rasterised once and every later frame
                  // only re-composites it under a new clip.
                  child: RepaintBoundary(
                    child: _buildPathPresentation(palette, level, world),
                  ),
                  builder: (context, child) {
                    final raw = _doorController.value;
                    // Reduced motion: window pinned open, fade carries the
                    // whole change. Otherwise the window grows and the fade is
                    // just a soft first frame.
                    final t = _doorFadeOnly ? 1.0 : _doorCurve.transform(raw);
                    final opacity =
                        _doorFadeOnly
                            ? raw
                            : (raw / _doorFadeFraction).clamp(0.0, 1.0);
                    return Opacity(
                      // Free once opaque — RenderOpacity skips the layer at 1.0
                      // — so the cross-fade costs nothing after it finishes.
                      opacity: opacity,
                      child: ClipRRect(
                        clipper: _DoorClipper(
                          from: _doorFromRect!,
                          progress: t,
                        ),
                        child: child,
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// The path view exactly as it looks once open — scene, header and map.
  ///
  /// Built standalone so the door animation can reveal the finished view while
  /// [_viewingPath] is still false and the lobby is still mounted underneath.
  /// Because the door's last frame is this same widget at full size, the state
  /// swap at the end of the animation changes nothing on screen.
  Widget _buildPathPresentation(
    GamePalette palette,
    int level,
    WorldStyle world,
  ) {
    final sceneOn =
        world.hasBackdrop &&
        context.read<ChildProvider>().graphicsQuality != GraphicsQuality.low;
    return DecoratedBox(
      // Opaque either way: the door must not let the lobby show through.
      decoration:
          sceneOn
              ? const BoxDecoration(color: AppColors.background)
              : BoxDecoration(gradient: palette.gameBackground),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (sceneOn) WorldBackdrop(style: world),
          SafeArea(
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(palette, level, asPath: true),
                    Expanded(child: _buildPathRow()),
                  ],
                ),
                _buildMascotCorner(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// BPS keeps the child company from the corner, waving hello on entry and
  /// whenever the guidance voice speaks.
  Widget _buildMascotCorner() {
    return Positioned(
      left: AppSpacing.md,
      bottom: AppSpacing.sm,
      child: IgnorePointer(
        child: ListenableBuilder(
          listenable: _mascot,
          builder:
              (context, _) => Mascot(
                height: 92,
                pose: _mascot.pose,
                gesture: _mascot.gesture,
                gestureTrigger: _mascot.tick,
                semanticLabel: 'BPS the mascot',
              ),
        ),
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────

  /// [asPath] forces the open-My-Path rendering regardless of current state,
  /// so the door animation can show the header it is travelling towards.
  Widget _buildHeader(GamePalette palette, int level, {bool asPath = false}) {
    final title =
        (_viewingPath || asPath)
            ? 'My Path'
            : _viewingAll
            ? 'All Games'
            : (_selected?.displayName ?? 'Choose a Game');
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          if (_inView || asPath)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Material(
                color: AppColors.white.withAlpha(200),
                shape: const CircleBorder(),
                child: IconButton(
                  // My Path leaves the way it arrived — the door closes back
                  // into its button. The category and All rows are a plain
                  // swap, as they were.
                  onPressed:
                      () =>
                          (_viewingPath || asPath)
                              ? _exitPath()
                              : setState(() {
                                _selected = null;
                                _viewingAll = false;
                              }),
                  icon: Icon(Icons.arrow_back_rounded, color: palette.primary),
                  tooltip: 'Back',
                ),
              ),
            ),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.white.withAlpha(235),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      title,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.displayMedium.copyWith(
                        color: palette.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: palette.primary.withAlpha(30),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'Level $level',
                      style: AppTextStyles.labelSmall.copyWith(
                        color: palette.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          // The shop lives here and at the end of a session — never inside a
          // game (STAR-G3). A child who can reach it mid-play tends to play
          // for the shop rather than for the game, which is the failure mode
          // this whole feature is shaped to avoid.
          //
          // Hidden entirely when the parent turned it off (STAR-G2). Stars go
          // on accruing regardless, so turning it back on later costs nothing.
          if (context.watch<ChildProvider>().shopEnabled)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Material(
              color: AppColors.white.withAlpha(200),
              shape: const CircleBorder(),
              child: IconButton(
                onPressed: _openStarShop,
                icon: Icon(Icons.checkroom_rounded, color: palette.primary),
                tooltip: 'My Costumes',
              ),
            ),
          ),
          Material(
            color: AppColors.white.withAlpha(200),
            shape: const CircleBorder(),
            child: IconButton(
              onPressed: _exitToParent,
              icon: Icon(Icons.lock_rounded, color: palette.primary),
              tooltip: 'Exit (parent only)',
            ),
          ),
        ],
      ),
    );
  }

  // ── Step 1: category buttons ───────────────────────────────────────────

  /// The world shown inside the "My Path" button, or null when there is no
  /// scene to show (Classic, or the lowest graphics tier).
  Widget? _lobbyWorldPreview() {
    final childProv = context.read<ChildProvider>();
    final world = childProv.activeWorldStyle;
    if (!world.hasBackdrop ||
        childProv.graphicsQuality == GraphicsQuality.low) {
      return null;
    }
    return WorldBackdrop(style: world, borderRadius: 24);
  }

  Widget _buildCategoryButtons(GamePalette palette) {
    final path = _learningPath();
    final buttons = <Widget>[
      // AI-recommended path first — the child's suggested starting point.
      // Keys anchor the guided-start pointing hand.
      if (path.isNotEmpty)
        KeyedSubtree(
          key: _pathButtonKey,
          child: _CategoryButton(
            label: 'My Path',
            icon: Icons.route_rounded,
            gradient: const [
              Color(0xFFC7B4EC),
              Color(0xFFA9E3CC),
            ], // lavender → mint
            count: path.length,
            // The button wears the world it leads into, so the door reads as
            // stepping through rather than the screen changing.
            backdrop: _lobbyWorldPreview(),
            onTap: _enterPath,
          ),
        ),
      KeyedSubtree(
        key: _allButtonKey,
        child: _CategoryButton(
          label: 'All',
          icon: Icons.apps_rounded,
          gradient: const [
            Color(0xFFFBD89A),
            Color(0xFFA9E3CC),
          ], // amber → mint
          count: _allGames().length,
          onTap: () => _enterView(() => _viewingAll = true),
        ),
      ),
      for (final cat in _categoryOrder)
        _CategoryButton(
          label: cat.displayName,
          icon: _iconForCategory(cat),
          gradient: _gradientForCategory(cat),
          count: _gamesFor(cat).length,
          onTap: () => _enterView(() => _selected = cat),
        ),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) => _categoryRow(buttons, constraints),
      ),
    );
  }

  /// Lays the category cards out as compact tiles rather than full-height
  /// columns.
  ///
  /// This row sits inside an [Expanded], which hands its child a *tight*
  /// height — so a plain `Row` of `Expanded` children stretched every card
  /// from the header to the bottom of the screen, and on a 1152x720 tablet
  /// that left the icon and label marooned in the middle of a very tall panel.
  /// Each card is given its own bounded box instead, and the group is centred
  /// in whatever space is left.
  ///
  /// Sizes come from the incoming constraints, never from the device: the
  /// cards take an equal share of the available width within
  /// [_categoryCardMinWidth]..[_categoryCardMaxWidth], and their height
  /// follows that width at a fixed ratio within [_categoryCardMinHeight]..
  /// [_categoryCardMaxHeight] — shrinking below that only when the viewport
  /// itself is shorter. When the share would fall under the minimum the row
  /// scrolls sideways instead of squeezing the cards.
  Widget _categoryRow(List<Widget> buttons, BoxConstraints constraints) {
    const gap = AppSpacing.md;
    final gaps = gap * (buttons.length - 1);

    final share = (constraints.maxWidth - gaps) / buttons.length;
    final cardWidth = share.clamp(_categoryCardMinWidth, _categoryCardMaxWidth);
    final cardHeight = (cardWidth * _categoryCardHeightRatio)
        .clamp(_categoryCardMinHeight, _categoryCardMaxHeight)
        // A short landscape phone gets shorter cards, not an overflow.
        .clamp(0.0, constraints.maxHeight);

    final row = Row(
      mainAxisSize: MainAxisSize.min,
      // Cards size themselves; nothing stretches to the tallest sibling.
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (var i = 0; i < buttons.length; i++) ...[
          SizedBox(width: cardWidth, height: cardHeight, child: buttons[i]),
          if (i != buttons.length - 1) const SizedBox(width: gap),
        ],
      ],
    );

    final fits = cardWidth * buttons.length + gaps <= constraints.maxWidth;
    return Center(
      child:
          fits
              ? row
              : SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: row,
              ),
    );
  }

  // ── Step 2: the category's games ───────────────────────────────────────

  Widget _buildGamesRow(int fallbackLevel, GamePalette palette) {
    if (_viewingPath) return _buildPathRow();

    final games = _viewingAll ? _allGames() : _gamesFor(_selected!);
    if (games.isEmpty) {
      return Center(
        child: Text(
          'No games yet for this category.',
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.mutedForeground,
          ),
        ),
      );
    }

    /// Builds card [i], keyed on the first so the guided-start hand has
    /// something to point at.
    Widget cardAt(int i) {
      // Per-game difficulty: parent override → AI per-area → fallback.
      final difficulty = GameLauncher.difficultyFor(
        context,
        games[i],
        fallback: fallbackLevel,
      );
      final card = _GameCard(
        entry: games[i],
        difficulty: difficulty,
        onTap: () => _launch(games[i].id, difficulty),
      );
      return i == 0 ? KeyedSubtree(key: _guideCardKey, child: card) : card;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: LayoutBuilder(
        builder:
            (context, constraints) =>
                _usesGameGrid(constraints)
                    ? _gamesGrid(games.length, cardAt, constraints)
                    : _gamesScrollRow(games.length, cardAt, constraints),
      ),
    );
  }

  /// Tablets get the wrapped grid; phones keep the single scrolling row.
  ///
  /// A phone's row is already the right shape for the screen — one line of
  /// cards, swiped sideways — and a grid there would only shrink them. The
  /// height check keeps a short landscape phone (which is wide enough to look
  /// like a tablet) on the row as well.
  bool _usesGameGrid(BoxConstraints constraints) =>
      isTabletFormFactor &&
      constraints.maxHeight >= _kGameCardHeight * 2 + AppSpacing.md;

  /// Phones: one horizontal row of cards, vertically centred.
  ///
  /// The bare `SizedBox` here used to be handed a *tight* height by the
  /// `Expanded` above it, which a `SizedBox` cannot shrink out of — so its 200
  /// was ignored and every card ran the full height of the screen. Centring
  /// first makes the height loose, and only then does the box bound the row.
  Widget _gamesScrollRow(
    int count,
    Widget Function(int) cardAt,
    BoxConstraints constraints,
  ) {
    return Center(
      child: SizedBox(
        height: _kGameCardHeight.clamp(0.0, constraints.maxHeight),
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          itemCount: count,
          separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.md),
          itemBuilder: (_, i) => cardAt(i),
        ),
      ),
    );
  }

  /// Tablets: the same cards wrapped into two or three rows and scrolled
  /// vertically, so a full category is taken in at a glance instead of being
  /// swiped past one card at a time.
  ///
  /// The column count is whatever fits at the card's natural width, which on a
  /// 1152dp tablet is five — turning twelve games into three rows and seven
  /// into two. The grid shrink-wraps, so a short category (five games, one row)
  /// stays centred rather than clinging to the top, and only scrolls once the
  /// rows genuinely overflow.
  Widget _gamesGrid(
    int count,
    Widget Function(int) cardAt,
    BoxConstraints constraints,
  ) {
    const gap = AppSpacing.md;
    final available = constraints.maxWidth - AppSpacing.lg * 2;
    final columns = ((available + gap) ~/ (_kGameCardWidth + gap)).clamp(
      1,
      count,
    );
    final gridWidth = columns * _kGameCardWidth + (columns - 1) * gap;

    return Center(
      child: SizedBox(
        width: gridWidth,
        child: GridView.builder(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          itemCount: count,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: gap,
            crossAxisSpacing: gap,
            childAspectRatio: _kGameCardWidth / _kGameCardHeight,
          ),
          itemBuilder: (_, i) => cardAt(i),
        ),
      ),
    );
  }

  /// The AI-recommended path: same cards, in recommended order, numbered,
  /// each starting at the difficulty the assessment suggested. Steps unlock
  /// sequentially — the child must finish a game to open the next one.
  Widget _buildPathRow() {
    final path = _learningPath();
    if (path.isEmpty) {
      return Center(
        child: Text(
          'Finish an assessment to get your path!',
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.mutedForeground,
          ),
        ),
      );
    }
    // Watched so cards re-render (unlock) when a game completes.
    final completed = context.watch<AssessmentProvider>().pathCompletedGameIds;
    // The guided-start hand points at the step the child should play next:
    // the first incomplete step (always unlocked by the sequence rule).
    var guideIndex = path.indexWhere((e) => !completed.contains(e.game.id));
    if (guideIndex < 0) guideIndex = 0;
    final childProv = context.watch<ChildProvider>();
    return PathMapView(
      path: path,
      completedGameIds: completed,
      // The parent's manual override still wins over the path level.
      difficultyOverride: childProv.difficultyOverride,
      style: childProv.activeWorldStyle,
      currentStepKey: _guideCardKey,
      onLaunch: _launch,
    );
  }
}

/// One of the three large skill-category buttons (step 1).
class _CategoryButton extends StatelessWidget {
  const _CategoryButton({
    required this.label,
    required this.icon,
    required this.gradient,
    required this.count,
    required this.onTap,
    this.backdrop,
  });

  final String label;
  final IconData icon;
  final List<Color> gradient;
  final int count;
  final VoidCallback onTap;

  /// A scene painted inside the button in place of [gradient] — used by "My
  /// Path" to show the world it opens into. Text flips to light when set.
  final Widget? backdrop;

  @override
  Widget build(BuildContext context) {
    final onScene = backdrop != null;
    final labelColor = onScene ? AppColors.white : AppColors.foreground;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            // A scene replaces the gradient rather than layering over it.
            gradient:
                onScene
                    ? null
                    : LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: gradient,
                    ),
            boxShadow: [
              BoxShadow(
                color: gradient.first.withAlpha(120),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Stack(
            fit: StackFit.passthrough,
            children: [
              if (onScene)
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: backdrop,
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: AppColors.white.withAlpha(200),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        icon,
                        color: AppColors.primaryPurple,
                        size: 38,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.titleLarge.copyWith(
                        color: labelColor,
                        fontWeight: FontWeight.w800,
                        shadows:
                            onScene
                                ? const [
                                  Shadow(
                                    color: Color(0x99000000),
                                    blurRadius: 5,
                                  ),
                                ]
                                : null,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$count ${count == 1 ? 'game' : 'games'}',
                      style: AppTextStyles.bodySmall.copyWith(
                        color:
                            onScene
                                ? AppColors.white.withValues(alpha: 0.85)
                                : AppColors.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Clips to a rounded window between [from] and the full canvas.
///
/// The child is always laid out at full size and only the *window* changes, so
/// nothing inside scales or reflows during the animation — the path view is
/// uncovered rather than zoomed, which is what makes it read as a door. Driven
/// in reverse it is the same door closing, frame for frame.
/// A rounded rect rather than a [Path]: `clipRRect` is a fast path on the
/// raster thread, while a general `clipPath` is not — and the door redraws this
/// clip on every frame.
class _DoorClipper extends CustomClipper<RRect> {
  const _DoorClipper({required this.from, required this.progress});

  final Rect from;

  /// 0 = just the button's rect, 1 = the whole canvas.
  final double progress;

  @override
  RRect getClip(Size size) {
    final full = Rect.fromLTWH(0, 0, size.width, size.height);
    final rect = Rect.lerp(from, full, progress)!;
    // Corners open out as the window grows, ending square at the screen edge.
    final radius = 24 * (1 - progress);
    return RRect.fromRectAndRadius(rect, Radius.circular(radius));
  }

  @override
  bool shouldReclip(_DoorClipper oldClipper) =>
      oldClipper.from != from || oldClipper.progress != progress;
}

/// The gentle pre-limit warning (AUM-162): a small pill that fades in at the
/// top of the screen — above the lobby or whatever game is open — sits
/// quietly, and is withdrawn a few seconds later by the lobby.
///
/// Deliberately calm: soft colours, no sound, no motion beyond one slow fade
/// (skipped entirely under reduced motion), and it never intercepts a touch.
/// Its only job is to make the rest screen that follows unsurprising.
class _BreakSoonNotice extends StatefulWidget {
  const _BreakSoonNotice({required this.reduced});

  final bool reduced;

  @override
  State<_BreakSoonNotice> createState() => _BreakSoonNoticeState();
}

class _BreakSoonNoticeState extends State<_BreakSoonNotice> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: IgnorePointer(
          child: AnimatedOpacity(
            opacity: _visible ? 1 : 0,
            duration:
                widget.reduced
                    ? Duration.zero
                    : const Duration(milliseconds: 700),
            curve: Curves.easeInOut,
            child: Material(
              color: Colors.transparent,
              child: Container(
                margin: const EdgeInsets.only(top: AppSpacing.md),
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppColors.white.withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.bedtime_rounded,
                      size: 20,
                      color: AppColors.primaryPurple,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Almost time for a break',
                      style: AppTextStyles.titleMedium.copyWith(
                        color: AppColors.foreground,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A game card shown in the horizontal row (step 2).
///
/// Picture first, name on a white strip underneath, and nothing else but the
/// difficulty pill: the child using this row cannot read, so the game's own
/// logo tile is what they actually choose by. The registry's one-line
/// description is deliberately not shown here — it is written for the parent,
/// and it survives on game_lab's launcher, where a reader is the audience.
///
/// Used by the category and "All" rows. My Path no longer uses this — it
/// renders steps as platforms via [PathMapView].
class _GameCard extends StatelessWidget {
  const _GameCard({
    required this.entry,
    required this.difficulty,
    required this.onTap,
  });

  final GameEntry entry;

  /// 1 Easy / 2 Medium / 3 Hard — from the child's per-area AI level.
  final int difficulty;

  final VoidCallback? onTap;

  static const _tierLabels = {1: 'Easy', 2: 'Medium', 3: 'Hard'};
  static const _tierColors = {
    1: Color(0xFF6FAE97), // sage — gentle
    2: Color(0xFFDD9B4A), // amber — moderate
    3: Color(0xFFC96B6B), // clay — challenge
  };

  @override
  Widget build(BuildContext context) {
    const radius = 22.0;
    final tier = _tierLabels[difficulty] ?? 'Medium';
    return SizedBox(
      // Sized by the grid on a tablet; this is the width the phone row uses.
      width: _kGameCardWidth,
      // One node for the whole card. The logo's semanticLabel and the name
      // strip underneath both carried entry.name, so TalkBack read every card
      // twice ("Match It … Match It"). Merged here into a single button that
      // also says which difficulty it will start at.
      child: Semantics(
        button: true,
        label: '${entry.name}, $tier',
        excludeSemantics: true,
        onTap: onTap,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(radius),
            onTap: onTap,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(radius),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: entry.gradientColors,
                ),
                boxShadow: [
                  BoxShadow(
                    color: entry.gradientColors.first.withAlpha(90),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              // Clipped so the name strip's straight top edge can meet the
              // card's rounded corners without a seam.
              child: ClipRRect(
                borderRadius: BorderRadius.circular(radius),
                child: Column(
                  children: [
                    Expanded(
                      child: Stack(
                        children: [
                          // Inset at the top so the difficulty pill sits beside
                          // the artwork rather than on top of it.
                          Padding(
                            padding: const EdgeInsets.only(top: 20),
                            child: Center(
                              child: GameLogo(
                                asset: entry.logoAsset,
                                size: 104,
                                fallbackIcon: entry.icon,
                                fallbackColor: AppColors.primaryPurple,
                                semanticLabel: entry.name,
                              ),
                            ),
                          ),
                          // Per-game difficulty tier from the child's AI level.
                          Positioned(
                            top: 10,
                            right: 10,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.white.withAlpha(225),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                tier,
                                style: AppTextStyles.labelSmall.copyWith(
                                  color:
                                      _tierColors[difficulty] ?? _tierColors[2],
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: double.infinity,
                      // Fixed to two lines' worth so the strips — and therefore
                      // the artwork above them — line up across the row, whether
                      // a game's name wraps or not.
                      height: 62,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      color: AppColors.white.withAlpha(240),
                      child: Text(
                        entry.name,
                        textAlign: TextAlign.center,
                        style: AppTextStyles.titleLarge.copyWith(
                          color: AppColors.foreground,
                          fontWeight: FontWeight.w800,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
