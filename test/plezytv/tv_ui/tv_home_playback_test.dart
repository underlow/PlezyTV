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
  final calls = <String>[];

  @override
  Future<({MediaItem? item, MediaItem? onDeckEpisode})> fetchItemWithOnDeck(
    String id, {
    void Function(MediaItem item)? onItemReady,
  }) async {
    calls.add('onDeck:$id');
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
}
