import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_paged_source.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_paged_grid.dart';
import '../tv_theme_test_helper.dart';

void main() {
  testWidgets('focus overflow is visible on all grid edges, scrolling remains bounded', (tester) async {
    final source = TvPagedSource<int>(loadPage: (o, n) async => const TvPage([0, 1, 2, 3, 4, 5], 6));
    addTearDown(source.dispose);
    await source.requestIndex(0);
    await pumpTvWidget(
      tester,
      TvPagedGrid<int>(
        source: source,
        columns: 6,
        cellWidth: 228,
        cellHeight: 390,
        itemBuilder: (_, i, item, focused) => Text('$i'),
      ),
    );
    final grid = find.byType(GridView);
    expect(tester.widget<GridView>(grid).clipBehavior, Clip.none);
    final clip = tester.widget<ClipRect>(find.ancestor(of: grid, matching: find.byType(ClipRect)).first);
    final bounds = clip.clipper!.getClip(const Size(1488, 800));
    expect(bounds.contains(const Offset(-20, -20)), isTrue);
    expect(bounds.contains(const Offset(1508, 820)), isTrue);
    expect(bounds.contains(const Offset(0, -30)), isFalse);
  });

  testWidgets('3000 slots: held down retains focus; sparse jump waits for load', (tester) async {
    final calls = <int>[];
    final destination = Completer<TvPage<int>>();
    final nextPage = Completer<TvPage<int>>();
    final source = TvPagedSource<int>(
      loadPage: (offset, limit) async {
        calls.add(offset);
        if (offset == 60) return nextPage.future;
        if (offset == 2460) return destination.future;
        return TvPage(List.generate(limit, (i) => offset + i), 3000);
      },
    );
    await source.requestIndex(0);
    final key = GlobalKey<TvPagedGridState<int>>();
    await pumpTvWidget(
      tester,
      TvPagedGrid<int>(
        key: key,
        source: source,
        columns: 6,
        cellWidth: 228,
        cellHeight: 390,
        itemBuilder: (_, index, item, focused) =>
            ColoredBox(color: focused ? Colors.white : Colors.grey, child: Text('$index')),
      ),
    );
    key.currentState!.requestFocus();
    await tester.pump();
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'TV grid 0');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'TV grid 6');
    for (var i = 0; i < 80; i++) {
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.pump();
      final expected = (i + 2) * 6;
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'TV grid $expected');
      expect(key.currentState!.focusedIndex, expected);
      if (expected == 78) {
        expect(source[expected], isNull);
        final node = FocusManager.instance.primaryFocus;
        nextPage.complete(TvPage(List.generate(60, (i) => 60 + i), 3000));
        await tester.pump();
        await tester.pump();
        expect(source[expected], expected);
        expect(FocusManager.instance.primaryFocus, same(node));
        expect(key.currentState!.focusedIndex, expected);
      }
    }
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
    final previous = FocusManager.instance.primaryFocus;
    final jumping = key.currentState!.jumpTo(2500);
    await tester.pump();
    await tester.pump();
    expect(FocusManager.instance.primaryFocus, previous);
    destination.complete(TvPage(List.generate(60, (i) => 2460 + i), 3000));
    await jumping;
    await tester.pump();
    await tester.pump();
    expect(key.currentState!.focusedIndex, 2500);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'TV grid 2500');
    expect(calls.length, lessThan(20));
    expect(calls.where((offset) => offset > 600 && offset < 2400), isEmpty);
    await tester.pumpWidget(const SizedBox());
    source.dispose();
  });
  testWidgets('page updates rebuild only their cells; stale visible page reloads', (tester) async {
    final builds = <int, int>{};
    var version = 0;
    final source = TvPagedSource<int>(
      pageSize: 6,
      loadPage: (o, n) async => TvPage(List.generate(n, (i) => o + i + version), 3000),
    );
    await source.requestIndex(0);
    await source.requestIndex(6);
    await pumpTvWidget(
      tester,
      TvPagedGrid<int>(
        source: source,
        columns: 6,
        cellWidth: 228,
        cellHeight: 390,
        itemBuilder: (_, i, item, focused) {
          builds[i] = (builds[i] ?? 0) + 1;
          return Text('$item');
        },
      ),
    );
    await tester.pump();
    final secondPage = builds[6];
    final firstPage = builds[0]!;
    source.update(0, 999);
    await tester.pump();
    expect(builds[0], greaterThan(firstPage));
    expect(builds[6], secondPage);
    version = 100;
    source.markStale(0);
    await tester.pump();
    await tester.pump();
    expect(source[0], 100);
    expect(builds[6], secondPage);
    await tester.pumpWidget(const SizedBox());
    source.dispose();
  });
  testWidgets('a newer jump cancels the older pending focus', (tester) async {
    final pending = Completer<TvPage<int>>();
    final source = TvPagedSource<int>(
      loadPage: (o, n) async => o == 2460 ? pending.future : TvPage(List.generate(n, (i) => o + i), 3000),
    );
    await source.requestIndex(0);
    final key = GlobalKey<TvPagedGridState<int>>();
    await pumpTvWidget(
      tester,
      TvPagedGrid<int>(
        key: key,
        source: source,
        columns: 6,
        cellWidth: 228,
        cellHeight: 390,
        itemBuilder: (_, i, item, focused) => Text('$i'),
      ),
    );
    final old = key.currentState!.jumpTo(2500);
    await tester.pump();
    await key.currentState!.jumpTo(12);
    await tester.pump();
    await tester.pump();
    pending.complete(TvPage(List.generate(60, (i) => 2460 + i), 3000));
    await old;
    await tester.pump();
    expect(key.currentState!.focusedIndex, 12);
    await tester.pumpWidget(const SizedBox());
    source.dispose();
  });
}
