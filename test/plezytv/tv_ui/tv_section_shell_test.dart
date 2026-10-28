import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:plezy/media/ids.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:plezy/focus/dpad_navigator.dart';
import 'package:plezy/focus/input_mode_tracker.dart';
import 'package:plezy/focus/key_event_utils.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/providers/catalog_sources_provider.dart';
import 'package:plezy/services/catalog/catalog_source.dart';
import 'package:plezy/services/companion_remote/companion_remote_receiver.dart';
import 'package:plezy/services/music/music_playback_service.dart';
import 'package:plezy/media/media_library.dart';
import 'package:plezy/mixins/refreshable.dart';
import 'package:plezy/mixins/tab_visibility_aware.dart';
import 'package:plezy/navigation/main_screen_scope.dart';
import 'package:plezy/navigation/navigation_tabs.dart';
import 'package:plezy/navigation/profile_navigation_scope.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_side_menu.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_button.dart';
import 'package:plezy/plezytv/tv_ui/tv_strings.dart';
import 'package:plezy/plezytv/tv_ui/tv_tokens.dart';
import 'package:plezy/plezytv/tv_ui/shell/tv_section_shell.dart';
import 'package:plezy/plezytv/tv_ui/shell/tv_shell_section.dart';
import 'package:plezy/plezytv/tv_ui/shell/tv_shell_session_controller.dart';
import 'package:plezy/plezytv/tv_ui/tv_settings.dart';
import 'package:plezy/providers/hidden_libraries_provider.dart';
import 'package:plezy/providers/libraries_provider.dart';
import 'package:plezy/providers/multi_server_provider.dart';
import 'package:plezy/screens/libraries/library_quick_picker_sheet.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/widgets/overlay_sheet.dart';

import 'package:plezy/providers/discover_provider.dart';
import 'package:plezy/plezytv/tv_ui/home/tv_home_screen.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_horizontal_row.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_hero.dart';
import 'package:plezy/media/media_hub.dart';
import 'package:plezy/media/media_server_client.dart';
import '../../test_helpers/media_items.dart';

import '../../test_helpers/prefs.dart';
import '../../test_helpers/stub_music_playback_service.dart';

class _HomeDiscover extends ChangeNotifier implements DiscoverProvider {
  @override
  List<MediaItem> onDeck = [testMediaItem(id: 'first', title: 'first'), testMediaItem(id: 'second', title: 'second')];
  @override
  List<MediaHub> hubs = [];
  @override
  bool isLoading = false, areHubsLoading = false, isLoadInFlight = false, hasMoreContinueWatching = false;
  @override
  String? errorMessage;
  int loads = 0, staleChecks = 0, continues = 0;
  void emit() => notifyListeners();
  @override
  Future<void> load() async {
    loads++;
  }

  @override
  bool refreshIfStale() {
    staleChecks++;
    return false;
  }

  @override
  Future<void> refreshContinueWatching() async {
    continues++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Libraries extends ChangeNotifier implements LibrariesProvider {
  @override
  List<MediaLibrary> libraries = [];
  @override
  LibrariesLoadState loadState = LibrariesLoadState.loaded;
  @override
  bool get isLoading => loadState == LibrariesLoadState.loading;
  int refreshes = 0;
  @override
  Future<void> refresh() async {
    refreshes++;
  }

  void emit() => notifyListeners();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Hidden extends ChangeNotifier implements HiddenLibrariesProvider {
  @override
  Future<void> ensureInitialized() async {}
  @override
  Set<String> hiddenLibraryKeys = {};
  void emit() => notifyListeners();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Servers extends ChangeNotifier implements MultiServerProvider {
  @override
  MediaServerClient? getClientForServer(ServerId serverId) => null;
  @override
  bool hasLiveTv = false;
  @override
  int totalServerCount = 1;
  @override
  List<({String displayName, ServerId serverId})> get authErrorServers => [];
  @override
  List<({String displayName, ServerId serverId})> get accessDeniedServers => [];
  void emit() => notifyListeners();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Sources extends ChangeNotifier implements CatalogSourcesProvider {
  @override
  bool hasAnySource = false;
  @override
  List<CatalogSource> watchlistCapableSources = [];
  void emit() => notifyListeners();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Music extends StubMusicPlaybackService {
  @override
  MediaItem? currentTrack;
  @override
  MusicPlaybackStatus get status => MusicPlaybackStatus.paused;
  void emit() => notifyListeners();
}

class _Session extends ChangeNotifier implements TvShellSessionController {
  _Session(this.emitIntent);
  final void Function(TvShellContentIntent) emitIntent;
  @override
  bool isOffline = false;
  void offline(bool value) {
    isOffline = value;
    notifyListeners();
  }

  Completer<bool?>? attempt;
  int retries = 0;
  @override
  Future<bool?> retry() async {
    retries++;
    isReconnecting = true;
    notifyListeners();
    final result = await attempt!.future;
    if (result == true) offline(false);
    isReconnecting = false;
    notifyListeners();
    return result;
  }

  @override
  bool isReconnecting = false;
  @override
  Future<void> start() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Probe extends StatefulWidget {
  const _Probe({required super.key, required this.tab});
  final NavigationTabId tab;
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe>
    with Refreshable, FullRefreshable, FocusableTab, LibraryLoadable, TabVisibilityAware, ManualRefreshable {
  final first = FocusNode();
  final second = FocusNode();
  int primes = 0, refreshes = 0, resets = 0, shown = 0, hidden = 0, manualRefreshes = 0;
  final loads = <String>[];
  bool consumeBack = false;
  @override
  void primeRefresh() => primes++;
  @override
  void manualRefresh() => manualRefreshes++;
  @override
  void refresh() => refreshes++;
  @override
  void fullRefresh() => resets++;
  @override
  void loadLibraryByKey(String key) => loads.add(key);
  @override
  void focusActiveTabIfReady() => first.requestFocus();
  @override
  void onTabShown() => shown++;
  @override
  void onTabHidden() => hidden++;
  @override
  Widget build(BuildContext context) => Focus(
    onKeyEvent: (_, event) {
      if (consumeBack && event.logicalKey == LogicalKeyboardKey.escape) {
        return handleBackKeyAction(event, () => consumeBack = false);
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        if (event is KeyDownEvent) MainScreenFocusScope.focusSidebarOf(context);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: Row(
      children: [
        TextButton(focusNode: first, onPressed: () {}, child: Text('${widget.tab.name} first')),
        TextButton(focusNode: second, onPressed: () {}, child: const Text('second')),
      ],
    ),
  );
  @override
  void dispose() {
    first.dispose();
    second.dispose();
    super.dispose();
  }
}

class _CatalogSource implements CatalogSource {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _WatchlistProbe extends StatefulWidget {
  const _WatchlistProbe({required super.key, required this.onOpenSearch});
  final VoidCallback onOpenSearch;
  @override
  State<_WatchlistProbe> createState() => _WatchlistProbeState();
}

class _WatchlistProbeState extends State<_WatchlistProbe>
    with Refreshable, FullRefreshable, FocusableTab, TabVisibilityAware {
  final first = FocusNode();
  int refreshes = 0, resets = 0, shown = 0, hidden = 0;
  @override
  void refresh() => refreshes++;
  @override
  void fullRefresh() => resets++;
  @override
  void focusActiveTabIfReady() => first.requestFocus();
  @override
  void onTabShown() => shown++;
  @override
  void onTabHidden() => hidden++;
  @override
  Widget build(BuildContext context) =>
      TextButton(focusNode: first, onPressed: widget.onOpenSearch, child: const Text('watchlist first'));
  @override
  void dispose() {
    first.dispose();
    super.dispose();
  }
}

class _ExitBinding extends AutomatedTestWidgetsFlutterBinding {
  int exits = 0;
  @override
  Future<ui.AppExitResponse> exitApplication(ui.AppExitType type, [int exitCode = 0]) async {
    exits++;
    return ui.AppExitResponse.exit;
  }
}

const home = TvShellSection.tab(NavigationTabId.discover);
const search = TvShellSection.tab(NavigationTabId.search);
const movies = MediaLibrary(id: '1', backend: MediaBackend.plex, title: 'Movies', serverId: 's1', serverName: 'One');
const watchlist = TvShellSection.watchlist();
const series = MediaLibrary(id: '2', backend: MediaBackend.plex, title: 'Series', serverId: 's1');

void main() {
  final binding = _ExitBinding();
  late _Libraries libraries;
  late _Hidden hidden;
  late _Servers servers;
  late _Sources sources;
  late _Music music;
  late _Session session;
  bool offlineStart = false;
  bool realHome = false;
  late _HomeDiscover homeProvider;
  late GlobalKey<TvSectionShellState> shell;
  late GlobalKey<NavigatorState> navigator;
  late RouteObserver<PageRoute<dynamic>> observer;
  final probes = <NavigationTabId, GlobalKey>{};
  _ProbeState probe(NavigationTabId tab) => probes[tab]!.currentState! as _ProbeState;
  GlobalKey? watchlistKey;
  _WatchlistProbeState watchlistProbe() => watchlistKey!.currentState! as _WatchlistProbeState;
  TvSideMenu menu(WidgetTester tester) => tester.widget(find.byType(TvSideMenu));
  bool menuShowsFocus(WidgetTester tester, String label) =>
      tester.widget<Text>(find.text(label)).style?.color == TvTokens.color.text.onFocus;

  Future<void> pump(WidgetTester tester) async {
    await SettingsService.getInstance();
    // Keyboard mode, so menu items draw their focus visuals.
    await tester.pumpWidget(const InputModeTracker(child: SizedBox.shrink()));
    InputModeTracker.reportNonPointerInput();
    await tester.pump();
    await tester.pumpWidget(
      InputModeTracker(
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider<DiscoverProvider>.value(value: homeProvider),
            ChangeNotifierProvider<LibrariesProvider>.value(value: libraries),
            ChangeNotifierProvider<HiddenLibrariesProvider>.value(value: hidden),
            ChangeNotifierProvider<MultiServerProvider>.value(value: servers),
            ChangeNotifierProvider<CatalogSourcesProvider>.value(value: sources),
            ChangeNotifierProvider<MusicPlaybackService>.value(value: music),
          ],
          child: MaterialApp(
            navigatorKey: navigator,
            navigatorObservers: [observer],
            home: ProfileNavigationScope(
              navigatorKey: navigator,
              routeObserver: observer,
              mainScaffoldMessengerKey: GlobalKey<ScaffoldMessengerState>(),
              child: TvSectionShell(key: shell, isOfflineMode: false, initialPromptHandled: true),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> key(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }

  setUp(() {
    offlineStart = false;
    realHome = false;
    homeProvider = _HomeDiscover();
    resetSharedPreferencesForTest();
    libraries = _Libraries()..libraries = [movies, series];
    hidden = _Hidden();
    servers = _Servers();
    sources = _Sources();
    music = _Music();
    shell = GlobalKey<TvSectionShellState>();
    navigator = GlobalKey<NavigatorState>();
    observer = RouteObserver<PageRoute<dynamic>>();
    probes.clear();
    watchlistKey = null;
    TvSectionShell.watchlistBuilderForTesting = (_, key, onOpenSearch) {
      watchlistKey = key;
      return _WatchlistProbe(key: key, onOpenSearch: onOpenSearch);
    };
    TvSectionShell.sessionControllerFactoryForTesting = (_, emit) =>
        session = (_Session(emit)..isOffline = offlineStart);
    TvSectionShell.sectionBuilderForTesting = (_, tab, key) {
      if (realHome && tab == NavigationTabId.discover) return TvHomeScreen(key: key);
      probes[tab] = key;
      return _Probe(key: key, tab: tab);
    };
  });
  tearDown(() {
    TvSectionShell.sectionBuilderForTesting = null;
    TvSectionShell.watchlistBuilderForTesting = null;
    TvSectionShell.sessionControllerFactoryForTesting = null;
    BackKeyCoordinator.clear();
    BackKeyUpSuppressor.clearSuppression();
    homeProvider.dispose();
    libraries.dispose();
    hidden.dispose();
    servers.dispose();
    sources.dispose();
    music.dispose();
  });

  TvButton retryButton(WidgetTester tester) => tester.widget<TvButton>(
    find.widgetWithText(TvButton, session.isReconnecting ? TvStrings.connecting : TvStrings.retry),
  );

  testWidgets('T4 real Home receives shell lifecycle and Back/left hooks', (tester) async {
    realHome = true;
    await pump(tester);
    expect(find.byType(TvHomeScreen), findsOneWidget);
    expect(homeProvider.loads, 0);
    homeProvider.isLoadInFlight = true;
    session.emitIntent(TvShellContentIntent.initialLoad);
    expect(homeProvider.loads, 0);
    homeProvider.isLoadInFlight = false;
    session.emitIntent(TvShellContentIntent.refreshAfterResume);
    expect(homeProvider.continues, 1);
    session.emitIntent(TvShellContentIntent.fullReset);
    expect(homeProvider.loads, 1);
    final rail = tester.state<TvHorizontalRowState>(find.byType(TvHorizontalRow));
    expect(rail.focusInside.value, isTrue);
    await key(tester, LogicalKeyboardKey.arrowRight);
    expect(rail.focusedIndex, 1);
    await key(tester, LogicalKeyboardKey.escape);
    expect(rail.focusedIndex, 0);
    expect(rail.focusInside.value, isTrue);
    await key(tester, LogicalKeyboardKey.escape);
    expect(menu(tester).focusNode!.hasFocus, isTrue);
    await key(tester, LogicalKeyboardKey.arrowRight);
    expect(rail.focusInside.value, isTrue);
    await key(tester, LogicalKeyboardKey.arrowLeft);
    expect(menu(tester).focusNode!.hasFocus, isTrue);
    final beforeShown = homeProvider.staleChecks;
    shell.currentState!.selectSection(const TvShellSection.tab(NavigationTabId.settings));
    await tester.pumpAndSettle();
    shell.currentState!.selectSection(const TvShellSection.tab(NavigationTabId.discover));
    await tester.pumpAndSettle();
    expect(homeProvider.staleChecks, beforeShown + 2); // onTabShown and refresh
    expect(rail.focusInside.value, isTrue);
  });

  for (final hadContinue in [false, true]) {
    for (final lowerRail in [false, true]) {
      testWidgets('T4 shell return reveals shifted rail (hadContinue=$hadContinue lower=$lowerRail)', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1920, 1080);
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        realHome = true;
        homeProvider.onDeck = hadContinue ? [testMediaItem(id: 'episode', title: 'Episode')] : [];
        homeProvider.hubs = [
          for (var i = 0; i < 4; i++)
            MediaHub(
              id: 'hub$i',
              title: 'Hub $i',
              type: 'movie',
              items: [testMediaItem(id: 'movie$i', title: 'Movie $i')],
            ),
        ];
        await pump(tester);
        final hubIndex = lowerRail
            ? 2
            : hadContinue
            ? 1
            : 0;
        final beforeIndex = hubIndex + (hadContinue ? 1 : 0);
        for (var i = 0; i < beforeIndex; i++) {
          await key(tester, LogicalKeyboardKey.arrowDown);
        }
        final target = tester.widget<TvHero>(find.byType(TvHero)).item!.globalKey;
        unawaited(
          navigator.currentState!.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('Details')))),
        );
        await tester.pumpAndSettle();
        homeProvider.onDeck = hadContinue ? [] : [testMediaItem(id: 'episode', title: 'Episode')];
        homeProvider.emit();
        await tester.pumpAndSettle();
        navigator.currentState!.pop();
        await tester.pumpAndSettle();
        final afterIndex = hubIndex + (hadContinue ? 0 : 1);
        final restoredRail = find.byWidgetPredicate(
          (widget) => widget is TvHorizontalRow && widget.title == 'Hub $hubIndex',
          skipOffstage: false,
        );
        final restored = tester.state<TvHorizontalRowState>(restoredRail);
        final hero = tester.widget<TvHero>(find.byType(TvHero));
        expect(restored.focusInside.value, isTrue);
        expect(hero.item!.globalKey, target);
        expect(hero.compact, afterIndex > 1);
        expect(tester.getTopLeft(restoredRail).dy, afterIndex > 1 ? 254 : 394);
      });
    }
  }

  testWidgets('T4 A17: loading Home never takes focus back from Settings', (tester) async {
    realHome = true;
    homeProvider.onDeck = [];
    homeProvider.isLoading = homeProvider.areHubsLoading = true;
    await pump(tester);
    shell.currentState!.selectSection(const TvShellSection.tab(NavigationTabId.settings));
    await tester.pumpAndSettle();
    final settingsFocus = FocusManager.instance.primaryFocus;
    expect(probe(NavigationTabId.settings).first.hasFocus, isTrue);
    homeProvider.onDeck = [testMediaItem(id: 'arrived')];
    homeProvider.isLoading = homeProvider.areHubsLoading = false;
    homeProvider.emit();
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus, same(settingsFocus));
  });

  testWidgets('T4 A10c: offline shell does not mount Home', (tester) async {
    realHome = true;
    offlineStart = true;
    await pump(tester);
    expect(find.byType(TvHomeScreen), findsNothing);
    expect(find.text(TvStrings.noConnection), findsOneWidget);
    expect(homeProvider.loads, 0);
  });

  testWidgets('O1/O2 offline launch focuses Retry, settings opens section, downloads follows N1', (tester) async {
    offlineStart = true;
    await pump(tester);
    expect(shell.currentState!.currentSection, const TvShellSection.noConnection());
    expect(probes, isEmpty);
    expect(find.text(TvStrings.noConnection), findsOneWidget);
    expect(retryButton(tester).focusNode!.hasFocus, isTrue);
    expect(menu(tester).items.map((item) => item.label), [t.common.settings]);
    expect(menu(tester).currentIndex, isNull);
    await key(tester, LogicalKeyboardKey.arrowLeft);
    expect(find.text(t.common.settings), findsOneWidget);
    await key(tester, LogicalKeyboardKey.arrowRight);
    expect(retryButton(tester).focusNode!.hasFocus, isTrue);
    await SettingsService.instance.write(TvSettings.showDownloads, true);
    await tester.pumpAndSettle();
    expect(menu(tester).items.map((item) => item.label), [t.navigation.downloads, t.common.settings]);
    tester.widget<TvButton>(find.widgetWithText(TvButton, TvStrings.connectionSettings)).onSelect!();
    await tester.pumpAndSettle();
    expect(shell.currentState!.currentSection, const TvShellSection.tab(NavigationTabId.settings));
    expect(probe(NavigationTabId.settings).first.hasFocus, isTrue);
    shell.currentState!.focusMenu();
    await tester.pumpAndSettle();
    await key(tester, LogicalKeyboardKey.escape);
    expect(shell.currentState!.currentSection, const TvShellSection.noConnection());
    await key(tester, LogicalKeyboardKey.arrowRight);
    expect(retryButton(tester).focusNode!.hasFocus, isTrue);
    await key(tester, LogicalKeyboardKey.escape);
    await key(tester, LogicalKeyboardKey.escape);
    expect(find.text(t.common.pressBackAgainToExit), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('O1/O3 Retry shows disabled Connecting then configured startup and full menu', (tester) async {
    final settings = await SettingsService.getInstance();
    await settings.write(SettingsService.startupSection, NavigationTabId.downloads);
    offlineStart = true;
    await pump(tester);
    session.attempt = Completer<bool?>();
    retryButton(tester).onSelect!();
    await tester.pumpAndSettle();
    expect(retryButton(tester).label, TvStrings.connecting);
    expect(retryButton(tester).disabled, isTrue);
    retryButton(tester).onSelect!();
    expect(session.retries, 1);
    session.attempt!.complete(true);
    await tester.pumpAndSettle();
    expect(shell.currentState!.currentSection, const TvShellSection.tab(NavigationTabId.downloads));
    expect(probe(NavigationTabId.downloads).first.hasFocus, isTrue);
    expect(menu(tester).items.map((item) => item.label), contains(t.common.home));
  });

  testWidgets('O3 offline startup retains deferred Live TV preference until binding exposes it', (tester) async {
    final settings = await SettingsService.getInstance();
    await settings.write(SettingsService.startupSection, NavigationTabId.liveTv);
    offlineStart = true;
    await pump(tester);
    session.offline(false);
    await tester.pumpAndSettle();
    expect(shell.currentState!.currentSection, home);
    servers.hasLiveTv = true;
    servers.emit();
    await tester.pumpAndSettle();
    expect(shell.currentState!.currentSection, const TvShellSection.tab(NavigationTabId.liveTv));
  });

  testWidgets('O1 failed retry reports failure and permits another attempt', (tester) async {
    offlineStart = true;
    await pump(tester);
    session.attempt = Completer<bool?>();
    retryButton(tester).onSelect!();
    session.attempt!.complete(false);
    await tester.pumpAndSettle();
    expect(find.text(TvStrings.connectionFailed), findsOneWidget);
    expect(shell.currentState!.currentSection, const TvShellSection.noConnection());
    expect(retryButton(tester).disabled, isFalse);
  });

  testWidgets('O4 soft loss retains Series and focus; offline Back root; O3 auto return restores Series', (
    tester,
  ) async {
    await pump(tester);
    shell.currentState!.selectLibrary(series.globalKey);
    await tester.pumpAndSettle();
    final state = probe(NavigationTabId.libraries);
    state.second.requestFocus();
    await tester.pump();
    session.offline(true);
    await tester.pumpAndSettle();
    expect(shell.currentState!.currentSection, TvShellSection.library(series.globalKey));
    expect(state.second.hasFocus, isTrue);
    expect(state.hidden, 0);
    expect(menu(tester).items.map((item) => item.label), [t.common.settings]);
    expect(menu(tester).currentIndex, isNull);
    await key(tester, LogicalKeyboardKey.escape);
    await key(tester, LogicalKeyboardKey.escape);
    expect(shell.currentState!.currentSection, const TvShellSection.noConnection());
    session.offline(false);
    await tester.pumpAndSettle();
    expect(shell.currentState!.currentSection, TvShellSection.library(series.globalKey));
    expect(state.loads, [series.globalKey, series.globalKey]);
  });

  testWidgets('O3 deleted offline library falls back to configured startup', (tester) async {
    final settings = await SettingsService.getInstance();
    await settings.write(SettingsService.startupSection, NavigationTabId.search);
    await pump(tester);
    shell.currentState!.selectLibrary(series.globalKey);
    await tester.pumpAndSettle();
    session.offline(true);
    libraries.libraries = [movies];
    libraries.emit();
    await tester.pumpAndSettle();
    expect(shell.currentState!.currentSection, TvShellSection.library(series.globalKey));
    session.offline(false);
    await tester.pumpAndSettle();
    expect(shell.currentState!.currentSection, search);
  });

  testWidgets('O3 Live TV and Explore snapshots require availability on return', (tester) async {
    await pump(tester);
    for (final tab in [NavigationTabId.liveTv, NavigationTabId.explore]) {
      servers.hasLiveTv = true;
      sources.hasAnySource = true;
      servers.emit();
      sources.emit();
      await tester.pumpAndSettle();
      shell.currentState!.selectSection(TvShellSection.tab(tab));
      await tester.pumpAndSettle();
      session.offline(true);
      servers.hasLiveTv = false;
      sources.hasAnySource = false;
      servers.emit();
      sources.emit();
      await tester.pumpAndSettle();
      expect(shell.currentState!.currentSection, TvShellSection.tab(tab));
      session.offline(false);
      await tester.pumpAndSettle();
      expect(shell.currentState!.currentSection, home);
    }
  });

  testWidgets('O3 retry completion after new selection keeps section and its focus', (tester) async {
    await pump(tester);
    shell.currentState!.selectLibrary(series.globalKey);
    await tester.pumpAndSettle();
    session.offline(true);
    shell.currentState!.focusMenu();
    await tester.pumpAndSettle();
    await key(tester, LogicalKeyboardKey.escape);
    session.attempt = Completer<bool?>();
    retryButton(tester).onSelect!();
    shell.currentState!.selectSection(const TvShellSection.tab(NavigationTabId.settings));
    await tester.pumpAndSettle();
    final command = shell.currentState!.selectionCommand;
    session.attempt!.complete(true);
    await tester.pumpAndSettle();
    expect(shell.currentState!.selectionCommand, command);
    expect(shell.currentState!.currentSection, const TvShellSection.tab(NavigationTabId.settings));
    expect(probe(NavigationTabId.settings).first.hasFocus, isTrue);
  });

  testWidgets('S1 home starts focused with collapsed menu; F1/F2/F5 restore exact child', (tester) async {
    await pump(tester);
    final state = probe(NavigationTabId.discover);
    expect(state.first.hasFocus, isTrue);
    expect(menu(tester).currentIndex, 1);
    expect(find.text(t.common.home), findsNothing);
    state.second.requestFocus();
    await tester.pump();
    await key(tester, LogicalKeyboardKey.arrowLeft);
    expect(find.text(t.common.home), findsOneWidget);
    await key(tester, LogicalKeyboardKey.arrowRight);
    expect(state.second.hasFocus, isTrue);
    expect(find.text(t.common.home), findsNothing);
    shell.currentState!.focusMenu();
    await tester.pumpAndSettle();
    menu(tester).items[1].onSelect!();
    await tester.pumpAndSettle();
    expect(state.second.hasFocus, isTrue);
    expect(state.refreshes, 0);
  });

  testWidgets('S1 configured Downloads starts focused even when absent from menu', (tester) async {
    final settings = await SettingsService.getInstance();
    await settings.write(SettingsService.startupSection, NavigationTabId.downloads);
    await pump(tester);
    expect(shell.currentState!.currentSection, const TvShellSection.tab(NavigationTabId.downloads));
    expect(probe(NavigationTabId.downloads).first.hasFocus, isTrue);
    expect(menu(tester).currentIndex, isNull);
  });

  testWidgets('D2b refresh, search and settings shortcuts reuse sections', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await pump(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await key(tester, LogicalKeyboardKey.keyR);
    expect(probe(NavigationTabId.discover).manualRefreshes, 1);
    await key(tester, LogicalKeyboardKey.keyF);
    expect(shell.currentState!.currentSection, search);
    await key(tester, LogicalKeyboardKey.comma);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(shell.currentState!.currentSection, const TvShellSection.tab(NavigationTabId.settings));
    expect(navigator.currentState!.canPop(), isFalse);
    debugDefaultTargetPlatformOverride = null;
  });
  testWidgets('F3/F4 content handles Back first, then menu, root, hint, exit with expiry', (tester) async {
    binding.exits = 0;
    await pump(tester);
    shell.currentState!.selectLibrary(movies.globalKey);
    await tester.pumpAndSettle();
    final state = probe(NavigationTabId.libraries)..consumeBack = true;
    await key(tester, LogicalKeyboardKey.escape);
    expect(state.first.hasFocus, isTrue);
    await key(tester, LogicalKeyboardKey.escape);
    expect(find.text(t.common.home), findsOneWidget);
    await key(tester, LogicalKeyboardKey.escape);
    expect(shell.currentState!.currentSection, home);
    expect(menuShowsFocus(tester, t.common.home), isTrue);
    expect(menuShowsFocus(tester, movies.title), isFalse);
    expect(binding.exits, 0);
    await key(tester, LogicalKeyboardKey.escape);
    expect(find.text(t.common.pressBackAgainToExit), findsOneWidget);
    expect(binding.exits, 0);
    await tester.pump(const Duration(seconds: 4));
    await key(tester, LogicalKeyboardKey.escape);
    expect(binding.exits, 0);
    await key(tester, LogicalKeyboardKey.escape);
    expect(binding.exits, 1);
  });

  testWidgets('focused menu item keeps its focus visual when the current marker leaves it', (tester) async {
    await pump(tester);
    shell.currentState!.selectLibrary(movies.globalKey);
    await tester.pumpAndSettle();
    await key(tester, LogicalKeyboardKey.arrowLeft);
    expect(menuShowsFocus(tester, movies.title), isTrue);
    shell.currentState!.selectSection(TvShellSection.library(series.globalKey), focusContent: false);
    await tester.pumpAndSettle();
    expect(menuShowsFocus(tester, movies.title), isTrue);
    expect(menuShowsFocus(tester, series.title), isFalse);
  });

  testWidgets('M1/M2 live order, duplicate titles, hidden libraries, downloads setting', (tester) async {
    libraries.libraries = [
      movies,
      const MediaLibrary(id: '3', backend: MediaBackend.plex, title: 'Movies', serverId: 's2', serverName: 'Two'),
      series,
    ];
    servers.totalServerCount = 2;
    servers.hasLiveTv = true;
    await pump(tester);
    expect(menu(tester).items.map((item) => item.label), [
      t.common.search,
      t.common.home,
      'Movies · One',
      'Movies · Two',
      'Series',
      'More',
      t.navigation.liveTv,
      t.common.settings,
    ]);
    hidden.hiddenLibraryKeys = {movies.globalKey};
    hidden.emit();
    libraries.libraries = libraries.libraries.reversed.toList();
    libraries.emit();
    await tester.pumpAndSettle();
    expect(menu(tester).items.map((item) => item.label), [
      t.common.search,
      t.common.home,
      'Series',
      'Movies · Two',
      'More',
      t.navigation.liveTv,
      t.common.settings,
    ]);
    await SettingsService.instance.write(TvSettings.showDownloads, true);
    await tester.pumpAndSettle();
    expect(menu(tester).items.map((item) => item.label), contains(t.navigation.downloads));
    expect(shell.currentState!.isSectionAvailable(const TvShellSection.tab(NavigationTabId.downloads)), isTrue);
  });

  testWidgets('M1/M2 Explore follows source and setting; paused current track keeps Now playing', (tester) async {
    await pump(tester);
    List<String> labels() => menu(tester).items.map((item) => item.label).toList();
    expect(labels(), isNot(contains(t.navigation.explore)));
    sources.hasAnySource = true;
    sources.emit();
    music.currentTrack = MediaItem(id: 'track', backend: MediaBackend.plex, kind: MediaKind.track);
    music.emit();
    await tester.pumpAndSettle();
    expect(labels(), containsAllInOrder([t.navigation.explore, t.music.nowPlaying]));
    shell.currentState!.selectSection(const TvShellSection.tab(NavigationTabId.explore));
    await tester.pumpAndSettle();
    await SettingsService.instance.write(SettingsService.showExploreTab, false);
    music.currentTrack = null;
    music.emit();
    await tester.pumpAndSettle();
    expect(labels(), isNot(contains(t.navigation.explore)));
    expect(labels(), isNot(contains(t.music.nowPlaying)));
    expect(shell.currentState!.currentSection, home);
    sources.hasAnySource = false;
    sources.emit();
    await SettingsService.instance.write(SettingsService.showExploreTab, true);
    await tester.pumpAndSettle();
    expect(labels(), isNot(contains(t.navigation.explore)));
  });

  testWidgets('M2 More follows server count without hidden libraries; Live TV disappears live', (tester) async {
    await pump(tester);
    expect(menu(tester).items.map((item) => item.label), isNot(contains('More')));
    servers.totalServerCount = 2;
    servers.hasLiveTv = true;
    servers.emit();
    await tester.pumpAndSettle();
    expect(menu(tester).items.map((item) => item.label), containsAll(['More', t.navigation.liveTv]));
    shell.currentState!.selectSection(const TvShellSection.tab(NavigationTabId.liveTv));
    await tester.pumpAndSettle();
    servers.totalServerCount = 1;
    servers.hasLiveTv = false;
    servers.emit();
    await tester.pumpAndSettle();
    expect(shell.currentState!.currentSection, home);
    expect(menu(tester).items.map((item) => item.label), isNot(contains('More')));
  });
  testWidgets('M5/M6 More includes hidden libraries grouped by server, no current marker', (tester) async {
    hidden.hiddenLibraryKeys = {movies.globalKey, series.globalKey};
    await pump(tester);
    menu(tester).items.singleWhere((item) => item.label == 'More').onSelect!();
    await tester.pumpAndSettle();
    final picker = tester.widget<LibraryQuickPickerSheet>(find.byType(LibraryQuickPickerSheet));
    expect(picker.libraries, [movies, series]);
    expect(picker.groupByServer, isTrue);
    picker.onSelected(movies.globalKey);
    await tester.pumpAndSettle();
    expect(shell.currentState!.currentSection, TvShellSection.library(movies.globalKey));
    expect(menu(tester).currentIndex, isNull);
    expect(probe(NavigationTabId.libraries).loads, [movies.globalKey]);
    expect(probe(NavigationTabId.libraries).first.hasFocus, isTrue);
  });

  testWidgets('F5 shared Libraries screen reloads A B A, same section does not reload', (tester) async {
    await pump(tester);
    for (final lib in [movies, series, movies, movies]) {
      shell.currentState!.selectLibrary(lib.globalKey);
      await tester.pumpAndSettle();
    }
    expect(probe(NavigationTabId.libraries).loads, [movies.globalKey, series.globalKey, movies.globalKey]);
    expect(probe(NavigationTabId.discover).hidden, 1);
    shell.currentState!.selectSection(home);
    await tester.pumpAndSettle();
    expect(probe(NavigationTabId.discover).refreshes, 1);
    expect(probe(NavigationTabId.discover).shown, 2);
  });

  testWidgets('selection command cancels stale library and focus work', (tester) async {
    await pump(tester);
    final command = shell.currentState!.selectionCommand;
    shell.currentState!.selectLibrary(movies.globalKey);
    shell.currentState!.selectSection(search);
    await tester.pumpAndSettle();
    expect(shell.currentState!.selectionCommand, command + 2);
    expect(probe(NavigationTabId.libraries).loads, isEmpty);
    expect(probe(NavigationTabId.search).first.hasFocus, isTrue);
  });

  testWidgets('M2 hiding keeps current library; S16 removal resolves library default', (tester) async {
    await pump(tester);
    shell.currentState!.selectLibrary(movies.globalKey);
    await tester.pumpAndSettle();
    hidden.hiddenLibraryKeys = {movies.globalKey};
    hidden.emit();
    await tester.pumpAndSettle();
    expect(shell.currentState!.currentSection, TvShellSection.library(movies.globalKey));
    expect(menu(tester).currentIndex, isNull);
    libraries.libraries = [series];
    libraries.emit();
    await tester.pumpAndSettle();
    // L3 now delegates a removed selection to the library switch's default.
    expect(shell.currentState!.currentSection, const TvShellSection.tab(NavigationTabId.libraries));
  });

  testWidgets('S1 deferred startup Live TV selects on arrival unless user selected', (tester) async {
    final settings = await SettingsService.getInstance();
    await settings.write(SettingsService.startupSection, NavigationTabId.liveTv);
    await pump(tester);
    expect(shell.currentState!.currentSection, home);
    servers.hasLiveTv = true;
    servers.emit();
    await tester.pumpAndSettle();
    expect(shell.currentState!.currentSection, const TvShellSection.tab(NavigationTabId.liveTv));
  });

  testWidgets('S1 user command cancels deferred startup', (tester) async {
    final settings = await SettingsService.getInstance();
    await settings.write(SettingsService.startupSection, NavigationTabId.liveTv);
    await pump(tester);
    shell.currentState!.selectSection(search);
    await tester.pumpAndSettle();
    servers.hasLiveTv = true;
    servers.emit();
    await tester.pumpAndSettle();
    expect(shell.currentState!.currentSection, search);
  });

  testWidgets('T2 intents invoke only their method on mounted content probes', (tester) async {
    await pump(tester);
    session.emitIntent(TvShellContentIntent.initialLoad);
    expect(probes.keys, [NavigationTabId.discover]);
    shell.currentState!.selectSection(search);
    await tester.pumpAndSettle();
    shell.currentState!.selectLibrary(movies.globalKey);
    await tester.pumpAndSettle();
    for (final intent in TvShellContentIntent.values) {
      session.emitIntent(intent);
    }
    for (final tab in [NavigationTabId.discover, NavigationTabId.libraries, NavigationTabId.search]) {
      final state = probe(tab);
      expect(state.primes, tab == NavigationTabId.discover ? 2 : 1);
      expect(state.refreshes, 1);
      expect(state.resets, 1);
    }
    expect(libraries.refreshes, 1);
  });

  testWidgets('D2b sort sheet closes before menu on Back', (tester) async {
    await pump(tester);
    shell.currentState!.selectLibrary(movies.globalKey);
    await tester.pumpAndSettle();
    final state = probe(NavigationTabId.libraries);
    unawaited(
      OverlaySheetController.of(
        state.context,
      ).show<void>(builder: (_) => const TextButton(onPressed: null, child: Text('Sort'))),
    );
    await tester.pumpAndSettle();
    await key(tester, LogicalKeyboardKey.escape);
    expect(find.text('Sort'), findsNothing);
    expect(state.first.hasFocus, isTrue);
    expect(find.text(t.common.home), findsNothing);
  });

  testWidgets('D2a route return refreshes Home and suppresses release opening menu', (tester) async {
    await pump(tester);
    navigator.currentState!.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('Details'))));
    await tester.pumpAndSettle();
    expect(probe(NavigationTabId.discover).hidden, 1);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
    navigator.currentState!.pop();
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(probe(NavigationTabId.discover).refreshes, 1);
    expect(probe(NavigationTabId.discover).shown, 2);
    expect(find.text(t.common.home), findsNothing);
  });

  group('S10 watchlist section', () {
    void connectWatchlist() {
      sources.hasAnySource = true;
      sources.watchlistCapableSources = [_CatalogSource()];
      sources.emit();
    }

    List<String> labels(WidgetTester tester) => menu(tester).items.map((item) => item.label).toList();

    testWidgets('A1 item sits right after libraries, before More, Live TV and Explore; absent without source', (
      tester,
    ) async {
      servers.totalServerCount = 2;
      servers.hasLiveTv = true;
      await pump(tester);
      expect(labels(tester), isNot(contains(TvStrings.watchlist)));
      connectWatchlist();
      await tester.pumpAndSettle();
      expect(labels(tester), [
        t.common.search,
        t.common.home,
        'Movies',
        'Series',
        TvStrings.watchlist,
        'More',
        t.navigation.liveTv,
        t.navigation.explore,
        t.common.settings,
      ]);
      expect(watchlistKey, isNull, reason: 'mounted lazily');
      menu(tester).items.singleWhere((item) => item.label == TvStrings.watchlist).onSelect!();
      await tester.pumpAndSettle();
      expect(shell.currentState!.currentSection, watchlist);
      expect(menu(tester).currentIndex, labels(tester).indexOf(TvStrings.watchlist));
      expect(watchlistProbe().shown, 1);
      expect(watchlistProbe().first.hasFocus, isTrue);
    });

    testWidgets('A2 offline menu has no watchlist', (tester) async {
      offlineStart = true;
      connectWatchlist();
      await pump(tester);
      expect(labels(tester), isNot(contains(TvStrings.watchlist)));
      expect(shell.currentState!.isSectionAvailable(watchlist), isFalse);
    });

    testWidgets('A29 losing every watchlist source leaves for Home', (tester) async {
      connectWatchlist();
      await pump(tester);
      shell.currentState!.selectSection(watchlist);
      await tester.pumpAndSettle();
      sources.watchlistCapableSources = [];
      sources.emit();
      await tester.pumpAndSettle();
      expect(shell.currentState!.currentSection, home);
      expect(labels(tester), isNot(contains(TvStrings.watchlist)));
      expect(watchlistProbe().hidden, 1);
    });

    testWidgets('A30 connection loss shows No connection, return restores watchlist', (tester) async {
      connectWatchlist();
      await pump(tester);
      shell.currentState!.selectSection(watchlist);
      await tester.pumpAndSettle();
      final state = watchlistProbe();
      session.offline(true);
      await tester.pumpAndSettle();
      expect(labels(tester), isNot(contains(TvStrings.watchlist)));
      await key(tester, LogicalKeyboardKey.escape);
      await key(tester, LogicalKeyboardKey.escape);
      expect(shell.currentState!.currentSection, const TvShellSection.noConnection());
      expect(state.hidden, 1);
      session.offline(false);
      await tester.pumpAndSettle();
      expect(shell.currentState!.currentSection, watchlist);
      expect(state.shown, 2);
    });

    testWidgets('companion step passes through watchlist after libraries', (tester) async {
      connectWatchlist();
      await pump(tester);
      final receiver = CompanionRemoteReceiver.instance;
      shell.currentState!.selectSection(const TvShellSection.tab(NavigationTabId.libraries));
      await tester.pumpAndSettle();
      receiver.onTabNext!();
      await tester.pumpAndSettle();
      expect(shell.currentState!.currentSection, watchlist);
      receiver.onTabNext!();
      await tester.pumpAndSettle();
      expect(shell.currentState!.currentSection.tab, isNot(NavigationTabId.libraries));
      expect(shell.currentState!.currentSection, isNot(watchlist));
      receiver.onTabPrevious!();
      await tester.pumpAndSettle();
      expect(shell.currentState!.currentSection, watchlist);
      receiver.onTabPrevious!();
      await tester.pumpAndSettle();
      expect(shell.currentState!.currentSection.tab, NavigationTabId.libraries);
    });

    testWidgets('go to search selects Search', (tester) async {
      connectWatchlist();
      await pump(tester);
      shell.currentState!.selectSection(watchlist);
      await tester.pumpAndSettle();
      watchlistProbe().widget.onOpenSearch();
      await tester.pumpAndSettle();
      expect(shell.currentState!.currentSection, search);
      expect(watchlistProbe().hidden, 1);
    });

    testWidgets('selecting and returning to watchlist leaves Home hooks alone; shell drives watchlist hooks', (
      tester,
    ) async {
      connectWatchlist();
      await pump(tester);
      final homeProbe = probe(NavigationTabId.discover);
      shell.currentState!.selectSection(watchlist);
      await tester.pumpAndSettle();
      final hiddenAfterLeave = homeProbe.hidden, shownBefore = homeProbe.shown, refreshesBefore = homeProbe.refreshes;
      expect(hiddenAfterLeave, 1);
      final list = watchlistProbe();
      // A route over the list must not hide it (a started player would be cancelled).
      navigator.currentState!.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('Details'))));
      await tester.pumpAndSettle();
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(list.hidden, 0);
      expect(shell.currentState!.currentSection, watchlist);
      shell.currentState!.selectSection(watchlist);
      await tester.pumpAndSettle();
      session.emitIntent(TvShellContentIntent.refreshAfterResume);
      session.emitIntent(TvShellContentIntent.fullReset);
      await tester.sendKeyEvent(LogicalKeyboardKey.f5);
      await tester.pumpAndSettle();
      expect(homeProbe.hidden, hiddenAfterLeave);
      expect(homeProbe.shown, shownBefore);
      expect(homeProbe.refreshes, refreshesBefore + 1, reason: 'resume intent only');
      expect(list.shown, 1);
      expect(list.refreshes, 1);
      expect(list.resets, 1);
    });
  });
}
