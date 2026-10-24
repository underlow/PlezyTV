import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/library_first_character.dart';
import 'package:plezy/media/ids.dart';
import 'package:plezy/media/library_change_event.dart';
import 'package:plezy/utils/library_content_notifier.dart';
import 'package:plezy/media/library_query.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_hub.dart';
import 'package:plezy/media/media_playlist.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_library.dart';
import 'package:plezy/navigation/main_screen_scope.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_alpha_column.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_button.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_tabs.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_horizontal_row.dart';
import 'package:plezy/plezytv/tv_ui/tv_tokens.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_cards.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_paged_grid.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_skeletons.dart';
import 'package:plezy/plezytv/tv_ui/library/tv_library_controller.dart';
import 'package:plezy/plezytv/tv_ui/library/tv_library_preferences.dart';
import 'package:plezy/plezytv/tv_ui/library/tv_library_screen.dart';
import 'package:plezy/plezytv/tv_ui/tv_strings.dart';
import 'package:plezy/screens/libraries/alpha_jump_helper.dart';
import 'package:plezy/screens/libraries/library_alpha_bar_strategy.dart';
import 'package:plezy/utils/deletion_notifier.dart';
import 'package:plezy/utils/watch_state_notifier.dart';

import 'package:provider/provider.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/models/download_models.dart';
import 'package:plezy/providers/download_provider.dart';
import 'package:plezy/providers/multi_server_provider.dart';
import 'package:plezy/providers/offline_mode_provider.dart';
import 'package:plezy/providers/watch_state_store.dart';
import 'package:plezy/profiles/active_profile_provider.dart';
import 'package:plezy/media/media_server_client.dart';
import 'package:plezy/database/app_database.dart';
import '../../../test_helpers/multi_server_fixtures.dart';
import '../../../test_helpers/profile_stack.dart';
import '../tv_theme_test_helper.dart';
import 'fake_media_server_client.dart';

const library = MediaLibrary(
  id: '1',
  backend: MediaBackend.jellyfin,
  title: 'Movies',
  kind: MediaKind.movie,
  serverId: 'server',
);
MediaItem movie(int index) => MediaItem(
  id: '$index',
  backend: MediaBackend.jellyfin,
  title: 'Movie $index',
  kind: MediaKind.movie,
  serverId: 'server',
);

/// Real Plex visibility/jump rules with fixture buckets, without a PlexClient.
class PlexLetters extends PlexAlphaBarStrategy {
  PlexLetters() : super(plexClientProvider: () => throw UnimplementedError(), libraryKey: '1', isShared: false);
  @override
  Future<({List<LibraryFirstCharacter> chars, AlphaJumpHelper helper})> loadCharacters({
    required Map<String, dynamic> filters,
    required int? typeId,
    required bool descending,
  }) async {
    final chars = [
      for (final letter in ['#', 'A', 'B', 'C', 'D', 'M']) LibraryFirstCharacter(key: letter, title: letter, size: 60),
    ];
    return (chars: chars, helper: AlphaJumpHelper(chars, descending: descending));
  }
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await settle(tester);
}

String? get focus => FocusManager.instance.primaryFocus?.debugLabel;

class ChangedDetails extends NavigatorObserver {
  int opened = 0;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute == null) return;
    opened++;
    scheduleMicrotask(() => navigator!.removeRoute(route, true));
  }
}

class NoDownloads extends ChangeNotifier implements DownloadProvider {
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

void main() {
  TvLibraryController make(
    FakeMediaServerClient client, {
    TvLibraryPreferences? saved,
    LibraryAlphaBarStrategy? strategy,
    MediaLibrary lib = library,
  }) {
    final controller = TvLibraryController(
      library: lib,
      client: client,
      store: TvMemoryLibraryPreferences(seed: saved),
      alphaStrategy: strategy,
    );
    addTearDown(controller.dispose);
    return controller;
  }

  Future<GlobalKey<TvLibraryScreenState>> mount(
    WidgetTester tester,
    TvLibraryController controller, {
    Future<void> Function(BuildContext, MediaItem)? open,
    VoidCallback? sidebar,
  }) async {
    final key = GlobalKey<TvLibraryScreenState>();
    await pumpTvWidget(
      tester,
      MainScreenFocusScope(
        focusSidebar: sidebar ?? () {},
        sideNavigationWidth: 0,
        child: TvLibraryScreen(key: key, controller: controller, openItem: open),
      ),
    );
    return key;
  }

  for (final shellInset in [0.0, TvTokens.size.sidebar.collapsedW.toDouble()]) {
    testWidgets('library edges align at x=200 with shell inset $shellInset', (tester) async {
      final client = FakeMediaServerClient()..items = [movie(0)];
      client.hubs = [
        MediaHub(id: 'a', title: 'First row', type: 'movie', items: [movie(0)]),
        MediaHub(id: 'b', title: 'Second row', type: 'movie', items: [movie(1)]),
      ];
      final c = make(client);
      await pumpTvWidget(
        tester,
        MainScreenFocusScope(
          focusSidebar: () {},
          sideNavigationWidth: shellInset,
          foregroundLeft: shellInset,
          child: Padding(
            padding: EdgeInsets.only(left: shellInset),
            child: TvLibraryScreen(controller: c),
          ),
        ),
      );
      await settle(tester);
      expect(tester.getTopLeft(find.text('Movies')).dx, 200);
      expect(tester.getTopLeft(find.byType(TvTabs)).dx, 200);
      expect(tester.getTopLeft(find.byType(TvPoster).first).dx, 200);
      await c.select(tab: 'recommended');
      await settle(tester);
      expect(tester.getTopLeft(find.text('First row')).dx, 200);
      expect(tester.getTopLeft(find.text('Second row')).dx, 200);
      expect(tester.getTopLeft(find.byType(TvPoster).first).dx, 200);
      final rows = find.byType(TvHorizontalRow);
      expect(tester.getTopLeft(rows.at(1)).dy - tester.getBottomLeft(rows.at(0)).dy, TvTokens.space.rowGap);
    });
  }

  testWidgets('A21: real header immediately; skeleton only after 300ms; data focuses first card', (tester) async {
    final page = Completer<LibraryPage<MediaItem>>();
    final client = FakeMediaServerClient()..onPage = (_) => page.future;
    final c = make(client);
    await mount(tester, c);
    await tester.pump(const Duration(milliseconds: 299));
    expect(find.text('Movies'), findsOneWidget);
    expect(find.byType(TvPosterSkeleton), findsNothing);
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.byType(TvPosterSkeleton), findsNWidgets(12));
    expect(focus, isNot(startsWith('TV grid')));
    page.complete(LibraryPage(items: [movie(0)], totalCount: 1));
    await settle(tester);
    expect(find.byType(TvPosterSkeleton), findsNothing);
    expect(focus, 'TV grid 0');
  });

  for (final moveToHeader in [false, true]) {
    testWidgets('V5 saved Recommended first entry, header=$moveToHeader', (tester) async {
      final gate = Completer<List<MediaHub>>();
      final client = FakeMediaServerClient()..hubsPending = gate.future;
      final c = TvLibraryController(
        library: library,
        client: client,
        store: TvMemoryLibraryPreferences(seed: TvLibraryPreferences(tab: 'recommended')),
      );
      addTearDown(c.dispose);
      await mount(tester, c);
      await settle(tester);
      expect(find.byType(TvPosterSkeleton), findsNWidgets(12));
      if (moveToHeader) await press(tester, LogicalKeyboardKey.arrowUp);
      final owner = FocusManager.instance.primaryFocus;
      gate.complete([
        MediaHub(id: 'h', title: 'Hub', type: 'movie', items: [movie(0)]),
      ]);
      await settle(tester);
      if (moveToHeader) {
        expect(FocusManager.instance.primaryFocus, same(owner));
        expect(focus, 'Library sort');
      } else {
        expect(FocusManager.instance.primaryFocus, isNot(same(owner)));
        expect(find.byType(TvPoster), findsOneWidget);
      }
    });
  }

  testWidgets('V5 slow Recommended tab load keeps selected tab focus', (tester) async {
    final gate = Completer<List<MediaHub>>();
    final client = FakeMediaServerClient()
      ..items = [movie(0)]
      ..hubsPending = gate.future;
    final c = make(client);
    await mount(tester, c);
    await settle(tester);
    await press(tester, LogicalKeyboardKey.arrowUp);
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(c.preferences.tab, 'recommended');
    await tester.pump(const Duration(milliseconds: 301));
    final owner = FocusManager.instance.primaryFocus;
    expect(find.byType(TvPosterSkeleton), findsNWidgets(12));
    gate.complete([
      MediaHub(id: 'h', title: 'Hub', type: 'movie', items: [movie(1)]),
    ]);
    await settle(tester);
    expect(FocusManager.instance.primaryFocus, same(owner));
  });

  testWidgets('V5 loaded tab switches retain tab focus in both directions', (tester) async {
    final client = FakeMediaServerClient()
      ..items = [movie(0)]
      ..collections = [movie(1)]
      ..hubs = [
        MediaHub(id: 'h', title: 'Hub', type: 'movie', items: [movie(2)]),
      ]
      ..playlists = [
        const MediaPlaylist(id: 'p', backend: MediaBackend.jellyfin, title: 'Playlist', playlistType: 'video'),
      ];
    final c = make(client);
    await mount(tester, c);
    await settle(tester);
    expect(focus, 'TV grid 0');
    await press(tester, LogicalKeyboardKey.arrowUp);
    for (final key in [
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowLeft,
    ]) {
      await press(tester, key);
      await settle(tester);
      expect(focus, isNot(startsWith('TV grid')));
      expect(FocusManager.instance.primaryFocus!.ancestors.any((n) => n.debugLabel == 'Library tabs'), isTrue);
    }
  });

  testWidgets('fast data skips skeleton; moving to header during loading retains header focus', (tester) async {
    final page = Completer<LibraryPage<MediaItem>>();
    final c = make(FakeMediaServerClient()..onPage = (_) => page.future);
    await mount(tester, c);
    await tester.pump();
    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(focus, 'Library sort');
    page.complete(LibraryPage(items: [movie(0)], totalCount: 1));
    await settle(tester);
    expect(focus, 'Library sort');
    expect(find.byType(TvPosterSkeleton), findsNothing);
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(focus, 'TV grid 0');
  });

  testWidgets('loading completion preserves sidebar focus', (tester) async {
    final page = Completer<LibraryPage<MediaItem>>();
    final c = make(FakeMediaServerClient()..onPage = (_) => page.future);
    final menu = FocusNode(debugLabel: 'Test sidebar');
    addTearDown(menu.dispose);
    await pumpTvWidget(
      tester,
      MainScreenFocusScope(
        focusSidebar: menu.requestFocus,
        sideNavigationWidth: 0,
        child: Stack(
          children: [
            Focus(focusNode: menu, child: const SizedBox()),
            TvLibraryScreen(controller: c),
          ],
        ),
      ),
    );
    await settle(tester);
    await press(tester, LogicalKeyboardKey.arrowUp);
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(focus, 'Test sidebar');
    page.complete(LibraryPage(items: [movie(0)], totalCount: 1));
    await settle(tester);
    expect(focus, 'Test sidebar');
  });

  testWidgets('tabs switch in both directions; only left from first exits to sidebar', (tester) async {
    final c = make(FakeMediaServerClient()..items = List.generate(20, movie));
    var sidebar = 0;
    await mount(tester, c, sidebar: () => sidebar++);
    await settle(tester);
    await press(tester, LogicalKeyboardKey.arrowUp);
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(c.preferences.tab, 'collections');
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(c.preferences.tab, 'browse');
    expect(sidebar, 0);
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(c.preferences.tab, 'recommended');
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(sidebar, 1);
  });

  testWidgets('A7: server total and distinct filter fields; selection returns down to first', (tester) async {
    final client = FakeMediaServerClient()..items = List.generate(300, movie);
    final c = make(client);
    await mount(tester, c);
    await settle(tester);
    expect(find.text('Title · 300'), findsOneWidget);
    client.onPage = (_) async => LibraryPage(items: [movie(2)], totalCount: 1);
    await c.select(
      filters: const [
        LibraryFilter(field: 'genre', values: ['a', 'b']),
      ],
    );
    await settle(tester);
    expect(find.text('Filters · 1'), findsOneWidget);
    expect(find.text('Title · 1'), findsOneWidget);
  });

  testWidgets('A10/A11: held down traverses 300+ slots; Back goes to start then bubbles', (tester) async {
    final client = FakeMediaServerClient()..items = List.generate(360, movie);
    final delayed = Completer<LibraryPage<MediaItem>>();
    client.onPage = (q) async => q.offset == 60
        ? delayed.future
        : LibraryPage(items: client.items.skip(q.offset).take(q.limit).toList(), totalCount: 360);
    final c = make(client);
    var sidebar = 0;
    await mount(tester, c, sidebar: () => sidebar++);
    await settle(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.pump();
    expect(focus, 'TV grid 6');
    for (var i = 0; i < 25; i++) {
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.pump();
      final expected = (i + 2) * 6;
      expect(focus, 'TV grid $expected');
      expect(c.focusedIndex, expected);
      if (expected == 78) {
        expect(c.source[expected], isNull);
        final node = FocusManager.instance.primaryFocus;
        delayed.complete(LibraryPage(items: client.items.skip(60).take(60).toList(), totalCount: 360));
        await settle(tester);
        expect(c.source[expected]?.id, '$expected');
        expect(FocusManager.instance.primaryFocus, same(node));
        expect(c.focusedIndex, expected);
      }
    }
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
    await settle(tester);
    expect(c.focusedIndex, 156);
    expect(client.queries.length, lessThan(10));
    await press(tester, LogicalKeyboardKey.escape);
    expect(focus, 'TV grid 0');
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(sidebar, 1);
    await press(tester, LogicalKeyboardKey.arrowUp);
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(focus, 'TV grid 0');
  });

  testWidgets('second Back at grid start is delegated to the shell', (tester) async {
    final c = make(FakeMediaServerClient()..items = List.generate(360, movie));
    var backs = 0;
    await pumpTvWidget(
      tester,
      Focus(
        canRequestFocus: false,
        onKeyEvent: (_, event) {
          if (event.logicalKey != LogicalKeyboardKey.escape) return KeyEventResult.ignored;
          if (event is KeyDownEvent) backs++;
          return KeyEventResult.handled;
        },
        child: TvLibraryScreen(controller: c),
      ),
    );
    await settle(tester);
    unawaited(tester.state<TvPagedGridState<MediaItem>>(find.byType(TvPagedGrid<MediaItem>)).jumpTo(120));
    await settle(tester);
    await press(tester, LogicalKeyboardKey.escape);
    expect(focus, 'TV grid 0');
    expect(backs, 0);
    await press(tester, LogicalKeyboardKey.escape);
    expect(backs, 1);
  });

  testWidgets('A12: item route return restores same slot and scroll', (tester) async {
    final c = make(FakeMediaServerClient()..items = List.generate(360, movie));
    String? opened;
    await mount(
      tester,
      c,
      open: (context, item) async {
        opened = item.id;
        await Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('Item route'))));
      },
    );
    await settle(tester);
    final grid = tester.state<TvPagedGridState<MediaItem>>(find.byType(TvPagedGrid<MediaItem>));
    unawaited(grid.jumpTo(150));
    await settle(tester);
    final top = tester.getTopLeft(find.text('Movie 150')).dy;
    await press(tester, LogicalKeyboardKey.select);
    expect(opened, '150');
    expect(find.text('Item route'), findsOneWidget);
    Navigator.of(tester.element(find.text('Item route'))).pop();
    await settle(tester);
    expect(focus, 'TV grid 150');
    expect(tester.getTopLeft(find.text('Movie 150')).dy, top);
  });

  testWidgets('OK uses actual navigateToMediaItem details route and refresh result', (tester) async {
    final client = FakeMediaServerClient()..items = [movie(0)];
    final c = make(client);
    final observer = ChangedDetails();
    await pumpTvWidget(tester, TvLibraryScreen(controller: c), navigatorObservers: [observer]);
    await settle(tester);
    final before = client.queries.length;
    await press(tester, LogicalKeyboardKey.select);
    expect(observer.opened, 1);
    expect(client.queries.length, greaterThan(before));
    expect(focus, 'TV grid 0');
  });

  testWidgets('page failure leaves focusable slots; returning to failed slot retries', (tester) async {
    final client = FakeMediaServerClient()..items = List.generate(360, movie);
    var fail = true;
    client.onPage = (query) async {
      if (query.offset == 60 && fail) throw StateError('page offline');
      return LibraryPage(items: client.items.skip(query.offset).take(query.limit).toList(), totalCount: 360);
    };
    final c = make(client);
    await mount(tester, c);
    await settle(tester);
    final grid = tester.state<TvPagedGridState<MediaItem>>(find.byType(TvPagedGrid<MediaItem>));
    unawaited(grid.jumpTo(60, waitForLoad: false));
    await settle(tester);
    expect(focus, 'TV grid 60');
    expect(c.source[60], isNull);
    final before = client.queries.where((q) => q.offset == 60).length;
    await press(tester, LogicalKeyboardKey.arrowUp);
    fail = false;
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(focus, 'TV grid 60');
    expect(c.source[60], isNotNull);
    expect(client.queries.where((q) => q.offset == 60).length, greaterThan(before));
  });

  testWidgets('watch update rebuilds own page; adjacent page card instance stays stable', (tester) async {
    final client = FakeMediaServerClient()..items = List.generate(360, movie);
    final c = make(client);
    await mount(tester, c);
    await settle(tester);
    final grid = tester.state<TvPagedGridState<MediaItem>>(find.byType(TvPagedGrid<MediaItem>));
    unawaited(grid.jumpTo(54));
    await settle(tester);
    final old = tester.widget<TvPoster>(find.byWidgetPredicate((w) => w is TvPoster && w.item.id == '54'));
    client.onItem = (_) async => movie(60).copyWith(viewCount: 1);
    WatchStateNotifier().notify(
      WatchStateEvent(
        itemId: '60',
        serverId: ServerId('server'),
        parentChain: const [],
        changeType: WatchStateChangeType.watched,
      ),
    );
    await settle(tester);
    final unchanged = tester.widget<TvPoster>(find.byWidgetPredicate((w) => w is TvPoster && w.item.id == '54'));
    expect(identical(old, unchanged), isTrue);
    expect(c.source[60]!.isWatched, isTrue);
  });

  testWidgets('refresh preserves focused identity when it moves nearby', (tester) async {
    final client = FakeMediaServerClient()..items = List.generate(100, movie);
    final c = make(client);
    final key = await mount(tester, c);
    await settle(tester);
    unawaited(tester.state<TvPagedGridState<MediaItem>>(find.byType(TvPagedGrid<MediaItem>)).jumpTo(8));
    await settle(tester);
    client.items.insert(0, movie(999));
    key.currentState!.refresh();
    await settle(tester);
    expect(c.focusedIndex, 9);
    expect(focus, 'TV grid 9');
    expect(c.source[9]!.id, '8');
  });

  for (final index in [4, 5]) {
    testWidgets('deletion on item route returns to loaded neighbour at $index', (tester) async {
      final client = FakeMediaServerClient()..items = List.generate(6, movie);
      final c = make(client);
      BuildContext? detail;
      await mount(
        tester,
        c,
        open: (context, item) async {
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (context) {
                detail = context;
                return const Scaffold(body: Text('Details'));
              },
            ),
          );
        },
      );
      await settle(tester);
      unawaited(tester.state<TvPagedGridState<MediaItem>>(find.byType(TvPagedGrid<MediaItem>)).jumpTo(index));
      await settle(tester);
      await press(tester, LogicalKeyboardKey.select);
      final removed = client.items.removeAt(index);
      DeletionNotifier().notifyDeletedItem(item: removed);
      await settle(tester);
      Navigator.of(detail!).pop();
      await settle(tester);
      final target = index == 5 ? 4 : index;
      expect(focus, 'TV grid $target');
      expect(c.source[target], isNotNull);
      expect(c.source[target]!.id, index == 5 ? '4' : '5');
    });
  }

  testWidgets('A14/A15: Plex letters freeze highlight; sparse jump and refresh barrier retain target', (tester) async {
    const plex = MediaLibrary(
      id: '1',
      backend: MediaBackend.plex,
      title: 'Movies',
      kind: MediaKind.movie,
      serverId: 'server',
    );
    final client = FakeMediaServerClient(backend: MediaBackend.plex)..items = List.generate(360, movie);
    final c = make(client, lib: plex, strategy: PlexLetters());
    final key = await mount(tester, c);
    await settle(tester);
    unawaited(tester.state<TvPagedGridState<MediaItem>>(find.byType(TvPagedGrid<MediaItem>)).jumpTo(5));
    await settle(tester);
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(focus, 'TV letter #');
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(c.focusedIndex, 5);
    expect(tester.widget<TvAlphaColumn>(find.byType(TvAlphaColumn)).highlighted, '#');
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(focus, 'TV grid 5');
    await press(tester, LogicalKeyboardKey.arrowRight);
    for (var i = 0; i < 5; i++) {
      await press(tester, LogicalKeyboardKey.arrowDown);
    }
    final page = Completer<LibraryPage<MediaItem>>();
    client.onPage = (query) => query.offset == 300
        ? page.future
        : Future.value(LibraryPage(items: client.items.skip(query.offset).take(query.limit).toList(), totalCount: 360));
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    key.currentState!.refresh();
    await tester.pump();
    final before = client.queries.length;
    page.complete(LibraryPage(items: client.items.skip(300).toList(), totalCount: 360));
    await settle(tester);
    expect(focus, 'TV grid 300');
    expect(c.focusedIndex, 300);
    expect(client.queries.length, greaterThan(before));
    await c.select(sort: client.sorts.last);
    await settle(tester);
    expect(find.byType(TvAlphaColumn), findsNothing);
  });

  for (final backend in [MediaBackend.jellyfin, MediaBackend.emby]) {
    testWidgets('$backend: letter changes prefix and server count', (tester) async {
      final client = FakeMediaServerClient(backend: backend)..items = List.generate(100, movie);
      final c = make(
        client,
        lib: MediaLibrary(id: '1', backend: backend, title: 'Movies', kind: MediaKind.movie, serverId: 'server'),
      );
      await mount(tester, c);
      await settle(tester);
      unawaited(tester.state<TvPagedGridState<MediaItem>>(find.byType(TvPagedGrid<MediaItem>)).jumpTo(5));
      await settle(tester);
      await press(tester, LogicalKeyboardKey.arrowRight);
      await press(tester, LogicalKeyboardKey.arrowDown);
      client.onPage = (_) async => LibraryPage(items: [movie(40)], totalCount: 1);
      await press(tester, LogicalKeyboardKey.select);
      expect(c.alphaPrefix, 'A');
      expect(find.text('Title · 1'), findsOneWidget);
      expect(focus, 'TV grid 0');
      expect(client.queries.last.nameStartsWith, 'A');
    });
  }

  testWidgets('A22: filtered empty reset button clears clauses and returns content', (tester) async {
    final client = FakeMediaServerClient();
    final c = make(
      client,
      saved: TvLibraryPreferences(
        filters: const [
          LibraryFilter(field: 'genre', values: ['x']),
        ],
      ),
    );
    await mount(tester, c);
    await settle(tester);
    expect(find.text(TvStrings.libraryNoMatches), findsOneWidget);
    expect(focus, 'Library state action');
    client.items = [movie(0)];
    await press(tester, LogicalKeyboardKey.select);
    expect(c.preferences.filters, isEmpty);
    expect(focus, 'TV grid 0');
  });

  testWidgets('A23: empty refresh fetches data without scan', (tester) async {
    final client = FakeMediaServerClient();
    final c = make(client);
    await mount(tester, c);
    await settle(tester);
    expect(find.text(TvStrings.libraryEmpty('Movies')), findsOneWidget);
    expect(focus, 'Library state action');
    client.items = [movie(0)];
    await press(tester, LogicalKeyboardKey.select);
    expect(client.calls.where((call) => call.startsWith('page:')).length, 2);
    expect(focus, 'TV grid 0');
  });

  testWidgets('A24: first page error retry disabled while connecting, sidebar accessible', (tester) async {
    final client = FakeMediaServerClient()..onPage = (_) async => throw StateError('offline');
    final c = make(client);
    var menu = 0;
    await mount(tester, c, sidebar: () => menu++);
    await settle(tester);
    expect(find.text(TvStrings.noConnection), findsOneWidget);
    expect(focus, 'Library state action');
    final page = Completer<LibraryPage<MediaItem>>();
    client.onPage = (_) => page.future;
    await press(tester, LogicalKeyboardKey.select);
    expect(find.text(TvStrings.connecting), findsOneWidget);
    expect(
      tester.widget<TvButton>(find.byWidgetPredicate((w) => w is TvButton && w.label == TvStrings.connecting)).disabled,
      isTrue,
    );
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(menu, 1);
    page.complete(LibraryPage(items: [movie(0)], totalCount: 1));
    await settle(tester);
    expect(find.text(TvStrings.noConnection), findsNothing);
  });

  testWidgets('other tabs use Plezy labels and keep focus on tabs; episodes use four wide cells', (tester) async {
    final c = make(
      FakeMediaServerClient()..items = List.generate(10, movie),
      lib: const MediaLibrary(
        id: '1',
        backend: MediaBackend.jellyfin,
        title: 'Shows',
        kind: MediaKind.show,
        serverId: 'server',
      ),
    );
    await mount(tester, c);
    await settle(tester);
    await c.select(tab: 'collections');
    await settle(tester);
    expect(find.text('No collections in this library'), findsOneWidget);
    expect(focus, isNot(startsWith('TV grid')));
    await c.select(tab: 'browse', grouping: 'episodes');
    await settle(tester);
    expect(tester.widget<TvPagedGrid<MediaItem>>(find.byType(TvPagedGrid<MediaItem>)).columns, 4);
    expect(find.byType(TvEpisode), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  for (final longOk in [true, false]) {
    testWidgets('A13: ${longOk ? "long OK" : "Menu"} opens Plezy menu and mark watched updates card', (tester) async {
      final stack = await ProfileStack.create(withStorage: false);
      addTearDown(stack.dispose);
      final client = FakeMediaServerClient()..items = [movie(0)];
      final servers = testMultiServer(clients: [client]);
      final offline = OfflineModeProvider(servers.manager);
      final downloads = NoDownloads();
      final watch = WatchStateStore();
      addTearDown(offline.dispose);
      addTearDown(downloads.dispose);
      addTearDown(watch.dispose);
      final c = make(client);
      await pumpTvWidget(
        tester,
        MultiProvider(
          providers: [
            ChangeNotifierProvider<MultiServerProvider>.value(value: servers.provider),
            ChangeNotifierProvider<OfflineModeProvider>.value(value: offline),
            ChangeNotifierProvider<DownloadProvider>.value(value: downloads),
            ChangeNotifierProvider<WatchStateStore>.value(value: watch),
            ChangeNotifierProvider<ActiveProfileProvider>.value(value: stack.active),
          ],
          child: Scaffold(body: TvLibraryScreen(controller: c)),
        ),
      );
      await settle(tester);
      if (longOk) {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
        await tester.pump(const Duration(seconds: 1));
        await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
      } else {
        await press(tester, LogicalKeyboardKey.contextMenu);
      }
      expect(find.text(t.mediaMenu.markAsWatched), findsOneWidget);
      await tester.tap(find.text(t.mediaMenu.markAsWatched));
      await tester.pumpAndSettle();
      expect(client.calls, contains('watched:0'));
      expect(tester.widget<TvPoster>(find.byType(TvPoster)).item.isWatched, isTrue);
      expect(focus, 'TV grid 0');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('A13: watch event replaces mounted card without losing focus', (tester) async {
    final client = FakeMediaServerClient()..items = [movie(0)];
    final c = make(client);
    await mount(tester, c);
    await settle(tester);
    client.onItem = (_) async => movie(0).copyWith(viewCount: 1);
    WatchStateNotifier().notify(
      WatchStateEvent(
        itemId: '0',
        serverId: ServerId('server'),
        parentChain: const [],
        changeType: WatchStateChangeType.watched,
      ),
    );
    await settle(tester);
    expect(tester.widget<TvPoster>(find.byType(TvPoster)).item.isWatched, isTrue);
    expect(focus, 'TV grid 0');
  });
  for (final fail in [false, true]) {
    testWidgets('Plex first page ${fail ? 'error' : 'focus'} does not wait for alphabet', (tester) async {
      final alphabet = Completer<List<LibraryFirstCharacter>>();
      final client = FakePlexLibraryClient()
        ..items = List.generate(120, movie)
        ..onCharacters = () => alphabet.future;
      if (fail) client.onPage = (_) async => throw StateError('offline');
      final c = make(
        client,
        lib: const MediaLibrary(
          id: '1',
          backend: MediaBackend.plex,
          title: 'Movies',
          kind: MediaKind.movie,
          serverId: 'server',
        ),
      );
      await mount(tester, c);
      await settle(tester);
      expect(client.characterCalls, 1);
      expect(c.loading, isFalse);
      expect(focus, fail ? 'Library state action' : 'TV grid 0');
      if (fail) expect(find.text(TvStrings.retry), findsOneWidget);
      await c.select(sort: client.sorts.last);
      await settle(tester);
      expect(client.characterCalls, 1, reason: 'hidden sort must not request buckets');
      alphabet.complete([LibraryFirstCharacter(key: 'A', title: 'A', size: 120)]);
      await settle(tester);
      expect(c.characters, isEmpty, reason: 'late old alphabet must be discarded');
    });
  }
  for (final selection in [false, true]) {
    testWidgets('event during ${selection ? 'selection' : 'initialize'} still completes L17 focus', (tester) async {
      final gate = Completer<LibraryPage<MediaItem>>();
      final client = FakeMediaServerClient()..items = [movie(0)];
      final c = make(client);
      if (selection) await c.initialize();
      client.onPage = (_) => gate.future;
      if (selection) unawaited(c.select(descending: true));
      await mount(tester, c);
      await settle(tester);
      LibraryContentNotifier().notifyChanged(
        LibraryChangeEvent(serverId: ServerId('server'), libraryIds: {'1'}, itemsUpdated: true),
      );
      await settle(tester);
      client.onPage = null;
      gate.complete(LibraryPage(items: [movie(0)], totalCount: 1));
      await settle(tester);
      expect(c.loading, isFalse);
      expect(focus, 'TV grid 0');
    });
  }
}
