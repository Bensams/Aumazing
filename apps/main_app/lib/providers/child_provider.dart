import 'package:flutter/foundation.dart';
import 'package:shared_audio/shared_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_ui/shared_ui.dart';

import '../core/repositories/child_repository.dart';
import '../core/services/local_db_service.dart';
import '../features/stars/star_catalogue.dart';
import '../model/child_profile.dart';
import '../core/services/auth_service.dart';

/// What the parent should see after a child profile was deleted.
enum ChildDeletionOutcome {
  /// Another child is still available and is now the active one.
  switchedToAnotherChild,

  /// The deleted child was not the active one; nothing else changed.
  otherChildDeleted,

  /// That was the last child — the parent has to set one up again.
  noChildrenLeft,
}

/// Manages the parent's child profiles: which one is active, and the active
/// child's comfort / appearance settings.
///
/// This is the single source of truth for child selection. Nothing else may
/// assume "the first child in storage" is the active one.
class ChildProvider extends ChangeNotifier {
  final LocalDbService _localDb;
  final AuthService _authService;

  /// Built on first write, not at construction: the default repository pulls
  /// in the sync stack, which a widget test creating a provider has no reason
  /// to need.
  final ChildRepository? _injectedRepository;
  late final ChildRepository _childRepository =
      _injectedRepository ??
      ChildRepository(localDb: _localDb, authService: _authService);

  /// Every non-deleted child belonging to the current parent, oldest first.
  List<ChildProfile> _children = const [];

  ChildProfile? _profile;
  bool _isLoading = false;

  /// Parent's manual background-theme override. When null, the theme is
  /// derived from the child's sex. Persisted locally (no DB migration).
  GameTheme? _themeOverride;
  static const _themeOverrideKeyPrefix = 'theme_override_';

  /// Whether the child can reach the Star Shop at all (STAR-G2).
  ///
  /// Stars keep accruing while it is off, so turning it off costs the child
  /// nothing — a parent switching it back on later finds everything that was
  /// earned in the meantime still there.
  bool _shopEnabled = true;
  static const _shopEnabledKeyPrefix = 'star_shop_enabled_';

  /// Whether a purchase needs the parent to approve it (STAR-C6).
  ///
  /// Off by default: buying freely is most of what makes the stars feel like
  /// the child's own. A parent who would rather be asked can turn it on.
  bool _requirePurchaseApproval = false;
  static const _purchaseApprovalKeyPrefix = 'star_purchase_approval_';

  /// Parent's custom game-screen background. When null the child's game
  /// screens use the [activeTheme] preset gradients. Persisted locally per
  /// child (no DB migration).
  ChildBackground? _customBackground;
  static const _customBackgroundKeyPrefix = 'custom_background_';

  /// Parent's chosen look for the cards behind game objects — the tile under
  /// each shape, picture and item — plus its outline. Persisted locally per
  /// child (no DB migration).
  GameObjectStyle _objectStyle = const GameObjectStyle();
  static const _objectStyleKeyPrefix = 'object_style_';

  /// Parent's chosen scene for the child's "My Path" row. When null the path
  /// keeps its classic look. Persisted locally (no DB migration).
  WorldTheme? _worldOverride;
  static const _worldOverrideKeyPrefix = 'world_override_';

  /// Selected app/game language (English / Tagalog / Cebuano). Persisted
  /// locally; defaults to English.
  GameLanguage _language = GameLanguage.english;
  static const _languageKeyPrefix = 'language_';

  /// Selected voice-over pack — which recorded voice speaks the cues for the
  /// active language. Persisted locally per child; defaults to the language's
  /// default pack.
  String _voicePackId = defaultVoicePackForLanguage(
    GameLanguage.english.slug,
  ).id;
  static const _voicePackKeyPrefix = 'voice_pack_';

  /// Parent's manual difficulty override (1 Easy / 2 Medium / 3 Hard). When
  /// null, practice difficulty follows the AI's per-area assessment levels.
  /// Persisted locally per child (no DB migration).
  int? _difficultyOverride;
  static const _difficultyOverrideKeyPrefix = 'difficulty_override_';

  /// Graphics quality / performance tier (device-level). Lower tiers drop the
  /// video backgrounds and reward particles to ease device heat and sensory
  /// load. Defaults to High.
  GraphicsQuality _graphicsQuality = GraphicsQuality.high;
  static const _graphicsQualityKey = 'graphics_quality';
  static const _showTextPromptsKey = 'show_text_prompts';

  ChildProvider({
    LocalDbService? localDb,
    AuthService? authService,
    ChildRepository? childRepository,
  }) : _localDb = localDb ?? LocalDbService(),
       _authService = authService ?? AuthService(),
       _injectedRepository = childRepository;

  /// Where the parent's active-child selection is saved (AUM-151). Keyed by
  /// the parent's effective user id — a real account id or a `guest_<uuid>` —
  /// so two accounts on the same device can never inherit each other's
  /// selection.
  static const _activeChildKeyPrefix = 'active_child_';

  ChildProfile? get profile => _profile;
  bool get isLoading => _isLoading;
  bool get hasProfile => _profile != null;

  /// All of the parent's children, oldest first. Empty until [loadProfile].
  List<ChildProfile> get children => List.unmodifiable(_children);

  /// Id of the child whose data the app is currently showing.
  String? get activeChildId => _profile?.id;

  bool isActive(String childId) => _profile?.id == childId;

  // Comfort settings shortcuts
  bool get musicEnabled => _profile?.musicEnabled ?? true;
  double get musicVolume => _profile?.musicVolume ?? 0.5;
  String get musicCategory => _profile?.musicCategory ?? kDefaultBgmCategory;
  double get sfxVolume => _profile?.sfxVolume ?? 0.7;
  bool get vibrationEnabled => _profile?.vibrationEnabled ?? true;
  double get animationIntensity => _profile?.animationIntensity ?? 1.0;
  double get promptSpeed => _profile?.promptSpeed ?? 1.0;
  bool get sensoryPreferencesSet => _profile?.sensoryPreferencesSet ?? false;

  // Reward preference shortcuts
  RewardPreference get rewardPreference =>
      _profile?.rewardPreference ?? RewardPreference.bubbles;
  bool get useRandomReward => _profile?.useRandomReward ?? false;

  // ── Background theme ──────────────────────────────────────────────────

  /// The parent's manual theme override, or null if following the child's sex.
  GameTheme? get themeOverride => _themeOverride;

  /// Whether the active theme comes from a manual override (vs. auto-from-sex).
  bool get isThemeOverridden => _themeOverride != null;

  /// The active background theme: manual override if set, else derived from
  /// the child's sex (defaults to neutral).
  GameTheme get activeTheme =>
      _themeOverride ?? GameTheme.fromSexValue(_profile?.sex?.value);

  /// The parent's custom game background, or null when using a preset theme.
  ChildBackground? get customBackground => _customBackground;

  bool get hasCustomBackground => _customBackground != null;

  /// The full color palette for the [activeTheme] (game + dashboard).
  ///
  /// A custom background replaces only the *child* game background — the
  /// parent dashboard keeps `parentBackground` from the preset theme, so the
  /// dashboard's text and cards stay on the contrast they were designed
  /// against.
  GamePalette get activePalette {
    final base = GamePalettes.of(activeTheme);
    final custom = _customBackground;
    return custom == null ? base : base.withGameBackground(custom.toGradient());
  }

  // ── My Path world ─────────────────────────────────────────────────────

  /// The parent's chosen path scene, or null while on the classic look.
  WorldTheme? get worldOverride => _worldOverride;

  /// Whether a world has been chosen (vs. the untouched classic default).
  bool get isWorldOverridden => _worldOverride != null;

  /// The active world — classic unless the parent has opted into one.
  WorldTheme get activeWorld => _worldOverride ?? WorldTheme.classic;

  /// Trail / badge / backdrop styling for the [activeWorld].
  WorldStyle get activeWorldStyle => WorldStyles.of(activeWorld);

  // ── Difficulty override ───────────────────────────────────────────────

  /// The parent's manual difficulty override (1–3), or null when practice
  /// difficulty follows the AI's per-area levels.
  int? get difficultyOverride => _difficultyOverride;

  /// Whether difficulty comes from a manual override (vs. auto-from-AI).
  bool get isDifficultyOverridden => _difficultyOverride != null;

  /// Sets a manual difficulty override (clamped to 1–3) and persists it.
  Future<void> setDifficultyOverride(int difficulty) async {
    _difficultyOverride = difficulty.clamp(1, 3);
    notifyListeners();
    final id = _profile?.id;
    if (id != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        '$_difficultyOverrideKeyPrefix$id',
        _difficultyOverride!,
      );
    }
  }

  /// Clears the override so difficulty follows the AI assessment again.
  Future<void> clearDifficultyOverride() async {
    _difficultyOverride = null;
    notifyListeners();
    final id = _profile?.id;
    if (id != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_difficultyOverrideKeyPrefix$id');
    }
  }

  /// Loads any persisted difficulty override for the current child.
  Future<void> _loadDifficultyOverride() async {
    final id = _profile?.id;
    if (id == null) {
      _difficultyOverride = null;
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    _difficultyOverride = prefs.getInt('$_difficultyOverrideKeyPrefix$id');
  }

  // ── Language ──────────────────────────────────────────────────────────

  /// The active app/game language (defaults to English).
  GameLanguage get language => _language;

  /// Localized strings for the active language.
  AppStrings get strings => AppStrings(_language);

  // ── Voice pack ────────────────────────────────────────────────────────

  /// The selected voice pack, falling back to the active language's default
  /// if the stored pack was removed from the registry.
  VoicePack get voicePack =>
      voicePackById(_voicePackId) ??
      defaultVoicePackForLanguage(_language.slug);

  /// Asset folder [VoiceOverService] should read voice-over cues from.
  String get voiceAssetFolder => voicePack.assetFolder;

  /// Rate [VoiceOverService] should speak cues at, from the parent's
  /// prompt-speed setting.
  double get voicePlaybackRate => voiceRateForPromptSpeed(promptSpeed);

  /// Voice packs the parent can choose between for the active language.
  List<VoicePack> get availableVoicePacks =>
      voicePacksForLanguage(_language.slug);

  /// Selects a voice pack and persists it locally.
  ///
  /// Ignores packs that do not belong to the active language, so audio and
  /// on-screen text can never drift apart.
  Future<void> setVoicePack(String voicePackId) async {
    final pack = voicePackById(voicePackId);
    if (pack == null || pack.languageSlug != _language.slug) return;

    _voicePackId = pack.id;
    notifyListeners();
    await _persistVoicePack();
  }

  Future<void> _persistVoicePack() async {
    final id = _profile?.id;
    if (id == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_voicePackKeyPrefix$id', _voicePackId);
  }

  /// Loads the persisted voice pack for the current child.
  ///
  /// Must run after [_loadLanguage]: a stored pack belonging to a different
  /// language is discarded in favour of the current language's default.
  Future<void> _loadVoicePack() async {
    final id = _profile?.id;
    if (id == null) {
      _voicePackId = defaultVoicePackForLanguage(_language.slug).id;
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final stored = voicePackById(prefs.getString('$_voicePackKeyPrefix$id'));
    _voicePackId = stored != null && stored.languageSlug == _language.slug
        ? stored.id
        : defaultVoicePackForLanguage(_language.slug).id;
  }

  // ── Graphics quality (heat / sensory) ─────────────────────────────────

  /// The active graphics quality tier (Low / Medium / High).
  GraphicsQuality get graphicsQuality => _graphicsQuality;

  /// Whether backgrounds should be static (video only plays on High).
  bool get useStaticBackground => _graphicsQuality.useStaticBackground;

  /// Whether motion/particle effects should be minimised (Low only).
  bool get reducedMotion => _graphicsQuality.reducedMotion;

  /// Whether on-screen instruction text is drawn.
  ///
  /// Off suits pre-readers and children who find text busy; the spoken
  /// voice-over still plays either way, so turning this off removes clutter
  /// without removing the instruction.
  bool get showTextPrompts => _showTextPrompts;
  bool _showTextPrompts = true;

  Future<void> setShowTextPrompts(bool value) async {
    _showTextPrompts = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showTextPromptsKey, value);
  }

  Future<void> _loadShowTextPrompts() async {
    final prefs = await SharedPreferences.getInstance();
    _showTextPrompts = prefs.getBool(_showTextPromptsKey) ?? true;
  }

  /// Reads whether to use a static background directly — usable before a
  /// profile is loaded (e.g. on the login / loading screens).
  static Future<bool> readUseStaticBackground() async {
    final prefs = await SharedPreferences.getInstance();
    return GraphicsQuality.fromSlug(
      prefs.getString(_graphicsQualityKey),
    ).useStaticBackground;
  }

  /// Returns the sensory settings as a map for use in scoring/assessment.
  Map<String, dynamic> get sensorySettingsMap =>
      _profile?.sensorySettingsMap ??
      {
        'music_enabled': true,
        'music_volume': 0.5,
        'sfx_volume': 0.7,
        'vibration_enabled': true,
        'animation_intensity': 1.0,
        'prompt_speed': 1.0,
      };

  /// Loads every child of the current parent from the SQLite cache, and keeps
  /// (or picks) the active one.
  ///
  /// An already-selected child stays active across a reload. Otherwise the
  /// parent's saved selection for this account is restored (AUM-151); only
  /// when neither matches one of this parent's children does the oldest
  /// profile take over — a deliberate choice over "whatever storage returned
  /// first", so adding a child never silently takes over the session.
  Future<void> loadProfile() async {
    _isLoading = true;
    notifyListeners();

    try {
      // Device-level preference — load regardless of profile/auth state.
      await _loadGraphicsQuality();
      await _loadShowTextPrompts();

      final userId = _authService.effectiveUserId;
      if (userId == null) {
        _children = const [];
        _profile = null;
        return;
      }

      final previousId = _profile?.id;
      _children = _sorted(await _localDb.getChildren(userId: userId));
      final savedId = await _readSavedActiveChildId(userId);
      // In-session selection wins, then this parent's saved choice. A saved
      // id that is stale (child deleted) or belongs to another parent simply
      // fails the lookup and falls through to the oldest child.
      _profile =
          _childById(previousId) ??
          _childById(savedId) ??
          (_children.isEmpty ? null : _children.first);
      // Re-save, so a fallback (or a cleared selection) is what the next
      // launch restores instead of retrying the stale id every time.
      await _persistActiveChild(userId);
      await _loadActiveChildPreferences();
    } catch (e) {
      debugPrint('[ChildProvider] loadProfile error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ── Child selection ───────────────────────────────────────────────────

  /// Makes [childId] the active child for this session.
  ///
  /// Every per-child preference is re-read from that child's own keys, so
  /// nothing from the previous child survives the switch. Callers must also
  /// reload the child-scoped providers — see `switchActiveChild` in
  /// `services/child_switch_service.dart`, which does both.
  ///
  /// Returns false when no such child belongs to this parent.
  Future<bool> selectChild(String childId) async {
    final target = _childById(childId);
    if (target == null) return false;
    if (_profile?.id == childId) return true;

    _profile = target;
    await _loadActiveChildPreferences();
    await _persistActiveChild(_authService.effectiveUserId);
    notifyListeners();
    return true;
  }

  // ── Add / edit / delete ───────────────────────────────────────────────

  /// Creates another child for this parent without touching existing ones.
  ///
  /// The new child gets its own id and its own local (and, once synced,
  /// cloud) record. It only becomes active when [makeActive] is set, or when
  /// the parent had no child at all.
  Future<ChildProfile> addChild({
    required String displayName,
    required DateTime birthDate,
    required String avatar,
    ChildSex? sex,
    bool musicEnabled = true,
    double musicVolume = 0.5,
    String musicCategory = kDefaultBgmCategory,
    double sfxVolume = 0.7,
    bool vibrationEnabled = true,
    double promptSpeed = 1.0,
    bool sensoryPreferencesSet = false,
    RewardPreference rewardPreference = RewardPreference.bubbles,
    bool useRandomReward = false,
    String characterId = 'bps',
    bool makeActive = false,
  }) async {
    final created = await _childRepository.createChild(
      displayName: displayName,
      birthDate: birthDate,
      avatar: avatar,
      sex: sex,
      musicEnabled: musicEnabled,
      musicVolume: musicVolume,
      musicCategory: musicCategory,
      sfxVolume: sfxVolume,
      vibrationEnabled: vibrationEnabled,
      promptSpeed: promptSpeed,
      sensoryPreferencesSet: sensoryPreferencesSet,
      rewardPreference: rewardPreference,
      useRandomReward: useRandomReward,
      characterId: characterId,
    );

    _children = _sorted([..._children, created]);
    if (makeActive || _profile == null) {
      _profile = created;
      await _loadActiveChildPreferences();
      await _persistActiveChild(_authService.effectiveUserId);
    }
    notifyListeners();
    return created;
  }

  /// Edits one child's profile details. Other children are untouched.
  ///
  /// Returns the updated profile, or null when [childId] is unknown.
  Future<ChildProfile?> editChild(
    String childId, {
    String? displayName,
    DateTime? birthDate,
    String? avatar,
    ChildSex? sex,
    RewardPreference? rewardPreference,
    bool? useRandomReward,
  }) async {
    final existing = _childById(childId);
    if (existing == null) return null;

    final updated = await _childRepository.updateChild(
      existing,
      displayName: displayName,
      birthDate: birthDate,
      avatar: avatar,
      sex: sex,
      rewardPreference: rewardPreference,
      useRandomReward: useRandomReward,
    );

    _replaceInList(updated);
    if (_profile?.id == childId) _profile = updated;
    notifyListeners();
    return updated;
  }

  /// Deletes one child along with its local per-child data, queuing the cloud
  /// deletion for the next sync.
  ///
  /// When the active child is removed another available child takes over; the
  /// caller is responsible for reloading child-scoped providers (or, on
  /// [ChildDeletionOutcome.noChildrenLeft], sending the parent to setup).
  Future<ChildDeletionOutcome> deleteChild(String childId) async {
    final target = _childById(childId);
    if (target == null) return ChildDeletionOutcome.otherChildDeleted;

    final wasActive = _profile?.id == childId;

    await _childRepository.deleteChild(childId);
    await _purgeChildPreferences(childId);

    _children = [
      for (final child in _children)
        if (child.id != childId) child,
    ];

    if (!wasActive) return ChildDeletionOutcome.otherChildDeleted;

    _profile = _children.isEmpty ? null : _children.first;
    await _loadActiveChildPreferences();
    // Save the replacement (or the cleared selection) so the next launch
    // does not try to restore the deleted child.
    await _persistActiveChild(_authService.effectiveUserId);
    notifyListeners();

    return _profile == null
        ? ChildDeletionOutcome.noChildrenLeft
        : ChildDeletionOutcome.switchedToAnotherChild;
  }

  // ── Internals ─────────────────────────────────────────────────────────

  /// The saved active-child id for [userId], or null when nothing was saved.
  ///
  /// When the account has no saved selection of its own but the guest account
  /// it was migrated from does (see [AuthService.previousGuestUserId]), the
  /// guest's selection is used — the children themselves were migrated to the
  /// new id, so the choice still refers to a child this parent owns. The
  /// caller validates the id against the loaded children either way.
  Future<String?> _readSavedActiveChildId(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('$_activeChildKeyPrefix$userId');
      if (saved != null) return saved;

      final previousGuestId = _authService.previousGuestUserId;
      if (previousGuestId != null && previousGuestId != userId) {
        final inherited = prefs.getString(
          '$_activeChildKeyPrefix$previousGuestId',
        );
        if (inherited != null) return inherited;
      }

      // Guest → permanent conversion: the children were backfilled to the new
      // account id, but the selection was saved under the guest id. Adopting
      // it here is safe because the caller only accepts an id that resolves
      // to one of *this* parent's loaded children — a guest selection that
      // was never backfilled simply fails that lookup.
      final storedGuestId = await _authService.getStoredGuestUserId();
      if (storedGuestId != null && storedGuestId != userId) {
        return prefs.getString('$_activeChildKeyPrefix$storedGuestId');
      }
      return null;
    } catch (e) {
      debugPrint('[ChildProvider] read saved active child failed: $e');
      return null;
    }
  }

  /// Saves the active child for [userId] — or removes the entry when no child
  /// is active — so the next launch restores exactly this state.
  Future<void> _persistActiveChild(String? userId) async {
    if (userId == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = _profile?.id;
      if (id == null) {
        await prefs.remove('$_activeChildKeyPrefix$userId');
      } else {
        await prefs.setString('$_activeChildKeyPrefix$userId', id);
      }
    } catch (e) {
      debugPrint('[ChildProvider] persist active child failed: $e');
    }
  }

  /// Carries a saved active-child selection from one account id to another —
  /// the guest → permanent conversion, where the children are backfilled to
  /// the new account id and the stored guest session is cleared right after.
  ///
  /// Static because it runs at conversion time, from the bind flow, where no
  /// ChildProvider for the new identity exists yet. An existing selection
  /// under [toUserId] is never overwritten: that account already made its own
  /// choice. The next [loadProfile] validates the carried id and falls back
  /// if the child did not survive the backfill.
  static Future<void> migrateSavedActiveChild({
    required String fromUserId,
    required String toUserId,
  }) async {
    if (fromUserId == toUserId) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('$_activeChildKeyPrefix$fromUserId');
      if (saved == null) return;
      if (prefs.getString('$_activeChildKeyPrefix$toUserId') == null) {
        await prefs.setString('$_activeChildKeyPrefix$toUserId', saved);
      }
      await prefs.remove('$_activeChildKeyPrefix$fromUserId');
    } catch (e) {
      debugPrint('[ChildProvider] migrate saved active child failed: $e');
    }
  }

  ChildProfile? _childById(String? id) {
    if (id == null) return null;
    for (final child in _children) {
      if (child.id == id) return child;
    }
    return null;
  }

  /// Oldest first, so the list order — and the default active child — does
  /// not depend on how storage happened to sort the rows. Children created in
  /// the same instant fall back to their ids, so the order is still stable.
  static List<ChildProfile> _sorted(List<ChildProfile> children) {
    final sorted = [...children]
      ..sort((a, b) {
        final byCreation = a.createdAt.compareTo(b.createdAt);
        return byCreation != 0 ? byCreation : a.id.compareTo(b.id);
      });
    return sorted;
  }

  void _replaceInList(ChildProfile updated) {
    _children = [
      for (final child in _children)
        if (child.id == updated.id) updated else child,
    ];
  }

  /// Re-reads every per-child preference for the active child. With no active
  /// child each falls back to its default, so a switch can never leave the
  /// previous child's theme, language or difficulty behind.
  Future<void> _loadActiveChildPreferences() async {
    await _loadThemeOverride();
    await _loadStarShopPrefs();
    await _loadCustomBackground();
    await _loadObjectStyle();
    await _loadWorldOverride();
    await _loadLanguage();
    await _loadVoicePack();
    await _loadDifficultyOverride();
  }

  /// Removes every locally stored preference and cached progress key that
  /// belongs to a deleted child.
  ///
  /// All per-child keys in the app end in `_<childId>` (theme, background,
  /// object style, world, language, voice, difficulty, screen time, AI
  /// prediction, assessment snapshots, path progress), so matching on the
  /// suffix covers them without every feature having to register itself here.
  Future<void> _purgeChildPreferences(String childId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stale = [
        for (final key in prefs.getKeys())
          if (key.endsWith('_$childId')) key,
      ];
      for (final key in stale) {
        await prefs.remove(key);
      }
    } catch (e) {
      debugPrint('[ChildProvider] purge preferences failed: $e');
    }
  }

  /// Updates comfort settings and persists them.
  Future<void> updateComfortSettings({
    bool? musicEnabled,
    double? musicVolume,
    String? musicCategory,
    double? sfxVolume,
    bool? vibrationEnabled,
    double? animationIntensity,
    double? promptSpeed,
    bool? sensoryPreferencesSet,
  }) async {
    if (_profile == null) return;

    _profile = _profile!.copyWith(
      musicEnabled: musicEnabled,
      musicVolume: musicVolume,
      musicCategory: musicCategory,
      sfxVolume: sfxVolume,
      vibrationEnabled: vibrationEnabled,
      animationIntensity: animationIntensity,
      promptSpeed: promptSpeed,
      sensoryPreferencesSet: sensoryPreferencesSet,
    );

    await _localDb.upsertChild(_profile!);
    _replaceInList(_profile!);
    notifyListeners();
  }

  /// Updates child profile details.
  Future<void> updateProfile({
    String? displayName,
    DateTime? birthDate,
    String? avatar,
  }) async {
    if (_profile == null) return;

    _profile = _profile!.copyWith(
      displayName: displayName,
      birthDate: birthDate,
      avatar: avatar,
    );

    await _localDb.upsertChild(_profile!);
    _replaceInList(_profile!);
    notifyListeners();
  }

  /// Updates reward preferences and persists them.
  Future<void> updateRewardPreferences({
    RewardPreference? rewardPreference,
    bool? useRandomReward,
  }) async {
    if (_profile == null) return;

    _profile = _profile!.copyWith(
      rewardPreference: rewardPreference,
      useRandomReward: useRandomReward,
    );

    await _localDb.upsertChild(_profile!, markPending: true);
    _replaceInList(_profile!);
    notifyListeners();
  }

  /// Changes which character keeps this child company (STAR-A2).
  ///
  /// Stars, unlocks and the equipped costume all survive: the character is who
  /// wears the costume, not what owns it. A parent who realises after a week
  /// that their child prefers a different companion must not have to weigh
  /// that against losing everything the child earned.
  Future<void> setCharacter(ChildCharacter character) async {
    if (_profile == null) return;
    _profile = _profile!.copyWith(characterId: character.id);
    await _localDb.upsertChild(_profile!, markPending: true);
    _replaceInList(_profile!);
    notifyListeners();
  }

  /// Wears [costume], or [Costume.none] to go back to the character's own
  /// clothes (STAR-D1).
  ///
  /// Deliberately does not re-check ownership: the shop is the only caller and
  /// it offers only what the child owns. Checking again here would create a
  /// second source of truth for "owned", and the two would eventually disagree.
  Future<void> setEquippedCostume(Costume costume) async {
    if (_profile == null) return;
    _profile = _profile!.copyWith(equippedCostume: costume.id);
    await _localDb.upsertChild(_profile!, markPending: true);
    _replaceInList(_profile!);
    notifyListeners();
  }

  /// Sets a manual background-theme override and persists it locally.
  Future<void> setThemeOverride(GameTheme theme) async {
    _themeOverride = theme;
    notifyListeners();
    final id = _profile?.id;
    if (id != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_themeOverrideKeyPrefix$id', theme.slug);
    }
  }

  /// Clears the manual override so the theme follows the child's sex again.
  Future<void> clearThemeOverride() async {
    _themeOverride = null;
    notifyListeners();
    final id = _profile?.id;
    if (id != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_themeOverrideKeyPrefix$id');
    }
  }

  /// Loads any persisted theme override for the current child.
  // ── Star Shop parent controls ─────────────────────────────────────────

  bool get shopEnabled => _shopEnabled;
  bool get requirePurchaseApproval => _requirePurchaseApproval;

  Future<void> setShopEnabled(bool enabled) async {
    _shopEnabled = enabled;
    notifyListeners();
    final id = _profile?.id;
    if (id != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('$_shopEnabledKeyPrefix$id', enabled);
    }
  }

  Future<void> setRequirePurchaseApproval(bool required) async {
    _requirePurchaseApproval = required;
    notifyListeners();
    final id = _profile?.id;
    if (id != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('$_purchaseApprovalKeyPrefix$id', required);
    }
  }

  Future<void> _loadStarShopPrefs() async {
    final id = _profile?.id;
    if (id == null) {
      _shopEnabled = true;
      _requirePurchaseApproval = false;
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    _shopEnabled = prefs.getBool('$_shopEnabledKeyPrefix$id') ?? true;
    _requirePurchaseApproval =
        prefs.getBool('$_purchaseApprovalKeyPrefix$id') ?? false;
  }

  Future<void> _loadThemeOverride() async {
    final id = _profile?.id;
    if (id == null) {
      _themeOverride = null;
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final slug = prefs.getString('$_themeOverrideKeyPrefix$id');
    _themeOverride = slug == null ? null : GameTheme.fromSlug(slug);
  }

  /// The look of the cards behind game objects.
  GameObjectStyle get objectStyle => _objectStyle;

  /// Sets the game-object card style and persists it locally.
  ///
  /// Also pushes it to the global the Flame components read, so a change
  /// made in Settings is live the next time a game renders rather than
  /// waiting for an app restart.
  Future<void> setObjectStyle(GameObjectStyle style) async {
    _objectStyle = style;
    GameObjectStyle.current = style;
    notifyListeners();
    final id = _profile?.id;
    if (id != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_objectStyleKeyPrefix$id', style.encode());
    }
  }

  /// Loads any persisted object style for the current child.
  Future<void> _loadObjectStyle() async {
    final id = _profile?.id;
    if (id == null) {
      _objectStyle = const GameObjectStyle();
    } else {
      final prefs = await SharedPreferences.getInstance();
      _objectStyle =
          GameObjectStyle.decode(
            prefs.getString('$_objectStyleKeyPrefix$id'),
          ) ??
          const GameObjectStyle();
    }
    GameObjectStyle.current = _objectStyle;
  }

  /// Sets a custom child game background and persists it locally.
  Future<void> setCustomBackground(ChildBackground background) async {
    _customBackground = background;
    notifyListeners();
    final id = _profile?.id;
    if (id != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        '$_customBackgroundKeyPrefix$id',
        background.encode(),
      );
    }
  }

  /// Clears the custom background so the preset theme applies again.
  Future<void> clearCustomBackground() async {
    _customBackground = null;
    notifyListeners();
    final id = _profile?.id;
    if (id != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_customBackgroundKeyPrefix$id');
    }
  }

  /// Loads any persisted custom background for the current child.
  Future<void> _loadCustomBackground() async {
    final id = _profile?.id;
    if (id == null) {
      _customBackground = null;
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    // decode() returns null for anything unparseable, so a corrupt value
    // degrades to the preset theme instead of failing startup.
    _customBackground = ChildBackground.decode(
      prefs.getString('$_customBackgroundKeyPrefix$id'),
    );
  }

  /// Sets the "My Path" scene and persists it locally.
  Future<void> setWorldOverride(WorldTheme world) async {
    _worldOverride = world;
    notifyListeners();
    final id = _profile?.id;
    if (id != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_worldOverrideKeyPrefix$id', world.slug);
    }
  }

  /// Clears the chosen scene so the path returns to its classic look.
  Future<void> clearWorldOverride() async {
    _worldOverride = null;
    notifyListeners();
    final id = _profile?.id;
    if (id != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_worldOverrideKeyPrefix$id');
    }
  }

  /// Loads any persisted world choice for the current child.
  Future<void> _loadWorldOverride() async {
    final id = _profile?.id;
    if (id == null) {
      _worldOverride = null;
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final slug = prefs.getString('$_worldOverrideKeyPrefix$id');
    _worldOverride = slug == null ? null : WorldTheme.fromSlug(slug);
  }

  /// Sets the app/game language and persists it locally.
  ///
  /// Switching language resets the voice pack to the new language's default —
  /// an earlier alternate-voice choice is not restored when switching back.
  Future<void> setLanguage(GameLanguage language) async {
    _language = language;

    final current = voicePackById(_voicePackId);
    final voicePackChanged =
        current == null || current.languageSlug != language.slug;
    if (voicePackChanged) {
      _voicePackId = defaultVoicePackForLanguage(language.slug).id;
    }

    notifyListeners();
    final id = _profile?.id;
    if (id != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_languageKeyPrefix$id', language.slug);
    }
    if (voicePackChanged) await _persistVoicePack();
  }

  /// Stores the language and voice a parent chose during initial profile
  /// setup, keyed against the child row that has just been created.
  ///
  /// Setup writes these directly rather than going through [setLanguage] /
  /// [setVoicePack]: those persist against `_profile`, which is still null
  /// until the home screen loads the new child.
  ///
  /// The live in-memory language and voice only change when [childId] is the
  /// active child — adding a second child from Manage Children must not
  /// re-language the child currently playing.
  Future<void> applyInitialPreferences({
    required String childId,
    required GameLanguage language,
    required String voicePackId,
  }) async {
    final pack = voicePackById(voicePackId);
    final resolvedPackId = pack != null && pack.languageSlug == language.slug
        ? pack.id
        : defaultVoicePackForLanguage(language.slug).id;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_languageKeyPrefix$childId', language.slug);
    await prefs.setString('$_voicePackKeyPrefix$childId', resolvedPackId);

    if (_profile == null || _profile!.id == childId) {
      _language = language;
      _voicePackId = resolvedPackId;
    }
    notifyListeners();
  }

  /// Stores the game background a parent chose during initial profile setup,
  /// keyed against the child row that has just been created.
  ///
  /// Same reason as [applyInitialPreferences]: [setCustomBackground] persists
  /// against `_profile`, which is still null while setup is running, so a
  /// background chosen there would be held in memory and never written.
  ///
  /// The live in-memory background only changes when [childId] is the active
  /// child, so adding a sibling cannot repaint the screens of the child
  /// currently playing.
  Future<void> applyInitialBackground({
    required String childId,
    required ChildBackground background,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_customBackgroundKeyPrefix$childId',
      background.encode(),
    );
    if (_profile == null || _profile!.id == childId) {
      _customBackground = background;
    }
    notifyListeners();
  }

  /// Loads the persisted language for the current child (defaults to English).
  Future<void> _loadLanguage() async {
    final id = _profile?.id;
    if (id == null) {
      _language = GameLanguage.english;
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final slug = prefs.getString('$_languageKeyPrefix$id');
    _language = GameLanguage.fromSlug(slug);
  }

  /// Sets the graphics quality tier and persists it (device-level).
  Future<void> setGraphicsQuality(GraphicsQuality quality) async {
    _graphicsQuality = quality;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_graphicsQualityKey, quality.slug);
  }

  /// Loads the persisted graphics quality (defaults to High).
  Future<void> _loadGraphicsQuality() async {
    final prefs = await SharedPreferences.getInstance();
    _graphicsQuality = GraphicsQuality.fromSlug(
      prefs.getString(_graphicsQualityKey),
    );
  }

  void clear() {
    _children = const [];
    _profile = null;
    _themeOverride = null;
    _customBackground = null;
    _objectStyle = const GameObjectStyle();
    GameObjectStyle.current = _objectStyle;
    _worldOverride = null;
    _difficultyOverride = null;
    _language = GameLanguage.english;
    _voicePackId = defaultVoicePackForLanguage(GameLanguage.english.slug).id;
    _graphicsQuality = GraphicsQuality.high;
    notifyListeners();
  }
}
