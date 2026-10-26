import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:plezy/plezytv/settings_transfer/settings_transfer_service.dart';
import 'package:plezy/services/storage_service.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/database/app_database.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/media/ids.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_hub.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_person.dart';
import 'package:plezy/media/media_server_client.dart';
import 'package:plezy/media/server_capabilities.dart';
import 'package:plezy/models/download_models.dart';
import 'package:plezy/navigation/main_screen_scope.dart';
import 'package:plezy/navigation/profile_navigation_scope.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_cards.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_person_card.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_skeletons.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_tabs.dart';
import 'package:plezy/plezytv/tv_ui/movie/tv_movie_screen.dart';
import 'package:plezy/plezytv/tv_ui/search/tv_search_controller.dart';
import 'package:plezy/plezytv/tv_ui/search/tv_search_history.dart';
import 'package:plezy/plezytv/tv_ui/search/tv_search_keyboard.dart';
import 'package:plezy/plezytv/tv_ui/search/tv_search_screen.dart';
import 'package:plezy/plezytv/tv_ui/tv_focusable.dart';
import 'package:plezy/plezytv/tv_ui/tv_settings.dart';
import 'package:plezy/profiles/active_profile_provider.dart';
import 'package:plezy/providers/discover_provider.dart';
import 'package:plezy/providers/download_provider.dart';
import 'package:plezy/providers/hidden_libraries_provider.dart';
import 'package:plezy/providers/multi_server_provider.dart';
import 'package:plezy/providers/offline_mode_provider.dart';
import 'package:plezy/providers/watch_state_store.dart';
import 'package:plezy/screens/actor_media_screen.dart';
import 'package:plezy/screens/media_detail_screen.dart';
import 'package:plezy/services/data_aggregation_service.dart';
import 'package:plezy/services/offline_watch_sync_service.dart';
import 'package:plezy/screens/video_player_screen.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/utils/media_server_http_client.dart';
import 'package:plezy/utils/video_player_navigation.dart';
import 'package:plezy/utils/watch_state_notifier.dart';
import 'package:provider/provider.dart';

import '../../../test_helpers/media_items.dart';
import '../../../test_helpers/multi_server_fixtures.dart';
import '../../../test_helpers/prefs.dart';
import '../../../test_helpers/profile_stack.dart';
import '../tv_theme_test_helper.dart';

MediaItem media(String id, MediaKind kind, {String? title}) =>
    testMediaItem(id: id, kind: kind, title: title ?? id, serverId: 'server', durationMs: 3600000);

List<MediaItem> movies(int count, [String prefix = 'movie']) => [
  for (var i = 0; i < count; i++) media('$prefix$i', MediaKind.movie),
];

MediaPerson person(String id, PersonCredit? credit) =>
    MediaPerson(id: id, name: 'Person $id', backend: MediaBackend.plex, serverId: ServerId('server'), credit: credit);

SearchAggregationResult answer({List<MediaItem> items = const [], List<MediaPerson> people = const []}) => (
  hits: const [],
  candidates: items,
  people: people,
  succeededServerIds: const {'server'},
  cancelledServerIds: const {},
  failedServerIds: const {},
);

class _Search {
  final calls = <String>[];
  SearchAggregationResult Function(String query) respond = (_) => answer();
  Object? error;
  Completer<SearchAggregationResult>? hold;

  Future<SearchAggregationResult> call(String query, AbortController abort) async {
    calls.add(query);
    if (hold case final completer?) return completer.future;
    if (error case final e?) throw e;
    return respond(query);
  }
}

/// History whose value depends on the active profile scope.
class _ScopedHistory implements TvSearchHistoryStore {
  String scope = 'a';
  final values = <String, List<String>>{};
  @override
  Future<List<String>> load() async => List.of(values[scope] ?? const []);
  @override
  Future<void> save(List<String> history) async => values[scope] = List.of(history);
}

class _ActionClient implements MediaServerClient {
  _ActionClient([this.id = 'server']);
  final String id;
  final watched = <MediaItem>[];
  @override
  ServerId get serverId => ServerId(id);
  @override
  void close() {}
  @override
  MediaBackend get backend => MediaBackend.plex;
  @override
  ServerCapabilities get capabilities =>
      const ServerCapabilities(videoTranscoding: false, continueWatchingRemoval: true);
  @override
  Future<void> markWatched(MediaItem item) async => watched.add(item);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Hidden libraries whose keys the test changes (R4).
class _Hidden extends ChangeNotifier implements HiddenLibrariesProvider {
  Set<String> keys = {};
  @override
  Set<String> get hiddenLibraryKeys => Set.unmodifiable(keys);
  @override
  Future<void> ensureInitialized() async {}
  void hide(String key) {
    keys = {...keys, key};
    notifyListeners();
  }

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

/// Players and detail routes are recorded and closed before they build.
class _Routes extends NavigatorObserver {
  final players = <VideoPlayerRoute>[];
  final pages = <PageRoute<dynamic>>[];
  int get details => pages.length;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is VideoPlayerRoute) {
      players.add(route);
      scheduleMicrotask(() => navigator!.removeRoute(route));
    } else if (previousRoute != null && route is PageRoute) {
      pages.add(route);
      scheduleMicrotask(() => navigator!.removeRoute(route, true));
    }
  }
}

/// Discover data for the idle rows; [load] counts calls.
class _Discover extends ChangeNotifier implements DiscoverProvider {
  @override
  List<MediaItem> onDeck = [];
  @override
  List<MediaHub> hubs = [];
  @override
  bool isLoading = false, areHubsLoading = false, isLoadInFlight = false, hasMoreContinueWatching = false;
  @override
  String? errorMessage;
  int loads = 0;
  bool loadStartsLoading = false;

  @override
  Future<void> load() async {
    loads++;
    if (loadStartsLoading) {
      isLoading = areHubsLoading = isLoadInFlight = true;
      errorMessage = null;
      notifyListeners();
    }
  }

  @override
  Future<void> updateItem(MediaItem item) async {}

  void ready(List<MediaHub> value) {
    hubs = value;
    isLoading = areHubsLoading = isLoadInFlight = false;
    errorMessage = null;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MediaHub hub(String id, {int count = 3}) =>
    MediaHub(id: id, title: id, type: 'movie', items: movies(count, id), size: count, serverId: 'server');

final continueHub = MediaHub(
  id: 'continueWatching',
  title: 'Continue Watching',
  type: 'mixed',
  items: movies(2, 'cw'),
  size: 2,
  serverId: 'server',
);

Finder _key(String id) => find.byKey(ValueKey('tv-search-key-$id'));

class _FileTransfer extends SettingsTransferService {
  const _FileTransfer(this.file);
  final File file;
  @override
  Future<File> settingsFile() async => file;
}

void main() {
  late _Search search;
  late _ScopedHistory history;
  late FocusNode menu;
  late GlobalKey<TvSearchScreenState> screen;
  late RouteObserver<PageRoute<dynamic>> routes;
  MediaItem? Function(MediaItem item) fetch = (_) => null;
  final fetched = <String>[];

  setUp(() async {
    resetSharedPreferencesForTest();
    await SettingsService.getInstance();
    search = _Search();
    history = _ScopedHistory();
    menu = FocusNode(debugLabel: 'menu');
    screen = GlobalKey<TvSearchScreenState>();
    routes = RouteObserver<PageRoute<dynamic>>();
    fetch = (_) => null;
    fetched.clear();
  });
  tearDown(() => menu.dispose());

  Future<void> pump(
    WidgetTester tester, {
    List<NavigatorObserver> observers = const [],
    _ActionClient? client,
    ActiveProfileProvider? profile,
    WatchStateStore? watchState,
    _Discover? discover,
    _Hidden? hidden,
    List<_ActionClient> moreClients = const [],
    ValueNotifier<int>? section,
  }) async {
    final servers = client == null ? null : testMultiServer(clients: [client, ...moreClients]);
    final downloads = _NoDownloads();
    final offlineWatch = _OfflineWatch();
    final offline = servers == null ? null : OfflineModeProvider(servers.manager);
    addTearDown(downloads.dispose);
    addTearDown(offlineWatch.dispose);
    if (offline != null) addTearDown(offline.dispose);
    await pumpTvWidget(
      tester,
      MultiProvider(
        builder: (context, child) => Scaffold(body: child),
        providers: [
          if (servers != null) ChangeNotifierProvider<MultiServerProvider>.value(value: servers.provider),
          ChangeNotifierProvider<DownloadProvider>.value(value: downloads),
          ChangeNotifierProvider<OfflineWatchSyncService>.value(value: offlineWatch),
          if (offline != null) ChangeNotifierProvider<OfflineModeProvider>.value(value: offline),
          if (profile != null) ChangeNotifierProvider<ActiveProfileProvider>.value(value: profile),
          if (watchState != null) ChangeNotifierProvider<WatchStateStore>.value(value: watchState),
          if (discover != null) ChangeNotifierProvider<DiscoverProvider>.value(value: discover),
          if (hidden != null) ChangeNotifierProvider<HiddenLibrariesProvider>.value(value: hidden),
        ],
        child: ProfileNavigationScope(
          navigatorKey: GlobalKey<NavigatorState>(),
          routeObserver: routes,
          mainScaffoldMessengerKey: GlobalKey<ScaffoldMessengerState>(),
          child: MainScreenFocusScope(
            focusSidebar: menu.requestFocus,
            sideNavigationWidth: 0,
            child: Stack(
              children: [
                Focus(focusNode: menu, child: const SizedBox()),
                ValueListenableBuilder<int>(
                  valueListenable: section ?? const AlwaysStoppedAnimation(0),
                  builder: (context, index, child) => IndexedStack(index: index, children: [child!, const SizedBox()]),
                  child: TvSearchScreen(
                    key: screen,
                    searchForTesting: search.call,
                    fetchForTesting: (item) async {
                      fetched.add(item.id);
                      return fetch(item);
                    },
                    historyForTesting: history,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      reduced: true,
      appTheme: monoTheme(MonoPalette.dark),
      navigatorObservers: [routes, ...observers],
    );
    await tester.pumpAndSettle();
  }

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key, {int times = 1}) async {
    for (var i = 0; i < times; i++) {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
    }
  }

  bool keyFocused(WidgetTester tester, String id) =>
      Focus.of(tester.element(find.descendant(of: _key(id), matching: find.byType(Semantics)).first)).hasFocus;

  /// Id of the media item or person whose card holds primary focus.
  String? focusedId(WidgetTester tester) {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return null;
    final poster = ctx.findAncestorWidgetOfExactType<TvPoster>();
    if (poster != null) return poster.item.id;
    final episode = ctx.findAncestorWidgetOfExactType<TvEpisode>();
    if (episode != null) return episode.item.id;
    final personCard = ctx.findAncestorWidgetOfExactType<TvPersonCard>();
    if (personCard != null) return personCard.name;
    final element = ctx as Element;
    for (final type in [TvPoster, TvEpisode, TvPersonCard]) {
      final found = find.descendant(of: find.byElementPredicate((e) => e == element), matching: find.byType(type));
      if (found.evaluate().isNotEmpty) {
        final widget = found.evaluate().first.widget;
        return switch (widget) {
          TvPoster(:final item) => item.id,
          TvEpisode(:final item) => item.id,
          TvPersonCard(:final name) => name,
          _ => null,
        };
      }
    }
    return null;
  }

  TvSearchController controller() => screen.currentState!.controller;

  Future<void> results(WidgetTester tester, String query) async {
    screen.currentState!.controller.setQuery(query);
    await tester.pump(TvSearchController.debounce);
    await tester.pumpAndSettle();
  }

  testWidgets('file import and preference writes update a retained Search keyboard', (tester) async {
    final section = ValueNotifier(0);
    addTearDown(section.dispose);
    await pump(tester, section: section);
    final retained = screen.currentState;
    expect(tester.widget<TvSearchKeyboard>(find.byType(TvSearchKeyboard)).layout, TvSearchKeyboardLayout.ru);
    final directory = Directory.systemTemp.createTempSync('search-import-');
    addTearDown(() => directory.deleteSync(recursive: true));
    await tester.runAsync(() async {
      final storage = await StorageService.getInstance();
      await storage.setActiveProfileId('search-import');
    });
    final file = File('${directory.path}/settings.json');
    for (final layout in [TvSearchKeyboardLayout.en, TvSearchKeyboardLayout.digits]) {
      section.value = 1;
      await tester.pumpAndSettle();
      file.writeAsStringSync(
        jsonEncode({
          'formatVersion': 1,
          'prefs': {
            TvSettings.searchKeyboardLayout.key: {'type': 'string', 'value': layout.prefValue},
          },
        }),
      );
      final result = await tester.runAsync(() => _FileTransfer(file).importFromFile());
      expect(result!.keysImported, 1);
      SettingsService.instance.refreshListenables();
      await tester.pumpAndSettle();
      section.value = 0;
      await tester.pumpAndSettle();
      expect(screen.currentState, same(retained));
      expect(tester.widget<TvSearchKeyboard>(find.byType(TvSearchKeyboard)).layout, layout);
    }
    await SettingsService.instance.write(TvSettings.searchKeyboardLayout, 'ru');
    await tester.pumpAndSettle();
    expect(tester.widget<TvSearchKeyboard>(find.byType(TvSearchKeyboard)).layout, TvSearchKeyboardLayout.ru);
  });

  testWidgets('A1 focus, A3 → to the first movie, A4 ← to the last pressed key', (tester) async {
    search.respond = (_) => answer(items: [...movies(3), media('show0', MediaKind.show)]);
    await pump(tester);
    expect(keyFocused(tester, 'char:а'), isTrue);
    // «Н» is row 2, column 2.
    await press(tester, LogicalKeyboardKey.arrowDown, times: 2);
    await press(tester, LogicalKeyboardKey.arrowRight, times: 2);
    expect(keyFocused(tester, 'char:н'), isTrue);
    await press(tester, LogicalKeyboardKey.enter);
    expect(find.text('н'), findsOneWidget);
    await press(tester, LogicalKeyboardKey.arrowUp, times: 2);
    await press(tester, LogicalKeyboardKey.arrowRight, times: 3);
    expect(keyFocused(tester, 'char:е'), isTrue);
    await tester.pump(TvSearchController.debounce);
    await tester.pumpAndSettle();
    expect(search.calls, ['н']);
    expect(find.text(TvSearchStrings.rowMovies), findsWidgets);
    expect(find.text(TvSearchStrings.rowShows), findsWidgets);
    expect(find.text('3'), findsOneWidget);
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(focusedId(tester), 'movie0');
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(keyFocused(tester, 'char:н'), isTrue);
  });

  testWidgets('A5: People tab grid with roles, ↓ from tabs focuses the first person', (tester) async {
    search.respond = (_) => answer(
      items: movies(2),
      people: [person('1', PersonCredit.actor), person('2', PersonCredit.director), person('3', null)],
    );
    await pump(tester);
    await results(tester, 'дюн');
    expect(find.text(TvSearchStrings.rowPeople), findsOneWidget);
    await press(tester, LogicalKeyboardKey.arrowRight, times: 6);
    expect(focusedId(tester), 'movie0');
    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(tester.state<TvTabsState>(find.byType(TvTabs)).focusedIndex, 0);
    // Tabs: All, Movies, People.
    await press(tester, LogicalKeyboardKey.arrowRight, times: 2);
    expect(tester.state<TvTabsState>(find.byType(TvTabs)).focusedIndex, 2);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(controller().selectedTab, TvSearchTab.people);
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(focusedId(tester), 'Person 1');
    // Focus is on the grid slot: the card has no node of its own and shows the
    // token ring through its external-focus mode (CQ1).
    expect(FocusManager.instance.primaryFocus!.context!.findAncestorWidgetOfExactType<TvPersonCard>(), isNull);
    expect(find.descendant(of: find.byType(TvPersonCard), matching: find.byType(TvFocusable)), findsNothing);
    final cards = tester.widgetList<TvPersonCard>(find.byType(TvPersonCard)).toList();
    expect([for (final card in cards) card.externalFocus], [true, false, false]);
    final ring = tester.widget<TvFocusVisual>(
      find.descendant(of: find.widgetWithText(TvPersonCard, 'Person 1'), matching: find.byType(TvFocusVisual)),
    );
    expect(ring.state.focused, isTrue);
    expect(ring.kind, TvFocusKind.ring);
    expect(find.text(t.explore.creditRole.actor), findsOneWidget);
    expect(find.text(t.explore.creditRole.director), findsOneWidget);
    expect(find.byType(TvPersonCard), findsNWidgets(3));
  });

  testWidgets('A6: a refined query keeps old results until it answers; tab kept or reset', (tester) async {
    search.respond = (q) => answer(items: [...movies(2), media('show0', MediaKind.show)]);
    await pump(tester);
    await results(tester, 'дюна');
    controller().selectTab(TvSearchTab.movies);
    await tester.pumpAndSettle();
    search.hold = Completer();
    controller().setQuery('дюн');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(controller().refining, isTrue);
    expect(find.byType(TvTabs), findsOneWidget);
    expect(find.byType(TvPoster), findsNWidgets(2));
    expect(find.byType(TvRowSkeleton), findsNothing);
    search.hold!.complete(answer(items: movies(1)));
    search.hold = null;
    await tester.pumpAndSettle();
    expect(controller().selectedTab, TvSearchTab.movies);
    search.respond = (q) => answer(items: [media('show0', MediaKind.show)]);
    await results(tester, 'д');
    expect(controller().selectedTab, TvSearchTab.all);
  });

  testWidgets('R8: skeletons after 300 ms on a first search', (tester) async {
    search.hold = Completer();
    await pump(tester);
    controller().setQuery('дюн');
    await tester.pump(TvSearchController.debounce);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(TvRowSkeleton), findsNothing);
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.byType(TvRowSkeleton), findsWidgets);
    search.hold!.complete(answer(items: movies(1)));
    await tester.pumpAndSettle();
    expect(find.byType(TvRowSkeleton), findsNothing);
  });

  testWidgets('A11: unavailable shows Retry, → reaches it, the keyboard still types', (tester) async {
    search.error = const TvSearchUnavailable();
    await pump(tester);
    await press(tester, LogicalKeyboardKey.enter); // «а»
    await tester.pump(TvSearchController.debounce);
    await tester.pumpAndSettle();
    expect(find.text(TvSearchStrings.unavailable), findsOneWidget);
    expect(find.text(t.errors.searchUnavailable), findsOneWidget);
    await press(tester, LogicalKeyboardKey.enter); // «а» again
    expect(find.text('аа'), findsOneWidget);
    await tester.pump(TvSearchController.debounce);
    await tester.pumpAndSettle();
    // «а» is column 0: → walks the row to «е», then leaves to Retry.
    await press(tester, LogicalKeyboardKey.arrowRight, times: 6);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'TV Search retry');
    final before = search.calls.length;
    await press(tester, LogicalKeyboardKey.enter);
    expect(search.calls.length, before + 1);
    expect(search.calls.last, 'аа');
  });

  testWidgets('A12: submitSearchQuery focuses the first result, ← goes to the first key', (tester) async {
    search.respond = (_) => answer(items: movies(3));
    await pump(tester);
    await press(tester, LogicalKeyboardKey.arrowRight); // «б»
    await press(tester, LogicalKeyboardKey.enter);
    controller().clear();
    screen.currentState!.submitSearchQuery('matrix');
    await tester.pumpAndSettle();
    expect(find.text('matrix'), findsOneWidget);
    expect(focusedId(tester), 'movie0');
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(keyFocused(tester, 'char:а'), isTrue);
  });

  testWidgets('R10: a submitted query without results focuses the first key', (tester) async {
    await pump(tester);
    menu.requestFocus();
    screen.currentState!.submitSearchQuery('врнгл');
    await tester.pumpAndSettle();
    expect(find.text(TvSearchStrings.nothingFound), findsOneWidget);
    expect(keyFocused(tester, 'char:а'), isTrue);
  });

  testWidgets('A23/A8: only albums and tracks — nothing found, no tabs, no history', (tester) async {
    search.respond = (_) => answer(items: [media('album', MediaKind.album), media('track', MediaKind.track)]);
    await pump(tester);
    await results(tester, 'врнгл');
    expect(find.text(TvSearchStrings.nothingFound), findsOneWidget);
    expect(find.text(TvSearchStrings.nothingFoundHelp('врнгл')), findsOneWidget);
    expect(find.byType(TvTabs), findsNothing);
    expect(keyFocused(tester, 'char:а'), isTrue);
    screen.currentState!.onTabHidden();
    await tester.pumpAndSettle();
    expect(history.values['a'], isNull);
  });

  testWidgets('A26: Back in the Movies grid returns to the last key; tab and results stay', (tester) async {
    search.respond = (_) => answer(items: movies(6));
    await pump(tester);
    await press(tester, LogicalKeyboardKey.enter); // «а»
    await tester.pump(TvSearchController.debounce);
    await tester.pumpAndSettle();
    controller().selectTab(TvSearchTab.movies);
    await tester.pumpAndSettle();
    await press(tester, LogicalKeyboardKey.arrowRight, times: 6);
    expect(focusedId(tester), 'movie0');
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(focusedId(tester), 'movie1');
    await press(tester, LogicalKeyboardKey.escape);
    expect(keyFocused(tester, 'char:а'), isTrue);
    expect(controller().selectedTab, TvSearchTab.movies);
    expect(find.byType(TvPoster), findsNWidgets(6));
  });

  testWidgets('A9: Back on the keyboard records the shown query', (tester) async {
    search.respond = (_) => answer(items: movies(1));
    await pump(tester);
    await results(tester, 'дюн');
    await press(tester, LogicalKeyboardKey.escape);
    expect(history.values['a'], ['дюн']);
  });

  testWidgets('A24: replaced results keep the focused item, else the first card, else the keyboard', (tester) async {
    var list = movies(5);
    search.respond = (_) => answer(items: list);
    await pump(tester);
    await results(tester, 'дюн');
    screen.currentState!.focusSearchInput();
    await tester.pumpAndSettle();
    await press(tester, LogicalKeyboardKey.arrowRight, times: 6);
    await press(tester, LogicalKeyboardKey.arrowRight, times: 2);
    expect(focusedId(tester), 'movie2');

    list = [list[0], list[1], list[3], list[4]];
    screen.currentState!.refresh();
    await tester.pumpAndSettle();
    expect(focusedId(tester), 'movie0');

    list = movies(5);
    screen.currentState!.refresh();
    await tester.pumpAndSettle();
    await press(tester, LogicalKeyboardKey.arrowRight, times: 2);
    expect(focusedId(tester), 'movie2');
    list = [media('new', MediaKind.movie), ...movies(5)];
    screen.currentState!.refresh();
    await tester.pumpAndSettle();
    expect(focusedId(tester), 'movie2');

    list = const [];
    screen.currentState!.refresh();
    await tester.pumpAndSettle();
    expect(find.text(TvSearchStrings.nothingFound), findsOneWidget);
    expect(keyFocused(tester, 'char:а'), isTrue);
  });

  testWidgets('A18 primeRefresh repeats the query; A16 fullRefresh clears it and rereads history', (tester) async {
    search.respond = (_) => answer(items: movies(1));
    history.values['a'] = ['old a'];
    history.values['b'] = ['old b'];
    await pump(tester);
    expect(screen.currentState!.history, ['old a']);
    await results(tester, 'дюн');
    screen.currentState!.primeRefresh();
    await tester.pumpAndSettle();
    expect(search.calls, ['дюн', 'дюн']);
    expect(find.text('дюн'), findsOneWidget);

    history.scope = 'b';
    screen.currentState!.fullRefresh();
    await tester.pumpAndSettle();
    expect(controller().query, '');
    expect(find.text(TvSearchStrings.placeholder), findsOneWidget);
    expect(screen.currentState!.history, ['old b']);
  });

  testWidgets('R9: onTabHidden, paused and a covering route record shown results', (tester) async {
    search.respond = (q) => answer(items: movies(1));
    await pump(tester);
    await results(tester, 'Дюна');
    screen.currentState!.onTabHidden();
    await tester.pumpAndSettle();
    expect(history.values['a'], ['Дюна']);
    screen.currentState!.onTabShown();

    await results(tester, 'тьма');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(history.values['a'], ['тьма', 'Дюна']);

    await results(tester, 'дюна');
    unawaited(Navigator.of(screen.currentContext!).push(MaterialPageRoute<void>(builder: (_) => const SizedBox())));
    await tester.pumpAndSettle();
    expect(history.values['a'], ['дюна', 'тьма']);
  });

  for (final details in [false, true]) {
    testWidgets('A20: episode OK ${details ? "opens details" : "plays"}; Play/Pause plays', (tester) async {
      final settings = await SettingsService.getInstance();
      if (details) await settings.write(SettingsService.episodeAction, EpisodeAction.details);
      final episode = testMediaItem(
        id: 'ep',
        kind: MediaKind.episode,
        title: 'Ep',
        serverId: 'server',
        parentIndex: 1,
        index: 1,
        durationMs: 3600000,
        grandparentId: 'show',
      );
      search.respond = (_) => answer(items: [episode, ...movies(1)]);
      final observer = _Routes();
      await pump(tester, client: _ActionClient(), observers: [observer]);
      await results(tester, 'ep');
      // Rows: Movies, then Episodes.
      await press(tester, LogicalKeyboardKey.arrowRight, times: 6);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedId(tester), 'ep');
      await press(tester, LogicalKeyboardKey.enter);
      expect(observer.players.length, details ? 0 : 1);
      expect(observer.details, details ? 1 : 0);
      expect(history.values['a'], ['ep']);
      await press(tester, LogicalKeyboardKey.mediaPlayPause);
      expect(observer.players.length, details ? 1 : 2);
    });
  }

  testWidgets('A22: a menu action refreshes the card and keeps focus on it', (tester) async {
    final stack = await ProfileStack.create(withStorage: false);
    addTearDown(stack.dispose);
    final store = WatchStateStore();
    addTearDown(store.dispose);
    final client = _ActionClient();
    search.respond = (_) => answer(items: movies(2));
    fetch = (item) => item.copyWith(title: 'Updated');
    await pump(tester, client: client, profile: stack.active, watchState: store);
    await results(tester, 'movie');
    await press(tester, LogicalKeyboardKey.arrowRight, times: 6);
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(focusedId(tester), 'movie1');
    await press(tester, LogicalKeyboardKey.contextMenu);
    await tester.tap(find.text(t.mediaMenu.markAsWatched));
    await tester.pumpAndSettle();
    expect(client.watched.map((e) => e.id), ['movie1']);
    expect(fetched, ['movie1']);
    expect(find.text('Updated'), findsOneWidget);
    expect(focusedId(tester), 'movie1');
    expect(tester.takeException(), isNull);
  });

  testWidgets('A14: the keyboard layout is saved and restored on a new mount', (tester) async {
    await pump(tester);
    expect(_key('char:а'), findsOneWidget);
    await tester.tap(_key('layout:${TvSearchKeyboardLayout.en.prefValue}'));
    await tester.pumpAndSettle();
    expect(_key('char:a'), findsOneWidget);
    expect(SettingsService.instance.read(TvSettings.searchKeyboardLayout), 'en');
    await tester.pumpWidget(const SizedBox.shrink());
    screen = GlobalKey<TvSearchScreenState>();
    await pump(tester);
    expect(_key('char:a'), findsOneWidget);
    expect(_key('char:а'), findsNothing);
  });

  group('R4/A24 hidden libraries', () {
    late _Hidden hidden;
    late List<MediaItem> all;
    setUp(() {
      hidden = _Hidden();
      all = movies(5);
      // movie2 lives in library «kids».
      search.respond = (_) => answer(
        items: [
          for (final item in all)
            if (!(item.id == 'movie2' && hidden.keys.contains('kids'))) item,
        ],
      );
    });

    Future<void> focusMovie(WidgetTester tester, int index) async {
      await press(tester, LogicalKeyboardKey.arrowRight, times: 6);
      await press(tester, LogicalKeyboardKey.arrowRight, times: index);
      expect(focusedId(tester), 'movie$index');
    }

    testWidgets('hiding another library while shown searches again and keeps the item', (tester) async {
      await pump(tester, hidden: hidden);
      await results(tester, 'дюн');
      await focusMovie(tester, 3);
      final before = search.calls.length;
      hidden.hide('other');
      await tester.pumpAndSettle();
      expect(search.calls.length, before + 1);
      expect(focusedId(tester), 'movie3');
      hidden.hide('other'); // same key set: no search
      await tester.pumpAndSettle();
      expect(search.calls.length, before + 1);
    });

    testWidgets('F1: hiding the focused item\'s library from another section — first card on return', (tester) async {
      await pump(tester, hidden: hidden);
      await results(tester, 'дюн');
      await focusMovie(tester, 2);
      screen.currentState!.onTabHidden();
      menu.requestFocus();
      await tester.pumpAndSettle();
      final before = search.calls.length;
      hidden.hide('kids');
      await tester.pumpAndSettle();
      expect(search.calls.length, before + 1);
      expect(find.byType(TvPoster), findsNWidgets(4));
      screen.currentState!.onTabShown();
      screen.currentState!.focusActiveTabIfReady();
      await tester.pumpAndSettle();
      expect(focusedId(tester), 'movie0');
      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(tester.state<TvSearchKeyboardState>(find.byType(TvSearchKeyboard)).hasFocus, isTrue);
    });

    testWidgets('F1: a re-search under a covering route keeps a surviving item after pop', (tester) async {
      await pump(tester, hidden: hidden);
      await results(tester, 'дюн');
      await focusMovie(tester, 3);
      unawaited(
        Navigator.of(
          screen.currentContext!,
        ).push(MaterialPageRoute<void>(builder: (_) => const Focus(autofocus: true, child: SizedBox()))),
      );
      await tester.pumpAndSettle();
      hidden.hide('kids');
      await tester.pumpAndSettle();
      Navigator.of(screen.currentContext!).pop();
      await tester.pumpAndSettle();
      expect(focusedId(tester), 'movie3');
    });

    testWidgets('F1: a re-search under a covering route that removes the focused item — first card after pop', (
      tester,
    ) async {
      await pump(tester, hidden: hidden);
      await results(tester, 'дюн');
      await focusMovie(tester, 2);
      unawaited(
        Navigator.of(
          screen.currentContext!,
        ).push(MaterialPageRoute<void>(builder: (_) => const Focus(autofocus: true, child: SizedBox()))),
      );
      await tester.pumpAndSettle();
      hidden.hide('kids');
      await tester.pumpAndSettle();
      expect(find.byType(TvPoster, skipOffstage: false), findsNWidgets(4));
      Navigator.of(screen.currentContext!).pop();
      await tester.pumpAndSettle();
      expect(focusedId(tester), 'movie0');
      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(tester.state<TvSearchKeyboardState>(find.byType(TvSearchKeyboard)).hasFocus, isTrue);
    });

    testWidgets('F1: a re-search that leaves nothing focuses the keyboard on return', (tester) async {
      await pump(tester, hidden: hidden);
      all = [all[2]];
      await results(tester, 'дюн');
      await press(tester, LogicalKeyboardKey.arrowRight, times: 6);
      expect(focusedId(tester), 'movie2');
      screen.currentState!.onTabHidden();
      menu.requestFocus();
      hidden.hide('kids');
      await tester.pumpAndSettle();
      expect(find.text(TvSearchStrings.nothingFound), findsOneWidget);
      screen.currentState!.onTabShown();
      screen.currentState!.focusActiveTabIfReady();
      await tester.pumpAndSettle();
      expect(tester.state<TvSearchKeyboardState>(find.byType(TvSearchKeyboard)).hasFocus, isTrue);
    });
  });

  testWidgets('F3: a submitted query answered while hidden focuses the first card on return, once', (tester) async {
    search.respond = (_) => answer(items: movies(3));
    await pump(tester);
    screen.currentState!.onTabHidden();
    menu.requestFocus();
    screen.currentState!.submitSearchQuery('matrix');
    menu.requestFocus();
    await tester.pumpAndSettle();
    expect(find.byType(TvPoster), findsNWidgets(3));
    screen.currentState!.onTabShown();
    screen.currentState!.focusActiveTabIfReady();
    await tester.pumpAndSettle();
    expect(focusedId(tester), 'movie0');
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(keyFocused(tester, 'char:а'), isTrue);
    screen.currentState!.primeRefresh();
    await tester.pumpAndSettle();
    expect(keyFocused(tester, 'char:а'), isTrue);
  });

  testWidgets('F2: Retry keeps a usable focus while loading; a second failure focuses Retry again', (tester) async {
    search.error = const TvSearchUnavailable();
    await pump(tester);
    await results(tester, 'аа');
    await press(tester, LogicalKeyboardKey.arrowRight, times: 6);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'TV Search retry');

    search.hold = Completer();
    await press(tester, LogicalKeyboardKey.enter);
    expect(controller().state, TvSearchState.loading);
    search.hold!.completeError(const TvSearchUnavailable());
    search.hold = null;
    await tester.pumpAndSettle();
    expect(find.text(TvSearchStrings.unavailable), findsOneWidget);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'TV Search retry');

    search.hold = Completer();
    await press(tester, LogicalKeyboardKey.enter);
    expect(controller().state, TvSearchState.loading);
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(tester.state<TvSearchKeyboardState>(find.byType(TvSearchKeyboard)).hasFocus, isTrue);
    search.hold!.complete(answer(items: movies(1)));
    search.hold = null;
    await tester.pumpAndSettle();
  });

  testWidgets('F2: a successful retry focuses the first card', (tester) async {
    search.error = const TvSearchUnavailable();
    await pump(tester);
    await results(tester, 'аа');
    await press(tester, LogicalKeyboardKey.arrowRight, times: 6);
    search
      ..error = null
      ..respond = (_) => answer(items: movies(2));
    await press(tester, LogicalKeyboardKey.enter);
    expect(focusedId(tester), 'movie0');
  });

  group('A21 fresh watch state after a round-trip', () {
    Future<WatchStateStore> setup(WidgetTester tester, _Routes observer) async {
      final stack = await ProfileStack.create(withStorage: false);
      addTearDown(stack.dispose);
      final store = WatchStateStore();
      addTearDown(store.dispose);
      search.respond = (_) => answer(items: movies(2));
      await pump(tester, client: _ActionClient(), profile: stack.active, watchState: store, observers: [observer]);
      await results(tester, 'movie');
      return store;
    }

    MediaItem poster(WidgetTester tester, String id) =>
        tester.widgetList<TvPoster>(find.byType(TvPoster)).firstWhere((p) => p.item.id == id).item;

    testWidgets('rows: the card shows the new status after details', (tester) async {
      final observer = _Routes();
      await setup(tester, observer);
      await press(tester, LogicalKeyboardKey.arrowRight, times: 6);
      await press(tester, LogicalKeyboardKey.enter);
      expect(observer.details, 1);
      WatchStateNotifier().notifyWatched(item: movies(2).first, isNowWatched: true);
      await tester.pumpAndSettle();
      expect(poster(tester, 'movie0').isWatched, isTrue);
      expect(focusedId(tester), 'movie0');
    });

    testWidgets('grid: the card and Play/Pause use the new status after playing', (tester) async {
      final observer = _Routes();
      await setup(tester, observer);
      controller().selectTab(TvSearchTab.movies);
      await tester.pumpAndSettle();
      await press(tester, LogicalKeyboardKey.arrowRight, times: 6);
      expect(focusedId(tester), 'movie0');
      await press(tester, LogicalKeyboardKey.mediaPlayPause);
      expect(observer.players.length, 1);
      WatchStateNotifier().notifyProgress(item: movies(2).first, viewOffset: 1800000, duration: 3600000);
      await tester.pumpAndSettle();
      expect(poster(tester, 'movie0').viewOffsetMs, 1800000);
      await press(tester, LogicalKeyboardKey.mediaPlayPause);
      expect(observer.players.length, 2);
      final page = observer.players.last.buildPage(
        screen.currentContext!,
        kAlwaysCompleteAnimation,
        kAlwaysCompleteAnimation,
      );
      expect((page as VideoPlayerScreen).metadata.viewOffsetMs, 1800000);
    });
  });

  testWidgets('partial results: the snackbar shows once per revision', (tester) async {
    var failed = true;
    search.respond = (_) => (
      hits: const [],
      candidates: movies(2),
      people: const <MediaPerson>[],
      succeededServerIds: const {'server'},
      cancelledServerIds: const <String>{},
      failedServerIds: failed ? const {'other'} : const <String>{},
    );
    await pump(tester);
    await results(tester, 'дюн');
    expect(find.text(t.messages.searchPartialResults), findsOneWidget);
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(find.text(t.messages.searchPartialResults), findsNothing);
    controller().selectTab(TvSearchTab.movies);
    await tester.pumpAndSettle();
    expect(find.text(t.messages.searchPartialResults), findsNothing);
    failed = false;
    screen.currentState!.refresh();
    await tester.pumpAndSettle();
    expect(find.text(t.messages.searchPartialResults), findsNothing);
    failed = true;
    screen.currentState!.refresh();
    await tester.pumpAndSettle();
    expect(find.text(t.messages.searchPartialResults), findsOneWidget);
  });

  testWidgets('A7/R6: OK opens movie details and person media; both record history', (tester) async {
    final observer = _Routes();
    search.respond = (_) => answer(items: movies(1), people: [person('1', PersonCredit.actor)]);
    await pump(tester, client: _ActionClient(), observers: [observer]);
    Widget page(int i) => switch (observer.pages[i]) {
      final MaterialPageRoute<dynamic> route => route.builder(screen.currentContext!),
      final route => route.buildPage(screen.currentContext!, kAlwaysCompleteAnimation, kAlwaysDismissedAnimation),
    };
    await results(tester, 'дюн');
    await press(tester, LogicalKeyboardKey.arrowRight, times: 6);
    expect(focusedId(tester), 'movie0');
    await press(tester, LogicalKeyboardKey.enter);
    expect(observer.details, 1);
    final details = page(0);
    expect(details, anyOf(isA<TvMovieScreen>(), isA<MediaDetailScreen>()));
    expect((details as dynamic).metadata.id, 'movie0');
    expect(history.values['a'], ['дюн']);

    // Row person card, after another query so its own history entry shows.
    await results(tester, 'тьма');
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(focusedId(tester), 'Person 1');
    await press(tester, LogicalKeyboardKey.enter);
    expect(observer.details, 2);
    final row = page(1);
    expect(row, isA<ActorMediaScreen>());
    expect((row as ActorMediaScreen).personId, '1');
    expect(row.actorName, 'Person 1');
    expect(history.values['a'], ['тьма', 'дюн']);

    // People grid card.
    await results(tester, 'фильм');
    await press(tester, LogicalKeyboardKey.arrowUp, times: 2);
    // Tabs: All, Movies, People.
    await press(tester, LogicalKeyboardKey.arrowRight, times: 2);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(controller().selectedTab, TvSearchTab.people);
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(focusedId(tester), 'Person 1');
    await press(tester, LogicalKeyboardKey.enter);
    expect(observer.details, 3);
    final grid = page(2);
    expect(grid, isA<ActorMediaScreen>());
    expect((grid as ActorMediaScreen).personId, '1');
    expect(history.values['a'], ['фильм', 'тьма', 'дюн']);
  });

  testWidgets('R6: with several servers, captions name the server', (tester) async {
    MediaItem on(String id, MediaKind kind) => testMediaItem(
      id: id,
      kind: kind,
      title: id,
      serverId: 'server',
      durationMs: 1,
    ).copyWith(serverName: 'Living room', year: 2021);
    search.respond = (_) => answer(items: [on('m', MediaKind.movie)]);
    await pump(tester, client: _ActionClient(), moreClients: [_ActionClient('second')]);
    await results(tester, 'm');
    expect(find.text('2021 · Living room'), findsOneWidget);
  });

  group('T5 idle screen', () {
    late _Discover discover;
    setUp(() => discover = _Discover()..hubs = [continueHub, hub('trending'), hub('recent'), hub('third')]);

    String? focusLabel() => FocusManager.instance.primaryFocus?.debugLabel;

    testWidgets('A1: history and two Home hubs (no Continue Watching); → ↓ ↑ ← focus', (tester) async {
      history.values['a'] = ['Тьма', 'Дюна'];
      await pump(tester, discover: discover);
      expect(keyFocused(tester, 'char:а'), isTrue);
      expect(find.text(TvSearchStrings.recentSearches), findsOneWidget);
      expect(find.text('Тьма'), findsOneWidget);
      expect(find.text('Дюна'), findsOneWidget);
      expect(screen.currentState!.hubTitles, ['trending', 'recent']);
      expect(find.text('Continue Watching'), findsNothing);
      expect(find.text('third'), findsNothing);
      expect(discover.loads, 0);

      await press(tester, LogicalKeyboardKey.arrowRight, times: 6);
      expect(focusLabel(), 'TV Search recent 0');
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(focusLabel(), 'TV Search recent 1');
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedId(tester), 'trending0');
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedId(tester), 'recent0');
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(focusedId(tester), 'trending0');
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(focusLabel(), 'TV Search recent 0');
      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(keyFocused(tester, 'char:а'), isTrue);
    });

    testWidgets('R10: without history → goes to the first hub card', (tester) async {
      await pump(tester, discover: discover);
      expect(find.text(TvSearchStrings.recentSearches), findsNothing);
      await press(tester, LogicalKeyboardKey.arrowRight, times: 6);
      expect(focusedId(tester), 'trending0');
    });

    testWidgets('A10: a recent query with results searches at once and focuses the first result', (tester) async {
      history.values['a'] = ['Тьма'];
      search.respond = (_) => answer(items: movies(2));
      await pump(tester, discover: discover);
      await press(tester, LogicalKeyboardKey.arrowRight, times: 6);
      expect(focusLabel(), 'TV Search recent 0');
      await press(tester, LogicalKeyboardKey.enter);
      expect(search.calls, ['Тьма']);
      expect(controller().query, 'Тьма');
      expect(focusedId(tester), 'movie0');
    });

    testWidgets('A10/A8: a recent query without results — nothing found, rows below, focus on «а»', (tester) async {
      history.values['a'] = ['Тьма'];
      await pump(tester, discover: discover);
      await press(tester, LogicalKeyboardKey.arrowRight, times: 6);
      await press(tester, LogicalKeyboardKey.enter);
      expect(search.calls, ['Тьма']);
      expect(find.text(TvSearchStrings.nothingFound), findsOneWidget);
      expect(find.text(TvSearchStrings.nothingFoundHelp('Тьма')), findsOneWidget);
      expect(keyFocused(tester, 'char:а'), isTrue);
      // Rows under the text, without history.
      expect(find.text(TvSearchStrings.recentSearches), findsNothing);
      expect(find.text('trending'), findsOneWidget);
      expect(find.text('recent'), findsOneWidget);
      final textY = tester.getTopLeft(find.text(TvSearchStrings.nothingFound)).dy;
      expect(tester.getTopLeft(find.text('trending')).dy, greaterThan(textY));
      await press(tester, LogicalKeyboardKey.arrowRight, times: 6);
      expect(focusedId(tester), 'trending0');
    });

    testWidgets('initial provider: one load(), skeletons, then rows', (tester) async {
      discover
        ..hubs = []
        ..isLoading = true
        ..areHubsLoading = true
        ..loadStartsLoading = true;
      await pump(tester, discover: discover);
      expect(discover.loads, 1);
      expect(find.byType(TvRowSkeleton), findsWidgets);
      screen.currentState!.primeRefresh();
      screen.currentState!.fullRefresh();
      await tester.pumpAndSettle();
      expect(discover.loads, 1);
      discover.ready([hub('trending')]);
      await tester.pumpAndSettle();
      expect(find.byType(TvRowSkeleton), findsNothing);
      expect(screen.currentState!.hubTitles, ['trending']);
    });

    testWidgets('A19: error — no rows, no skeletons; primeRefresh with servers — rows appear', (tester) async {
      discover
        ..hubs = []
        ..errorMessage = 'No servers';
      await pump(tester, discover: discover, client: _ActionClient());
      expect(discover.loads, 1); // mount retries a failed load once; it fails again
      expect(find.byType(TvRowSkeleton), findsNothing);
      expect(screen.currentState!.hubTitles, isEmpty);
      discover.loadStartsLoading = true;
      screen.currentState!.primeRefresh();
      await tester.pump();
      expect(discover.loads, 2);
      expect(find.byType(TvRowSkeleton), findsWidgets);
      discover.ready([hub('trending'), hub('recent')]);
      await tester.pumpAndSettle();
      expect(find.byType(TvRowSkeleton), findsNothing);
      expect(screen.currentState!.hubTitles, ['trending', 'recent']);
    });

    testWidgets('only Continue Watching — no rows block, → keeps focus on the keyboard', (tester) async {
      discover.hubs = [continueHub];
      await pump(tester, discover: discover);
      expect(screen.currentState!.hubTitles, isEmpty);
      expect(find.byType(TvPoster), findsNothing);
      expect(find.byType(TvRowSkeleton), findsNothing);
      await press(tester, LogicalKeyboardKey.arrowRight, times: 6);
      expect(focusedId(tester), isNull);
      expect(tester.state<TvSearchKeyboardState>(find.byType(TvSearchKeyboard)).hasFocus, isTrue);
    });
  });
}
