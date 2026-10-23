import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/media_hub.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/providers/discover_provider.dart';
import 'package:plezy/plezytv/tv_ui/home/tv_home_model.dart';

import '../../test_helpers/media_items.dart';

class HomeProvider implements DiscoverProvider {
  @override
  List<MediaItem> onDeck = [];
  @override
  List<MediaHub> hubs = [];
  @override
  bool isLoading = false;
  @override
  bool areHubsLoading = false;
  @override
  bool isLoadInFlight = false;
  @override
  bool hasMoreContinueWatching = false;
  @override
  String? errorMessage;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MediaHub hub(String id, List<MediaItem> items, {bool more = false, int size = 20}) =>
    MediaHub(id: id, title: id, type: 'mixed', items: items, more: more, size: size);

void main() {
  late HomeProvider provider;
  late TvHomeModelBuilder builder;
  setUp(() {
    provider = HomeProvider();
    builder = TvHomeModelBuilder();
  });

  test('A7: only supported kinds, provider order, no empty or duplicate continue hub', () {
    final video = testMediaItem();
    final album = testMediaItem(kind: MediaKind.album);
    final supported = [
      MediaKind.movie,
      MediaKind.show,
      MediaKind.season,
      MediaKind.episode,
      MediaKind.collection,
    ].map((kind) => testMediaItem(id: kind.name, kind: kind)).toList();
    provider.onDeck = [video];
    provider.hasMoreContinueWatching = true;
    provider.hubs = [
      hub('albums', [album], more: true),
      hub('home.continue', [video]),
      hub('mixed', [...supported, album], more: true),
      hub('last', [video]),
    ];
    final model = builder.build(provider);
    expect(model.rows.map((row) => row.title), ['Continue Watching', 'mixed', 'last']);
    expect(model.rows.first.kind, TvHomeRowKind.continueWatching);
    expect(model.rows.first.hasMore, isTrue);
    expect(model.rows.first.count, isNull); // Plezy TV headers show no counter.
    expect(model.rows[1].items, supported);
    expect(model.rows[1].hasMore, isTrue);
    expect(model.rows[1].count, isNull);
    expect(model.rows.last.count, 20);
    expect(model.rows.last.hub, same(provider.hubs.last));
    expect(() => model.rows.clear(), throwsUnsupportedError);
    expect(() => model.rows[1].items.clear(), throwsUnsupportedError);
  });

  test('R3 applies to onDeck too; unsupported-only data is empty', () {
    provider.onDeck = [testMediaItem(kind: MediaKind.track)];
    provider.hubs = [
      hub(
        'unsupported',
        MediaKind.values
            .where(
              (kind) => !{
                MediaKind.movie,
                MediaKind.show,
                MediaKind.season,
                MediaKind.episode,
                MediaKind.collection,
              }.contains(kind),
            )
            .map((kind) => testMediaItem(kind: kind))
            .toList(),
      ),
    ];
    expect(builder.build(provider).state, TvHomeState.empty);
  });

  test('A9: onDeck works while hubs load and after failed empty hubs', () {
    provider.onDeck = [testMediaItem()];
    provider.areHubsLoading = true;
    final loading = builder.build(provider);
    expect(loading.state, TvHomeState.content);
    expect(loading.onDeckState, TvHomePartState.ready);
    expect(loading.hubsState, TvHomePartState.loading);
    provider.areHubsLoading = false;
    final ready = builder.build(provider);
    expect(ready.state, TvHomeState.content);
    expect(ready.hubsState, TvHomePartState.ready);
    expect(ready.rows, same(loading.rows));
  });

  test('A9b: hubs are unpublished until onDeck completes', () {
    provider.isLoading = provider.areHubsLoading = true;
    final waiting = builder.build(provider);
    expect(waiting.state, TvHomeState.loading);
    expect(waiting.hubsState, TvHomePartState.loading);
    expect(waiting.rows, isEmpty);
    provider.isLoading = provider.areHubsLoading = false;
    provider.hubs = [
      hub('published', [testMediaItem()]),
    ];
    expect(builder.build(provider).state, TvHomeState.content);
  });

  for (final withOnDeck in [false, true]) {
    test('refresh preserves hub rows and identity (onDeck=$withOnDeck)', () {
      if (withOnDeck) provider.onDeck = [testMediaItem()];
      provider.hubs = [
        hub('existing', [testMediaItem()]),
      ];
      final before = builder.build(provider);
      provider.isLoading = provider.areHubsLoading = provider.isLoadInFlight = true;
      final refreshing = builder.build(provider);
      expect(refreshing.state, TvHomeState.content);
      expect(refreshing.rows, same(before.rows));
      expect(refreshing.rows.length, withOnDeck ? 2 : 1);
      expect(refreshing.hubsState, TvHomePartState.loading);
    });
  }

  test('cancelled onDeck does not hide successfully published hubs', () {
    provider.isLoading = true;
    provider.hubs = [
      hub('published', [testMediaItem()]),
    ];
    final model = builder.build(provider);
    expect(model.state, TvHomeState.content);
    expect(model.rows.single.title, 'published');
    expect(model.onDeckState, TvHomePartState.loading);
    expect(model.hubsState, TvHomePartState.ready);
  });

  test('existing content wins over an error; rows cached until list replacement', () {
    provider.onDeck = [testMediaItem()];
    final first = builder.build(provider);
    provider.errorMessage = 'failed';
    provider.isLoadInFlight = true;
    final next = builder.build(provider);
    expect(next.state, TvHomeState.content);
    expect(next.rows, same(first.rows));
    expect(next.isLoadInFlight, isFalse); // Settled parts re-enable controls before the drain ends.
    provider.onDeck = List.of(provider.onDeck);
    expect(builder.build(provider).rows, isNot(same(first.rows)));
    final rows = builder.build(provider).rows;
    provider.hubs = [
      hub('new', [testMediaItem()]),
    ];
    expect(builder.build(provider).rows, isNot(same(rows)));
  });

  test('focus identity distinguishes servers and survives item replacement', () {
    final a = testMediaItem(id: 'same', serverId: 'a');
    final b = testMediaItem(id: 'same', serverId: 'b');
    expect(TvHomeRow.itemKey(a), isNot(TvHomeRow.itemKey(b)));
    expect(TvHomeRow.itemKey(a), TvHomeRow.itemKey(testMediaItem(id: 'same', serverId: 'a')));
  });
}
