import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/library_query.dart';
import 'package:plezy/media/ids.dart';
import 'package:plezy/plezytv/tv_ui/show/tv_show_controller.dart';
import 'package:plezy/plezytv/tv_ui/show/tv_show_logic.dart';
import 'package:plezy/plezytv/tv_ui/show/tv_show_screen.dart';
import 'package:plezy/plezytv/tv_ui/tv_ui.dart';
import 'package:plezy/utils/media_navigation_helper.dart';
import 'package:plezy/utils/watch_state_notifier.dart';
import 'fake_media_server_client.dart';

MediaItem item(String id, MediaKind kind, {int? number, int? season, int? watched, int? offset}) => MediaItem(
  id: id,
  backend: MediaBackend.jellyfin,
  kind: kind,
  title: id,
  serverId: 'server',
  index: number,
  durationMs: 3600000,
).copyWith(parentIndex: season, viewCount: watched, viewOffsetMs: offset);
void main() {
  tearDown(TvUi.resetForTesting);
  test('primary action prioritizes on-deck and resumes with remaining time', () {
    final episode = item('e3', MediaKind.episode, number: 3, season: 1, offset: 1500000);
    final action = tvShowPrimaryAction(onDeck: episode, episodes: [], complete: false)!;
    expect(action.episode, episode);
    expect(action.label, contains('Continue S1 E3'));
    expect(action.label, contains('35'));
    expect(action.startPositionMs, 1500000);
  });
  test('unwatched specials alone do not prevent rewatch; restart ignores offset', () {
    final first = item('e1', MediaKind.episode, number: 1, season: 1, watched: 1);
    final special = item('special', MediaKind.episode, season: 0);
    final action = tvShowPrimaryAction(episodes: [special, first], complete: true, firstEpisode: first)!;
    expect(action.label, 'Rewatch');
    expect(action.startPositionMs, 0);
    expect(tvShowPrimaryAction(episodes: [first], complete: false)!.restart, false);
  });
  test('initial selection and remembered focus respect explicit episode', () {
    final seasons = [item('s1', MediaKind.season, number: 1), item('s2', MediaKind.season, number: 2)];
    expect(tvShowInitialTab(seasons), 0);
    expect(tvShowInitialTab(seasons, seasonId: 's2'), 2);
    expect(tvShowInitialTab(seasons, flattened: true, episodeId: 'e'), 1);
    final episodes = [item('e1', MediaKind.episode, watched: 1), item('e2', MediaKind.episode)];
    expect(tvShowFocusEpisode(episodes)!.id, 'e2');
    expect(tvShowFocusEpisode(episodes, initialEpisodeId: 'e1')!.id, 'e1');
    expect(tvShowFocusEpisode(episodes, lastEpisodeId: 'e2', initialEpisodeId: 'e1')!.id, 'e2');
  });
  testWidgets('route gate and converted navigation targets preserve initial identities', (tester) async {
    TvUi.enabledForTesting = () => true;
    final show = item('show', MediaKind.show);
    final route = TvUi.showDetailRoute(metadata: show)!;
    expect(route.opaque, true);
    expect(TvUi.showDetailRoute(metadata: show, isOffline: true), null);
    expect(TvUi.showDetailRoute(metadata: show, enabled: false), null);
    expect(TvUi.showDetailRoute(metadata: item('movie', MediaKind.movie)), null);
    final episode = item('e4', MediaKind.episode, season: 2).copyWith(parentId: 's2', grandparentId: 'show');
    final target = mediaDetailNavigationTargetFor(episode);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) =>
              TextButton(onPressed: () => navigateToMediaItemDetails(context, episode), child: const Text('Open')),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final screen = tester.widget<TvShowScreen>(find.byType(TvShowScreen));
    expect(screen.metadata.id, target.metadata.id);
    expect(screen.initialSeasonId, 's2');
    expect(screen.initialSeasonIndex, 2);
    expect(screen.initialEpisodeId, 'e4');
    final seasonTarget = mediaDetailNavigationTargetFor(
      item('s2', MediaKind.season, number: 2).copyWith(parentId: 'show'),
    );
    expect(TvUi.showDetailRoute(metadata: seasonTarget.metadata), isNotNull);
    final orphan = mediaDetailNavigationTargetFor(item('e', MediaKind.episode).copyWith(parentId: 's'));
    expect(TvUi.showDetailRoute(metadata: orphan.metadata), null);
  });
  FakeShowClient fixture() => FakeShowClient()
    ..show = item('show', MediaKind.show)
    ..seasons = [
      item('s1', MediaKind.season, number: 1),
      item('s2', MediaKind.season, number: 2).copyWith(leafCount: 0, viewedLeafCount: 0),
    ]
    ..episodes = {
      's1': [item('e1', MediaKind.episode, season: 1, watched: 1), item('e2', MediaKind.episode, season: 1)],
      's2': [],
    };
  test('metadata precedes rows; fallback uses loaded pages without scanning; refresh reloads cache', () async {
    final client = fixture();
    final controller = TvShowController(client: client, metadata: client.show, pageSize: 1);
    addTearDown(controller.dispose);
    await controller.load();
    expect(controller.error, null);
    expect(client.calls.first, 'metadata');
    expect(controller.flattened, false);
    expect(controller.primaryAction!.episode.id, 'e1');
    expect(controller.primaryAction!.restart, false);
    expect(controller.episodesFor('s1'), hasLength(1));
    expect(client.calls.where((call) => call.startsWith('page:')), ['page:s1:0']);
    await controller.loadMoreEpisodes('s1');
    expect(controller.primaryAction!.episode.id, 'e2');
    await controller.refresh();
    expect(controller.episodesFor('s1'), hasLength(2));
  });
  test('only specials unwatched yields rewatch of first regular episode', () async {
    final client = fixture();
    client.seasons.insert(0, item('s0', MediaKind.season, number: 0));
    client.episodes['s1'] = [item('e1', MediaKind.episode, season: 1, watched: 1)];
    client.episodes['s0'] = [item('extra', MediaKind.episode, season: 0)];
    final controller = TvShowController(client: client, metadata: client.show);
    addTearDown(controller.dispose);
    await controller.load();
    expect(controller.primaryAction!.restart, true);
    expect(controller.primaryAction!.episode.id, 'e1');
  });
  test('aggregate regular season counts allow rewatch without fetching other seasons', () async {
    final client = fixture();
    client.seasons = [
      item('s0', MediaKind.season, number: 0).copyWith(leafCount: 1, viewedLeafCount: 0),
      item('s1', MediaKind.season, number: 1).copyWith(leafCount: 100, viewedLeafCount: 100),
      item('s2', MediaKind.season, number: 2).copyWith(leafCount: 100, viewedLeafCount: 100),
    ];
    client.episodes['s1'] = [for (var i = 0; i < 100; i++) item('e$i', MediaKind.episode, season: 1, watched: 1)];
    final c = TvShowController(client: client, metadata: client.show, pageSize: 1);
    addTearDown(c.dispose);
    await c.load();
    expect(c.primaryAction!.restart, true);
    expect(client.calls.where((call) => call.startsWith('page:')), ['page:s1:0']);
    final old = c.episodesFor('s1');
    client.onPage = (_, _, _) => Future.error(StateError('offline'));
    await c.refresh();
    expect(c.error, isA<StateError>());
    expect(c.episodesFor('s1'), old);
  });
  test('new refresh supersedes late metadata and errors', () async {
    final client = fixture();
    final pending = Completer<({MediaItem? item, MediaItem? onDeckEpisode})>();
    client.onFetch = () => pending.future;
    final controller = TvShowController(client: client, metadata: client.show);
    addTearDown(controller.dispose);
    final old = controller.load();
    await Future<void>.delayed(Duration.zero);
    client.onFetch = null;
    await controller.refresh();
    pending.completeError(StateError('old offline'));
    await old;
    expect(controller.error, null);
    client.onFetch = () => Future.error(StateError('offline'));
    await controller.refresh();
    expect(controller.error, isA<StateError>());
    expect(controller.loading, false);
  });
  test('Jellyfin flattening and hierarchical watch events are server scoped', () async {
    final client = fixture()..seasons = [];
    client.episodes['show'] = [item('e1', MediaKind.episode, season: 1)];
    final controller = TvShowController(client: client, metadata: client.show);
    addTearDown(controller.dispose);
    await controller.load();
    expect(controller.flattened, true);
    controller.applyWatchEvent(
      WatchStateEvent(
        itemId: 'show',
        serverId: ServerId('other'),
        changeType: WatchStateChangeType.watched,
        parentChain: [],
        isNowWatched: true,
      ),
    );
    expect(controller.watchStateChanged, false);
    controller.applyWatchEvent(
      WatchStateEvent(
        itemId: 'show',
        serverId: ServerId('server'),
        changeType: WatchStateChangeType.watched,
        parentChain: [],
        isNowWatched: true,
      ),
    );
    expect(controller.watchStateChanged, true);
    expect(controller.episodesFor('show').single.isWatched, true);
  });
  test('Plex prefs flattening and failed prefs preserve usable seasons', () async {
    final client = fixture()..backend = MediaBackend.plex;
    client.show = client.show.copyWith(libraryId: 'library');
    client.onDeck = item('onDeck', MediaKind.episode, season: 1);
    var fail = false;
    final controller = TvShowController(
      client: client,
      metadata: client.show,
      libraryPrefs: (id) async {
        expect(id, 'library');
        if (fail) throw StateError('prefs unavailable');
        return {'flattenSeasons': 1};
      },
    );
    addTearDown(controller.dispose);
    await controller.load();
    expect(controller.flattened, true);
    fail = true;
    await controller.refresh();
    expect(controller.flattened, false);
    expect(controller.error, null);
    expect(controller.seasons.first.parentId, 'show');
  });
  test('late episode page cannot replace refreshed cache or loading state', () async {
    final client = fixture();
    final controller = TvShowController(client: client, metadata: client.show);
    addTearDown(controller.dispose);
    await controller.load();
    final pending = Completer<LibraryPage<MediaItem>>();
    client.onPage = (_, _, _) => pending.future;
    final oldPage = controller.loadMoreEpisodes('s2');
    client.onPage = null;
    client.episodes['s2'] = [item('new', MediaKind.episode, season: 2)];
    await controller.refresh();
    pending.complete(LibraryPage(items: [item('old', MediaKind.episode, season: 2)], totalCount: 1));
    await oldPage;
    expect(controller.episodesFor('s2').map((e) => e.id), ['new']);
    expect(controller.isLoadingEpisodes('s2'), false);
  });
  test('metadata omits unknown fields, progress only for started episodes, trailer detection', () {
    final show = item('show', MediaKind.show).copyWith(year: 2024, studio: 'Studio', leafCount: 10);
    expect(tvShowMetadata(show, [item('s1', MediaKind.season)]), '2024 · 1 season · 10 episodes · Studio');
    expect(tvShowMetadata(item('empty', MediaKind.show), []), '');
    expect(tvShowWatchedProgress(item('e', MediaKind.episode)), null);
    expect(tvShowWatchedProgress(item('e', MediaKind.episode, offset: 600000)), contains('10'));
    final trailer = item('trailer', MediaKind.clip).copyWith(raw: {'ExtraType': 'Trailer'});
    expect(tvShowPrimaryTrailer(show, [item('extra', MediaKind.clip), trailer]), trailer);
  });
  test('flattened rewatch skips specials even when the server returns them first', () async {
    final client = fixture()..seasons = [];
    client.episodes['show'] = [
      item('special', MediaKind.episode, season: 0),
      item('regular', MediaKind.episode, season: 1, watched: 1),
    ];
    final controller = TvShowController(client: client, metadata: client.show);
    addTearDown(controller.dispose);
    await controller.load();
    expect(controller.primaryAction!.restart, true);
    expect(controller.primaryAction!.episode.id, 'regular');
  });
  test('watch event arriving during a page request survives the response', () async {
    final client = fixture()..onDeck = item('e2', MediaKind.episode, season: 1);
    final controller = TvShowController(client: client, metadata: client.show, pageSize: 1);
    addTearDown(controller.dispose);
    await controller.load();
    final pending = Completer<LibraryPage<MediaItem>>();
    client.onPage = (_, _, _) => pending.future;
    final request = controller.loadMoreEpisodes('s1');
    controller.applyWatchEvent(
      WatchStateEvent(
        itemId: 'e2',
        serverId: ServerId('server'),
        changeType: WatchStateChangeType.watched,
        parentChain: ['s1', 'show'],
        isNowWatched: true,
      ),
    );
    pending.complete(LibraryPage(items: [item('e2', MediaKind.episode, season: 1)], totalCount: 2));
    await request;
    expect(controller.episodesFor('s1').last.isWatched, true);
    expect(controller.watchStateChanged, true);
  });
}
