// MainScreen exposes these helpers for reuse, but marks them visibleForTesting.
// Keep the upstream file untouched and share its policies rather than copy them.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../media/media_server_client.dart';
import '../../../profiles/active_profile_binder.dart';
import '../../../profiles/active_profile_provider.dart';
import '../../../profiles/plex_home_service.dart';
import '../../../profiles/profile_selection_policy.dart';
import '../../../providers/account_preferences_controller.dart';
import '../../../providers/download_provider.dart';
import '../../../providers/hidden_libraries_provider.dart';
import '../../../providers/libraries_provider.dart';
import '../../../providers/multi_server_provider.dart';
import '../../../providers/offline_mode_provider.dart';
import '../../../providers/playback_state_provider.dart';
import '../../../screens/main_screen.dart';
import '../../../services/api_cache.dart';
import '../../../services/plex_client.dart';
import '../../../services/offline_watch_sync_service.dart';
import '../../../services/settings_service.dart';
import '../../../services/deep_links/deep_link.dart';
import '../../../services/deep_links/deep_link_service.dart';
import '../../../utils/app_logger.dart';
import '../../../watch_together/watch_together.dart';

/// The shell maps these to primeRefresh, refresh (+ libraries.refresh), and
/// fullRefresh respectively. This controller never selects a section or focus.
enum TvShellContentIntent { initialLoad, refreshAfterResume, fullReset }

/// Session services only; call start after the shell's first frame. Navigation
/// callbacks are supplied by the mounted shell; no widget is built here.
class TvShellSessionController extends ChangeNotifier with WidgetsBindingObserver {
  TvShellSessionController({
    required this.activeProfile,
    required this.binder,
    required this.multiServer,
    required this.offlineMode,
    required this.plexHome,
    required this.preferences,
    required this.libraries,
    required this.hiddenLibraries,
    required this.playbackState,
    required this.downloads,
    required this.watchSync,
    required this.onContentIntent,
    required this.hasConnections,
    required this.settleSession,
    required this.pushProfileSelection,
    required this.refreshSeerrUser,
    required this.hasActiveVideoPlayback,
    required this.hasActiveCompanionSession,
    required this.isMobilePlatform,
    required this.isRemoteHost,
    required this.startCompanionHost,
    required this.checkForUpdates,
    required this.launchDeepLink,
    required this.watchTogether,
    required this.openWatchTogether,
    this.isOfflineMode = false,
    this.initialPromptHandled = false,
    this.settings = SettingsService.getInstance,
    this.clearVolatileCache = ApiCache.clearRegisteredVolatile,
    DeepLinkService? deepLinks,
    ContentRefreshResumeGate? contentResumeGate,
    this.bindingFallback = const Duration(seconds: 15),
  }) : deepLinks = deepLinks ?? DeepLinkService.instance,
       _contentResumeGate = contentResumeGate ?? ContentRefreshResumeGate(),
       // The shell selects its initial section before start() runs.
       _isOffline = isOfflineMode || offlineMode.isOffline,
       _offlineUntilConnected = isOfflineMode;

  final ActiveProfileProvider activeProfile;
  final ActiveProfileBinder binder;
  final MultiServerProvider multiServer;
  final OfflineModeProvider offlineMode;
  final PlexHomeService plexHome;
  final AccountPreferencesController preferences;
  final LibrariesProvider libraries;
  final HiddenLibrariesProvider hiddenLibraries;
  final PlaybackStateProvider playbackState;
  final DownloadProvider downloads;
  final OfflineWatchSyncService watchSync;
  final void Function(TvShellContentIntent) onContentIntent;
  final Future<bool> Function() hasConnections;
  final Future<void> Function() settleSession, pushProfileSelection;
  final Future<void> Function() refreshSeerrUser;
  final bool Function() hasActiveVideoPlayback, hasActiveCompanionSession;
  final bool isMobilePlatform, isRemoteHost;
  final Future<void> Function() startCompanionHost, checkForUpdates;

  /// Acts on a `plezytv://` link (launcher shelf rows, live TV, automation).
  final Future<void> Function(DeepLink link, {required bool isOffline}) launchDeepLink;
  final WatchTogetherProvider? watchTogether;
  final Future<bool> Function(WatchCopy) openWatchTogether;
  final bool isOfflineMode, initialPromptHandled;
  final Future<SettingsService> Function() settings;
  final Future<void> Function() clearVolatileCache;
  final DeepLinkService deepLinks;
  DeepLinkSession? _deepLinkSession;
  final Duration bindingFallback;
  final ContentRefreshResumeGate _contentResumeGate;
  final _profileResumeGate = ProfileSelectionResumeGate();
  final _coveredServers = <String>{};
  final _providerVersions = <PlexClient, int>{};
  final _providerSubscriptions = <PlexClient>{};
  bool _librariesReady = false;

  void _syncProviderSubscriptions() {
    if (!_alive || !_librariesReady) return;
    final clients = multiServer.serverManager.onlineClients.values.whereType<PlexClient>().toSet();
    for (final client in _providerSubscriptions.difference(clients)) {
      client.mediaProvidersVersion.removeListener(_syncProviderSubscriptions);
      _providerVersions.remove(client);
    }
    var changed = false;
    for (final client in clients) {
      if (!_providerSubscriptions.contains(client)) {
        client.mediaProvidersVersion.addListener(_syncProviderSubscriptions);
      }
      final version = client.mediaProvidersVersion.value;
      if ((_providerVersions[client] ?? 0) != version) changed = true;
      _providerVersions[client] = version;
    }
    _providerSubscriptions
      ..clear()
      ..addAll(clients);
    if (changed) unawaited(_guard(libraries.refresh));
  }

  StreamSubscription<Map<String, bool>>? _serverSubscription;
  Timer? _bindingTimer;
  bool _started = false, _disposed = false, _primingArmed = false, _primed = false;
  bool _isOffline, _offlineUntilConnected, _isReconnecting = false, _showingPicker = false;
  bool _wasBinding = false, _hadProfiles = false;
  bool _startupUpdatePending = false;
  String? _lastProfileId;

  bool get isDisposed => _disposed;
  bool get isOffline => _isOffline;
  bool get isReconnecting => _isReconnecting;
  bool get _alive => _started && !_disposed;

  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;
    _lastProfileId = activeProfile.activeId;
    _hadProfiles = activeProfile.profiles.isNotEmpty;
    activeProfile.addListener(_profileChanged);
    offlineMode.addListener(_offlineChanged);
    multiServer.addListener(_offlineChanged);
    WidgetsBinding.instance.addObserver(this);
    // MainScreen registers these from the route flag before reconciling the
    // provider. Keep navigation callbacks available after this session recovers.
    if (!isOfflineMode) {
      watchTogether?.navigatorOpener = _openWatch;
    }
    if (multiServer.hasConnectedServers) _offlineUntilConnected = false;
    _isOffline = shouldRenderMainScreenOffline(
      providerOffline: offlineMode.isOffline,
      startupOfflineUntilConnected: _offlineUntilConnected,
      hasVisibleConnectedServers: multiServer.hasConnectedServers,
    );
    notifyListeners();
    binder.start();
    if (!_isOffline) {
      unawaited(plexHome.start());
      _armStartup();
    }
    // MainScreen enters this bootstrap before its post-frame provider
    // reconciliation. Preserve its preferences, prompt and companion duties
    // for an online route even when the provider is already offline; only
    // the network services above depend on the reconciled state.
    if (!isOfflineMode || !_isOffline) {
      await preferences.ensureActiveLoaded();
      if (!_alive) return;
      await _initialPrompt();
      if (!_alive) return;
      final prefs = await settings();
      if (!_alive) return;
      if (isRemoteHost && prefs.read(SettingsService.enableCompanionRemoteServer)) {
        unawaited(_guard(startCompanionHost));
      }
    }
    if (!_alive) return;
    // Links act once the profile is settled and its preferences are loaded.
    _attachDeepLinks();
    // An online route still owes its startup check when bootstrap finds the
    // provider offline. A true offline launch does not acquire that duty.
    _startupUpdatePending = !isOfflineMode || !_isOffline;
    await _checkPendingStartupUpdate();
  }

  Future<void> _checkPendingStartupUpdate() async {
    if (!_alive || _isOffline || !_startupUpdatePending) return;
    final prefs = await settings();
    if (!_alive || _isOffline || !_startupUpdatePending) return;
    _startupUpdatePending = false;
    if (prefs.read(SettingsService.autoCheckUpdatesOnStartup)) {
      unawaited(_guard(checkForUpdates));
    }
  }

  Future<void> _guard(Future<void> Function() action) async {
    if (!_alive) return;
    try {
      await action();
    } catch (e, st) {
      appLogger.w('TV shell session service failed', error: e, stackTrace: st);
    }
  }

  void _armStartup() {
    if (!_alive || _primingArmed || _isOffline) return;
    _primingArmed = true;
    _bindingTimer = Timer(bindingFallback, () => _primeOnSettle(fromTimeout: true));
    _primeOnSettle();
    _resumeDownloads();
    _serverSubscription = multiServer.serverManager.statusStream.listen((_) {
      _resumeDownloads();
      _syncProviderSubscriptions();
    });
  }

  void _primeOnSettle({bool fromTimeout = false}) {
    if (!_alive || !_primingArmed || _primed || (activeProfile.isBinding && !fromTimeout)) return;
    _primed = !activeProfile.isBinding;
    _bindingTimer?.cancel();
    unawaited(_guard(_primeOnlineServices));
  }

  Future<void> _primeOnlineServices() async {
    if (!_alive || _isOffline) return;
    if (multiServer.serverManager.onlineServerIds.isNotEmpty && multiServer.hasConnectedServers) {
      libraries.initialize(multiServer.aggregationService);
      for (final client in multiServer.serverManager.onlineClients.values.whereType<PlexClient>()) {
        _providerVersions[client] = client.mediaProvidersVersion.value;
      }
      await libraries.loadLibraries();
      if (!_alive) return;
      _librariesReady = true;
      _syncProviderSubscriptions();
      watchSync.onServersConnected();
      unawaited(downloads.refreshMetadataFromCache());
      _resumeDownloads();
    }
    if (_alive) onContentIntent(TvShellContentIntent.initialLoad);
  }

  void _resumeDownloads() {
    final clients = multiServer.serverManager.onlineClients;
    final ids = clients.keys.toSet();
    final newlyOnline = ids.difference(_coveredServers);
    final MediaServerClient? client = clients.values.firstOrNull;
    if (!_alive || newlyOnline.isEmpty || client == null) {
      _coveredServers.retainAll(ids);
      return;
    }
    _coveredServers
      ..clear()
      ..addAll(ids);
    unawaited(
      _guard(() async {
        await downloads.ensureInitialized();
        if (!_alive) return;
        downloads.resumeQueuedDownloads(client);
        unawaited(downloads.syncDownloadCollections(multiServer.serverManager, newlyOnline));
      }),
    );
  }

  void _profileChanged() {
    if (!_alive) return;
    final action = profileInvalidationAction(
      previousProfileId: _lastProfileId,
      currentProfileId: activeProfile.activeId,
      wasBindingPreviously: _wasBinding,
      isBindingNow: activeProfile.isBinding,
    );
    _lastProfileId = activeProfile.activeId;
    _wasBinding = activeProfile.isBinding;
    final hasProfiles = activeProfile.profiles.isNotEmpty;
    if (!_hadProfiles && hasProfiles && activeProfile.activeId == null) unawaited(_guard(_initialPrompt));
    _hadProfiles = hasProfiles;
    if (action == ProfileInvalidationAction.invalidateNow) unawaited(_guard(_invalidate));
    _primeOnSettle();
  }

  Future<void> _initialPrompt() async {
    if (!_alive || initialPromptHandled || _showingPicker) return;
    await runInitialProfilePrompt(
      activeProfile: activeProfile,
      claimPrompt: () {
        if (!_alive || _showingPicker) return false;
        return _showingPicker = true;
      },
      releasePrompt: () => _showingPicker = false,
      isMounted: () => _alive,
      isOfflineMode: isOfflineMode,
      hasConnections: hasConnections,
      settleSession: settleSession,
      pushProfileSelection: _pushPicker,
      settings: settings,
    );
  }

  Future<void> _pushPicker() async {
    if (!_alive) return;
    _showingPicker = true;
    // A link waits for the viewer's choice; a different profile acts on it
    // in its own session.
    _detachDeepLinks();
    try {
      await pushProfileSelection();
    } finally {
      _showingPicker = false;
    }
    _attachDeepLinks();
  }

  /// Mirrors MainScreen: this profile session owns `plezytv://` links.
  void _attachDeepLinks() {
    if (!_alive || _showingPicker) return;
    final session = _deepLinkSession ??= DeepLinkSession(
      profileId: activeProfile.activeId,
      launch: (link) => _guard(() => launchDeepLink(link, isOffline: _isOffline)),
    );
    deepLinks.attach(session);
  }

  void _detachDeepLinks() {
    if (_deepLinkSession case final session?) deepLinks.detach(session);
  }

  Future<void> _invalidate() async {
    try {
      await clearVolatileCache();
    } catch (e, st) {
      appLogger.w('TV shell cache clear failed', error: e, stackTrace: st);
    }
    if (!_alive) return;
    await hiddenLibraries.refresh();
    if (!_alive) return;
    libraries.clear();
    if (multiServer.serverManager.serverIds.isNotEmpty) {
      watchSync.onServersConnected();
      unawaited(downloads.refreshMetadataFromCache());
      libraries.initialize(multiServer.aggregationService);
      await libraries.refresh();
      if (!_alive) return;
    }
    playbackState.clearShuffle();
    onContentIntent(TvShellContentIntent.fullReset);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_alive) return;
    final resumed = _profileResumeGate.consumePromptOn(state);
    final stale = _contentResumeGate.consumeRefreshOn(state);
    if (resumed) unawaited(_guard(refreshSeerrUser));
    if (shouldShowProfileSelectionOnResume(
      resumedFromBackground: resumed,
      isOffline: _isOffline,
      alreadyShowingProfileSelection: _showingPicker,
      isMobilePlatform: isMobilePlatform,
      hasActiveVideoPlayback: hasActiveVideoPlayback(),
      hasActiveCompanionRemoteSession: resumed && hasActiveCompanionSession(),
    )) {
      unawaited(
        _guard(() async {
          final prefs = await settings();
          if (_alive && !_showingPicker && activeProfile.requiresSelectionOnOpen(prefs)) await _pushPicker();
        }),
      );
    }
    if (stale && !_isOffline && _primed && !hasActiveVideoPlayback() && multiServer.hasConnectedServers) {
      onContentIntent(TvShellContentIntent.refreshAfterResume);
    }
  }

  void _offlineChanged() {
    if (!_alive) return;
    _syncProviderSubscriptions();
    if (multiServer.hasConnectedServers) _offlineUntilConnected = false;
    final offline = shouldRenderMainScreenOffline(
      providerOffline: offlineMode.isOffline,
      startupOfflineUntilConnected: _offlineUntilConnected,
      hasVisibleConnectedServers: multiServer.hasConnectedServers,
    );
    if (offline == _isOffline) return;
    _isOffline = offline;
    notifyListeners();
    if (!offline) unawaited(_guard(_enterOnline));
  }

  Future<void> _enterOnline() async {
    unawaited(plexHome.start());
    binder.start();
    if (!multiServer.hasConnectedServers && activeProfile.active != null) {
      await binder.rebindActive();
      if (!_alive) return;
    }
    await preferences.ensureActiveLoaded();
    if (!_alive) return;
    await _checkPendingStartupUpdate();
    if (!_alive) return;
    if (!_primingArmed) {
      _armStartup();
    } else {
      await _primeOnlineServices();
    }
  }

  /// Null means ignored (already running or disposed). False is a failed
  /// connection attempt, including service errors; the shell displays feedback.
  Future<bool?> retry() async {
    if (!_alive || _isReconnecting) return null;
    _isReconnecting = true;
    notifyListeners();
    try {
      binder.start();
      final manager = multiServer.serverManager;
      await manager.checkServerHealth();
      if (!_alive) return null;
      await manager.reconnectOfflineServers(forceRediscovery: true);
      if (!_alive) return null;
      if (shouldRetryActiveProfileBindAfterReconnect(
        hasActiveProfile: activeProfile.active != null,
        hasVisibleConnectedServers: multiServer.hasConnectedServers,
        hasManagerOnlineServers: manager.onlineServerIds.isNotEmpty,
        hasKnownOfflineServers: manager.offlineServerIds.isNotEmpty,
      )) {
        await binder.rebindActive();
      }
      if (!_alive) return null;
      if (!multiServer.hasConnectedServers) return false;
      _offlineUntilConnected = false;
      _offlineChanged();
      return !_isOffline;
    } catch (e, st) {
      appLogger.w('TV shell reconnect failed', error: e, stackTrace: st);
      return _alive ? false : null;
    } finally {
      if (_alive) {
        _isReconnecting = false;
        notifyListeners();
      }
    }
  }

  Future<bool> _openWatch(WatchCopy copy) async {
    if (!_alive) return false;
    try {
      return await openWatchTogether(copy);
    } catch (e) {
      appLogger.w('TV shell Watch Together navigation failed', error: e);
      return false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    if (_started) {
      activeProfile.removeListener(_profileChanged);
      offlineMode.removeListener(_offlineChanged);
      multiServer.removeListener(_offlineChanged);
    }
    for (final client in _providerSubscriptions) {
      client.mediaProvidersVersion.removeListener(_syncProviderSubscriptions);
    }
    _providerSubscriptions.clear();
    _providerVersions.clear();
    _serverSubscription?.cancel();
    _bindingTimer?.cancel();
    if (watchTogether?.navigatorOpener == _openWatch) watchTogether?.navigatorOpener = null;
    _detachDeepLinks();
    super.dispose();
  }
}
