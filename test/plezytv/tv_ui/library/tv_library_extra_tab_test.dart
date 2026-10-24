import 'dart:async';
import 'package:plezy/media/ids.dart';
import 'package:plezy/utils/deletion_notifier.dart';
import 'package:plezy/utils/watch_state_notifier.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_cards.dart';
import 'package:flutter/material.dart';
import 'package:plezy/plezytv/tv_ui/library/tv_library_controller.dart';
import 'package:plezy/plezytv/tv_ui/library/tv_library_preferences.dart';
import 'package:plezy/screens/media_detail_screen.dart';
import 'package:plezy/screens/collection_detail_screen.dart';
import 'package:plezy/screens/playlist/playlist_detail_screen.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_hub.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_playlist.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_alpha_column.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_all_card.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_horizontal_row.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_paged_grid.dart';
import 'package:plezy/plezytv/tv_ui/library/tv_library_extra_tab.dart';
import 'package:plezy/plezytv/tv_ui/library/tv_library_screen.dart';
import 'package:plezy/screens/libraries/libraries_screen.dart';
import '../tv_theme_test_helper.dart';
import 'fake_media_server_client.dart';
import 'tv_library_screen_test.dart' as fixtures;

// Inspect the real navigation destination without booting unrelated detail services.
class DestinationObserver extends NavigatorObserver {
  Widget? destination;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute == null || route is! MaterialPageRoute) return;
    destination = route.builder(navigator!.context);
    scheduleMicrotask(() => navigator!.removeRoute(route));
  }
}

void main() {
  TvLibraryController make(FakeMediaServerClient client) {
    final c = TvLibraryController(library: fixtures.library, client: client, store: TvMemoryLibraryPreferences());
    addTearDown(c.dispose);
    return c;
  }

  testWidgets('collection deletion reconciles and keeps neighboring focus', (tester) async {
    final client = FakeMediaServerClient()..collections = List.generate(3, fixtures.movie);
    final c = make(client);
    await pumpTvWidget(
      tester,
      Scaffold(
        body: TvLibraryExtraTab(
          controller: c,
          tab: LibraryTabType.collections,
          ownsTabFocus: () => true,
          onUp: () {},
          onLeft: () {},
        ),
      ),
    );
    await fixtures.settle(tester);
    await fixtures.press(tester, LogicalKeyboardKey.arrowRight);
    client.collections.removeAt(1);
    DeletionNotifier().notify(
      DeletionEvent(itemId: '1', serverId: ServerId('server'), parentChain: [], mediaType: 'collection'),
    );
    await fixtures.settle(tester);
    final grid = tester.state<TvPagedGridState<Object>>(find.byType(TvPagedGrid<Object>));
    expect(grid.focusedIndex, 1);
    expect(find.text('Movie 1'), findsNothing);
    expect(find.text('Movie 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('recommended watch event updates card and retains focus', (tester) async {
    final client = FakeMediaServerClient()
      ..hubs = [
        MediaHub(id: 'h', title: 'Hub', type: 'movie', items: [fixtures.movie(1)]),
      ];
    final c = make(client);
    await pumpTvWidget(
      tester,
      Scaffold(
        body: TvLibraryExtraTab(
          controller: c,
          tab: LibraryTabType.recommended,
          ownsTabFocus: () => true,
          onUp: () {},
          onLeft: () {},
        ),
      ),
    );
    await fixtures.settle(tester);
    final focus = FocusManager.instance.primaryFocus;
    client.hubs = [
      client.hubs.single.copyWith(items: [fixtures.movie(1).copyWith(viewCount: 1)]),
    ];
    WatchStateNotifier().notify(
      WatchStateEvent(
        itemId: '1',
        serverId: ServerId('server'),
        parentChain: [],
        changeType: WatchStateChangeType.watched,
      ),
    );
    await fixtures.settle(tester);
    expect(tester.widget<TvPoster>(find.byType(TvPoster)).item.isWatched, isTrue);
    expect(FocusManager.instance.primaryFocus, same(focus));
  });

  testWidgets('host switches all three tabs to their own queries', (tester) async {
    final client = FakeMediaServerClient();
    final item = fixtures.movie(1);
    client.hubs = [
      MediaHub(id: 'h', title: 'Library hub', type: 'movie', items: [item]),
    ];
    client.collections = [item];
    client.playlists = [
      const MediaPlaylist(id: 'p', backend: MediaBackend.jellyfin, title: 'Playlist', playlistType: 'video'),
    ];
    final c = make(client);
    await pumpTvWidget(tester, Scaffold(body: TvLibraryScreen(controller: c)));
    await fixtures.settle(tester);
    for (final name in ['recommended', 'collections', 'playlists', 'recommended']) {
      await c.select(tab: name);
      await fixtures.settle(tester);
      expect(
        find.text(
          name == 'recommended'
              ? 'Library hub'
              : name == 'collections'
              ? 'Movie 1'
              : 'Playlist',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('collections request the target page and Back returns to start', (tester) async {
    final client = FakeMediaServerClient()..collections = List.generate(100, fixtures.movie);
    final c = make(client);
    await pumpTvWidget(
      tester,
      Scaffold(
        body: TvLibraryExtraTab(
          controller: c,
          tab: LibraryTabType.collections,
          ownsTabFocus: () => true,
          onUp: () {},
          onLeft: () {},
        ),
      ),
    );
    await fixtures.settle(tester);
    final grid = tester.state<TvPagedGridState<Object>>(find.byType(TvPagedGrid<Object>));
    await grid.jumpTo(90);
    await fixtures.settle(tester);
    expect(client.calls, contains('collections:1:72:36'));
    expect(grid.focusedIndex, 90);
    await fixtures.press(tester, LogicalKeyboardKey.escape);
    await fixtures.settle(tester);
    expect(grid.focusedIndex, 0);
  });

  testWidgets('recommended remembers each row and opens All with Plezy hub screen', (tester) async {
    final client = FakeMediaServerClient()
      ..hubs = [
        for (var i = 0; i < 3; i++)
          MediaHub(id: '$i', title: 'Hub $i', type: 'movie', items: [fixtures.movie(i)], more: true),
      ];
    final c = make(client);
    final observer = DestinationObserver();
    var up = false;
    await pumpTvWidget(
      tester,
      Scaffold(
        body: TvLibraryExtraTab(
          controller: c,
          tab: LibraryTabType.recommended,
          ownsTabFocus: () => true,
          onUp: () => up = true,
          onLeft: () {},
        ),
      ),
      navigatorObservers: [observer],
    );
    await fixtures.settle(tester);
    await fixtures.press(tester, LogicalKeyboardKey.arrowRight);
    await fixtures.press(tester, LogicalKeyboardKey.arrowDown);
    await fixtures.press(tester, LogicalKeyboardKey.arrowDown);
    await fixtures.press(tester, LogicalKeyboardKey.arrowUp);
    await fixtures.press(tester, LogicalKeyboardKey.arrowUp);
    final rows = tester.stateList<TvHorizontalRowState>(find.byType(TvHorizontalRow)).toList();
    expect(rows.first.focusedIndex, 1);
    await fixtures.press(tester, LogicalKeyboardKey.enter);
    expect(observer.destination.runtimeType.toString(), 'HubDetailScreen');
    await fixtures.settle(tester);
    await fixtures.press(tester, LogicalKeyboardKey.arrowUp);
    expect(up, isTrue);
    expect(tester.takeException(), isNull);
  });

  for (final tab in [LibraryTabType.recommended, LibraryTabType.collections, LibraryTabType.playlists]) {
    testWidgets('${tab.name}: data, paged query, OK and return focus', (tester) async {
      final client = FakeMediaServerClient();
      final item = MediaItem(
        id: 'c',
        backend: MediaBackend.jellyfin,
        kind: tab == LibraryTabType.collections ? MediaKind.collection : MediaKind.movie,
        title: 'Featured',
        serverId: 'server',
      );
      const playlist = MediaPlaylist(
        id: 'p',
        backend: MediaBackend.jellyfin,
        title: 'Video playlist',
        playlistType: 'video',
        serverId: 'server',
      );
      client.hubs = [
        MediaHub(id: 'h', title: 'Library hub', type: 'movie', items: [item], size: 10, more: true),
      ];
      client.collections = [item];
      client.playlists = [playlist];
      final c = make(client);
      final observer = DestinationObserver();
      await pumpTvWidget(
        tester,
        Scaffold(
          body: TvLibraryExtraTab(controller: c, tab: tab, ownsTabFocus: () => true, onUp: () {}, onLeft: () {}),
        ),
        navigatorObservers: [observer],
      );
      await fixtures.settle(tester);
      expect(find.byType(TvAlphaColumn), findsNothing);
      if (tab == LibraryTabType.recommended) {
        expect(find.byType(TvHorizontalRow), findsOneWidget);
        expect(find.byType(TvAllCard), findsOneWidget);
        expect(client.calls, contains('hubs:1'));
      } else {
        expect(find.byType(TvPagedGrid<Object>), findsOneWidget);
        expect(
          client.calls,
          contains(tab == LibraryTabType.collections ? 'collections:1:0:36' : 'playlists:video:0:200'),
        );
      }
      final focus = FocusManager.instance.primaryFocus;
      await fixtures.press(tester, LogicalKeyboardKey.enter);
      expect(
        observer.destination,
        tab == LibraryTabType.collections
            ? isA<CollectionDetailScreen>()
            : tab == LibraryTabType.playlists
            ? isA<PlaylistDetailScreen>()
            : isA<MediaDetailScreen>(),
      );
      await fixtures.settle(tester);
      expect(FocusManager.instance.primaryFocus, same(focus));
      expect(tester.takeException(), isNull);
    });

    testWidgets('${tab.name}: Plezy empty text and focus stays on tabs', (tester) async {
      final c = make(FakeMediaServerClient());
      var returned = false;
      await pumpTvWidget(
        tester,
        Scaffold(
          body: TvLibraryExtraTab(
            controller: c,
            tab: tab,
            ownsTabFocus: () => true,
            onUp: () => returned = true,
            onLeft: () {},
          ),
        ),
      );
      await fixtures.settle(tester);
      expect(
        find.text(switch (tab) {
          LibraryTabType.recommended => 'No recommendations available',
          LibraryTabType.collections => 'No collections in this library',
          _ => 'No playlists found',
        }),
        findsOneWidget,
      );
      expect(returned, isTrue);
      expect(find.byType(TvPagedGrid<Object>), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
