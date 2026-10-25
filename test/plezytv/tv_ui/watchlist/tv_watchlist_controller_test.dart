import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/models/catalog/catalog_item.dart';
import 'package:plezy/plezytv/tv_ui/watchlist/tv_watchlist_availability.dart';
import 'package:plezy/plezytv/tv_ui/watchlist/tv_watchlist_controller.dart';
import 'package:plezy/providers/multi_server_provider.dart';
import 'package:plezy/services/catalog/catalog_library_matcher.dart';
import 'package:plezy/services/catalog/catalog_source.dart';
import 'package:plezy/services/data_aggregation_service.dart';

import '../../../test_helpers/library_lookup.dart';
import '../../../test_helpers/media_items.dart';

class _FakeSource implements CatalogSource {
  _FakeSource(this.id, this.items);

  @override
  final CatalogSourceId id;
  List<CatalogItem> items;
  int? failPage;
  int listFetches = 0;

  /// Membership snapshot; null until "loaded".
  Set<String>? members;
  final WatchlistChangeNotifier changes = WatchlistChangeNotifier();

  @override
  String get displayName => id.name;
  @override
  bool get supportsWatchlist => true;
  @override
  List<CatalogRowId> get supportedRows => const [CatalogRowId.watchlist];
  @override
  Listenable get watchlistChanges => changes;

  @override
  Future<CatalogPage> fetchRow(CatalogRowId row, {int page = 1, int limit = 25}) async {
    if (page == 1) listFetches++;
    if (page == failPage) throw Exception('page $page failed');
    final start = (page - 1) * limit;
    final end = (start + limit).clamp(0, items.length);
    return CatalogPage(items: items.sublist(start.clamp(0, items.length), end), hasMore: end < items.length);
  }

  @override
  Future<void> ensureWatchlistLoaded() async {}

  @override
  bool? isOnWatchlist(MediaKind kind, CatalogItemIds ids) {
    final m = members;
    if (m == null) return null;
    return m.contains('${kind.id}/${ids.entryKey}');
  }

  void loadSnapshot() {
    members = {for (final i in items) i.entryIdentityKey};
    changes.notify();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Sources extends ChangeNotifier {
  _Sources(this.list);
  List<CatalogSource> list;
  void set(List<CatalogSource> value) {
    list = value;
    notifyListeners();
  }
}

class _Matcher implements CatalogLibraryMatcher {
  final Set<String> found = {};
  @override
  Future<LibraryLookupResult> match(CatalogItem item, {bool refreshIncomplete = false}) async => libraryLookupResult(
    found.contains(item.title) ? [testMediaItem(id: item.title, serverId: 'a')] : const [],
    succeeded: {'a'},
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Servers extends ChangeNotifier implements MultiServerProvider {
  @override
  List<String> get expectedServerIds => const ['a'];
  @override
  List<String> get onlineServerIds => const ['a'];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

CatalogItem _item(
  CatalogSourceId source,
  int n, {
  MediaKind kind = MediaKind.movie,
  String? title,
  int? year,
  double? rating,
  List<String>? genres,
  DateTime? addedAt,
}) => CatalogItem(
  source: source,
  kind: kind,
  title: title ?? 'T$n',
  year: year,
  rating: rating,
  genres: genres,
  addedAt: addedAt,
  ids: CatalogItemIds(trakt: n),
);

List<String> _titles(TvWatchlistController c) => [for (final i in c.view) i.title];

void main() {
  late _Matcher matcher;
  late _Sources sources;
  late TvMemoryWatchlistPreferences prefs;
  final controllers = <TvWatchlistController>[];

  setUp(() {
    matcher = _Matcher();
    prefs = TvMemoryWatchlistPreferences();
  });

  tearDown(() {
    for (final c in controllers) {
      c.dispose();
      c.availability.dispose();
    }
    controllers.clear();
  });

  TvWatchlistController make(List<CatalogSource> list) {
    sources = _Sources(list);
    final c = TvWatchlistController(
      availability: TvWatchlistAvailability(matcher, _Servers()),
      sourcesListenable: sources,
      readSources: () => sources.list,
      preferences: prefs,
    );
    controllers.add(c);
    return c;
  }

  group('sources', () {
    test('Plex first and default; selection remembered per store (A25, A26)', () async {
      final trakt = _FakeSource(CatalogSourceId.trakt, [_item(CatalogSourceId.trakt, 1)]);
      final plex = _FakeSource(CatalogSourceId.plex, [_item(CatalogSourceId.plex, 2)]);
      final c = make([trakt, plex]);
      await c.load();
      expect(c.sources.map((s) => s.id), [CatalogSourceId.plex, CatalogSourceId.trakt]);
      expect(c.source, plex);
      expect(c.hasMultipleSources, isTrue);

      c.setFilters(const TvWatchlistFilters(decades: {2000}));
      await c.selectSource(trakt);
      expect(c.source, trakt);
      expect(c.filters.isEmpty, isTrue);
      expect(prefs.value.source, 'trakt');

      final again = make([trakt, plex]);
      await again.load();
      expect(again.source, trakt);
    });

    test('disconnecting the open source loads the default without forgetting it (A33)', () async {
      final trakt = _FakeSource(CatalogSourceId.trakt, [_item(CatalogSourceId.trakt, 1)]);
      final plex = _FakeSource(CatalogSourceId.plex, [_item(CatalogSourceId.plex, 2)]);
      prefs.value = const TvWatchlistPreferences(source: 'trakt');
      final c = make([trakt, plex]);
      await c.load();
      expect(c.source, trakt);

      sources.set([plex]);
      await pumpEventQueue();
      expect(c.source, plex);
      expect(c.phase, TvWatchlistPhase.ready);
      expect(prefs.value.source, 'trakt');

      final restarted = make([trakt, plex]);
      await restarted.load();
      expect(restarted.source, trakt);
    });

    test('replaced source object: notifications of the new object reach the controller', () async {
      final old = _FakeSource(CatalogSourceId.plex, [_item(CatalogSourceId.plex, 1), _item(CatalogSourceId.plex, 2)]);
      final c = make([old]);
      await c.load();
      final fresh = _FakeSource(CatalogSourceId.plex, [...old.items]);
      sources.set([fresh]);
      expect(c.source, fresh);

      fresh.loadSnapshot();
      fresh.members!.remove(old.items.first.entryIdentityKey);
      fresh.changes.notify();
      expect(_titles(c), ['T2']);

      final before = c.all.length;
      old.members = {};
      old.changes.notify();
      expect(c.all.length, before, reason: 'old object is unsubscribed');
    });
  });

  group('loading', () {
    test('1200 items are cut to the first 1000 (A31)', () async {
      final plex = _FakeSource(CatalogSourceId.plex, [for (var i = 0; i < 1200; i++) _item(CatalogSourceId.plex, i)]);
      final c = make([plex]);
      await c.load();
      expect(c.all.length, 1000);
      expect(c.view.length, 1000);
      expect(c.all.last.title, 'T999');
    });

    test('a failing page gives error; retry loads (A21)', () async {
      final plex = _FakeSource(CatalogSourceId.plex, [for (var i = 0; i < 250; i++) _item(CatalogSourceId.plex, i)])
        ..failPage = 2;
      final c = make([plex]);
      await c.load();
      expect(c.phase, TvWatchlistPhase.error);
      expect(c.view, isEmpty);

      plex.failPage = null;
      await c.retry();
      expect(c.phase, TvWatchlistPhase.ready);
      expect(c.all.length, 250);
      expect(c.lastChange, TvWatchlistChange.reset);
    });
  });

  group('sort (A14)', () {
    late _FakeSource src;
    setUp(() {
      const s = CatalogSourceId.trakt;
      src = _FakeSource(s, [
        _item(s, 1, title: 'beta', year: 2001, rating: 7, addedAt: DateTime(2024, 1, 1)),
        _item(s, 2, title: 'Alpha'),
        _item(s, 3, title: 'gamma', year: 2020, rating: 9, addedAt: DateTime(2025, 1, 1)),
        _item(s, 4, title: 'delta', year: 1990, rating: 5),
      ]);
    });

    test('added: dated newest first, undated after in source order', () async {
      final c = make([src]);
      await c.load();
      expect(_titles(c), ['gamma', 'beta', 'Alpha', 'delta']);
    });

    test('added without any dates keeps source order', () async {
      const s = CatalogSourceId.anilist;
      final c = make([
        _FakeSource(s, [_item(s, 1, title: 'x'), _item(s, 2, title: 'y'), _item(s, 3, title: 'z')]),
      ]);
      await c.load();
      expect(_titles(c), ['x', 'y', 'z']);
    });

    test('title A-Z, year and rating newest/highest first with missing last; persisted', () async {
      final c = make([src]);
      await c.load();
      c.setSort(TvWatchlistSort.title);
      expect(_titles(c), ['Alpha', 'beta', 'delta', 'gamma']);
      expect(c.lastChange, TvWatchlistChange.reset);
      c.setSort(TvWatchlistSort.year);
      expect(_titles(c), ['gamma', 'beta', 'delta', 'Alpha']);
      c.setSort(TvWatchlistSort.rating);
      expect(_titles(c), ['gamma', 'beta', 'delta', 'Alpha']);
      c.setTab(TvWatchlistTab.movies);
      expect(prefs.value.sort, TvWatchlistSort.rating);
      expect(prefs.value.tab, TvWatchlistTab.movies);

      final again = make([src]);
      await again.load();
      expect(again.sort, TvWatchlistSort.rating);
      expect(again.tab, TvWatchlistTab.movies);
    });
  });

  group('filters', () {
    const s = CatalogSourceId.trakt;

    test('genre filter with Shows tab (A15)', () async {
      final c = make([
        _FakeSource(s, [
          _item(s, 1, title: 'drama show', kind: MediaKind.show, genres: ['Drama'], year: 2010),
          _item(s, 2, title: 'drama movie', genres: ['Drama'], year: 2015),
          _item(s, 3, title: 'comedy show', kind: MediaKind.show, genres: ['Comedy'], year: 1995),
        ]),
      ]);
      await c.load();
      expect(c.genreOptions, ['Comedy', 'Drama']);
      expect(c.decadeOptions, [2010, 1990]);
      c.setFilters(const TvWatchlistFilters(genres: {'Drama'}));
      c.setTab(TvWatchlistTab.shows);
      expect(_titles(c), ['drama show']);
      expect(c.filters.count, 1);
      c.setTab(TvWatchlistTab.all);
      c.setFilters(const TvWatchlistFilters(decades: {1990}));
      expect(_titles(c), ['comedy show']);
    });

    test('no genres anywhere -> empty genre options, decades still work (A16)', () async {
      final c = make([
        _FakeSource(s, [_item(s, 1, year: 2001), _item(s, 2, year: 1985)]),
      ]);
      await c.load();
      expect(c.genreOptions, isEmpty);
      expect(c.decadeOptions, [2000, 1980]);
    });

    test('a saved filter value no longer in the list is dropped (A17)', () async {
      prefs.value = const TvWatchlistPreferences(
        filters: {
          'trakt': TvWatchlistFilters(genres: {'Drama'}, decades: {2000}),
        },
      );
      final c = make([
        _FakeSource(s, [
          _item(s, 1, genres: ['Comedy'], year: 2003),
          _item(s, 2, year: 1999),
        ]),
      ]);
      await c.load();
      expect(c.filters.genres, isEmpty);
      expect(c.filters.decades, {2000});
      expect(_titles(c), ['T1']);
      expect(prefs.value.filters['trakt']!.genres, isEmpty);
    });
  });

  group('changes (R13)', () {
    const s = CatalogSourceId.trakt;
    List<CatalogItem> three() => [_item(s, 1), _item(s, 2), _item(s, 3)];

    test('membership snapshot without changes does not re-read (A28)', () {
      fakeAsync((async) {
        final src = _FakeSource(s, three());
        final c = make([src]);
        c.load();
        async.flushMicrotasks();
        src.loadSnapshot();
        async.elapse(const Duration(seconds: 5));
        expect(src.listFetches, 1);
        expect(c.all.length, 3);
      });
    });

    test('isOnWatchlist=false removes at once; double notify gives one re-read (A27)', () {
      fakeAsync((async) {
        final src = _FakeSource(s, three());
        final c = make([src]);
        c.load();
        async.flushMicrotasks();
        src.loadSnapshot();
        src.members!.remove(src.items[1].entryIdentityKey);
        src.changes.notify();
        expect(_titles(c), ['T1', 'T3']);
        expect(c.lastChange, TvWatchlistChange.keepFocus);
        src.changes.notify();
        src.items = [src.items[0], src.items[2]];
        async.elapse(const Duration(seconds: 3));
        expect(src.listFetches, 2);
        expect(_titles(c), ['T1', 'T3']);
        expect(c.phase, TvWatchlistPhase.ready);
      });
    });

    test('an addition elsewhere shows up after one background re-read', () {
      fakeAsync((async) {
        final src = _FakeSource(s, three());
        final c = make([src]);
        c.load();
        async.flushMicrotasks();
        src.loadSnapshot();
        src.items = [_item(s, 4), ...src.items];
        src.members!.add(src.items.first.entryIdentityKey);
        src.changes.notify();
        src.changes.notify();
        async.elapse(const Duration(seconds: 3));
        expect(src.listFetches, 2);
        expect(c.all.length, 4);
        expect(c.lastChange, TvWatchlistChange.keepFocus);
      });
    });

    test('a failed re-read keeps the list', () {
      fakeAsync((async) {
        final src = _FakeSource(s, three());
        final c = make([src]);
        c.load();
        async.flushMicrotasks();
        src.loadSnapshot();
        src.failPage = 1;
        src.changes.notify();
        async.elapse(const Duration(seconds: 3));
        expect(c.all.length, 3);
        expect(c.phase, TvWatchlistPhase.ready);
      });
    });

    test('itemRemoved before the snapshot loads drops at once; restore puts it back (A34)', () async {
      final src = _FakeSource(s, three());
      final c = make([src]);
      await c.load();
      c.itemRemoved(src.items[1]);
      expect(_titles(c), ['T1', 'T3']);
      expect(c.lastChange, TvWatchlistChange.keepFocus);
      c.itemRestored(src.items[1]);
      expect(_titles(c), ['T1', 'T2', 'T3']);
    });

    test('a background re-read that still lists a locally removed item does not resurrect it', () async {
      final src = _FakeSource(s, three());
      final c = make([src]);
      await c.load();
      c.itemRemoved(src.items[0]);
      await c.backgroundRefresh();
      expect(_titles(c), ['T2', 'T3']);
    });
  });

  test('onServer tab follows availability with keepFocus', () async {
    const s = CatalogSourceId.trakt;
    matcher.found.add('T2');
    final c = make([
      _FakeSource(s, [_item(s, 1), _item(s, 2)]),
    ]);
    await c.load();
    c.setTab(TvWatchlistTab.onServer);
    await pumpEventQueue();
    expect(_titles(c), ['T2']);
    expect(c.lastChange, TvWatchlistChange.keepFocus);
  });

  test('preferences round-trip through encode/decode', () {
    const p = TvWatchlistPreferences(
      source: 'plex',
      sort: TvWatchlistSort.year,
      tab: TvWatchlistTab.shows,
      filters: {
        'plex': TvWatchlistFilters(genres: {'Drama'}, decades: {1990}),
      },
    );
    final back = TvWatchlistPreferences.decode(p.encode());
    expect(back.source, 'plex');
    expect(back.sort, TvWatchlistSort.year);
    expect(back.tab, TvWatchlistTab.shows);
    expect(back.filters['plex'], p.filters['plex']);
    expect(TvWatchlistPreferences.decode('garbage').sort, TvWatchlistSort.added);
  });
}
