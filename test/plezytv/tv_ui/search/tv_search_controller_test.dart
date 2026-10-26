import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/ids.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_person.dart';
import 'package:plezy/plezytv/tv_ui/search/tv_search_controller.dart';
import 'package:plezy/services/data_aggregation_service.dart';
import 'package:plezy/utils/media_server_http_client.dart';

MediaItem item(String id, MediaKind kind, {String? title}) =>
    MediaItem(id: id, backend: MediaBackend.plex, kind: kind, title: title ?? 'Дюна $id', serverId: 's1');

MediaPerson person(String id) =>
    MediaPerson(id: id, name: 'Дюн $id', backend: MediaBackend.plex, serverId: ServerId('s1'));

SearchAggregationResult result({
  List<MediaItem> items = const [],
  List<MediaPerson> people = const [],
  Set<String> succeeded = const {'s1'},
  Set<String> failed = const {},
  Set<String> cancelled = const {},
}) => (
  hits: const [],
  candidates: items,
  people: people,
  succeededServerIds: succeeded,
  cancelledServerIds: cancelled,
  failedServerIds: failed,
);

class FakeSearch {
  final calls = <String>[];
  final aborts = <AbortController>[];
  final pending = <String, Completer<SearchAggregationResult>>{};

  Future<SearchAggregationResult> call(String query, AbortController abort) {
    calls.add(query);
    aborts.add(abort);
    return (pending[query] = Completer()).future;
  }

  void answer(String query, SearchAggregationResult r) => pending[query]!.complete(r);
  void fail(String query, Object e) => pending[query]!.completeError(e);
}

void main() {
  late FakeSearch search;
  MediaItem? fetched;
  TvSearchController make() => TvSearchController(search: search.call, fetchItem: (_) async => fetched);

  setUp(() {
    search = FakeSearch();
    fetched = null;
  });

  test('debounce: one call for the last query 300 ms after typing stops', () {
    fakeAsync((async) {
      final c = make();
      c.setQuery('д');
      async.elapse(const Duration(milliseconds: 100));
      c.setQuery('дю');
      async.elapse(const Duration(milliseconds: 100));
      c.setQuery('дюн');
      async.elapse(const Duration(milliseconds: 299));
      expect(search.calls, isEmpty);
      async.elapse(const Duration(milliseconds: 1));
      expect(search.calls, ['дюн']);
      async.elapse(const Duration(seconds: 1));
      expect(search.calls, ['дюн']);
      c.dispose();
    });
  });

  test('a stale answer is dropped and its request aborted', () {
    fakeAsync((async) {
      final c = make();
      c.setQuery('д');
      c.searchNow();
      c.setQuery('дюн');
      c.searchNow();
      expect(search.aborts.first.isAborted, isTrue);
      search.answer('дюн', result(items: [item('1', MediaKind.movie)]));
      async.flushMicrotasks();
      search.answer('д', result(items: [item('2', MediaKind.show)]));
      async.flushMicrotasks();
      expect(c.shownQuery, 'дюн');
      expect(c.countOf(TvSearchKind.movies), 1);
      expect(c.countOf(TvSearchKind.shows), 0);
      c.dispose();
    });
  });

  test('empty query goes idle at once and cancels the search', () {
    fakeAsync((async) {
      final c = make()..setQuery('дюн');
      c.searchNow();
      c.setQuery('');
      expect(c.state, TvSearchState.idle);
      expect(search.aborts.single.isAborted, isTrue);
      search.answer('дюн', result(items: [item('1', MediaKind.movie)]));
      async.flushMicrotasks();
      expect(c.state, TvSearchState.idle);
      c.searchNow();
      expect(search.calls, ['дюн']);
      c.dispose();
    });
  });

  test('only albums and tracks is empty; only people is results with a people tab', () {
    fakeAsync((async) {
      final c = make()..setQuery('дюн');
      c.searchNow();
      search.answer('дюн', result(items: [item('1', MediaKind.album), item('2', MediaKind.track)]));
      async.flushMicrotasks();
      expect(c.state, TvSearchState.empty);
      expect(c.tabs, isEmpty);

      c.setQuery('дюна');
      c.searchNow();
      search.answer('дюна', result(people: [person('p')]));
      async.flushMicrotasks();
      expect(c.state, TvSearchState.results);
      expect(c.tabs, [TvSearchTab.all, TvSearchTab.people]);
      c.dispose();
    });
  });

  test('movies tab survives with movies and falls back to all without', () {
    fakeAsync((async) {
      final c = make()..setQuery('дюна');
      c.searchNow();
      search.answer('дюна', result(items: [item('1', MediaKind.movie), item('2', MediaKind.show)]));
      async.flushMicrotasks();
      c.selectTab(TvSearchTab.movies);
      expect(c.selectedTab, TvSearchTab.movies);

      c.setQuery('дюн');
      c.searchNow();
      search.answer('дюн', result(items: [item('3', MediaKind.movie)]));
      async.flushMicrotasks();
      expect(c.selectedTab, TvSearchTab.movies);

      c.setQuery('д');
      c.searchNow();
      search.answer('д', result(items: [item('2', MediaKind.show)]));
      async.flushMicrotasks();
      expect(c.selectedTab, TvSearchTab.all);
      c.dispose();
    });
  });

  test('unavailable: no servers, all failed, other errors; partial failure bumps revision', () {
    fakeAsync((async) {
      final c = make()..setQuery('a');
      c.searchNow();
      search.fail('a', const TvSearchUnavailable());
      async.flushMicrotasks();
      expect(c.state, TvSearchState.unavailable);
      expect(c.errorMessage, isNotNull);

      c.setQuery('b');
      c.searchNow();
      search.answer('b', result(succeeded: const {}, failed: const {'s1', 's2'}));
      async.flushMicrotasks();
      expect(c.state, TvSearchState.unavailable);

      c.setQuery('c');
      c.searchNow();
      search.answer('c', result(succeeded: const {}, cancelled: const {'s1'}));
      async.flushMicrotasks();
      expect(c.state, TvSearchState.unavailable);

      c.setQuery('d');
      c.searchNow();
      search.fail('d', StateError('boom'));
      async.flushMicrotasks();
      expect(c.state, TvSearchState.unavailable);

      expect(c.partialFailureRevision, 0);
      c.setQuery('дюна');
      c.searchNow();
      search.answer('дюна', result(items: [item('1', MediaKind.movie)], failed: const {'s2'}));
      async.flushMicrotasks();
      expect(c.state, TvSearchState.results);
      expect(c.partialFailureRevision, 1);
      c.searchNow();
      search.answer('дюна', result(items: [item('1', MediaKind.movie)], failed: const {'s2'}));
      async.flushMicrotasks();
      expect(c.partialFailureRevision, 2);
      c.dispose();
    });
  });

  test('skeleton appears only after 300 ms without an answer', () {
    fakeAsync((async) {
      final c = make()..setQuery('дюн');
      c.searchNow();
      expect(c.state, TvSearchState.loading);
      async.elapse(const Duration(milliseconds: 200));
      expect(c.showSkeleton, isFalse);
      async.elapse(const Duration(milliseconds: 150));
      expect(c.showSkeleton, isTrue);
      search.answer('дюн', result(items: [item('1', MediaKind.movie)]));
      async.flushMicrotasks();
      expect(c.showSkeleton, isFalse);
      c.dispose();
    });
  });

  test('refining keeps previous results without a skeleton', () {
    fakeAsync((async) {
      final c = make()..setQuery('дюн');
      c.searchNow();
      search.answer('дюн', result(items: [item('1', MediaKind.movie)]));
      async.flushMicrotasks();

      c.setQuery('дюна');
      c.searchNow();
      async.elapse(const Duration(milliseconds: 400));
      expect(c.state, TvSearchState.results);
      expect(c.refining, isTrue);
      expect(c.showSkeleton, isFalse);
      expect(c.countOf(TvSearchKind.movies), 1);
      expect(c.shownQuery, 'дюн');
      search.answer('дюна', result(items: [item('1', MediaKind.movie), item('2', MediaKind.movie)]));
      async.flushMicrotasks();
      expect(c.refining, isFalse);
      expect(c.shownQuery, 'дюна');
      c.dispose();
    });
  });

  test('countOf equals the tab grid length; rowOf is at most 20', () {
    fakeAsync((async) {
      final c = make()..setQuery('дюна');
      c.searchNow();
      search.answer('дюна', result(items: [for (var i = 0; i < 30; i++) item('$i', MediaKind.movie)]));
      async.flushMicrotasks();
      expect(c.countOf(TvSearchKind.movies), c.allOf(TvSearchKind.movies).length);
      expect(c.countOf(TvSearchKind.movies), 30);
      expect(c.rowOf(TvSearchKind.movies).length, 20);
      expect(c.rowOf(TvSearchKind.movies), c.allOf(TvSearchKind.movies).take(20).toList());
      c.dispose();
    });
  });

  test('refreshItem replaces the item in the row and the tab', () {
    fakeAsync((async) {
      final c = make()..setQuery('дюна');
      c.searchNow();
      final original = item('1', MediaKind.movie);
      search.answer('дюна', result(items: [original]));
      async.flushMicrotasks();
      fetched = original.copyWith(title: 'Дюна обновлённая');
      c.refreshItem(original);
      async.flushMicrotasks();
      expect(identical(c.rowOf(TvSearchKind.movies).single, fetched), isTrue);
      expect(identical(c.allOf(TvSearchKind.movies).single, fetched), isTrue);
      c.dispose();
    });
  });

  test('clear resets results and the tab', () {
    fakeAsync((async) {
      final c = make()..setQuery('дюна');
      c.searchNow();
      search.answer('дюна', result(items: [item('1', MediaKind.movie)]));
      async.flushMicrotasks();
      c.selectTab(TvSearchTab.movies);
      c.clear();
      expect(c.query, '');
      expect(c.state, TvSearchState.idle);
      expect(c.selectedTab, TvSearchTab.all);
      expect(c.countOf(TvSearchKind.movies), 0);
      c.dispose();
    });
  });
}
