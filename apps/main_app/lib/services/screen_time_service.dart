import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Per-child daily screen-time limits with age-based recommendations.
///
/// Recommended limits follow AAP/WHO guidance (≤1 hour/day of high-quality
/// content for ages 2–5, none before age 2, "less is better" at 2 per WHO)
/// tightened for ASD learners, who research shows are especially prone to
/// excessive screen use. The app's own session design (short 3–7 minute
/// games) means a small daily budget still fits several learning sessions.
///
/// Usage is tracked while the child is in child mode (lobby + practice
/// games). Assessments are not counted — they are short, infrequent, and
/// parent-initiated.
///
/// A per-session limit (AUM-162) sits alongside the daily one. A *session*
/// begins when the child enters child mode ([startSession]), continues
/// across every game they open, and ends when the parent leaves child mode
/// ([endSession]) — see [startSession] for the full lifecycle. Daily and
/// session usage are tracked independently, and the stricter remaining
/// budget ([activeRemainingSeconds]) is what gates play. "No session limit"
/// leaves the daily limit fully in force.
class ScreenTimeService extends ChangeNotifier {
  ScreenTimeService._();

  static final ScreenTimeService instance = ScreenTimeService._();

  String? _childId;
  int? _limitMinutes; // null or 0 = no limit
  int _usedTodaySeconds = 0;
  int _bonusTodaySeconds = 0; // parent-granted extra time for today
  String _usageDate = '';

  int? _sessionLimitMinutes; // null or 0 = no session limit
  int _sessionUsedSeconds = 0;
  int _sessionBonusSeconds = 0; // parent-granted extra time, this session only
  bool _sessionActive = false;

  /// The child the *active session* belongs to. Distinct from [_childId]:
  /// the loaded child can change (another lobby, a switch, sign-out) while
  /// an async completion from the previous child's session is still in
  /// flight, and those completions must target the child they were started
  /// for — never whoever happens to be loaded by then.
  String? _sessionChildId;

  /// Ownership token for the active session, handed out by [startSession]
  /// and required by [endSessionOwned]. Null when no session is running.
  /// Every session gets a fresh token, so a late `dispose` from Child A's
  /// lobby holds a token that no longer matches once Child B has loaded or
  /// started a session — and its end call becomes a no-op.
  int? _sessionToken;
  int _tokenCounter = 0;

  /// Bumped on every [load] so async completions belonging to a superseded
  /// load (or a session started under one) can detect they are stale.
  int _loadEpoch = 0;

  /// How long a suspended session (the app was killed or restarted mid-play)
  /// stays resumable. Within this window [startSession] picks the old usage
  /// back up, so a quick restart cannot dodge the session limit; past it the
  /// child has genuinely stopped playing and the next session starts fresh.
  static const Duration sessionResumeWindow = Duration(minutes: 5);

  /// Remaining seconds at which [isNearLimit] turns on — the child gets one
  /// gentle heads-up about this long before the rest screen appears.
  static const int warnBeforeSeconds = 120;

  /// Injectable clock so tests can drive midnight rollovers and the
  /// stale-session window without waiting for them.
  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  static String _limitKey(String childId) => 'screen_time_limit_$childId';
  static String _usageKey(String childId) => 'screen_time_usage_$childId';
  static String _bonusKey(String childId) => 'screen_time_bonus_$childId';

  // Both end with '_$childId', so ChildProvider's per-child preference purge
  // (deleteChild) cleans them up with everything else the child owned.
  static String _sessionLimitKey(String childId) => 'session_limit_$childId';
  static String _sessionStateKey(String childId) => 'session_state_$childId';

  static String _today() {
    final now = clock();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  /// Formats [seconds] as a compact, parent-readable duration for the
  /// settings and dashboard status rows.
  ///
  /// Partial minutes stay visible ("4m 30s") rather than being rounded up to
  /// a figure the parent can see is wrong, and negative input clamps to zero
  /// so a remaining value never reads below "0s".
  static String formatDuration(int seconds) {
    final total = seconds < 0 ? 0 : seconds;
    final minutes = total ~/ 60;
    final rest = total % 60;
    if (minutes == 0) return '${rest}s';
    if (rest == 0) return '${minutes}m';
    return '${minutes}m ${rest}s';
  }

  /// Recommended daily limit (minutes) for a child's age, per AAP/WHO
  /// guidance adjusted conservatively for ASD:
  /// - age 2: 20 min (WHO: sedentary screen time at 2 — less is better)
  /// - ages 3–4: 30 min
  /// - age 5: 45 min
  /// - age 6+: 60 min (the AAP ≤1 hour ceiling)
  static int recommendedMinutesForAge(int ageYears) {
    if (ageYears <= 2) return 20;
    if (ageYears <= 4) return 30;
    if (ageYears == 5) return 45;
    return 60;
  }

  /// Loads limits + today's usage for [childId]. Call when the active child
  /// changes (and on app start).
  ///
  /// The previous child's numbers are dropped synchronously, before the
  /// storage read, so a dashboard rebuilding mid-switch never shows the old
  /// child's usage bar under the new child's name (AUM-160). The values read
  /// from storage are only applied when [childId] is still the loaded child,
  /// so two rapid switches cannot interleave.
  ///
  /// Loading also drops any in-memory session — load() only ever runs
  /// outside child mode (app start, dashboard, child switch), where nothing
  /// may be counting. A session that was *suspended* by an app restart is
  /// not resurrected here: [startSession] picks it up when child mode
  /// begins, so its staleness is judged at the moment play would actually
  /// resume rather than at app start.
  Future<void> load(String childId) async {
    _loadEpoch++;
    final epoch = _loadEpoch;
    // Loading deterministically ends any session still in memory: load()
    // only runs outside child mode, and the owning lobby's dispose may land
    // arbitrarily late — its token is stale from this line on, so the
    // outgoing child's persisted session is cleaned up here rather than
    // left to that race. A same-child reload keeps the persisted state so
    // a restart within the resume window can still pick it up.
    final endedSessionChildId =
        (_sessionActive && _sessionChildId != childId) ? _sessionChildId : null;
    _sessionToken = null;
    _sessionChildId = null;
    _childId = childId;
    _limitMinutes = null;
    _usedTodaySeconds = 0;
    _bonusTodaySeconds = 0;
    _sessionLimitMinutes = null;
    _sessionUsedSeconds = 0;
    _sessionBonusSeconds = 0;
    _sessionActive = false;
    _usageDate = _today();
    try {
      final prefs = await SharedPreferences.getInstance();
      if (endedSessionChildId != null) {
        await prefs.remove(_sessionStateKey(endedSessionChildId));
      }
      final limit = prefs.getInt(_limitKey(childId));
      final sessionLimit = prefs.getInt(_sessionLimitKey(childId));
      final used = _readDated(prefs.getString(_usageKey(childId)));
      final bonus = _readDated(prefs.getString(_bonusKey(childId)));
      // A later load() took over while the prefs read ran — its child owns
      // the service now; applying these values would mix the two children.
      if (_loadEpoch != epoch) return;
      _limitMinutes = (limit == null || limit <= 0) ? null : limit;
      _sessionLimitMinutes =
          (sessionLimit == null || sessionLimit <= 0) ? null : sessionLimit;

      // Usage/bonus are stored as 'yyyy-mm-dd:seconds' so they naturally
      // reset each day.
      _usedTodaySeconds = used;
      _bonusTodaySeconds = bonus;
      _usageDate = _today();
    } catch (e) {
      debugPrint('[ScreenTime] load failed: $e');
    }
    notifyListeners();
  }

  int _readDated(String? raw) {
    if (raw == null) return 0;
    final parts = raw.split(':');
    if (parts.length != 2 || parts[0] != _today()) return 0;
    return int.tryParse(parts[1]) ?? 0;
  }

  Future<void> _writeDated(String key, int seconds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, '${_today()}:$seconds');
  }

  /// The child the service is currently loaded for (null before [load]).
  String? get loadedChildId => _childId;

  /// The parent-configured daily limit in minutes; null = no limit set.
  int? get limitMinutes => _limitMinutes;

  /// Seconds of child-mode play used today.
  int get usedTodaySeconds => _usedTodaySeconds;

  /// Whether a daily limit is active for the loaded child.
  bool get limitEnabled => _limitMinutes != null;

  /// Remaining seconds today, or null when no daily limit is set.
  int? get remainingSeconds {
    final limit = _limitMinutes;
    if (limit == null) return null;
    final budget = limit * 60 + _bonusTodaySeconds;
    final left = budget - _usedTodaySeconds;
    return left < 0 ? 0 : left;
  }

  /// The parent-configured per-session limit in minutes; null = "No session
  /// limit".
  int? get sessionLimitMinutes => _sessionLimitMinutes;

  /// Whether a session limit is active for the loaded child.
  bool get sessionLimitEnabled => _sessionLimitMinutes != null;

  /// True between [startSession] and [endSession].
  bool get sessionActive => _sessionActive;

  /// The child the running session belongs to; null when none is running.
  String? get sessionChildId => _sessionChildId;

  /// Seconds of play in the current session (0 when none is running).
  int get sessionUsedSeconds => _sessionUsedSeconds;

  /// Remaining seconds in this session, or null when no session limit is
  /// set. Never negative.
  int? get sessionRemainingSeconds {
    final limit = _sessionLimitMinutes;
    if (limit == null) return null;
    final left = limit * 60 + _sessionBonusSeconds - _sessionUsedSeconds;
    return left < 0 ? 0 : left;
  }

  /// The stricter of the two remaining budgets — this is what gates play.
  /// Null when neither limit is set.
  int? get activeRemainingSeconds {
    final daily = remainingSeconds;
    final session = sessionRemainingSeconds;
    if (daily == null) return session;
    if (session == null) return daily;
    return daily < session ? daily : session;
  }

  /// True when the daily limit is set and today's budget is used up.
  bool get isDailyExhausted => (remainingSeconds ?? 1) <= 0;

  /// True when the stricter active limit — daily or session — is used up.
  /// This is what every enforcement point (lobby entry, the usage ticker,
  /// the game-end choice) checks, so reaching either limit blocks play.
  bool get isExhausted => (activeRemainingSeconds ?? 1) <= 0;

  /// True in the last [warnBeforeSeconds] before the active limit runs out —
  /// the moment for the one gentle pre-break warning.
  bool get isNearLimit {
    final left = activeRemainingSeconds;
    return left != null && left > 0 && left <= warnBeforeSeconds;
  }

  /// Sets (or clears, with null/0) the daily limit for the loaded child.
  Future<void> setLimitMinutes(int? minutes) async {
    final childId = _childId;
    if (childId == null) return;
    _limitMinutes = (minutes == null || minutes <= 0) ? null : minutes;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_limitMinutes == null) {
        await prefs.remove(_limitKey(childId));
      } else {
        await prefs.setInt(_limitKey(childId), _limitMinutes!);
      }
    } catch (e) {
      debugPrint('[ScreenTime] setLimit failed: $e');
    }
  }

  /// Sets (or clears, with null/0 — "No session limit") the per-session
  /// limit for the loaded child. Clearing it never touches the daily limit.
  Future<void> setSessionLimitMinutes(int? minutes) async {
    final childId = _childId;
    if (childId == null) return;
    _sessionLimitMinutes = (minutes == null || minutes <= 0) ? null : minutes;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_sessionLimitMinutes == null) {
        await prefs.remove(_sessionLimitKey(childId));
      } else {
        await prefs.setInt(_sessionLimitKey(childId), _sessionLimitMinutes!);
      }
    } catch (e) {
      debugPrint('[ScreenTime] setSessionLimit failed: $e');
    }
  }

  /// Begins a play session for the loaded child, resuming a recently
  /// suspended one instead of starting fresh.
  ///
  /// Session lifecycle (AUM-162):
  /// * **Starts** when the child enters child mode — the lobby calls this as
  ///   it mounts, before any game opens.
  /// * **Continues** across the lobby, games, rewards and game-to-game
  ///   navigation: the lobby stays mounted beneath the game routes, so
  ///   nothing along that path calls this again and nothing resets the
  ///   counter.
  /// * **Ends** when the parent exits child mode, switches children or signs
  ///   out — every one of those pops the lobby, whose dispose calls
  ///   [endSessionOwned] with the token this method returned — including
  ///   "Exit Child Mode" on the lock screen. A dispose that lands late,
  ///   after another child has loaded, holds a stale token and no-ops.
  /// * **Suspends** on an app kill or restart: usage is persisted on every
  ///   tick, and a restart within [sessionResumeWindow] resumes the old
  ///   numbers here, so restarting the app cannot dodge the session limit.
  ///   An older suspension is stale — the child genuinely stopped playing —
  ///   and is dropped.
  /// * Parent-mode time is never counted: the usage ticker only exists in
  ///   the child lobby, and it pauses while the lock screen is up. Time in
  ///   the background is likewise not counted, matching the daily policy
  ///   (periodic timers do not fire while the app is suspended).
  /// * Clock safety: elapsed play is tick-accumulated, never derived from
  ///   wall-clock differences, so ordinary clock changes cannot inflate it.
  ///   A suspension whose last-active time is in the future (the clock was
  ///   set backwards) is treated as fresh, never stale.
  ///
  /// Returns an ownership token identifying the session just started, or
  /// null when no child is loaded or a newer [load] superseded this call.
  /// Whoever starts a session owns it: keep the token and hand it to
  /// [endSessionOwned], so a late end from a previous owner cannot touch a
  /// session that has since passed to another child.
  Future<int?> startSession() async {
    final childId = _childId;
    if (childId == null) return null;
    final epoch = _loadEpoch;
    var used = 0;
    var bonus = 0;
    try {
      final prefs = await SharedPreferences.getInstance();
      final suspended = _readSessionState(
        prefs.getString(_sessionStateKey(childId)),
      );
      // Another load() took over while the read ran — starting a session
      // now would attach this child's numbers to the newly loaded child.
      if (_loadEpoch != epoch) return null;
      if (suspended != null) {
        used = suspended.usedSeconds;
        bonus = suspended.bonusSeconds;
      }
    } catch (e) {
      debugPrint('[ScreenTime] startSession failed: $e');
    }
    if (_loadEpoch != epoch) return null;
    final token = ++_tokenCounter;
    _sessionToken = token;
    _sessionChildId = childId;
    _sessionActive = true;
    _sessionUsedSeconds = used;
    _sessionBonusSeconds = bonus;
    notifyListeners();
    await _persistSessionState();
    return token;
  }

  /// Ends the current session and clears its persisted state, so the next
  /// [startSession] begins at zero. Safe to call when none is running.
  ///
  /// The persisted state removed is the session *owner's* — never whichever
  /// child happens to be loaded by the time an async caller gets here.
  /// Route-teardown paths (the lobby's dispose) must use [endSessionOwned]
  /// instead, which additionally no-ops when the caller's session is gone.
  Future<void> endSession() async {
    final childId = _sessionChildId ?? _childId;
    _sessionToken = null;
    _sessionChildId = null;
    _sessionActive = false;
    _sessionUsedSeconds = 0;
    _sessionBonusSeconds = 0;
    notifyListeners();
    if (childId == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_sessionStateKey(childId));
    } catch (e) {
      debugPrint('[ScreenTime] endSession failed: $e');
    }
  }

  /// Child-scoped end for session owners: ends the session only if [token]
  /// still identifies it. A stale token — the service has since loaded
  /// another child, or a newer session replaced this one — makes the call a
  /// no-op, so Child A's late dispose can never reset or delete Child B's
  /// in-memory or persisted session (AUM-162).
  Future<void> endSessionOwned(int? token) async {
    if (token == null || token != _sessionToken) return;
    await endSession();
  }

  /// Parses 'usedSeconds:bonusSeconds:lastActiveEpochMs', returning null for
  /// anything malformed or stale (last active longer than
  /// [sessionResumeWindow] ago). A last-active time in the future — the
  /// device clock was set backwards — is not stale.
  ({int usedSeconds, int bonusSeconds})? _readSessionState(String? raw) {
    if (raw == null) return null;
    final parts = raw.split(':');
    if (parts.length != 3) return null;
    final used = int.tryParse(parts[0]);
    final bonus = int.tryParse(parts[1]);
    final lastMs = int.tryParse(parts[2]);
    if (used == null || bonus == null || lastMs == null) return null;
    final gap = clock().difference(DateTime.fromMillisecondsSinceEpoch(lastMs));
    if (gap > sessionResumeWindow) return null;
    return (
      usedSeconds: used < 0 ? 0 : used,
      bonusSeconds: bonus < 0 ? 0 : bonus,
    );
  }

  Future<void> _persistSessionState() async {
    final childId = _sessionChildId;
    final token = _sessionToken;
    if (childId == null || token == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      // Ended or superseded while getInstance ran — writing now would
      // resurrect a session that no longer exists.
      if (token != _sessionToken) return;
      await prefs.setString(
        _sessionStateKey(childId),
        '$_sessionUsedSeconds:$_sessionBonusSeconds:'
        '${clock().millisecondsSinceEpoch}',
      );
    } catch (e) {
      debugPrint('[ScreenTime] persist session failed: $e');
    }
  }

  /// Adds [seconds] of child-play time to today's usage and the running
  /// session's usage. The daily count rolls over automatically at midnight;
  /// the session deliberately does not: a sitting that spans midnight is
  /// still one sitting.
  ///
  /// Counts only while a session is active for the loaded child (AUM-162):
  /// the usage ticker lives in the child lobby and nowhere else, so a call
  /// landing after [endSession] — or from any parent-mode screen — is not
  /// child play and moves neither counter. Daily usage accumulated during
  /// active sessions is untouched by this guard.
  Future<void> addUsage(int seconds) async {
    if (!_sessionActive) return;
    final childId = _sessionChildId;
    if (childId == null || childId != _childId) return;
    if (_usageDate != _today()) {
      // Day rolled over while playing — start a fresh daily budget.
      _usedTodaySeconds = 0;
      _bonusTodaySeconds = 0;
      _usageDate = _today();
    }
    _usedTodaySeconds += seconds;
    if (_sessionActive) _sessionUsedSeconds += seconds;
    notifyListeners();
    try {
      await _writeDated(_usageKey(childId), _usedTodaySeconds);
    } catch (e) {
      debugPrint('[ScreenTime] addUsage failed: $e');
    }
    // Persisted every tick so an app kill mid-session loses at most one tick
    // — that is what lets a restart resume instead of reset (AUM-162).
    if (_sessionActive) await _persistSessionState();
  }

  /// Parent override: grants [minutes] of extra play time for today only.
  /// The grant lifts whichever limit locked the screen, so a running session
  /// receives the same extra minutes as the daily budget.
  Future<void> extendToday(int minutes) async {
    final childId = _childId;
    if (childId == null) return;
    _bonusTodaySeconds += minutes * 60;
    if (_sessionActive) _sessionBonusSeconds += minutes * 60;
    notifyListeners();
    try {
      await _writeDated(_bonusKey(childId), _bonusTodaySeconds);
    } catch (e) {
      debugPrint('[ScreenTime] extendToday failed: $e');
    }
    if (_sessionActive) await _persistSessionState();
  }

  /// Parent action: resets today's usage to zero. Session usage (running or
  /// suspended) is cleared too — a parent resetting the day expects a fully
  /// fresh start, not a child still locked by the sitting they were in.
  Future<void> resetToday() async {
    final childId = _childId;
    if (childId == null) return;
    _usedTodaySeconds = 0;
    _bonusTodaySeconds = 0;
    _sessionUsedSeconds = 0;
    _sessionBonusSeconds = 0;
    notifyListeners();
    try {
      await _writeDated(_usageKey(childId), 0);
      await _writeDated(_bonusKey(childId), 0);
      if (_sessionActive) {
        await _persistSessionState();
      } else {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_sessionStateKey(childId));
      }
    } catch (e) {
      debugPrint('[ScreenTime] resetToday failed: $e');
    }
  }
}
