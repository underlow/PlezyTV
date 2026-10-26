import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/models/catalog/catalog_item.dart';
import 'package:plezy/plezytv/tv_ui/watchlist/tv_watchlist_availability.dart';
import 'package:plezy/providers/multi_server_provider.dart';
import 'package:plezy/services/catalog/catalog_library_matcher.dart';
import 'package:plezy/services/data_aggregation_service.dart';

import '../../../test_helpers/library_lookup.dart';
import '../../../test_helpers/media_items.dart';

class _Call {
  final CatalogItem item;
  final bool refresh;
  final Completer<LibraryLookupResult> completer = Completer();
  _Call(this.item, this.refresh);
}

class _FakeMatcher implements CatalogLibraryMatcher {
  final List<_Call> calls = [];
  int active = 0;
  int maxActive = 0;

  @override
  Future<LibraryLookupResult> match(CatalogItem item, {bool refreshIncomplete = false}) async {
    final call = _Call(item, refreshIncomplete);
    calls.add(call);
    active++;
    if (active > maxActive) maxActive = active;
    try {
      return await call.completer.future;
    } finally {
      active--;
    }
  }

  List<_Call> get open => calls.where((c) => !c.completer.isCompleted).toList();

  _Call callFor(CatalogItem item) => calls.lastWhere((c) => c.item == item);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeServers extends ChangeNotifier implements MultiServerProvider {
  @override
  List<String> expectedServerIds = ['a', 'b'];
  @override
  List<String> onlineServerIds = ['a'];

  void set({List<String>? expected, List<String>? online}) {
    if (expected != null) expectedServerIds = expected;
    if (online != null) onlineServerIds = online;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

CatalogItem _item(int n) => CatalogItem(
  source: CatalogSourceId.trakt,
  kind: MediaKind.movie,
  title: 'Movie $n',
  ids: CatalogItemIds(trakt: n),
);

MediaItem _copy(String id, String server) => testMediaItem(id: id, serverId: server);

final _complete = libraryLookupResult(const [], succeeded: {'a', 'b'});
LibraryLookupResult _found(List<MediaItem> copies, {bool complete = true}) =>
    libraryLookupResult(copies, succeeded: complete ? {'a', 'b'} : {'a'}, unqueried: complete ? {} : {'b'});
final _emptyIncomplete = libraryLookupResult(const [], succeeded: {'a'}, unqueried: {'b'});

void main() {
  late _FakeMatcher matcher;
  late _FakeServers servers;
  late DateTime now;
  late TvWatchlistAvailability availability;

  setUp(() {
    matcher = _FakeMatcher();
    servers = _FakeServers();
    now = DateTime.utc(2026, 10, 25, 12);
    availability = TvWatchlistAvailability(matcher, servers, now: () => now);
  });

  tearDown(() {
    // The dispose test already disposed it; a second dispose asserts.
    try {
      availability.dispose();
    } on FlutterError catch (_) {}
  });

  Future<void> answer(CatalogItem item, LibraryLookupResult result) async {
    matcher.open.firstWhere((c) => c.item == item).completer.complete(result);
    await pumpEventQueue();
  }

  Future<void> answerAll(LibraryLookupResult Function(CatalogItem) result) async {
    while (matcher.open.isNotEmpty) {
      for (final call in matcher.open) {
        call.completer.complete(result(call.item));
      }
      await pumpEventQueue();
    }
  }

  test('no more than 3 checks run at once', () async {
    final items = List.generate(10, _item);
    availability.setItems(items);
    expect(matcher.open, hasLength(TvWatchlistAvailability.maxConcurrent));
    expect(availability.checking, isTrue);
    await answerAll((_) => _complete);
    expect(matcher.calls, hasLength(10));
    expect(matcher.maxActive, lessThanOrEqualTo(3));
    expect(availability.checking, isFalse);
  });

  test('prioritized items are checked before the rest of the list', () async {
    final items = List.generate(10, _item);
    availability.setItems(items);
    availability.prioritize([items[8], items[9]]);
    await answer(items[0], _complete);
    await answer(items[1], _complete);
    expect(matcher.calls.skip(3).take(2).map((c) => c.item), [items[8], items[9]]);
  });

  test('statuses: copies with a silent server, empty with a silent server, complete miss', () async {
    final items = List.generate(3, _item);
    final copy = _copy('c', 'a');
    expect(availability.statusOf(items[0]), same(TvAvailability.pending));
    availability.setItems(items);
    expect(availability.statusOf(items[0]), same(TvAvailability.pending), reason: 'first check running');
    await answer(items[0], _found([copy], complete: false));
    await answer(items[1], _emptyIncomplete);
    await answer(items[2], _complete);
    final found = availability.statusOf(items[0]) as TvAvailabilityFound;
    expect(found.copies, [copy]);
    expect(found.complete, isFalse);
    expect(availability.statusOf(items[1]), same(TvAvailability.unchecked));
    expect(availability.statusOf(items[2]), same(TvAvailability.notFound));
  });

  test('a failed check is unchecked', () async {
    final item = _item(1);
    availability.setItems([item]);
    matcher.open.single.completer.completeError(StateError('boom'));
    await pumpEventQueue();
    expect(availability.statusOf(item), same(TvAvailability.unchecked));
  });

  test('a server coming online rechecks only incomplete results, once, with refreshIncomplete', () async {
    final items = List.generate(4, _item);
    availability.setItems(items);
    await answer(items[0], _found([_copy('x', 'a')], complete: false));
    await answer(items[1], _emptyIncomplete);
    await answer(items[2], _complete);
    await answer(items[3], _found([_copy('y', 'a')]));
    expect(matcher.calls, hasLength(4));

    servers.set(online: ['a']);
    servers.set(online: ['a']);
    await pumpEventQueue();
    expect(matcher.calls, hasLength(4), reason: 'same server set does not recheck');

    servers.set(online: ['a', 'b']);
    servers.set(online: ['b', 'a']);
    await pumpEventQueue();
    final rechecks = matcher.calls.skip(4).toList();
    expect(rechecks.map((c) => c.item), unorderedEquals([items[0], items[1]]));
    expect(rechecks.every((c) => c.refresh), isTrue);
    expect(availability.statusOf(items[0]), isA<TvAvailabilityFound>(), reason: 'old result kept meanwhile');

    // Another new server while those are in flight: no duplicates now; each
    // is queued once more only if it finishes incomplete (C2).
    servers.set(online: ['a', 'b', 'c']);
    servers.set(online: ['a', 'b', 'c', 'd']);
    await pumpEventQueue();
    expect(matcher.calls, hasLength(6));
    await answer(items[0], _found([_copy('x', 'a')]));
    await answer(items[1], _emptyIncomplete);
    expect(matcher.calls, hasLength(7));
    expect(matcher.calls.last.item, items[1]);
    expect(matcher.calls.last.refresh, isTrue);
    await answer(items[1], _emptyIncomplete);
    expect(matcher.calls, hasLength(7), reason: 'once per server change');
  });

  test('a server coming online re-runs a first check that was running and ends incomplete', () async {
    final items = List.generate(2, _item);
    availability.setItems(items);
    expect(matcher.open, hasLength(2));
    servers.set(online: ['a', 'b']);
    await pumpEventQueue();
    expect(matcher.calls, hasLength(2));
    await answer(items[0], _emptyIncomplete);
    await answer(items[1], _complete);
    expect(matcher.calls, hasLength(3));
    expect(matcher.calls.last.item, items[0]);
    expect(matcher.calls.last.refresh, isTrue);
  });

  test('a card check superseding a running first check inherits the server-online re-check (N3)', () async {
    final item = _item(1);
    final enriched = CatalogItem(
      source: CatalogSourceId.trakt,
      kind: MediaKind.movie,
      title: 'Movie 1',
      ids: const CatalogItemIds(trakt: 1, tmdb: 99),
    );
    availability.setItems([item]);
    final queued = matcher.open.single;
    servers.set(online: ['a', 'b']);
    final future = availability.check(item, enriched: enriched);
    queued.completer.complete(_emptyIncomplete);
    await pumpEventQueue();
    expect(matcher.calls, hasLength(3), reason: 'superseded check does not re-check by itself');
    matcher.callFor(item).completer.complete(_emptyIncomplete);
    matcher.callFor(enriched).completer.complete(_emptyIncomplete);
    await future;
    await pumpEventQueue();
    expect(matcher.calls, hasLength(4));
    expect(matcher.calls.last.item, item);
    expect(matcher.calls.last.refresh, isTrue);
    await answer(item, _emptyIncomplete);
    expect(matcher.calls, hasLength(4), reason: 'flags consumed, no spurious re-check');
  });

  test('a server coming online during a card check re-runs it if it ends incomplete (N3)', () async {
    final item = _item(1);
    availability.setItems([item]);
    await answer(item, _complete);
    final future = availability.check(item, retry: true);
    servers.set(online: ['a', 'b']);
    await pumpEventQueue();
    expect(matcher.calls, hasLength(2), reason: 'no duplicate while the card check runs');
    matcher.calls.last.completer.complete(_emptyIncomplete);
    await future;
    await pumpEventQueue();
    expect(matcher.calls, hasLength(3));
    expect(matcher.calls.last.refresh, isTrue);
  });

  test('a card check replacing a queued refresh job asks with refreshIncomplete (N3)', () async {
    final items = List.generate(4, _item);
    availability.setItems(items);
    await answerAll((_) => _emptyIncomplete);
    servers.set(online: ['a', 'b']);
    await pumpEventQueue();
    expect(matcher.open, hasLength(3));
    final waiting = items.firstWhere((i) => !matcher.open.any((c) => c.item == i));
    final enriched = CatalogItem(
      source: CatalogSourceId.trakt,
      kind: MediaKind.movie,
      title: waiting.title,
      ids: CatalogItemIds(trakt: waiting.ids.trakt, tmdb: 99),
    );
    unawaited(availability.check(waiting, enriched: enriched));
    expect(matcher.callFor(waiting).refresh, isTrue);
    expect(matcher.callFor(enriched).refresh, isTrue);
  });

  test('changed expectedServerIds rechecks every item; the old result shows until replaced', () async {
    final items = List.generate(3, _item);
    final gone = _copy('g', 'b');
    availability.setItems(items);
    await answer(items[0], _emptyIncomplete);
    await answer(items[1], _found([gone]));
    await answer(items[2], _complete);
    expect(matcher.calls, hasLength(3));
    servers.set(expected: ['a']);
    await pumpEventQueue();
    expect(matcher.calls.skip(3).map((c) => c.item), unorderedEquals(items));
    expect(matcher.calls.skip(3).every((c) => c.refresh), isTrue);
    expect((availability.statusOf(items[1]) as TvAvailabilityFound).copies, [gone]);
    await answer(items[1], libraryLookupResult(const [], succeeded: {'a'}));
    expect(availability.statusOf(items[1]), same(TvAvailability.notFound), reason: 'removed server copy gone');
  });

  test('changed expectedServerIds re-runs checks that were running at the change', () async {
    final item = _item(1);
    availability.setItems([item]);
    servers.set(expected: ['a']);
    await pumpEventQueue();
    expect(matcher.calls, hasLength(1));
    await answer(item, _complete);
    expect(matcher.calls, hasLength(2));
  });

  test('reset forgets results, the queue and running checks', () async {
    final items = List.generate(5, _item);
    availability.setItems(items);
    await answer(items[0], _found([_copy('c', 'a')]));
    final revision = availability.foundRevision;
    final watcher = availability.watch(items[0]);
    expect(watcher.value, isA<TvAvailabilityFound>());
    availability.reset();
    expect(availability.statusOf(items[0]), same(TvAvailability.pending));
    expect(watcher.value, same(TvAvailability.pending));
    expect(availability.foundRevision, isNot(revision));
    expect(availability.checking, isFalse);
    // A late answer from before the reset is ignored.
    await answer(items[1], _complete);
    expect(availability.statusOf(items[1]), same(TvAvailability.pending));
    expect(matcher.open, hasLength(2), reason: 'queue cleared, nothing new started');
  });

  test('priority survives setItems', () async {
    final items = List.generate(10, _item);
    availability.setItems(items);
    availability.prioritize([items[8], items[9]]);
    availability.setItems(items.reversed.toList());
    await answer(items[0], _complete);
    await answer(items[1], _complete);
    expect(matcher.calls.skip(3).take(2).map((c) => c.item), [items[8], items[9]]);
  });

  test('watch notifies only for its item; foundRevision moves only on found changes', () async {
    final items = List.generate(2, _item);
    availability.setItems(items);
    var first = 0;
    availability.watch(items[0]).addListener(() => first++);
    final revision = availability.foundRevision;
    await answer(items[1], _complete);
    expect(first, 0);
    expect(availability.foundRevision, revision);
    await answer(items[0], _found([_copy('c', 'a')]));
    expect(first, 1);
    expect(availability.foundRevision, revision + 1);
  });

  test('sectionOpened rechecks only notFound results older than 10 minutes', () async {
    final items = List.generate(3, _item);
    availability.setItems(items.take(2).toList());
    await answer(items[0], _complete);
    await answer(items[1], _found([_copy('c', 'a')]));
    now = now.add(const Duration(minutes: 5));
    availability.setItems(items);
    await answer(items[2], _complete);

    now = now.add(const Duration(minutes: 6));
    availability.sectionOpened();
    await pumpEventQueue();
    expect(matcher.open.map((c) => c.item), [items[0]]);
  });

  test('a check by the enriched form shows on the original item and merges both forms', () async {
    final item = _item(1);
    final enriched = CatalogItem(
      source: CatalogSourceId.trakt,
      kind: MediaKind.movie,
      title: 'Movie 1',
      ids: const CatalogItemIds(trakt: 1, tmdb: 99),
    );
    final a = _copy('a1', 'a');
    final b = _copy('b1', 'b');
    final future = availability.check(item, enriched: enriched);
    matcher.callFor(item).completer.complete(_found([a], complete: false));
    matcher.callFor(enriched).completer.complete(_found([b]));
    final status = await future as TvAvailabilityFound;
    expect(status.copies, unorderedEquals([a, b]));
    final shown = availability.statusOf(item) as TvAvailabilityFound;
    expect(shown.copies, unorderedEquals([a, b]));
  });

  test('setItems during a card check of a never-checked item does not start a duplicate (P3)', () async {
    final item = _item(1);
    final enriched = CatalogItem(
      source: CatalogSourceId.trakt,
      kind: MediaKind.movie,
      title: 'Movie 1',
      ids: const CatalogItemIds(trakt: 1, tmdb: 99),
    );
    final b = _copy('b1', 'b');
    final future = availability.check(item, enriched: enriched);
    final before = matcher.calls.length;
    availability.setItems([item]);
    await pumpEventQueue();
    expect(matcher.calls, hasLength(before), reason: 'no queued duplicate');
    matcher.callFor(item).completer.complete(_complete);
    matcher.callFor(enriched).completer.complete(_found([b]));
    await future;
    expect(availability.statusOf(item), isA<TvAvailabilityFound>());
  });

  test('check returns a known result; retry goes with refreshIncomplete', () async {
    final item = _item(1);
    availability.setItems([item]);
    await answer(item, _emptyIncomplete);
    expect(await availability.check(item), same(TvAvailability.unchecked));
    expect(matcher.calls, hasLength(1));

    final future = availability.check(item, retry: true);
    expect(matcher.calls.last.refresh, isTrue);
    matcher.calls.last.completer.complete(_found([_copy('c', 'a')]));
    expect(await future, isA<TvAvailabilityFound>());
  });

  test('late answers after dispose do not notify', () async {
    final item = _item(1);
    availability.setItems([item]);
    var notified = 0;
    availability.addListener(() => notified++);
    availability.dispose();
    matcher.open.single.completer.complete(_complete);
    await pumpEventQueue();
    expect(notified, 0);
  });
}
