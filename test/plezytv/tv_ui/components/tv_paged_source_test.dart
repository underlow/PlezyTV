import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_paged_source.dart';

void main() {
  test('old generation is discarded and concurrent requests coalesce', () async {
    final pending = <Completer<TvPage<int>>>[];
    final source = TvPagedSource<int>(
      loadPage: (_, _) {
        final c = Completer<TvPage<int>>();
        pending.add(c);
        return c.future;
      },
    );
    final old = source.requestIndex(0);
    expect(identical(old, source.requestIndex(1)), isTrue);
    source.reset();
    final next = source.requestIndex(0);
    pending[1].complete(const TvPage([2], 1));
    await next;
    pending[0].complete(const TvPage([1], 1));
    await old;
    expect(source[0], 2);
    source.dispose();
  });
  test('synchronous loader failures retry and page signals stay local', () async {
    var fail = true;
    final source = TvPagedSource<int>(
      pageSize: 2,
      loadPage: (offset, limit) {
        if (fail) throw StateError('sync failure');
        return Future.value(TvPage([offset, offset + 1], 10));
      },
    );
    var first = 0, second = 0;
    source.pageListenable(0).addListener(() => first++);
    source.pageListenable(2).addListener(() => second++);
    await source.requestIndex(0);
    fail = false;
    await source.requestIndex(0);
    expect(source[0], 0);
    expect(first, 2);
    expect(second, 0);
    await source.requestIndex(2);
    source.update(0, 99);
    expect(first, 3);
    expect(second, 1);
    source.dispose();
  });
  test('failed page retries on next request', () async {
    var calls = 0;
    final source = TvPagedSource<int>(
      loadPage: (_, _) async {
        if (++calls == 1) throw StateError('offline');
        return const TvPage([1], 1);
      },
    );
    await source.requestIndex(0);
    expect(source.errors, isNotEmpty);
    await source.requestIndex(0);
    expect(source.errors, isEmpty);
    expect(source[0], 1);
    source.dispose();
  });
  test('remove shifts sparse cache and reloads subsequent pages', () async {
    final values = List.generate(12, (i) => i);
    final calls = <int>[];
    final source = TvPagedSource<int>(
      pageSize: 3,
      loadPage: (offset, limit) async {
        calls.add(offset);
        return TvPage(values.skip(offset).take(limit).toList(), values.length);
      },
    );
    await source.requestIndex(0);
    await source.requestIndex(6);
    values.removeAt(1);
    source.removeAt(1);
    expect(source.totalCount, 11);
    expect(source[1], 2);
    expect(source[5], 6);
    await source.requestIndex(6);
    expect(source[6], 7);
    expect(calls, [0, 6, 6]);
    source.dispose();
  });
  test('refresh retains cache while loading and anchors by id locally', () async {
    var values = List.generate(3000, (i) => i);
    final calls = <int>[];
    final source = TvPagedSource<int>(
      pageSize: 10,
      loadPage: (offset, limit) async {
        calls.add(offset);
        return TvPage(values.skip(offset).take(limit).toList(), values.length);
      },
    );
    await source.requestIndex(2500);
    values = [-1, ...values];
    final refresh = source.refresh(anchorIndex: 2500, idOf: (i) => i);
    expect(source[2500], 2500);
    expect(await refresh, 2501);
    expect(calls, [2500, 2490, 2500, 2510]);
    source.dispose();
  });
}
