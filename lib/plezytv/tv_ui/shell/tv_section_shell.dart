import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../focus/key_event_utils.dart';
import '../../../focus/dpad_navigator.dart';
import '../../../i18n/strings.g.dart';
import '../../../mixins/refreshable.dart';
import '../../../mixins/tab_visibility_aware.dart';
import '../../../navigation/main_screen_scope.dart';
import '../../../navigation/navigation_tabs.dart';
import '../../../navigation/page_refresh_shortcut.dart';
import '../../../navigation/profile_navigation_scope.dart';
import '../../../navigation/settings_shortcut.dart';
import '../../../providers/catalog_sources_provider.dart';
import '../../../providers/companion_remote_provider.dart';
import '../../../services/companion_remote/companion_remote_receiver.dart';
import '../../../models/companion_remote/remote_command.dart';
import '../../../providers/hidden_libraries_provider.dart';
import '../../../providers/libraries_provider.dart';
import '../../../providers/multi_server_provider.dart';
import '../../../screens/discover_screen.dart';
import '../../../screens/downloads/downloads_screen.dart';
import '../../../screens/explore_screen.dart';
import '../../../screens/libraries/libraries_screen.dart';
import '../../../screens/libraries/library_quick_picker_sheet.dart';
import '../../../screens/livetv/live_tv_screen.dart';
import '../../../screens/search_screen.dart';
import '../../../screens/settings/settings_screen.dart';
import '../../../services/app_exit_service.dart';
import '../../../services/music/music_playback_service.dart';
import '../../../services/settings_service.dart';
import '../../../utils/content_utils.dart';
import '../../../utils/desktop_window_padding.dart';
import '../../../utils/music_navigation.dart';
import '../../../widgets/auth_error_banner.dart';
import '../../../widgets/music/mini_player.dart';
import '../../../widgets/overlay_sheet.dart';
import '../components/tv_side_menu.dart';
import '../tv_settings.dart';
import '../tv_strings.dart';
import '../tv_theme.dart';
import '../tv_tokens.dart';
import 'tv_shell_section.dart';
import 'tv_no_connection_screen.dart';
import 'tv_shell_session_controller.dart';
import 'tv_shell_session_services.dart';

typedef TvSectionBuilder = Widget Function(BuildContext context, NavigationTabId tab, GlobalKey key);
typedef TvSessionControllerFactory =
    TvShellSessionController? Function(BuildContext context, void Function(TvShellContentIntent) onContentIntent);

/// TV home navigation and section surface.
class TvSectionShell extends StatefulWidget {
  const TvSectionShell({super.key, required this.isOfflineMode, required this.initialPromptHandled});

  final bool isOfflineMode;
  final bool initialPromptHandled;

  /// Return a stateful probe using [key]; implement the same capability mixins
  /// as a real section to observe focus, refresh, visibility and library loads.
  @visibleForTesting
  static TvSectionBuilder? sectionBuilderForTesting;
  @visibleForTesting
  static TvSessionControllerFactory? sessionControllerFactoryForTesting;

  @override
  State<TvSectionShell> createState() => TvSectionShellState();
}

class TvSectionShellState extends State<TvSectionShell> with RouteAware {
  final _keys = {for (final tab in NavigationTabId.values) tab: GlobalKey()};
  final _mountedTabs = <NavigationTabId>{};
  final _contentScope = FocusScopeNode(debugLabel: 'TV sections');
  final _retryFocus = FocusNode(debugLabel: 'TV retry connection');
  final _menuFocus = FocusNode(debugLabel: 'TV menu entry');
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  TvShellSection _current = const TvShellSection.tab(NavigationTabId.discover);
  int _selectionCommand = 0;
  int? _retryCommand;
  TvShellSection? _beforeOffline;
  bool _wasOffline = false;

  bool get _isOffline => _session?.isOffline ?? widget.isOfflineMode;
  TvShellSection get _root =>
      _isOffline ? const TvShellSection.noConnection() : const TvShellSection.tab(NavigationTabId.discover);
  NavigationTabId? _pendingStartup;
  bool _initialized = false, _selectionMade = false, _suppressBackAfterPop = false;
  Timer? _exitTimer;
  TvShellSessionController? _session;
  RouteObserver<PageRoute<dynamic>>? _observer;
  PageRoute<dynamic>? _route;
  MiniPlayerInsetController? _miniPlayerInsets;
  CompanionRemoteProvider? _companion;
  void Function(RemoteCommand)? _commandHandler;

  TvShellSection get currentSection => _current;
  int get selectionCommand => _selectionCommand;

  bool get _hasExplore =>
      (context.read<CatalogSourcesProvider?>()?.hasAnySource ?? false) &&
      (SettingsService.instanceOrNull?.read(SettingsService.showExploreTab) ?? true);

  List<NavigationTab> get availableTabs => NavigationTab.getVisibleTabs(
    isOffline: _isOffline,
    hasLiveTv: context.read<MultiServerProvider>().hasLiveTv,
    hasExplore: _hasExplore,
  );

  bool isSectionAvailable(TvShellSection section) => section.isNoConnection
      ? _isOffline
      : availableTabs.any((tab) => tab.id == section.tab) &&
            (section.libraryGlobalKey == null ||
                context.read<LibrariesProvider>().libraries.any((lib) => lib.globalKey == section.libraryGlobalKey));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = ProfileNavigationScope.maybeOf(context);
    final route = ModalRoute.of(context);
    if (_observer != scope?.routeObserver || _route != route) {
      _observer?.unsubscribe(this);
      _observer = scope?.routeObserver;
      _route = route is PageRoute ? route : null;
      if (_route != null) _observer?.subscribe(this, _route!);
    }
    _miniPlayerInsets = context.read<MiniPlayerInsetController?>();
    if (_initialized) return;
    _initialized = true;
    final factory = TvSectionShell.sessionControllerFactoryForTesting;
    _session = factory != null
        ? factory(context, handleContentIntent)
        : createTvShellSessionController(
            context,
            isOfflineMode: widget.isOfflineMode,
            initialPromptHandled: widget.initialPromptHandled,
            onContentIntent: handleContentIntent,
          );
    _session?.addListener(_sessionChanged);
    final preferred = SettingsService.instanceOrNull?.read(SettingsService.startupSection);
    if (preferred != null && !isSectionAvailable(TvShellSection.tab(preferred))) _pendingStartup = preferred;
    _wasOffline = _isOffline;
    _current = _isOffline
        ? const TvShellSection.noConnection()
        : TvShellSection.tab(
            preferred != null && isSectionAvailable(TvShellSection.tab(preferred))
                ? preferred
                : NavigationTabId.discover,
          );
    if (!_current.isNoConnection) _mountedTabs.add(_current.tab);
    _afterSelection(() {
      if (!_current.isNoConnection) _onScreen<TabVisibilityAware>(_current.tab, (screen) => screen.onTabShown());
      _focusContent(restore: false);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _setupCompanionRemote();
      unawaited(_session?.start());
    });
  }

  // Register after the first frame: the focus scope must exist before S5 sees
  // this State as ready and searches its descendants for library selection.
  void _setupCompanionRemote() {
    final receiver = CompanionRemoteReceiver.instance;
    _companion = context.read<CompanionRemoteProvider?>();
    _commandHandler = (command) {
      if (mounted) receiver.handleCommand(command, context);
    };
    _companion?.onCommandReceived = _commandHandler;
    receiver.navigationOwner = this;
    void tab(NavigationTabId id) => selectSection(TvShellSection.tab(id));
    void step(int direction) {
      final tabs = availableTabs;
      if (tabs.isEmpty) return;
      final index = _current.isNoConnection ? -1 : tabs.indexWhere((tab) => tab.id == _current.tab);
      tab(tabs[(index < 0 ? 0 : (index + direction) % tabs.length)].id);
    }

    receiver.onTabNext = () => step(1);
    receiver.onTabPrevious = () => step(-1);
    receiver.onTabDiscover = () => tab(NavigationTabId.discover);
    receiver.onTabLibraries = () => tab(NavigationTabId.libraries);
    receiver.onTabSearch = () => _search(null);
    receiver.onTabDownloads = () => tab(NavigationTabId.downloads);
    receiver.onTabSettings = () => tab(NavigationTabId.settings);
    receiver.onHome = () => selectSection(_root);
    receiver.onSearchAction = _search;
  }

  void _search(String? query) {
    const section = TvShellSection.tab(NavigationTabId.search);
    if (!isSectionAvailable(section)) return;
    final trimmed = query?.trim() ?? '';
    selectSection(section, focusContent: trimmed.isEmpty);
    _afterSelection(() {
      _onScreen<SearchInputFocusable>(NavigationTabId.search, (screen) {
        if (trimmed.isEmpty) {
          screen.focusSearchInput();
        } else {
          screen.submitSearchQuery(trimmed);
        }
      });
    });
  }

  void _sessionChanged() {
    if (!mounted) return;
    final offline = _isOffline;
    if (offline != _wasOffline) {
      _wasOffline = offline;
      _exitTimer?.cancel();
      if (offline) {
        _beforeOffline = _current;
      } else {
        final previous = _beforeOffline;
        _beforeOffline = null;
        if (_retryCommand == null || _retryCommand == _selectionCommand) {
          final target = previous != null && isSectionAvailable(previous) ? previous : _startupSection();
          selectSection(target, explicit: false);
        }
      }
    }
    setState(() {});
  }

  TvShellSection _startupSection() {
    final preferred = SettingsService.instanceOrNull?.read(SettingsService.startupSection);
    final section = preferred == null ? _root : TvShellSection.tab(preferred);
    return isSectionAvailable(section) ? section : _root;
  }

  Future<void> _retry() async {
    final session = _session;
    if (session == null || session.isReconnecting || _retryCommand != null) return;
    final command = _selectionCommand;
    _retryCommand = command;
    try {
      final success = await session.retry();
      if (!mounted || command != _selectionCommand) return;
      if (success == false) {
        (ProfileNavigationScope.maybeOf(context)?.mainScaffoldMessengerKey.currentState ?? _messengerKey.currentState)
            ?.showSnackBar(const SnackBar(content: Text(TvStrings.connectionFailed)));
      }
    } finally {
      _retryCommand = null;
    }
  }

  void _onScreen<T>(NavigationTabId tab, void Function(T) action) {
    final state = _keys[tab]?.currentState;
    if (state is T) action(state as T);
  }

  /// Delayed section work must belong to the latest selection command.
  void _afterSelection(VoidCallback action) {
    final command = _selectionCommand;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && command == _selectionCommand) action();
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void focusMenu() => _menuFocus.requestFocus();

  void _focusContent({bool restore = true}) {
    if (restore) _contentScope.requestFocus();
    _afterSelection(() {
      if (restore && _contentScope.focusedChild != null && _contentScope.hasFocus) return;
      if (_current.isNoConnection) {
        _retryFocus.requestFocus();
      } else {
        _onScreen<FocusableTab>(_current.tab, (screen) => screen.focusActiveTabIfReady());
      }
    });
  }

  void selectSection(TvShellSection section, {bool focusContent = true, bool explicit = true}) {
    if (!isSectionAvailable(section)) return;
    if (explicit) {
      _selectionMade = true;
      _pendingStartup = null;
    }
    final previous = _current;
    final changed = previous != section;
    // A repeated selection also cancels pending focus/load work.
    setState(() {
      _selectionCommand++;
      _current = section;
      if (!section.isNoConnection) _mountedTabs.add(section.tab);
      _exitTimer?.cancel();
    });
    if (!previous.isNoConnection && (section.isNoConnection || previous.tab != section.tab)) {
      _onScreen<TabVisibilityAware>(previous.tab, (screen) => screen.onTabHidden());
    }
    _afterSelection(() {
      if (!section.isNoConnection && (previous.isNoConnection || previous.tab != section.tab)) {
        _onScreen<TabVisibilityAware>(section.tab, (screen) => screen.onTabShown());
      }
      if (changed && section.libraryGlobalKey != null) {
        _onScreen<LibraryLoadable>(section.tab, (screen) => screen.loadLibraryByKey(section.libraryGlobalKey!));
      }
      if (changed && !section.isNoConnection && section.tab == NavigationTabId.discover) {
        _onScreen<Refreshable>(section.tab, (screen) => screen.refresh());
      }
      if (focusContent) _focusContent(restore: !changed);
    });
  }

  void selectLibrary(String key) => selectSection(TvShellSection.library(key));

  /// T2 sends distinct intents; only mounted content sections receive them.
  void handleContentIntent(TvShellContentIntent intent) {
    if (!mounted) return;
    if (intent == TvShellContentIntent.refreshAfterResume) {
      unawaited(context.read<LibrariesProvider>().refresh());
    }
    for (final tab in [NavigationTabId.discover, NavigationTabId.libraries, NavigationTabId.search]) {
      switch (intent) {
        case TvShellContentIntent.initialLoad:
          _onScreen<FullRefreshable>(tab, (screen) => screen.primeRefresh());
        case TvShellContentIntent.refreshAfterResume:
          _onScreen<Refreshable>(tab, (screen) => screen.refresh());
        case TvShellContentIntent.fullReset:
          _onScreen<FullRefreshable>(tab, (screen) => screen.fullRefresh());
      }
    }
  }

  void _back() {
    if (!_menuFocus.hasFocus) {
      focusMenu();
      return;
    }
    final root = _root;
    if (_current != root) {
      selectSection(root, focusContent: false);
      return;
    }
    if (_exitTimer?.isActive ?? false) {
      _exitTimer?.cancel();
      unawaited(AppExitService.requestExit());
    } else {
      _exitTimer = Timer(const Duration(seconds: 3), () {});
      (ProfileNavigationScope.maybeOf(context)?.mainScaffoldMessengerKey.currentState ??
              _messengerKey.currentState ??
              ScaffoldMessenger.maybeOf(context))
          ?.showSnackBar(SnackBar(content: Text(t.common.pressBackAgainToExit), duration: const Duration(seconds: 3)));
    }
  }

  KeyEventResult _keyEvent(FocusNode node, KeyEvent event) {
    if (_suppressBackAfterPop && event.logicalKey.isBackKey) {
      if (event is KeyUpEvent) _suppressBackAfterPop = false;
      return KeyEventResult.handled;
    }
    if (_menuFocus.hasFocus && event.logicalKey == LogicalKeyboardKey.arrowRight) {
      if (event is KeyDownEvent) _focusContent();
      return KeyEventResult.handled;
    }
    final refresh = dispatchPageRefreshShortcut(
      event,
      _current.isNoConnection ? null : _keys[_current.tab]?.currentState,
    );
    if (refresh == KeyEventResult.handled) return refresh;
    if (isSettingsShortcut(event)) {
      selectSection(const TvShellSection.tab(NavigationTabId.settings));
      return KeyEventResult.handled;
    }
    final keyboard = HardwareKeyboard.instance;
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.keyF &&
        (keyboard.isMetaPressed || keyboard.isControlPressed) &&
        !keyboard.isAltPressed &&
        !keyboard.isShiftPressed) {
      selectSection(const TvShellSection.tab(NavigationTabId.search));
      return KeyEventResult.handled;
    }
    return handleBackKeyAction(event, _back);
  }

  @override
  void didPushNext() {
    _miniPlayerInsets?.setNavBarSuspended(true);
    if (!_current.isNoConnection && _current.tab == NavigationTabId.discover) {
      _onScreen<TabVisibilityAware>(_current.tab, (screen) => screen.onTabHidden());
    }
  }

  @override
  void didPopNext() {
    _suppressBackAfterPop = true;
    if (BackKeyPressTracker.isBackKeyDown) BackKeyUpSuppressor.suppressBackUntilKeyUp();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _suppressBackAfterPop = false;
      });
    });
    _miniPlayerInsets?.setNavBarSuspended(false);
    if (!_current.isNoConnection && _current.tab == NavigationTabId.discover) {
      _onScreen<TabVisibilityAware>(_current.tab, (screen) => screen.onTabShown());
      _onScreen<Refreshable>(_current.tab, (screen) => screen.refresh());
    }
  }

  Widget _screen(NavigationTabId tab) {
    final key = _keys[tab]!;
    final probe = TvSectionShell.sectionBuilderForTesting;
    if (probe != null) return probe(context, tab, key);
    return switch (tab) {
      NavigationTabId.discover => DiscoverScreen(key: key),
      NavigationTabId.libraries => LibrariesScreen(
        key: key,
        onLibraryOrderChanged: () => setState(() {}),
        onLibrarySelected: (key) {
          if (_current.tab == NavigationTabId.libraries && _current.libraryGlobalKey != key) {
            setState(() {
              _selectionMade = true;
              _pendingStartup = null;
              _current = TvShellSection.library(key);
              _selectionCommand++;
              _exitTimer?.cancel();
            });
          }
        },
      ),
      NavigationTabId.liveTv => LiveTvScreen(key: key),
      NavigationTabId.explore => ExploreScreen(key: key),
      NavigationTabId.search => SearchScreen(key: key),
      NavigationTabId.downloads => DownloadsScreen(key: key),
      NavigationTabId.settings => SettingsScreen(key: key),
    };
  }

  Future<void> _showMore(BuildContext context) async {
    final controller = OverlaySheetController.of(context);
    final result = await controller.show<String>(
      showDragHandle: true,
      builder: (_) => Consumer<LibrariesProvider>(
        builder: (_, libraries, _) => LibraryQuickPickerSheet(
          libraries: libraries.libraries,
          selectedLibraryKey: _current.libraryGlobalKey,
          isLoading: libraries.isLoading,
          groupByServer: true,
          emptyMessage: t.libraries.noLibrariesFound,
          onSelected: controller.close,
        ),
      ),
    );
    if (mounted && result != null) selectLibrary(result);
  }

  Widget _surface(BuildContext context) {
    final libraries = context.watch<LibrariesProvider>();
    final hidden = context.watch<HiddenLibrariesProvider>().hiddenLibraryKeys;
    final servers = context.watch<MultiServerProvider>();
    context.watch<CatalogSourcesProvider?>();
    final music = context.watch<MusicPlaybackService?>();
    final tabs = availableTabs;
    final pending = _pendingStartup;
    if (!_isOffline && !_selectionMade && pending != null && tabs.any((tab) => tab.id == pending)) {
      _afterSelection(() {
        _pendingStartup = null;
        selectSection(TvShellSection.tab(pending), explicit: false);
      });
      // Only a completed load establishes that a selected library was removed.
      // ignore: invalid_use_of_visible_for_testing_member
    } else if ((_current.libraryGlobalKey == null || libraries.loadState == LibrariesLoadState.loaded) &&
        !isSectionAvailable(_current) &&
        !_isOffline) {
      _afterSelection(() {
        if (!_isOffline && !isSectionAvailable(_current)) {
          selectSection(_current.isNoConnection ? _startupSection() : _root, explicit: false);
        }
      });
    }
    final entries = <({TvShellSection? section, TvSideMenuItem item})>[];
    void addTab(NavigationTabId id) {
      final tab = tabs.where((tab) => tab.id == id).firstOrNull;
      if (tab == null) return;
      final section = TvShellSection.tab(id);
      entries.add((
        section: section,
        item: TvSideMenuItem(
          key: ValueKey(section),
          icon: tab.icon,
          label: tab.getLabel(),
          onSelect: () => selectSection(section),
        ),
      ));
    }

    addTab(NavigationTabId.search);
    addTab(NavigationTabId.discover);
    if (tabs.any((tab) => tab.id == NavigationTabId.libraries)) {
      final names = <String, int>{};
      for (final lib in libraries.libraries) {
        names.update(lib.title, (count) => count + 1, ifAbsent: () => 1);
      }
      for (final lib in libraries.libraries.where((lib) => !hidden.contains(lib.globalKey))) {
        final section = TvShellSection.library(lib.globalKey);
        entries.add((
          section: section,
          item: TvSideMenuItem(
            key: ValueKey(section),
            icon: ContentTypeHelper.getLibraryIcon(lib.kind.id),
            label: names[lib.title]! > 1 && lib.serverName != null ? '${lib.title} · ${lib.serverName}' : lib.title,
            onSelect: () => selectLibrary(lib.globalKey),
          ),
        ));
      }
      if (libraries.libraries.any((lib) => hidden.contains(lib.globalKey)) || servers.totalServerCount > 1) {
        entries.add((
          section: null,
          item: TvSideMenuItem(
            key: const ValueKey('more'),
            icon: Icons.more_horiz,
            label: TvStrings.moreLibraries,
            onSelect: () => unawaited(_showMore(context)),
          ),
        ));
      }
    }
    addTab(NavigationTabId.liveTv);
    addTab(NavigationTabId.explore);
    if (music?.currentTrack != null && !_isOffline) {
      entries.add((
        section: null,
        item: TvSideMenuItem(
          key: const ValueKey('nowPlaying'),
          icon: Icons.music_note,
          label: t.music.nowPlaying,
          onSelect: () => unawaited(openNowPlaying(context)),
        ),
      ));
    }
    if (SettingsService.instanceOrNull?.read(TvSettings.showDownloads) ?? false) addTab(NavigationTabId.downloads);
    addTab(NavigationTabId.settings);
    final index = entries.indexWhere((entry) => entry.section == _current);
    final width = TvTheme.of(context).px(TvTokens.size.sidebar.collapsedW);
    return MainScreenFocusScope(
      focusSidebar: focusMenu,
      selectLibrary: selectLibrary,
      openSettings: () => selectSection(const TvShellSection.tab(NavigationTabId.settings)),
      sideNavigationWidth: width,
      reservedSideNavigationWidth: width,
      foregroundLeft: width,
      foregroundWidth: MediaQuery.sizeOf(context).width - width,
      viewportWidth: MediaQuery.sizeOf(context).width,
      child: SideNavigationScope(
        child: TvSideMenu(
          focusNode: _menuFocus,
          items: entries.map((entry) => entry.item).toList(),
          currentIndex: index < 0 ? null : index,
          dividerBeforeIndex: entries.length - 1,
          child: Padding(
            padding: EdgeInsets.only(left: width),
            child: FocusScope(
              node: _contentScope,
              child: Column(
                children: [
                  const AuthErrorBanner(),
                  Expanded(
                    child: IndexedStack(
                      index: _current.isNoConnection ? NavigationTabId.values.length : _current.tab.index,
                      children: [
                        for (final tab in NavigationTabId.values)
                          TickerMode(
                            enabled: !_current.isNoConnection && _current.tab == tab,
                            child: _mountedTabs.contains(tab) ? _screen(tab) : const SizedBox.shrink(),
                          ),
                        TvNoConnectionScreen(
                          retryFocus: _retryFocus,
                          reconnecting: _session?.isReconnecting ?? false,
                          onRetry: () => unawaited(_retry()),
                          onSettings: () => selectSection(const TvShellSection.tab(NavigationTabId.settings)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => TvTheme(
    child: ScaffoldMessenger(
      key: ProfileNavigationScope.maybeOf(context)?.mainScaffoldMessengerKey ?? _messengerKey,
      child: Scaffold(
        body: OverlaySheetHost(
          canPop: false,
          onSystemBack: () {
            if (!BackKeyCoordinator.consumeIfHandled()) _back();
          },
          child: Focus(
            onKeyEvent: _keyEvent,
            child: ListenableBuilder(
              listenable: Listenable.merge([
                if (SettingsService.instanceOrNull case final settings?) ...[
                  settings.listenable(TvSettings.showDownloads),
                  settings.listenable(SettingsService.showExploreTab),
                ],
              ]),
              builder: (context, _) => _surface(context),
            ),
          ),
        ),
      ),
    ),
  );

  @override
  void dispose() {
    final receiver = CompanionRemoteReceiver.instance;
    if (identical(_companion?.onCommandReceived, _commandHandler)) _companion?.onCommandReceived = null;
    if (identical(receiver.navigationOwner, this)) {
      receiver.onTabNext = null;
      receiver.onTabPrevious = null;
      receiver.onTabDiscover = null;
      receiver.onTabLibraries = null;
      receiver.onTabSearch = null;
      receiver.onTabDownloads = null;
      receiver.onTabSettings = null;
      receiver.onHome = null;
      receiver.onSearchAction = null;
      receiver.navigationOwner = null;
    }
    _observer?.unsubscribe(this);
    _exitTimer?.cancel();
    _session?.removeListener(_sessionChanged);
    _session?.dispose();
    _retryFocus.dispose();
    _menuFocus.dispose();
    _contentScope.dispose();
    super.dispose();
  }
}
