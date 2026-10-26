import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/focus/input_mode_tracker.dart';
import 'package:plezy/main.dart' show rootNavigatorKey;
import 'package:plezy/media/ids.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_library.dart';
import 'package:plezy/media/media_server_client.dart';
import 'package:plezy/database/app_database.dart';
import 'package:plezy/models/download_models.dart';
import 'package:plezy/mixins/refreshable.dart';
import 'package:plezy/mixins/tab_visibility_aware.dart';
import 'package:plezy/navigation/navigation_tabs.dart';
import 'package:plezy/navigation/profile_navigation_scope.dart';
import 'package:plezy/plezytv/screen_links/screen_link_router.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_cards.dart';
import 'package:plezy/plezytv/tv_ui/search/tv_search_controller.dart';
import 'package:plezy/plezytv/tv_ui/search/tv_search_history.dart';
import 'package:plezy/plezytv/tv_ui/search/tv_search_screen.dart';
import 'package:plezy/plezytv/tv_ui/shell/tv_shell_session_controller.dart';
import 'package:plezy/plezytv/tv_ui/tv_shell.dart';
import 'package:plezy/plezytv/tv_ui/tv_theme.dart';
import 'package:plezy/providers/catalog_sources_provider.dart';
import 'package:plezy/providers/download_provider.dart';
import 'package:plezy/providers/hidden_libraries_provider.dart';
import 'package:plezy/providers/libraries_provider.dart';
import 'package:plezy/providers/multi_server_provider.dart';
import 'package:plezy/providers/offline_mode_provider.dart';
import 'package:plezy/services/catalog/catalog_source.dart';
import 'package:plezy/services/companion_remote/companion_remote_receiver.dart';
import 'package:plezy/services/data_aggregation_service.dart';
import 'package:plezy/services/offline_watch_sync_service.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/utils/media_server_http_client.dart';
import 'package:provider/provider.dart';

import '../../../test_helpers/prefs.dart';

const _lib = MediaLibrary(id: '1', backend: MediaBackend.plex, title: 'Movies', serverId: 's1', serverName: 'One');
const _search = TvShellSection.tab(NavigationTabId.search);
const _watchlist = TvShellSection.watchlist();

MediaItem _movie(String id) =>
    MediaItem(id: id, backend: MediaBackend.plex, kind: MediaKind.movie, title: id, serverId: 's1');

class _Libraries extends ChangeNotifier implements LibrariesProvider {
  @override
  List<MediaLibrary> libraries = [_lib];
  @override
  LibrariesLoadState loadState = LibrariesLoadState.loaded;
  @override
  bool get isLoading => false;
  @override
  Future<void> refresh() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Hidden extends ChangeNotifier implements HiddenLibrariesProvider {
  @override
  Set<String> hiddenLibraryKeys = {};
  @override
  Future<void> ensureInitialized() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Client implements MediaServerClient {
  @override
  Future<MediaItem?> fetchItem(String id) async => id == '123' ? _movie('123') : null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Servers extends ChangeNotifier implements MultiServerProvider {
  @override
  bool hasLiveTv = false;
  @override
  bool get hasConnectedServers => true;
  @override
  List<String> get onlineServerIds => ['s1'];
  @override
  List<String> get expectedServerIds => ['s1'];
  @override
  MediaServerClient? getClientForServer(ServerId id) => _Client();
  @override
  int totalServerCount = 1;
  @override
  List<({String displayName, ServerId serverId})> get authErrorServers => [];
  @override
  List<({String displayName, ServerId serverId})> get accessDeniedServers => [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Sources extends ChangeNotifier implements CatalogSourcesProvider {
  @override
  bool hasAnySource = true;
  @override
  List<CatalogSource> watchlistCapableSources = [_CatalogSource()];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CatalogSource implements CatalogSource {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Offline extends ChangeNotifier implements OfflineModeProvider {
  @override
  bool get isOffline => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoDownloads extends ChangeNotifier implements DownloadProvider {
  @override
  String syncRuleKeyForClient(MediaServerClient client, String ratingKey, {ServerId? serverId}) => ratingKey;
  @override
  bool hasSyncRule(String key) => false;
  @override
  DownloadProgress? getProgress(String key) => null;
  @override
  Future<DownloadedMediaItem?> getCompletedDownload(String key) async => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _OfflineWatch extends ChangeNotifier implements OfflineWatchSyncService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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

  @override
  bool get isReconnecting => false;
  @override
  Future<void> start() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _History implements TvSearchHistoryStore {
  List<String> value = [];
  @override
  Future<List<String>> load() async => List.of(value);
  @override
  Future<void> save(List<String> history) async => value = List.of(history);
}

class _Probe extends StatefulWidget {
  const _Probe({required super.key, required this.label, this.onPressed});
  final String label;
  final VoidCallback? onPressed;
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> with Refreshable, FullRefreshable, FocusableTab, TabVisibilityAware {
  final node = FocusNode();
  @override
  void refresh() {}
  @override
  void fullRefresh() {}
  @override
  void focusActiveTabIfReady() => node.requestFocus();
  @override
  void onTabShown() {}
  @override
  void onTabHidden() {}
  @override
  Widget build(BuildContext context) =>
      TextButton(focusNode: node, onPressed: widget.onPressed, child: Text(widget.label));
  @override
  void dispose() {
    node.dispose();
    super.dispose();
  }
}

/// Routes pushed above the shell are recorded and removed before they build.
class _Routes extends NavigatorObserver {
  final pushed = <Route<dynamic>>[];
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute == null) return;
    pushed.add(route);
    scheduleMicrotask(() => navigator!.removeRoute(route));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final router = ScreenLinkRouter.instance;
  final receiver = CompanionRemoteReceiver.instance;
  late _Session session;
  late _History history;
  late _Routes routes;
  late List<String> calls;
  late GlobalKey searchKey;
  VoidCallback? openSearch;

  TvSectionShellState shell(WidgetTester tester) => tester.state(find.byType(TvSectionShell));
  TvSearchScreenState screen() => searchKey.currentState! as TvSearchScreenState;

  String? focusedId() =>
      FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<TvPoster>()?.item.id;

  Future<void> mount(WidgetTester tester) async {
    await SettingsService.getInstance();
    final observer = RouteObserver<PageRoute<dynamic>>();
    final providers = (
      libraries: _Libraries(),
      hidden: _Hidden(),
      servers: _Servers(),
      sources: _Sources(),
      downloads: _NoDownloads(),
      watch: _OfflineWatch(),
      offline: _Offline(),
    );
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1920, 1080);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      providers.libraries.dispose();
      providers.hidden.dispose();
      providers.servers.dispose();
      providers.sources.dispose();
      providers.downloads.dispose();
      providers.watch.dispose();
      providers.offline.dispose();
    });
    await tester.pumpWidget(
      InputModeTracker(
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider<LibrariesProvider>.value(value: providers.libraries),
            ChangeNotifierProvider<HiddenLibrariesProvider>.value(value: providers.hidden),
            ChangeNotifierProvider<MultiServerProvider>.value(value: providers.servers),
            ChangeNotifierProvider<CatalogSourcesProvider>.value(value: providers.sources),
            ChangeNotifierProvider<DownloadProvider>.value(value: providers.downloads),
            ChangeNotifierProvider<OfflineWatchSyncService>.value(value: providers.watch),
            ChangeNotifierProvider<OfflineModeProvider>.value(value: providers.offline),
          ],
          child: MaterialApp(
            navigatorKey: rootNavigatorKey,
            navigatorObservers: [observer, routes],
            home: ProfileNavigationScope(
              navigatorKey: rootNavigatorKey,
              routeObserver: observer,
              mainScaffoldMessengerKey: GlobalKey<ScaffoldMessengerState>(),
              child: const TvTheme(child: TvShell(isOfflineMode: false, initialPromptHandled: true)),
            ),
          ),
        ),
      ),
    );
    InputModeTracker.reportNonPointerInput();
    profileNavigationRegistry.attachNavigator(rootNavigatorKey);
    await tester.pumpAndSettle();
  }

  Future<void> link(WidgetTester tester, String target) async {
    expect(router.claim('plezytv://screen/$target'), isTrue);
    await tester.pump();
    await tester.pumpAndSettle();
  }

  Future<void> showResults(WidgetTester tester, String query) async {
    shell(tester).selectSection(_search);
    await tester.pumpAndSettle();
    screen().controller.setQuery(query);
    await tester.pump(TvSearchController.debounce);
    await tester.pumpAndSettle();
  }

  void expectMatrixFocused() {
    expect(find.descendant(of: find.byType(TvSearchScreen), matching: find.text('matrix')), findsOneWidget);
    expect(focusedId(), 'movie0');
  }

  setUp(() {
    resetSharedPreferencesForTest();
    history = _History();
    routes = _Routes();
    calls = [];
    searchKey = GlobalKey();
    openSearch = null;
    TvSectionShell.sessionControllerFactoryForTesting = (_, emit) => session = _Session(emit);
    TvSectionShell.watchlistBuilderForTesting = (_, key, onOpen) {
      openSearch = onOpen;
      return _Probe(key: key, label: 'watchlist', onPressed: onOpen);
    };
    TvSectionShell.sectionBuilderForTesting = (_, tab, key) {
      if (tab != NavigationTabId.search) return _Probe(key: key, label: tab.name);
      searchKey = key;
      return TvSearchScreen(
        key: key,
        searchForTesting: (query, AbortController abort) async {
          calls.add(query);
          final SearchAggregationResult result = (
            hits: const [],
            candidates: [for (var i = 0; i < 3; i++) _movie('movie$i')],
            people: const [],
            succeededServerIds: const {'s1'},
            cancelledServerIds: const {},
            failedServerIds: const {},
          );
          return result;
        },
        fetchForTesting: (_) async => null,
        historyForTesting: history,
      );
    };
  });
  tearDown(() {
    router.queue.dispose();
    profileNavigationRegistry.detachNavigator(rootNavigatorKey);
    TvSectionShell.sectionBuilderForTesting = null;
    TvSectionShell.watchlistBuilderForTesting = null;
    TvSectionShell.sessionControllerFactoryForTesting = null;
  });

  testWidgets('A12: search?q=matrix opens Search with the query and focuses the first result', (tester) async {
    await mount(tester);
    expect(find.byType(TvSearchScreen), findsNothing);
    await link(tester, 'search?q=matrix');
    expect(shell(tester).currentSection, _search);
    expect(calls, ['matrix']);
    expectMatrixFocused();
  });

  testWidgets('A13: companion search opens Search with the query and focuses the first result', (tester) async {
    await mount(tester);
    receiver.onSearchAction!('  matrix ');
    await tester.pumpAndSettle();
    expect(shell(tester).currentSection, _search);
    expect(calls, ['matrix']);
    expectMatrixFocused();
  });

  testWidgets('Go to search from Watchlist opens Search with focus on the keyboard', (tester) async {
    await mount(tester);
    shell(tester).selectSection(_watchlist);
    await tester.pumpAndSettle();
    openSearch!();
    await tester.pumpAndSettle();
    expect(shell(tester).currentSection, _search);
    final focused = FocusManager.instance.primaryFocus?.context;
    expect(focused, isNotNull);
    expect(focused!.findAncestorWidgetOfExactType<TvSearchScreen>(), isNotNull);
    expect(focusedId(), isNull);
  });

  testWidgets('A18: initialLoad after reconnect keeps and repeats the shown query', (tester) async {
    await mount(tester);
    await showResults(tester, 'дюн');
    expect(calls, ['дюн']);
    session.offline(true);
    await tester.pumpAndSettle();
    session.offline(false);
    await tester.pumpAndSettle();
    session.emitIntent(TvShellContentIntent.initialLoad);
    await tester.pumpAndSettle();
    expect(shell(tester).currentSection, _search);
    expect(screen().controller.query, 'дюн');
    expect(find.descendant(of: find.byType(TvSearchScreen), matching: find.text('дюн')), findsOneWidget);
    expect(calls, ['дюн', 'дюн']);
  });

  testWidgets('an item link over search results records the query in history', (tester) async {
    await mount(tester);
    await showResults(tester, 'дюна');
    expect(history.value, isEmpty);
    expect(router.claim('plezytv://screen/item?id=123&server=s1'), isTrue);
    await tester.pumpAndSettle();
    expect(routes.pushed, hasLength(1));
    expect(history.value, ['дюна']);
    expect(shell(tester).currentSection, _search);
  });
}
