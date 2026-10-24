import 'package:plezy/models/download_models.dart';
import 'package:plezy/media/ids.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_server_client.dart';
import 'package:plezy/media/server_capabilities.dart';
import 'package:plezy/database/app_database.dart';
import 'package:plezy/providers/download_provider.dart';
import 'package:plezy/providers/multi_server_provider.dart';
import 'package:plezy/providers/offline_mode_provider.dart';
import 'package:plezy/profiles/active_profile_provider.dart';
import 'package:plezy/services/offline_watch_sync_service.dart';
import 'package:plezy/utils/video_player_navigation.dart';
import 'package:plezy/screens/video_player_screen.dart';
import 'package:plezy/widgets/media_context_menu.dart';
import 'package:plezy/i18n/strings.g.dart';
import '../../test_helpers/multi_server_fixtures.dart';
import '../../test_helpers/profile_stack.dart';
import "dart:async";

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:plezy/providers/watch_state_store.dart';
import 'package:plezy/utils/watch_state_notifier.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:plezy/providers/discover_provider.dart';
import 'package:plezy/media/media_hub.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/navigation/main_screen_scope.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_all_card.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_button.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_cards.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_hero.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_horizontal_row.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_skeletons.dart';
import 'package:plezy/plezytv/tv_ui/home/tv_home_screen.dart';
import 'package:plezy/plezytv/tv_ui/tv_strings.dart';
import 'package:plezy/plezytv/tv_ui/tv_tint_service.dart';
import 'package:plezy/plezytv/tv_ui/tv_tinted_background.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/screens/hub_detail_screen.dart';
import 'package:plezy/widgets/optimized_media_image.dart';
import '../../test_helpers/media_items.dart';
import '../../test_helpers/prefs.dart';
import 'tv_theme_test_helper.dart';

class _ActionClient implements MediaServerClient {
  final watched = <MediaItem>[];
  final removed = <MediaItem>[];
  final lookups = <String>[];
  MediaItem? nextEpisode;
  @override
  ServerId get serverId => ServerId('server');
  @override
  void close() {}
  @override
  MediaBackend get backend => MediaBackend.plex;
  @override
  ServerCapabilities get capabilities =>
      const ServerCapabilities(videoTranscoding: false, continueWatchingRemoval: true);
  @override
  Future<({MediaItem? item, MediaItem? onDeckEpisode})> fetchItemWithOnDeck(
    String id, {
    void Function(MediaItem item)? onItemReady,
  }) async {
    lookups.add(id);
    return (item: null, onDeckEpisode: nextEpisode);
  }

  @override
  Future<void> markWatched(MediaItem item) async => watched.add(item);
  @override
  Future<void> removeFromContinueWatching(MediaItem item) async => removed.add(item);
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

class _Launches extends NavigatorObserver {
  final routes = <VideoPlayerRoute>[];
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is VideoPlayerRoute) {
      routes.add(route);
      scheduleMicrotask(() => navigator!.removeRoute(route));
    }
  }
}

// Return the real details route's changed result before mounting its upstream
// dependency tree. This exercises Home's actual navigateToMediaItem callback.
class _ChangedDetails extends NavigatorObserver {
  int opened = 0;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute == null) return;
    opened++;
    scheduleMicrotask(() => navigator!.removeRoute(route, true));
  }
}

class _Discover extends ChangeNotifier implements DiscoverProvider {
  @override
  List<MediaItem> onDeck = [];
  @override
  List<MediaHub> hubs = [];
  @override
  bool isLoading = false, areHubsLoading = false, isLoadInFlight = false, hasMoreContinueWatching = false;
  @override
  String? errorMessage;
  int loads = 0, staleChecks = 0, continueRefreshes = 0, manualRefreshes = 0, allLoads = 0;
  bool stale = false, loadStartsLoading = false;
  final updatedItems = <MediaItem>[];
  @override
  Future<void> updateItem(MediaItem item) async {
    updatedItems.add(item);
  }

  @override
  Future<void> load() async {
    loads++;
    if (loadStartsLoading) {
      isLoading = areHubsLoading = isLoadInFlight = true;
      errorMessage = null;
      emit();
    }
  }

  @override
  bool refreshIfStale() {
    staleChecks++;
    return stale;
  }

  @override
  Future<void> refreshContinueWatching() async {
    continueRefreshes++;
  }

  @override
  Future<DiscoverRefreshOutcome> refreshNow() async {
    manualRefreshes++;
    isLoading = areHubsLoading = isLoadInFlight = true;
    errorMessage = null;
    emit();
    return DiscoverRefreshOutcome.refreshed;
  }

  @override
  Future<List<MediaItem>> loadAllContinueWatching() async {
    allLoads++;
    return onDeck;
  }

  void emit() => notifyListeners();
  void ready() {
    isLoading = areHubsLoading = isLoadInFlight = false;
    emit();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

List<MediaItem> items(String prefix, [int count = 12]) => [
  for (var i = 0; i < count; i++)
    testMediaItem(
      id: '$prefix$i',
      title: '$prefix$i',
      serverId: 'server',
      kind: prefix == 'episode' ? MediaKind.episode : MediaKind.movie,
      parentIndex: 1,
      index: i + 1,
      durationMs: 3600000,
      viewOffsetMs: 600000,
      summary: 'Summary $prefix$i',
    ),
];
MediaHub hub(String id, [int count = 12]) =>
    MediaHub(id: id, title: id, type: 'movie', items: items(id, count), size: count);

void main() {
  late _Discover provider;
  late FocusNode menu;
  late GlobalKey<TvHomeScreenState> home;
  setUp(() async {
    resetSharedPreferencesForTest();
    await SettingsService.getInstance();
    provider = _Discover();
    menu = FocusNode(debugLabel: 'test menu');
    home = GlobalKey<TvHomeScreenState>();
  });
  tearDown(() {
    menu.dispose();
    provider.dispose();
  });

  Future<void> pump(
    WidgetTester tester, {
    bool reduced = true,
    WatchStateStore? watchState,
    List<NavigatorObserver> observers = const [],
    _ActionClient? actionClient,
    ActiveProfileProvider? profile,
  }) async {
    final servers = actionClient == null ? null : testMultiServer(clients: [actionClient]);
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
          ChangeNotifierProvider<DiscoverProvider>.value(value: provider),
          if (servers != null) ChangeNotifierProvider<MultiServerProvider>.value(value: servers.provider),
          ChangeNotifierProvider<DownloadProvider>.value(value: downloads),
          ChangeNotifierProvider<OfflineWatchSyncService>.value(value: offlineWatch),
          if (offline != null) ChangeNotifierProvider<OfflineModeProvider>.value(value: offline),
          if (profile != null) ChangeNotifierProvider<ActiveProfileProvider>.value(value: profile),
          if (watchState != null) ChangeNotifierProvider<WatchStateStore>.value(value: watchState),
        ],
        child: MainScreenFocusScope(
          focusSidebar: menu.requestFocus,
          sideNavigationWidth: 0,
          child: Stack(
            children: [
              Focus(focusNode: menu, child: const SizedBox()),
              TvHomeScreen(key: home),
            ],
          ),
        ),
      ),
      reduced: reduced,
      appTheme: monoTheme(MonoPalette.dark),
      navigatorObservers: observers,
    );
    await tester.pump();
    await tester.pump();
  }

  Future<void> key(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }

  TvHorizontalRowState row(WidgetTester tester, int index) =>
      tester.state<TvHorizontalRowState>(find.byType(TvHorizontalRow).at(index));
  TvHero hero(WidgetTester tester) => tester.widget<TvHero>(find.byType(TvHero));
  void content() {
    provider.onDeck = items('episode');
    provider.hubs = [hub('movies'), hub('shows'), hub('more')];
  }

  testWidgets('A1/A2/A3: first card, hero, vertical row memory and compact geometry', (tester) async {
    content();
    await pump(tester);
    await tester.pumpAndSettle();
    expect(hero(tester).item!.id, 'episode0');
    expect(row(tester, 0).focusInside.value, isTrue);
    expect(hero(tester).hideSpoilers, SettingsService.instance.read(SettingsService.hideSpoilers));
    await key(tester, LogicalKeyboardKey.arrowUp);
    expect(row(tester, 0).focusInside.value, isTrue);
    await key(tester, LogicalKeyboardKey.arrowDown);
    for (var i = 0; i < 4; i++) {
      await key(tester, LogicalKeyboardKey.arrowRight);
    }
    expect(hero(tester).item!.id, 'movies4');
    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(hero(tester).compact, isTrue);
    expect(tester.getTopLeft(find.byType(TvHorizontalRow).at(2)).dy, 420);
    await key(tester, LogicalKeyboardKey.arrowUp);
    expect(hero(tester).compact, isFalse);
    expect(hero(tester).item!.id, 'movies4');
    expect(row(tester, 1).focusedIndex, 4);
    expect(tester.getTopLeft(find.byType(TvHorizontalRow).at(1)).dy, 600);
  });

  testWidgets('R1: hide-spoilers preference updates the hero', (tester) async {
    content();
    await SettingsService.instance.write(SettingsService.hideSpoilers, true);
    await pump(tester);
    await tester.pumpAndSettle();
    expect(hero(tester).hideSpoilers, isTrue);
    await SettingsService.instance.write(SettingsService.hideSpoilers, false);
    await tester.pumpAndSettle();
    expect(hero(tester).hideSpoilers, isFalse);
  });

  testWidgets('A4: text follows rapid focus before backdrop debounce', (tester) async {
    content();
    await pump(tester);
    await tester.pumpAndSettle();
    for (var i = 1; i <= 3; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(hero(tester).item!.id, 'episode$i');
    }
    expect(tester.widget<TvTintedBackground>(find.byType(TvTintedBackground)).source.item.id, 'episode3');
  });

  testWidgets('A4: existing background requests final artwork only after 300ms', (tester) async {
    final source = ValueNotifier(TvArtworkSource(item: items('episode')[0]));
    final requested = <String>[];
    final service = TvTintService(
      fetch: (source, backdrop, width) async {
        requested.add(source.item.id);
        return null;
      },
    );
    await pumpTvWidget(
      tester,
      ValueListenableBuilder<TvArtworkSource>(
        valueListenable: source,
        builder: (_, value, _) => TvTintedBackground(source: value, service: service),
      ),
    );
    await tester.pumpAndSettle();
    requested.clear();
    for (var i = 1; i <= 3; i++) {
      source.value = TvArtworkSource(item: items('episode')[i]);
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 299));
    expect(requested, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    expect(requested, ['episode3', 'episode3']); // tint and backdrop
    await tester.pumpWidget(const SizedBox.shrink());
    source.dispose();
  });

  testWidgets('R10: horizontal focus updates hero without rebuilding rail/card builders', (tester) async {
    content();
    await pump(tester);
    await tester.pumpAndSettle();
    final rails = tester.widgetList<TvHorizontalRow>(find.byType(TvHorizontalRow)).toList();
    final cards = tester.widgetList<TvEpisode>(find.byType(TvEpisode)).toList();
    var railBuilds = 0, cardBuilds = 0;
    final previous = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      previous?.call(element, builtOnce);
      if (element.widget is TvHorizontalRow) railBuilds++;
      if (element.widget is TvEpisode || element.widget is TvPoster) cardBuilds++;
    };
    addTearDown(() => debugOnRebuildDirtyWidget = previous);
    await key(tester, LogicalKeyboardKey.arrowRight);
    expect(hero(tester).item!.id, 'episode1');
    expect(tester.widgetList<TvHorizontalRow>(find.byType(TvHorizontalRow)).toList(), orderedEquals(rails));
    expect(tester.widgetList<TvEpisode>(find.byType(TvEpisode)).toList(), orderedEquals(cards));
    expect(cards.length, lessThan(12));
    expect(railBuilds, 0);
    expect(cardBuilds, 0);
    final image = tester.widget<OptimizedMediaImage>(
      find.descendant(of: find.byType(TvEpisode).first, matching: find.byType(OptimizedMediaImage)),
    );
    expect(image.width, 400);
    expect(image.height, 225);
  });

  testWidgets('R10: compact hero animation preserves rails/cards and row focus geometry', (tester) async {
    content();
    await pump(tester, reduced: false);
    await tester.pumpAndSettle();
    await key(tester, LogicalKeyboardKey.arrowDown);
    final rails = tester.widgetList<TvHorizontalRow>(find.byType(TvHorizontalRow)).toList();
    var railBuilds = 0, cardBuilds = 0;
    final previous = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      previous?.call(element, builtOnce);
      if (element.widget is TvHorizontalRow) railBuilds++;
      if (element.widget is TvEpisode || element.widget is TvPoster) cardBuilds++;
    };
    addTearDown(() => debugOnRebuildDirtyWidget = previous);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    // Focus changes may build newly visible cards. Count only animation frames.
    railBuilds = cardBuilds = 0;
    for (var frame = 0; frame < 24; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      if (frame == 0) {
        expect(tester.getSize(find.byType(TvHero)).height, inExclusiveRange(420, 600));
      }
      expect(railBuilds, 0, reason: 'hero animation frame $frame');
      expect(cardBuilds, 0, reason: 'hero animation frame $frame');
      if (frame == 3) await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    }
    await tester.pumpAndSettle();
    expect(tester.widgetList<TvHorizontalRow>(find.byType(TvHorizontalRow)).toList(), orderedEquals(rails));
    expect(hero(tester).compact, isTrue);
    expect(hero(tester).item!.id, 'shows1');
    expect(row(tester, 2).focusInside.value, isTrue);
    expect(row(tester, 2).focusedIndex, 1);
    expect(tester.getTopLeft(find.byType(TvHorizontalRow).at(2)).dy, 420);
    await key(tester, LogicalKeyboardKey.arrowUp);
    expect(hero(tester).compact, isFalse);
    expect(row(tester, 1).focusInside.value, isTrue);
    expect(tester.getTopLeft(find.byType(TvHorizontalRow).at(1)).dy, 600);
  });

  testWidgets('A14: Continue Watching OK respects play setting', (tester) async {
    final settings = await SettingsService.getInstance();
    await settings.write(SettingsService.continueWatchingAction, ContinueWatchingAction.play);
    provider.onDeck = items('episode', 1);
    final observer = _Launches();
    await pump(tester, actionClient: _ActionClient(), observers: [observer]);
    await tester.pumpAndSettle();
    await key(tester, LogicalKeyboardKey.enter);
    expect(observer.routes, hasLength(1));
    final player =
        observer.routes.single.buildPage(
              home.currentContext!,
              const AlwaysStoppedAnimation(1.0),
              const AlwaysStoppedAnimation(0.0),
            )
            as VideoPlayerScreen;
    expect(player.metadata.id, 'episode0');
  });

  for (final transport in [LogicalKeyboardKey.mediaPlayPause, LogicalKeyboardKey.mediaPlay]) {
    testWidgets('A15: $transport bypasses details settings for episode and show', (tester) async {
      final settings = await SettingsService.getInstance();
      await settings.write(SettingsService.continueWatchingAction, ContinueWatchingAction.details);
      await settings.write(SettingsService.episodeAction, EpisodeAction.details);
      provider.onDeck = items('episode', 1);
      provider.hubs = [
        MediaHub(
          id: 'shows',
          title: 'Shows',
          type: 'show',
          items: [testMediaItem(id: 'show', kind: MediaKind.show, serverId: 'server')],
        ),
      ];
      final client = _ActionClient()..nextEpisode = items('episode', 2).last;
      final observer = _Launches();
      await pump(tester, actionClient: client, observers: [observer]);
      await tester.pumpAndSettle();
      await key(tester, transport);
      await key(tester, LogicalKeyboardKey.arrowDown);
      await key(tester, transport);
      expect(observer.routes, hasLength(2));
      expect(client.lookups, ['show']);
      final players = observer.routes
          .map(
            (route) =>
                route.buildPage(
                      home.currentContext!,
                      const AlwaysStoppedAnimation(1.0),
                      const AlwaysStoppedAnimation(0.0),
                    )
                    as VideoPlayerScreen,
          )
          .toList();
      expect(players.map((p) => p.metadata.id), ['episode0', 'episode1']);
      expect(players.map((p) => p.metadata.viewOffsetMs), everyElement(600000));
      expect(find.byType(TvHomeScreen), findsOneWidget);
    });
  }

  for (final longOk in [true, false]) {
    testWidgets('A6: ${longOk ? "long OK" : "Menu"} opens Plezy actions and refreshes source', (tester) async {
      final stack = await ProfileStack.create(withStorage: false);
      addTearDown(stack.dispose);
      final client = _ActionClient();
      provider.onDeck = items('episode', 2);
      final store = WatchStateStore();
      addTearDown(store.dispose);
      await pump(tester, actionClient: client, profile: stack.active, watchState: store);
      await tester.pumpAndSettle();
      if (longOk) {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
        await tester.pump(const Duration(seconds: 1));
        await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
      } else {
        await key(tester, LogicalKeyboardKey.contextMenu);
      }
      expect(tester.widget<MediaContextMenu>(find.byType(MediaContextMenu).first).isInContinueWatching, isTrue);
      expect(find.text(t.mediaMenu.markAsWatched), findsOneWidget);
      expect(find.text(t.mediaMenu.removeFromContinueWatching), findsOneWidget);
      await tester.tap(find.text(t.mediaMenu.markAsWatched));
      await tester.pumpAndSettle();
      expect(client.watched.map((e) => e.id), ['episode0']);
      expect(provider.updatedItems.map((e) => e.id), ['episode0']);
      expect(row(tester, 0).focusInside.value, isTrue);
      await key(tester, LogicalKeyboardKey.contextMenu);
      await tester.tap(find.text(t.mediaMenu.removeFromContinueWatching));
      await tester.pumpAndSettle();
      expect(client.removed.map((e) => e.id), ['episode0']);
      expect(provider.continueRefreshes, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('A8/A9b: 300ms skeleton, phased readiness and automatic focus transfer', (tester) async {
    provider.isLoading = provider.areHubsLoading = provider.isLoadInFlight = true;
    await pump(tester);
    expect(menu.hasFocus, isTrue);
    expect(find.byType(TvHeroSkeleton), findsNothing);
    await tester.pump(const Duration(milliseconds: 299));
    expect(find.byType(TvHeroSkeleton), findsNothing);
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.byType(TvHeroSkeleton), findsOneWidget);
    // Provider holds early hub responses privately until onDeck completes.
    final earlyHubs = [hub('early')];
    provider.emit();
    await tester.pump();
    expect(find.byType(TvHorizontalRow), findsNothing);
    provider.onDeck = items('episode');
    provider.isLoading = false;
    provider.hubs = [];
    provider.emit();
    await tester.pumpAndSettle();
    expect(row(tester, 0).focusInside.value, isTrue);
    expect(find.byType(TvRowSkeleton), findsOneWidget);
    provider.hubs = earlyHubs;
    provider.ready();
    await tester.pumpAndSettle();
    expect(find.byType(TvRowSkeleton), findsNothing);
    expect(find.byType(TvHorizontalRow), findsNWidgets(2));
  });

  testWidgets('fast load never paints skeleton', (tester) async {
    provider.isLoading = provider.areHubsLoading = true;
    await pump(tester);
    await tester.pump(const Duration(milliseconds: 100));
    content();
    provider.ready();
    await tester.pumpAndSettle();
    expect(find.byType(TvHeroSkeleton), findsNothing);
    expect(row(tester, 0).focusInside.value, isTrue);
  });

  for (final error in [false, true]) {
    testWidgets('A10/A10b/A10d/A11: terminal=$error, retry ownership and disabling', (tester) async {
      provider.errorMessage = error ? 'Server failed' : null;
      await pump(tester);
      await tester.pumpAndSettle();
      final button = tester.widget<TvButton>(find.byType(TvButton));
      expect(button.focusNode!.hasFocus, isTrue);
      expect(button.label, error ? TvStrings.retry : TvStrings.refresh);
      provider.loadStartsLoading = true;
      await key(tester, LogicalKeyboardKey.enter);
      expect(provider.loads, 2);
      expect(provider.manualRefreshes, 0);
      expect(tester.widget<TvButton>(find.byType(TvButton)).disabled, isTrue);
      expect(find.text(TvStrings.connecting), findsOneWidget);
      provider.loadStartsLoading = true;
      await key(tester, LogicalKeyboardKey.enter);
      expect(provider.loads, 2);
      expect(provider.manualRefreshes, 0);
      provider.errorMessage = error ? 'Server failed again' : null;
      provider.ready();
      await tester.pumpAndSettle();
      expect(tester.widget<TvButton>(find.byType(TvButton)).focusNode!.hasFocus, isTrue);
      await key(tester, LogicalKeyboardKey.enter);
      content();
      provider.ready();
      await tester.pumpAndSettle();
      expect(row(tester, 0).focusInside.value, isTrue);
      expect(hero(tester).item!.id, 'episode0');
    });
  }

  for (final escape in ['menu', 'route', 'section', 'retry-menu']) {
    testWidgets('R6/A17: arriving data preserves user focus in $escape', (tester) async {
      if (escape == 'retry-menu') {
        provider.errorMessage = 'Failed';
      } else {
        provider.isLoading = provider.areHubsLoading = true;
      }
      await pump(tester);
      await tester.pumpAndSettle();
      FocusNode? dialog;
      if (escape == 'route') {
        dialog = FocusNode();
        unawaited(
          showDialog<void>(
            context: home.currentContext!,
            builder: (_) => AlertDialog(
              content: TextButton(focusNode: dialog, autofocus: true, onPressed: () {}, child: const Text('dialog')),
            ),
          ),
        );
        await tester.pumpAndSettle();
      } else if (escape == 'section') {
        home.currentState!.onTabHidden();
        menu.requestFocus();
        await tester.pump();
      } else {
        if (escape == 'retry-menu') {
          provider.loadStartsLoading = true;
          await key(tester, LogicalKeyboardKey.enter);
          await key(tester, LogicalKeyboardKey.arrowLeft);
        } else {
          await key(tester, LogicalKeyboardKey.arrowUp);
        }
      }
      content();
      provider.ready();
      await tester.pumpAndSettle();
      expect(escape == 'route' ? dialog!.hasFocus : menu.hasFocus, isTrue);
      if (dialog != null) {
        Navigator.of(home.currentContext!).pop();
        await tester.pumpAndSettle();
        dialog.dispose();
      }
    });
  }

  testWidgets('A12/A18: refresh hooks, reorder/removal, removed row fallback', (tester) async {
    content();
    await pump(tester);
    await tester.pumpAndSettle();
    for (var i = 0; i < 3; i++) {
      await key(tester, LogicalKeyboardKey.arrowRight);
    }
    final state = home.currentState!;
    state.refresh();
    expect(provider.continueRefreshes, 1);
    provider.stale = true;
    state.refresh();
    expect(provider.continueRefreshes, 1);
    state.onTabHidden();
    state.onTabShown();
    expect(provider.staleChecks, 3);
    provider.isLoadInFlight = true;
    state.primeRefresh();
    expect(provider.loads, 1);
    provider.isLoadInFlight = false;
    state.primeRefresh();
    expect(provider.loads, 2);
    state.fullRefresh();
    expect(provider.loads, 3);
    provider.onDeck = [provider.onDeck[3], ...provider.onDeck.take(3), ...provider.onDeck.skip(4)];
    provider.emit();
    await tester.pumpAndSettle();
    expect(hero(tester).item!.id, 'episode3');
    expect(row(tester, 0).focusedIndex, 0);
    provider.onDeck = provider.onDeck.skip(1).toList();
    provider.emit();
    await tester.pumpAndSettle();
    expect(hero(tester).item!.id, 'episode0');
    provider.onDeck = [];
    provider.emit();
    await tester.pumpAndSettle();
    expect(row(tester, 0).focusInside.value, isTrue);
    expect(hero(tester).item!.id, 'movies0');
  });

  testWidgets('R9: disappearing lower rail falls back to first card, not remembered column', (tester) async {
    content();
    await pump(tester);
    await tester.pumpAndSettle();
    for (var i = 0; i < 3; i++) {
      await key(tester, LogicalKeyboardKey.arrowRight);
    }
    await key(tester, LogicalKeyboardKey.arrowDown);
    provider.hubs = provider.hubs.skip(1).toList();
    provider.emit();
    await tester.pumpAndSettle();
    expect(row(tester, 0).focusInside.value, isTrue);
    expect(row(tester, 0).focusedIndex, 0);
    expect(hero(tester).item!.id, 'episode0');
  });

  testWidgets('A19: Back to row start then shell; left escapes first card', (tester) async {
    content();
    await pump(tester);
    await tester.pumpAndSettle();
    for (var i = 0; i < 8; i++) {
      await key(tester, LogicalKeyboardKey.arrowRight);
    }
    expect(row(tester, 0).focusedIndex, 8);
    await key(tester, LogicalKeyboardKey.escape);
    expect(row(tester, 0).focusedIndex, 0);
    expect(row(tester, 0).focusInside.value, isTrue);
    await key(tester, LogicalKeyboardKey.arrowLeft);
    expect(menu.hasFocus, isTrue);
    home.currentState!.focusActiveTabIfReady();
    await tester.pumpAndSettle();
    expect(row(tester, 0).focusedIndex, 0);
  });

  testWidgets('A16: 25-item Continue Watching opens All and restores focus', (tester) async {
    content();
    provider.onDeck = items('episode', 25);
    provider.hasMoreContinueWatching = true;
    await pump(tester);
    await tester.pumpAndSettle();
    for (var i = 0; i < 25; i++) {
      await key(tester, LogicalKeyboardKey.arrowRight);
    }
    expect(find.byType(TvAllCard), findsOneWidget);
    expect(row(tester, 0).focusedIndex, 25);
    await key(tester, LogicalKeyboardKey.enter);
    final detail = tester.widget<HubDetailScreen>(find.byType(HubDetailScreen));
    expect(detail.hub.id, 'continue_watching');
    expect(detail.isInContinueWatching, isTrue);
    expect(detail.usesContinueWatchingAction, isTrue);
    expect(detail.loadItems, isNotNull);
    expect(provider.allLoads, 1);
    Navigator.of(tester.element(find.byType(HubDetailScreen))).pop();
    await tester.pumpAndSettle();
    expect(row(tester, 0).focusedIndex, 25);
    expect(row(tester, 0).focusInside.value, isTrue);
  });
  testWidgets('A16: hub All opens the original unfiltered Plezy hub', (tester) async {
    final original = MediaHub(
      id: 'mixed',
      title: 'Mixed',
      type: 'mixed',
      more: true,
      size: 3,
      items: [
        testMediaItem(id: 'video'),
        testMediaItem(id: 'audio', kind: MediaKind.album),
      ],
    );
    provider.hubs = [original];
    await pump(tester);
    await tester.pumpAndSettle();
    await key(tester, LogicalKeyboardKey.arrowRight);
    expect(find.byType(TvAllCard), findsOneWidget);
    await key(tester, LogicalKeyboardKey.enter);
    final detail = tester.widget<HubDetailScreen>(find.byType(HubDetailScreen));
    expect(detail.hub, same(original));
    expect(detail.hub.items.length, 2);
    expect(detail.loadItems, isNull);
    expect(detail.isInContinueWatching, isFalse);
    expect(detail.usesContinueWatchingAction, isFalse);
  });
  for (final removeRow in [true, false]) {
    for (final hooks in [true, false]) {
      testWidgets('B1: route return restores ${removeRow ? "first row" : "same-row neighbour"} (hooks=$hooks)', (
        tester,
      ) async {
        provider.onDeck = items('episode', removeRow ? 1 : 3);
        provider.hubs = [hub('movies')];
        await pump(tester);
        await tester.pumpAndSettle();
        if (!removeRow) await key(tester, LogicalKeyboardKey.arrowRight);
        final navigator = Navigator.of(home.currentContext!);
        unawaited(navigator.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('details')))));
        if (hooks) home.currentState!.onTabHidden();
        await tester.pumpAndSettle();
        provider.onDeck = removeRow ? [] : [provider.onDeck.first, provider.onDeck.last];
        provider.emit();
        await tester.pumpAndSettle();
        navigator.pop();
        if (hooks) {
          home.currentState!.onTabShown();
          home.currentState!.refresh();
        }
        await tester.pumpAndSettle();
        expect(row(tester, 0).focusInside.value, isTrue);
        expect(hero(tester).item!.id, removeRow ? 'movies0' : 'episode2');
      });
    }
  }

  testWidgets('B1: vanished All row returns to first card even when next row also has All', (tester) async {
    provider.onDeck = items('episode', 1);
    provider.hasMoreContinueWatching = true;
    provider.hubs = [MediaHub(id: 'movies', title: 'Movies', type: 'movie', items: items('movies'), more: true)];
    await pump(tester);
    await tester.pumpAndSettle();
    await key(tester, LogicalKeyboardKey.arrowRight);
    final navigator = Navigator.of(home.currentContext!);
    unawaited(navigator.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('list')))));
    home.currentState!.onTabHidden();
    await tester.pumpAndSettle();
    provider.onDeck = [];
    provider.emit();
    await tester.pumpAndSettle();
    navigator.pop();
    home.currentState!.onTabShown();
    await tester.pumpAndSettle();
    expect(row(tester, 0).focusedIndex, 0);
    expect(row(tester, 0).focusInside.value, isTrue);
    expect(hero(tester).item!.id, 'movies0');
  });

  testWidgets('B2: WatchStateStore updates mounted card and hero without provider list replacement', (tester) async {
    final store = WatchStateStore();
    addTearDown(store.dispose);
    provider.hubs = [hub('movies')];
    await pump(tester, watchState: store);
    await tester.pumpAndSettle();
    final original = provider.hubs.single.items.first;
    WatchStateNotifier().notifyProgress(item: original, viewOffset: 1800000, duration: 3600000);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(tester.widget<TvPoster>(find.byType(TvPoster).first).item.viewOffsetMs, 1800000);
    expect(hero(tester).item!.viewOffsetMs, 1800000);
    WatchStateNotifier().notifyWatched(item: original, isNowWatched: true);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(tester.widget<TvPoster>(find.byType(TvPoster).first).item.isWatched, isTrue);
    expect(hero(tester).item!.isWatched, isTrue);
    expect(provider.hubs.single.items.first, same(original));
  });

  testWidgets('B2: changed details result refreshes its source through provider.updateItem', (tester) async {
    provider.hubs = [hub('movies')];
    final observer = _ChangedDetails();
    await pump(tester, observers: [observer]);
    await tester.pumpAndSettle();
    await key(tester, LogicalKeyboardKey.enter);
    expect(observer.opened, 1);
    expect(provider.updatedItems.map((item) => item.globalKey), [provider.hubs.single.items.first.globalKey]);
    expect(provider.continueRefreshes, 0);
  });

  testWidgets('B3: arriving content fills hero without taking menu focus', (tester) async {
    provider.isLoading = provider.areHubsLoading = true;
    await pump(tester);
    await key(tester, LogicalKeyboardKey.arrowUp);
    content();
    provider.ready();
    await tester.pumpAndSettle();
    expect(menu.hasFocus, isTrue);
    expect(hero(tester).item?.id, 'episode0');
  });

  testWidgets('B3: menu hero follows remembered card, then first card when its row vanishes', (tester) async {
    content();
    await pump(tester);
    await tester.pumpAndSettle();
    for (var i = 0; i < 3; i++) {
      await key(tester, LogicalKeyboardKey.arrowRight);
    }
    await key(tester, LogicalKeyboardKey.arrowDown);
    menu.requestFocus();
    await tester.pumpAndSettle();
    provider.emit();
    await tester.pumpAndSettle();
    expect(hero(tester).item!.id, 'movies0');
    expect(menu.hasFocus, isTrue);
    provider.hubs = provider.hubs.skip(1).toList();
    provider.emit();
    await tester.pumpAndSettle();
    expect(hero(tester).item!.id, 'episode0');
    expect(menu.hasFocus, isTrue);
  });

  testWidgets('B4: error uses helpful copy instead of raw provider exception', (tester) async {
    provider.errorMessage = 'Exception: No servers available';
    await pump(tester);
    await tester.pumpAndSettle();
    expect(find.text(provider.errorMessage!), findsNothing);
    expect(find.text(TvStrings.noConnectionHelp), findsOneWidget);
  });

  testWidgets('B5: failed error retry uses load without manual-refresh snackbar', (tester) async {
    provider.errorMessage = 'Failed';
    await pump(tester);
    await tester.pumpAndSettle();
    provider.loadStartsLoading = true;
    await key(tester, LogicalKeyboardKey.enter);
    expect(provider.loads, 2);
    expect(provider.manualRefreshes, 0);
    provider.errorMessage = 'Failed again';
    provider.ready();
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
    expect(tester.widget<TvButton>(find.byType(TvButton)).focusNode!.hasFocus, isTrue);
  });

  testWidgets('B6: deferred row reveal tolerates removal in the same frame', (tester) async {
    content();
    await pump(tester);
    await tester.pumpAndSettle();
    provider.onDeck = [];
    provider.emit();
    // Focus flush queues a reveal behind the already queued removed-row fallback.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(row(tester, 0).focusInside.value, isTrue);
  });

  for (final error in [true, false]) {
    testWidgets('B7: terminal error=$error clears stale tinted backdrop', (tester) async {
      content();
      await pump(tester);
      await tester.pumpAndSettle();
      expect(find.byType(TvTintedBackground), findsOneWidget);
      provider.onDeck = [];
      provider.hubs = [];
      provider.errorMessage = error ? 'Failed' : null;
      provider.emit();
      await tester.pumpAndSettle();
      expect(find.byType(TvTintedBackground), findsNothing);
      expect(find.byType(TvPlainBackground), findsOneWidget);
    });
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS, TargetPlatform.macOS]) {
    testWidgets('I1: resume refresh branch on $platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      content();
      await pump(tester);
      await tester.pumpAndSettle();
      final before = provider.staleChecks;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(provider.staleChecks, before + 1);
      expect(provider.continueRefreshes, platform == TargetPlatform.macOS ? 0 : 1);
      provider.stale = true;
      home.currentState!.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(provider.continueRefreshes, platform == TargetPlatform.macOS ? 0 : 1);
      home.currentState!.onTabHidden();
      final hidden = provider.staleChecks;
      home.currentState!.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(provider.staleChecks, hidden);
      debugDefaultTargetPlatformOverride = null;
    });
  }
  for (final reduced in [false, true]) {
    for (final scenario in [
      (hadContinue: false, hubIndex: 0, dialog: false),
      (hadContinue: true, hubIndex: 1, dialog: false),
      (hadContinue: false, hubIndex: 2, dialog: true),
      (hadContinue: true, hubIndex: 2, dialog: true),
    ]) {
      testWidgets('return reveals shifted rail: $scenario reduced=$reduced', (tester) async {
        provider.hubs = [hub('zero'), hub('one'), hub('two'), hub('three')];
        provider.onDeck = scenario.hadContinue ? items('episode', 1) : [];
        await pump(tester, reduced: reduced);
        await tester.pumpAndSettle();
        final beforeIndex = scenario.hubIndex + (scenario.hadContinue ? 1 : 0);
        for (var i = 0; i < beforeIndex; i++) {
          await key(tester, LogicalKeyboardKey.arrowDown);
        }
        final target = hero(tester).item!.globalKey;
        final navigator = Navigator.of(home.currentContext!);
        if (scenario.dialog) {
          unawaited(
            showDialog<void>(
              context: home.currentContext!,
              builder: (_) => const AlertDialog(content: Text('dialog')),
            ),
          );
        } else {
          unawaited(navigator.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('details')))));
        }
        await tester.pumpAndSettle();
        provider.onDeck = scenario.hadContinue ? [] : items('episode', 1);
        provider.emit();
        await tester.pumpAndSettle();
        navigator.pop();
        await tester.pumpAndSettle();
        final afterIndex = scenario.hubIndex + (scenario.hadContinue ? 0 : 1);
        final expectedHeight = afterIndex > 1 ? 420.0 : 600.0;
        expect(row(tester, afterIndex).focusInside.value, isTrue);
        expect(hero(tester).item!.globalKey, target);
        expect(hero(tester).compact, afterIndex > 1);
        expect(tester.getTopLeft(find.byType(TvHorizontalRow).at(afterIndex)).dy, expectedHeight);
      });
    }
  }
}
