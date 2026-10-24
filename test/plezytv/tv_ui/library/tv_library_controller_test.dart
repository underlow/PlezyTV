import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/ids.dart';
import 'package:plezy/media/library_change_event.dart';
import 'package:plezy/providers/libraries_provider.dart';
import 'package:plezy/utils/library_content_notifier.dart';
import 'package:plezy/media/library_filter_result.dart';
import 'package:plezy/media/library_query.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_library.dart';
import 'package:plezy/media/media_sort.dart';
import 'package:plezy/plezytv/tv_ui/library/tv_library_controller.dart';
import 'package:plezy/plezytv/tv_ui/library/tv_library_preferences.dart';
import 'package:plezy/plezytv/tv_ui/library/tv_library_query.dart';
import 'package:plezy/services/storage_service.dart';
import 'package:plezy/utils/deletion_notifier.dart';
import 'package:plezy/utils/watch_state_notifier.dart';
import '../../../test_helpers/prefs.dart';
import 'fake_media_server_client.dart';

const library = MediaLibrary(
  id: '1',
  backend: MediaBackend.jellyfin,
  title: 'Movies',
  kind: MediaKind.movie,
  serverId: 'server',
);
MediaItem item(String id, {MediaKind kind = MediaKind.movie, int? leafCount}) =>
    MediaItem(id: id, backend: MediaBackend.jellyfin, title: id, kind: kind, serverId: 'server', leafCount: leafCount);
Future<void> flush() => Future<void>.delayed(Duration.zero);

class EventLibraries extends LibrariesProvider {
  int epoch = 0;
  @override
  int libraryContentEpoch(String globalKey) => epoch;
  void changed() {
    epoch++;
    notifyListeners();
  }
}

void main() {
  setUp(resetSharedPreferencesForTest);
  TvLibraryController controller(
    FakeMediaServerClient client, {
    TvLibraryPreferencesStore? store,
    MediaLibrary lib = library,
  }) {
    final c = TvLibraryController(library: lib, client: client, store: store ?? TvMemoryLibraryPreferences());
    addTearDown(c.dispose);
    return c;
  }

  test('query glue matches Plezy grouping, shared video, defaults and prefix', () {
    for (final pair in {
      'movies': MediaKind.movie,
      'shows': MediaKind.show,
      'seasons': MediaKind.season,
      'episodes': MediaKind.episode,
      'artists': MediaKind.artist,
      'albums': MediaKind.album,
      'tracks': MediaKind.track,
    }.entries) {
      expect(tvLibraryQuery(library: library, grouping: pair.key, filters: const []).kind, pair.value);
    }
    const shared = MediaLibrary(id: 's', backend: MediaBackend.plex, title: 'Shared', isShared: true);
    final q = tvLibraryQuery(library: shared, grouping: 'all', filters: const []);
    expect(q.filters.single.field, 'type');
    expect(q.filters.single.values, ['1', '2', '3', '4']);
    const mixed = MediaLibrary(
      id: 'm',
      backend: MediaBackend.jellyfin,
      title: 'Mixed',
      defaultBrowseKinds: [MediaKind.movie, MediaKind.show],
    );
    expect(
      tvLibraryQuery(library: mixed, grouping: 'all', filters: const [], alphaPrefix: 'A').includeKinds,
      mixed.defaultBrowseKinds,
    );
    expect(tvLibraryQuery(library: mixed, grouping: 'all', filters: const [], alphaPrefix: 'A').nameStartsWith, 'A');
    expect(tvSortLibraryType(library, 'episodes'), library.kind.id);
    expect(tvSortLibraryType(library, 'albums'), MediaKind.album.id);
    expect(tvSortLibraryType(library, 'tracks'), MediaKind.track.id);
    expect(tvDefaultSortDescending(const MediaSort(key: 'addedAt', title: 'Added', defaultDirection: 'desc')), isTrue);
    expect(tvDefaultSortDescending(const MediaSort(key: 'title', title: 'Title')), isFalse);
    expect(tvCanGroupByFolders(library, FakeMediaServerClient()), isTrue);
    expect(tvCanGroupByFolders(shared, FakeMediaServerClient()), isFalse);
  });
  test('A9 storage writes are read through Plezy accessors and restore', () async {
    final storage = await StorageService.getInstance();
    final c = controller(FakeMediaServerClient(), store: TvStorageLibraryPreferences(storage));
    await c.initialize();
    const filter = LibraryFilter(field: 'year', values: ['2020']);
    await c.select(tab: 'collections', sort: c.sorts.last, filters: [filter]);
    expect(storage.getLibraryTab(library.globalKey), 'collections');
    expect(storage.getLibrarySort(library.globalKey), {'key': 'addedAt', 'descending': true});
    expect(storage.getLibraryGrouping(library.globalKey), 'movies');
    expect(storage.getLibraryFilters(sectionId: library.globalKey), [filter]);
    final restored = controller(FakeMediaServerClient(), store: TvStorageLibraryPreferences(storage));
    await restored.initialize();
    expect(restored.preferences.tab, 'collections');
    expect(restored.query().sort?.direction, LibrarySortDirection.descending);
    await c.select(clearSort: true);
    expect(storage.getLibrarySort(library.globalKey), isNull);
  });
  test('A20 memory route seeds only incoming filter and never writes storage', () async {
    final storage = await StorageService.getInstance();
    final persisted = TvStorageLibraryPreferences(storage);
    await persisted.save(
      library.globalKey,
      TvLibraryPreferences(
        tab: 'collections',
        grouping: 'movies',
        sortKey: 'addedAt',
        descending: true,
        filters: const [
          LibraryFilter(field: 'year', values: ['2020']),
        ],
      ),
    );
    final before = {for (final key in storage.prefs.keys) key: storage.prefs.get(key)};
    final c = controller(
      FakeMediaServerClient(),
      store: TvMemoryLibraryPreferences.filtered(
        await persisted.load(library.globalKey),
        const LibraryFilter(field: 'genre', values: ['action']),
      ),
    );
    await c.initialize();
    expect(c.preferences.tab, 'browse');
    expect(c.preferences.sortKey, 'addedAt');
    expect(c.preferences.filters.single.field, 'genre');
    await c.select(tab: 'playlists', sort: c.sorts.first, filters: []);
    expect({for (final key in storage.prefs.keys) key: storage.prefs.get(key)}, before);
  });
  test('sort response for disposed previous library is discarded', () async {
    final gate = Completer<List<MediaSort>>();
    final client = FakeMediaServerClient()..onSorts = (_, _) => gate.future;
    final old = TvLibraryController(library: library, client: client, store: TvMemoryLibraryPreferences());
    final load = old.initialize();
    await flush();
    old.dispose();
    const other = MediaLibrary(
      id: '2',
      backend: MediaBackend.jellyfin,
      title: 'Other',
      kind: MediaKind.show,
      serverId: 'server',
    );
    final next = controller(FakeMediaServerClient(), lib: other);
    await next.initialize();
    gate.complete([const MediaSort(key: 'stale', title: 'Stale')]);
    await load;
    expect(old.sorts, isEmpty);
    expect(next.sorts.first.key, 'titleSort');
    expect(client.queries, isEmpty);
  });
  test('MediaBrowser page completes before background filters, late generation ignored', () async {
    final filters = Completer<LibraryFilterResult>();
    final client = FakeMediaServerClient()..onFilters = () => filters.future;
    final c = controller(client);
    await c.initialize();
    expect(c.totalCount, 0);
    expect(c.filtersLoading, isTrue);
    expect(client.calls.indexOf('page:1:0'), lessThan(client.calls.indexOf('filters:1')));
    await c.setAlphaPrefix('A');
    expect(client.queries.last.nameStartsWith, 'A');
    filters.complete(LibraryFilterResult.empty);
    await flush();
    expect(c.filtersLoading, isFalse);
    expect(c.characters.length, 27);
    expect(c.showAlpha, isTrue); // Prefix keeps the column visible with <80 results.
    await c.select(grouping: 'movies');
    expect(c.alphaPrefix, isNull);
  });
  test('selection discards a stale page and resets source generation', () async {
    final page = Completer<LibraryPage<MediaItem>>();
    final client = FakeMediaServerClient()..onPage = (_) => page.future;
    final c = controller(client);
    final init = c.initialize();
    await flush();
    client.onPage = (_) async => LibraryPage(items: [item('new')], totalCount: 1);
    final gen = c.source.generation;
    await c.select(
      filters: const [
        LibraryFilter(field: 'year', values: ['2024']),
      ],
    );
    page.complete(LibraryPage(items: [item('old')], totalCount: 100));
    await init;
    expect(c.source.generation, greaterThan(gen));
    expect(c.source[0]?.id, 'new');
    expect(c.totalCount, 1);
  });
  test('watch patches loaded metadata, deletion shifts and honors download-only/server', () async {
    final client = FakeMediaServerClient()..items = [item('a'), item('b'), item('c')];
    final c = controller(client);
    await c.initialize();
    client.onItem = (id) async => item(id).copyWith(title: 'Updated');
    WatchStateNotifier().notify(
      WatchStateEvent(
        itemId: 'a',
        serverId: ServerId('server'),
        changeType: WatchStateChangeType.watched,
        parentChain: [],
      ),
    );
    await flush();
    expect(c.source[0]?.title, 'Updated');
    void deleted(String server, {bool local = false}) => DeletionNotifier().notify(
      DeletionEvent(
        itemId: 'a',
        serverId: ServerId(server),
        parentChain: [],
        mediaType: 'movie',
        isDownloadOnly: local,
      ),
    );
    deleted('other');
    deleted('server', local: true);
    await flush();
    expect(c.totalCount, 3);
    deleted('server');
    await flush();
    expect(c.totalCount, 2);
    expect(c.source[0]?.id, 'b');
    expect(c.source.needsReload(0), isTrue);
  });
  test('child deletion decrements parent counts, removing empty parent', () async {
    final c = controller(FakeMediaServerClient()..items = [item('show', kind: MediaKind.show, leafCount: 2)]);
    await c.initialize();
    void childDeleted() => DeletionNotifier().notify(
      DeletionEvent(itemId: 'episode', serverId: ServerId('server'), parentChain: ['show'], mediaType: 'episode'),
    );
    childDeleted();
    await flush();
    expect(c.source[0]?.leafCount, 1);
    childDeleted();
    await flush();
    expect(c.totalCount, 0);
  });
  test('refresh waits for alpha jump and retains folder stack and focus', () async {
    final client = FakeMediaServerClient()..items = [item('a'), item('b')];
    final c = controller(client);
    await c.initialize();
    c.focusedIndex = 1;
    c.setJumping(true);
    await c.refresh();
    expect(client.queries.length, 1);
    c.setJumping(false);
    await flush();
    expect(c.focusedIndex, 1);
    expect(client.queries.length, 2);
    await c.select(grouping: 'folders');
    c.folders.first.focusedIndex = 4;
    await c.openFolder(item('folder', kind: MediaKind.folder));
    c.folders.last.focusedIndex = 2;
    await c.refresh();
    expect(c.folders.length, 2);
    expect(c.folders.last.focusedIndex, 2);
    expect(c.popFolder(), isTrue);
    expect(c.folders.single.focusedIndex, 4);
    expect(c.popFolder(), isFalse);
  });
  test('reset filters clears the prefix but preserves sort and grouping', () async {
    final c = controller(FakeMediaServerClient());
    await c.initialize();
    await c.select(
      sort: c.sorts.last,
      filters: const [
        LibraryFilter(field: 'year', values: ['2024']),
      ],
    );
    await c.setAlphaPrefix('B');
    await c.resetFilters();
    expect(c.alphaPrefix, isNull);
    expect(c.preferences.filters, isEmpty);
    expect(c.preferences.sortKey, 'addedAt');
    expect(c.preferences.descending, isTrue);
    expect(c.grouping, 'movies');
  });
  test('folder errors are retryable and a popped level rejects late responses', () async {
    final client = FakeMediaServerClient();
    final c = controller(client);
    await c.initialize();
    client.onFolder = (_) async => throw StateError('offline');
    await c.select(grouping: 'folders');
    expect(c.folders.single.error, isA<StateError>());
    client.onFolder = (_) async => [item('folder', kind: MediaKind.folder)];
    await c.loadFolder(c.folders.single);
    expect(c.folders.single.error, isNull);
    final gate = Completer<List<MediaItem>>();
    client.onFolder = (_) => gate.future;
    final opening = c.openFolder(c.folders.single.items.single);
    final popped = c.folders.last;
    expect(c.popFolder(), isTrue);
    gate.complete([item('late')]);
    await opening;
    expect(c.folders.length, 1);
    expect(popped.items, isEmpty);
  });
  test('Plex discovers filters before requesting page one', () async {
    final gate = Completer<LibraryFilterResult>();
    final client = FakeMediaServerClient(backend: MediaBackend.plex)..onFilters = () => gate.future;
    const plexLibrary = MediaLibrary(
      id: '1',
      backend: MediaBackend.plex,
      title: 'Movies',
      kind: MediaKind.movie,
      serverId: 'server',
    );
    final c = controller(client, lib: plexLibrary);
    final load = c.initialize();
    await flush();
    expect(client.queries, isEmpty);
    gate.complete(LibraryFilterResult.empty);
    await load;
    expect(client.queries.length, 1);
    expect(c.filtersLoading, isFalse);
  });
  test('folder rows receive watch and server deletion events', () async {
    final client = FakeMediaServerClient()..items = [item('a'), item('b')];
    final c = controller(client);
    await c.initialize();
    await c.select(grouping: 'folders');
    client.onItem = (id) async => item(id).copyWith(title: 'Updated folder row');
    WatchStateNotifier().notify(
      WatchStateEvent(
        itemId: 'a',
        serverId: ServerId('server'),
        changeType: WatchStateChangeType.watched,
        parentChain: [],
      ),
    );
    await flush();
    expect(c.folders.single.items.first.title, 'Updated folder row');
    DeletionNotifier().notify(
      DeletionEvent(itemId: 'a', serverId: ServerId('server'), parentChain: [], mediaType: 'movie'),
    );
    await flush();
    expect(c.folders.single.items.single.id, 'b');
  });
  for (final selection in [false, true]) {
    for (final duringPage in [false, true]) {
      for (final providerEvent in [false, true]) {
        test(
          'refresh during ${selection ? 'selection' : 'initialize'} ${duringPage ? 'page' : 'options'} via ${providerEvent ? 'provider' : 'library event'} completes',
          () async {
            final provider = EventLibraries();
            final client = FakeMediaServerClient()..items = [item('a')];
            final c = TvLibraryController(
              library: library,
              client: client,
              store: TvMemoryLibraryPreferences(),
              librariesProvider: provider,
            );
            addTearDown(provider.dispose);
            addTearDown(c.dispose);
            if (selection) await c.initialize();
            final sorts = Completer<List<MediaSort>>();
            final page = Completer<LibraryPage<MediaItem>>();
            if (duringPage) {
              client.onPage = (_) => page.future;
            } else {
              client.onSorts = (_, _) => sorts.future;
            }
            final load = selection ? c.select(sort: client.sorts.last) : c.initialize();
            await flush();
            final generation = c.generation;
            if (providerEvent) {
              provider.changed();
            } else {
              LibraryContentNotifier().notifyChanged(
                LibraryChangeEvent(serverId: ServerId('server'), libraryIds: {'1'}, itemsUpdated: true),
              );
            }
            await flush();
            expect(c.generation, generation, reason: 'refresh must defer to the load owner');
            expect(c.loading, isTrue);
            client.onPage = null;
            client.onSorts = null;
            if (duringPage) {
              page.complete(LibraryPage(items: [item('a')], totalCount: 1));
            } else {
              sorts.complete(client.sorts);
            }
            await load;
            await flush();
            expect(c.loading, isFalse);
            expect(c.sorts, client.sorts);
            expect(c.selectedSort?.key, selection ? 'addedAt' : null);
            expect(c.source[0]?.id, 'a');
            final count = client.queries.length;
            await c.refresh();
            expect(client.queries.length, greaterThan(count));
            expect(c.loading, isFalse);
          },
        );
      }
    }
  }
}
