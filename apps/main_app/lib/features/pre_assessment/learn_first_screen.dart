import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:game_core/game_core.dart';
import 'package:provider/provider.dart';
import 'package:shared_audio/shared_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../dev/developer_automation_registry.dart';
import '../../providers/child_provider.dart';

/// "Let's learn first" — a short, unscored familiarisation step that runs
/// before the pre-assessment's first game, and again, identically, before the
/// post-assessment's.
///
/// Suggested by the SPED teachers and the panel. It protects what the
/// assessment measures: Do What I Say says "Tap the *red* *star*", so a child
/// who has never heard the word "purple" fails a trial on vocabulary rather
/// than on following an instruction. Here the child hears every colour and
/// shape word the assessment games use, puts a colour and a shape together,
/// and tries the two ways the games are played — a tap and a drag.
///
/// Four rules keep it familiarisation rather than coaching:
///
/// * **Nothing is scored.** There is no right answer on any page; touching a
///   picture only names it.
/// * **The content is fixed.** Every child sees the same pages in the same
///   order, so the step cannot be tuned to a child's weak spots.
/// * **It is symmetric.** The same step runs before the post-assessment, so a
///   pre → post change cannot be explained by it.
/// * **It never blocks.** The grown-up can skip it at any time, and the Next
///   arrow is always live — a child who will not touch anything still reaches
///   the games.
///
/// Whether it was finished or skipped, and how long it took, is kept in
/// [LearnFirstLog] so it can be reported alongside the results.
class LearnFirstScreen extends StatefulWidget {
  const LearnFirstScreen({
    super.key,
    required this.assessmentType,
    this.voiceOverFactory,
  });

  /// `pre` or `post` — which assessment this step is opening.
  final String assessmentType;

  /// Builds the narrator. Injectable so a widget test can observe the words
  /// spoken without a platform audio player.
  final VoiceOverService Function(BuildContext context)? voiceOverFactory;

  /// Test seam for flows that reach this screen through app navigation and so
  /// cannot pass [voiceOverFactory] themselves. Used when [voiceOverFactory]
  /// is null.
  @visibleForTesting
  static VoiceOverService Function(BuildContext context)? debugVoiceOverFactory;

  /// Pushes the step and returns how it went. A route popped by the system
  /// (back gesture) counts as skipped.
  static Future<LearnFirstOutcome> show(
    BuildContext context, {
    required String assessmentType,
    VoiceOverService Function(BuildContext context)? voiceOverFactory,
  }) async {
    final started = DateTime.now();
    final outcome = await Navigator.of(context).push<LearnFirstOutcome>(
      MaterialPageRoute(
        builder:
            (_) => LearnFirstScreen(
              assessmentType: assessmentType,
              voiceOverFactory: voiceOverFactory,
            ),
      ),
    );
    return outcome ??
        LearnFirstOutcome(
          completed: false,
          duration: DateTime.now().difference(started),
          pagesSeen: 1,
          wordsHeard: 0,
        );
  }

  @override
  State<LearnFirstScreen> createState() => _LearnFirstScreenState();
}

/// How the familiarisation step went, for the log.
class LearnFirstOutcome {
  const LearnFirstOutcome({
    required this.completed,
    required this.duration,
    required this.pagesSeen,
    required this.wordsHeard,
  });

  /// True when the child reached the end; false when the grown-up skipped.
  final bool completed;
  final Duration duration;

  /// How many of the four pages were shown.
  final int pagesSeen;

  /// How many distinct words the child chose to hear.
  final int wordsHeard;

  Map<String, dynamic> toJson() => {
    'completed': completed,
    'duration_ms': duration.inMilliseconds,
    'pages_seen': pagesSeen,
    'words_heard': wordsHeard,
  };
}

/// One picture the child can touch to hear its name.
class _Word {
  const _Word(this.id, this.cue, {required this.color, this.shape});

  final String id;
  final VoiceOverCue cue;
  final Color color;

  /// Null draws a plain colour swatch.
  final String? shape;
}

enum _Page { colours, shapes, together, howToPlay }

class _LearnFirstScreenState extends State<LearnFirstScreen> {
  // The exact palette Do What I Say uses, so "red" here is the red there.
  static const _red = Color(0xFFE53935);
  static const _blue = Color(0xFF1E88E5);
  static const _green = Color(0xFF43A047);
  static const _yellow = Color(0xFFFDD835);
  static const _purple = Color(0xFF8E24AA);
  static const _orange = Color(0xFFFB8C00);

  /// Shapes are shown in one neutral colour so the only thing that changes
  /// between them is the shape.
  static const _shapeInk = Color(0xFF5C6BC0);

  static const _colours = [
    _Word('red', VoiceOverCue.colorRed, color: _red),
    _Word('blue', VoiceOverCue.colorBlue, color: _blue),
    _Word('green', VoiceOverCue.colorGreen, color: _green),
    _Word('yellow', VoiceOverCue.colorYellow, color: _yellow),
    _Word('purple', VoiceOverCue.colorPurple, color: _purple),
    _Word('orange', VoiceOverCue.colorOrange, color: _orange),
  ];

  static const _shapes = [
    _Word(
      'circle',
      VoiceOverCue.shapeCircle,
      color: _shapeInk,
      shape: 'circle',
    ),
    _Word('star', VoiceOverCue.shapeStar, color: _shapeInk, shape: 'star'),
    _Word(
      'triangle',
      VoiceOverCue.shapeTriangle,
      color: _shapeInk,
      shape: 'triangle',
    ),
    _Word(
      'diamond',
      VoiceOverCue.shapeDiamond,
      color: _shapeInk,
      shape: 'diamond',
    ),
    _Word('heart', VoiceOverCue.shapeHeart, color: _shapeInk, shape: 'heart'),
  ];

  static const _together = [
    _Word('red_star', VoiceOverCue.phraseRedStar, color: _red, shape: 'star'),
    _Word(
      'blue_circle',
      VoiceOverCue.phraseBlueCircle,
      color: _blue,
      shape: 'circle',
    ),
    _Word(
      'yellow_triangle',
      VoiceOverCue.phraseYellowTriangle,
      color: _yellow,
      shape: 'triangle',
    ),
    _Word(
      'purple_heart',
      VoiceOverCue.phrasePurpleHeart,
      color: _purple,
      shape: 'heart',
    ),
  ];

  late final VoiceOverService _voice;
  final DateTime _startedAt = DateTime.now();
  _Page _page = _Page.colours;
  int _pagesSeen = 1;
  final Set<String> _heard = {};
  bool _tapDone = false;
  bool _dragDone = false;
  bool _finished = false;
  DeveloperFlowSession? _devFlow;

  @override
  void initState() {
    super.initState();
    _voice = (widget.voiceOverFactory ??
        LearnFirstScreen.debugVoiceOverFactory ??
        _defaultVoice)(context);
    // Developer auto-play drives the assessment through registered flows;
    // this step registers as one whose "launch" is simply to finish, so an
    // automated run passes straight through it.
    _devFlow = DeveloperAutomationRegistry.instance.registerFlow(
      flowLabel: 'Let\'s learn first',
      gameIndex: 0,
      gameCount: 1,
      launchNow: () => _finish(completed: false),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _introducePage());
  }

  static VoiceOverService _defaultVoice(BuildContext context) {
    final child = context.read<ChildProvider>();
    return VoiceOverService(
      languageCode: child.voiceAssetFolder,
      speed: child.voicePlaybackRate,
    );
  }

  @override
  void dispose() {
    DeveloperAutomationRegistry.instance.unregister(_devFlow);
    _voice.dispose();
    super.dispose();
  }

  /// One short spoken line as each page opens, so a pre-reader knows what to
  /// do without anyone reading the screen to them.
  void _introducePage() {
    if (!mounted) return;
    final cue = switch (_page) {
      _Page.colours ||
      _Page.shapes ||
      _Page.together => VoiceOverCue.touchThePicture,
      _Page.howToPlay => _tapDone ? VoiceOverCue.dragIt : VoiceOverCue.tapHere,
    };
    unawaited(_voice.play(cue, skipDebounce: true));
  }

  void _say(_Word word) {
    setState(() => _heard.add(word.id));
    unawaited(_voice.play(word.cue, skipDebounce: true));
  }

  void _next() {
    if (_page == _Page.howToPlay) {
      _finish(completed: true);
      return;
    }
    setState(() {
      _page = _Page.values[_page.index + 1];
      _pagesSeen = _page.index + 1;
    });
    _introducePage();
  }

  void _finish({required bool completed}) {
    if (_finished || !mounted) return;
    _finished = true;
    unawaited(_voice.stop());
    Navigator.of(context).pop(
      LearnFirstOutcome(
        completed: completed,
        duration: DateTime.now().difference(_startedAt),
        pagesSeen: _pagesSeen,
        wordsHeard: _heard.length,
      ),
    );
  }

  void _onPracticeTap() {
    if (_tapDone) return;
    setState(() => _tapDone = true);
    unawaited(_voice.playCorrectPraise());
    // Then invite the drag, a beat after the praise.
    Future<void>.delayed(const Duration(milliseconds: 1400), () {
      if (mounted && !_dragDone && _page == _Page.howToPlay) {
        unawaited(_voice.play(VoiceOverCue.dragIt, skipDebounce: true));
      }
    });
  }

  void _onPracticeDrop() {
    if (_dragDone) return;
    setState(() => _dragDone = true);
    unawaited(_voice.playCorrectPraise());
  }

  List<_Word> get _pageWords => switch (_page) {
    _Page.colours => _colours,
    _Page.shapes => _shapes,
    _Page.together => _together,
    _Page.howToPlay => const [],
  };

  /// Whether the child has done everything this page offers — used only to
  /// make the Next arrow pulse, never to hold it back.
  bool get _pageExplored =>
      _page == _Page.howToPlay
          ? _tapDone && _dragDone
          : _pageWords.every((w) => _heard.contains(w.id));

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _finish(completed: false);
      },
      child: Scaffold(
        backgroundColor: AppColors.lavenderLight,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              children: [
                _buildTopBar(),
                Expanded(
                  child: Center(
                    child:
                        _page == _Page.howToPlay
                            ? _buildHowToPlay()
                            : _buildWords(_pageWords),
                  ),
                ),
                Align(
                  alignment: Alignment.bottomRight,
                  child: _NextButton(
                    key: const Key('learnFirst.next'),
                    isLast: _page == _Page.howToPlay,
                    highlight: _pageExplored,
                    onPressed: _next,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    final title = switch (_page) {
      _Page.colours => 'Colours',
      _Page.shapes => 'Shapes',
      _Page.together => 'Colours and shapes',
      _Page.howToPlay => 'How to play',
    };
    return Row(
      children: [
        for (final p in _Page.values)
          Container(
            width: 12,
            height: 12,
            margin: const EdgeInsets.only(right: 6),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color:
                  p.index <= _page.index
                      ? AppColors.primaryPurple
                      : AppColors.white,
              border: Border.all(color: AppColors.primaryPurple),
            ),
          ),
        const SizedBox(width: AppSpacing.sm),
        // For the grown-up; the child is guided by voice.
        Expanded(
          child: Text(
            'Let\'s learn first · $title',
            style: AppTextStyles.titleMedium.copyWith(
              color: AppColors.textPrimary,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        TextButton(
          key: const Key('learnFirst.skip'),
          onPressed: () => _finish(completed: false),
          child: const Text('Skip'),
        ),
      ],
    );
  }

  Widget _buildWords(List<_Word> words) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // As large as the space allows, capped so six still fit on a phone.
        final side = (constraints.maxHeight * 0.42).clamp(72.0, 150.0);
        return Wrap(
          alignment: WrapAlignment.center,
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            for (final word in words)
              _WordTile(
                key: Key('learnFirst.word.${word.id}'),
                word: word,
                size: side,
                heard: _heard.contains(word.id),
                onTap: () => _say(word),
              ),
          ],
        );
      },
    );
  }

  Widget _buildHowToPlay() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = (constraints.maxHeight * 0.45).clamp(72.0, 150.0);
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // Tap: one big star.
            _WordTile(
              key: const Key('learnFirst.practiceTap'),
              word: const _Word(
                'practice_tap',
                VoiceOverCue.tapHere,
                color: Color(0xFFFFB300),
                shape: 'star',
              ),
              size: side,
              heard: _tapDone,
              onTap: _onPracticeTap,
            ),
            // Drag: a card and the box it goes into.
            if (!_dragDone)
              Draggable<String>(
                key: const Key('learnFirst.practiceDrag'),
                data: 'practice',
                feedback: Material(
                  type: MaterialType.transparency,
                  child: _ShapeSwatch(
                    color: _orange,
                    shape: 'circle',
                    size: side * 0.8,
                  ),
                ),
                childWhenDragging: SizedBox.square(dimension: side * 0.8),
                child: _ShapeSwatch(
                  color: _orange,
                  shape: 'circle',
                  size: side * 0.8,
                ),
              )
            else
              SizedBox.square(dimension: side * 0.8),
            DragTarget<String>(
              key: const Key('learnFirst.practiceBox'),
              onAcceptWithDetails: (_) => _onPracticeDrop(),
              builder: (context, candidate, _) {
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: side,
                  height: side,
                  decoration: BoxDecoration(
                    color:
                        candidate.isNotEmpty
                            ? AppColors.mint.withValues(alpha: 0.35)
                            : AppColors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: AppColors.primaryPurple,
                      width: 3,
                    ),
                  ),
                  child:
                      _dragDone
                          ? Center(
                            child: _ShapeSwatch(
                              color: _orange,
                              shape: 'circle',
                              size: side * 0.6,
                            ),
                          )
                          : const Icon(
                            Icons.move_to_inbox_rounded,
                            size: 48,
                            color: AppColors.primaryPurple,
                          ),
                );
              },
            ),
          ],
        );
      },
    );
  }
}

class _WordTile extends StatefulWidget {
  const _WordTile({
    super.key,
    required this.word,
    required this.size,
    required this.heard,
    required this.onTap,
  });

  final _Word word;
  final double size;
  final bool heard;
  final VoidCallback onTap;

  @override
  State<_WordTile> createState() => _WordTileState();
}

class _WordTileState extends State<_WordTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.word.id.replaceAll('_', ' '),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) {
          setState(() => _pressed = false);
          widget.onTap();
        },
        child: AnimatedScale(
          scale: _pressed && !GameMotion.reduced ? 0.92 : 1.0,
          duration: const Duration(milliseconds: 90),
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: AppShadows.card,
              border: Border.all(
                color: widget.heard ? AppColors.primaryPurple : AppColors.white,
                width: 3,
              ),
            ),
            child: Center(
              child: _ShapeSwatch(
                color: widget.word.color,
                shape: widget.word.shape,
                size: widget.size * 0.72,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A painted shape, or a plain colour blob when [shape] is null.
class _ShapeSwatch extends StatelessWidget {
  const _ShapeSwatch({
    required this.color,
    required this.shape,
    required this.size,
  });

  final Color color;
  final String? shape;
  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _SwatchPainter(color: color, shape: shape ?? 'circle'),
    );
  }
}

class _SwatchPainter extends CustomPainter {
  const _SwatchPainter({required this.color, required this.shape});

  final Color color;
  final String shape;

  @override
  void paint(Canvas canvas, Size size) {
    ShapePainter3D.drawByName(
      canvas,
      shape,
      size.width / 2,
      size.height / 2,
      size.shortestSide * 0.45,
      color,
    );
  }

  @override
  bool shouldRepaint(_SwatchPainter old) =>
      old.color != color || old.shape != shape;
}

class _NextButton extends StatelessWidget {
  const _NextButton({
    super.key,
    required this.isLast,
    required this.highlight,
    required this.onPressed,
  });

  final bool isLast;

  /// Drawn brighter once the page has been explored — an invitation, not a
  /// gate: the button works either way.
  final bool highlight;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: highlight && !GameMotion.reduced ? 1.08 : 1.0,
      duration: const Duration(milliseconds: 250),
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor:
              highlight ? AppColors.primaryPurple : AppColors.lavender,
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
        ),
        onPressed: onPressed,
        icon: Icon(
          isLast ? Icons.play_arrow_rounded : Icons.arrow_forward_rounded,
          size: 32,
        ),
        label: Text(isLast ? 'Let\'s play!' : 'Next'),
      ),
    );
  }
}

/// Keeps, on this device, a record of each familiarisation step: which
/// assessment it opened, whether it was finished or skipped, and how long it
/// took. Reported with the results so the step is never invisible in the
/// data.
///
/// Device-local for now. The assessment-run tables have no column for it,
/// and adding one is a schema change on both the local and the cloud
/// database.
class LearnFirstLog {
  LearnFirstLog._();

  static final LearnFirstLog instance = LearnFirstLog._();

  static const _key = 'learn_first_log_v1';

  /// Oldest entries are dropped past this, so the log cannot grow forever.
  static const _maxEntries = 100;

  Future<void> record({
    required String childId,
    required String? assessmentRunId,
    required String assessmentType,
    required LearnFirstOutcome outcome,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final entries = prefs.getStringList(_key) ?? <String>[];
      entries.add(
        jsonEncode({
          'child_id': childId,
          'assessment_run_id': assessmentRunId,
          'assessment_type': assessmentType,
          'recorded_at': DateTime.now().toIso8601String(),
          ...outcome.toJson(),
        }),
      );
      while (entries.length > _maxEntries) {
        entries.removeAt(0);
      }
      await prefs.setStringList(_key, entries);
    } catch (e) {
      debugPrint('[LearnFirstLog] could not record: $e');
    }
  }

  /// Every recorded step for [childId], oldest first.
  Future<List<Map<String, dynamic>>> entriesFor(String childId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return [
        for (final raw in prefs.getStringList(_key) ?? const <String>[])
          if (jsonDecode(raw) case final Map<String, dynamic> e
              when e['child_id'] == childId)
            e,
      ];
    } catch (e) {
      debugPrint('[LearnFirstLog] could not read: $e');
      return const [];
    }
  }
}
