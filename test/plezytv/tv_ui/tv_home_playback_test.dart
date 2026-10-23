import 'dart:async';
import 'package:plezy/services/data_aggregation_service.dart';
import 'package:plezy/services/multi_server_manager.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:plezy/providers/download_provider.dart';
import 'package:plezy/providers/multi_server_provider.dart';
import 'package:plezy/services/offline_watch_sync_service.dart';
import 'package:plezy/database/app_database.dart';
import 'package:plezy/utils/video_player_navigation.dart';
import '../../test_helpers/multi_server_fixtures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/library_query.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_server_client.dart';
import 'package:plezy/plezytv/tv_ui/home/tv_home_playback.dart';
import 'package:plezy/services/settings_service.dart';

import '../../test_helpers/prefs.dart';
import '../../test_helpers/media_items.dart';

MediaItem item(String id, MediaKind kind, {String server = 'a', int? index, int? viewCount}) => testMediaItem(
  id: id,
  backend: MediaBackend.plex,
  kind: kind,
  serverId: server,
  index: index,
  parentId: 'show',
  viewCount: viewCount,
  viewOffsetMs: 42000,
);

class Client implements MediaServerClient {
  MediaItem? onDeck;
  List<MediaItem> seasons = [];
  List<MediaItem> episodes = [];
  bool fail = false;
  Completer<void>? pending;
  final calls = <String>[];

  @override
  Future<({MediaItem? item, MediaItem? onDeckEpisode})> fetchItemWithOnDeck(
    String id, {
    void Function(MediaItem item)? onItemReady,
  }) async {
    calls.add('onDeck:$id');
    await pending?.future;
    if (fail) throw StateError('offline');
    return (item: null, onDeckEpisode: onDeck);
  }

  @override
  Future<List<MediaItem>> fetchChildren(String parentId) async {
    calls.add('seasons:$parentId');
    return seasons;
  }

  @override
  Future<LibraryPage<MediaItem>> fetchChildrenPage(String parentId, {int? start, int? size, abort}) async {
    calls.add('episodes:$parentId:$start:$size');
    if (fail) throw StateError('offline');
    return LibraryPage(
      items: episodes.take(size ?? episodes.length).toList(),
      totalCount: episodes.length,
      offset: start ?? 0,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class PagingClient extends Client implements SeasonEpisodePagingClient {
  String? requestedSeries;
  @override
  Future<LibraryPage<MediaItem>> fetchSeasonEpisodesPage(
    String seriesId,
    String seasonId, {
    int? start,
    int? size,
    abort,
  }) {
    requestedSeries = seriesId;
    return fetchChildrenPage(seasonId, start: start, size: size);
  }
}

class NoDownloads extends ChangeNotifier implements DownloadProvider {
  @override
  Future<DownloadedMediaItem?> getCompletedDownload(String key) async => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class OfflineWatch extends ChangeNotifier implements OfflineWatchSyncService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// Observe the real production route commit without building the native player.
class LaunchObserver extends NavigatorObserver {
  final launches = <Route<dynamic>>[];
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route.settings.name == kVideoPlayerRouteName) {
      launches.add(route);
      scheduleMicrotask(() => navigator!.removeRoute(route));
    }
  }
}

void main() {
  late Client client;
  late List<MediaItem> played;
  late List<MediaItem> details;
  late TvHomePlayback adapter;
  setUp(() {
    resetSharedPreferencesForTest();
    client = Client();
    played = [];
    details = [];
    adapter = TvHomePlayback(
      clientForItem: (_) => client,
      play: (item) async {
        played.add(item);
      },
      openDetails: (item) async {
        details.add(item);
      },
    );
  });

  test('A15: card settings do not affect episode/movie resume or show on-deck outside preview', () async {
    final settings = await SettingsService.getInstance();
    await settings.write(SettingsService.continueWatchingAction, ContinueWatchingAction.details);
    await settings.write(SettingsService.episodeAction, EpisodeAction.details);
    final episode = item('episode', MediaKind.episode);
    final movie = item('movie', MediaKind.movie);
    client.onDeck = item('outside-provider-preview', MediaKind.episode);
    await adapter.activate(episode);
    await adapter.activate(movie);
    await adapter.activate(item('show', MediaKind.show));
    expect(played.map((e) => e.id), ['episode', 'movie', 'outside-provider-preview']);
    expect(played.map((e) => e.viewOffsetMs), everyElement(42000));
    expect(details, isEmpty);
    expect(client.calls, ['onDeck:show']);
  });

  test('A15b: show skips specials; season starts with watched first episode', () async {
    client.seasons = [item('specials', MediaKind.season, index: 0), item('regular', MediaKind.season, index: 1)];
    client.episodes = [item('first-watched', MediaKind.episode, viewCount: 1), item('next', MediaKind.episode)];
    await adapter.activate(item('show', MediaKind.show));
    await adapter.activate(item('season', MediaKind.season));
    expect(played.map((e) => e.id), ['first-watched', 'first-watched']);
    expect(client.calls, ['onDeck:show', 'seasons:show', 'episodes:regular:0:1', 'episodes:season:0:1']);
  });

  test('A15c: collection, empty show/season and lookup errors open original details', () async {
    final inputs = [
      item('collection', MediaKind.collection),
      item('empty', MediaKind.show),
      item('season', MediaKind.season),
    ];
    for (final input in inputs) {
      await adapter.activate(input);
    }
    client.fail = true;
    final failed = item('failed', MediaKind.show);
    await adapter.activate(failed);
    expect(details, [...inputs, failed]);
    expect(played, isEmpty);
  });

  test('same show id uses its own server and stamps fetched episode identity', () async {
    final other = Client()..onDeck = item('b-next', MediaKind.episode);
    client.onDeck = item('a-next', MediaKind.episode);
    adapter = TvHomePlayback(
      clientForItem: (item) => item.serverId == 'a' ? client : other,
      play: (item) async {
        played.add(item);
      },
      openDetails: (item) async {
        details.add(item);
      },
    );
    await adapter.activate(item('same', MediaKind.show));
    await adapter.activate(item('same', MediaKind.show, server: 'b'));
    expect(client.calls, ['onDeck:same']);
    expect(other.calls, ['onDeck:same']);
    expect(played.map((e) => (e.id, e.serverId)), [('a-next', 'a'), ('b-next', 'b')]);
  });

  test('missing item client opens details', () async {
    adapter = TvHomePlayback(
      clientForItem: (_) => null,
      play: (item) async {
        played.add(item);
      },
      openDetails: (item) async {
        details.add(item);
      },
    );
    final show = item('show', MediaKind.show);
    await adapter.activate(show);
    expect(details, [show]);
    expect(played, isEmpty);
  });
  test('concurrent activation performs one lookup and one launch', () async {
    client.pending = Completer<void>();
    client.onDeck = item('next', MediaKind.episode);
    final first = adapter.activate(item('show', MediaKind.show));
    await adapter.activate(item('show', MediaKind.show));
    client.pending!.complete();
    await first;
    expect(client.calls, ['onDeck:show']);
    expect(played, hasLength(1));
  });

  test('season uses grandparent series ID for Jellyfin paging', () async {
    final paging = PagingClient()..episodes = [item('first', MediaKind.episode)];
    adapter = TvHomePlayback(
      clientForItem: (_) => paging,
      play: (e) async {
        played.add(e);
      },
      openDetails: (_) async {},
    );
    await adapter.activate(
      testMediaItem(
        id: 'season',
        kind: MediaKind.season,
        backend: MediaBackend.jellyfin,
        parentId: 'season-parent',
        grandparentId: 'series',
      ),
    );
    expect(paging.requestedSeries, 'series');
    expect(played.single.id, 'first');
  });

  testWidgets('forContext shows loading and drops lookup after another route is pushed', (tester) async {
    final servers = testMultiServer();
    // Keep real context routing/loading, substituting only the provider client.
    final provider = ItemClientProvider(client, servers.manager);
    addTearDown(provider.dispose);
    client.pending = Completer<void>();
    client.onDeck = item('next', MediaKind.episode);
    await tester.pumpWidget(
      ChangeNotifierProvider<MultiServerProvider>.value(
        value: provider,
        child: const MaterialApp(home: Scaffold(body: Text('Home'))),
      ),
    );
    final context = tester.element(find.text('Home'));
    final action = TvHomePlayback.forContext(context).activate(item('show', MediaKind.show));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    unawaited(Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const Text('Detail'))));
    await tester.pumpAndSettle();
    client.pending!.complete();
    await tester.pumpAndSettle();
    await action;
    expect(find.text('Detail'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator, skipOffstage: false), findsNothing);
  });

  testWidgets('real forContext commits video routes with both card settings set to details', (tester) async {
    final settings = await SettingsService.getInstance();
    await settings.write(SettingsService.continueWatchingAction, ContinueWatchingAction.details);
    await settings.write(SettingsService.episodeAction, EpisodeAction.details);
    final servers = testMultiServer();
    client.onDeck = item('on-deck', MediaKind.episode);
    final provider = ItemClientProvider(client, servers.manager);
    addTearDown(provider.dispose);
    final downloads = NoDownloads();
    final offline = OfflineWatch();
    addTearDown(downloads.dispose);
    addTearDown(offline.dispose);
    final observer = LaunchObserver();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<MultiServerProvider>.value(value: provider),
          ChangeNotifierProvider<DownloadProvider>.value(value: downloads),
          ChangeNotifierProvider<OfflineWatchSyncService>.value(value: offline),
        ],
        child: MaterialApp(
          navigatorObservers: [observer],
          home: const Scaffold(body: Text('Home')),
        ),
      ),
    );
    final playback = TvHomePlayback.forContext(tester.element(find.text('Home')));
    for (final kind in [MediaKind.movie, MediaKind.episode, MediaKind.show]) {
      final action = playback.activate(item(kind.name, kind));
      await tester.pumpAndSettle();
      await action;
    }
    expect(observer.launches, hasLength(3));
    expect(observer.launches, everyElement(isA<VideoPlayerRoute>()));
    expect(find.text('Home'), findsOneWidget);
  });
}

class ItemClientProvider extends MultiServerProvider {
  ItemClientProvider(this.client, MultiServerManager manager) : super(manager, DataAggregationService(manager));
  final MediaServerClient client;
  @override
  MediaServerClient? getClientForServer(serverId) => client;
}
