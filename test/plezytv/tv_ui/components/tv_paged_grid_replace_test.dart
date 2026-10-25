import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_paged_grid.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_paged_source.dart';
import 'package:plezy/plezytv/tv_ui/tv_tokens.dart';
import '../tv_theme_test_helper.dart';

void main() {
  late TvPagedSource<String> source;
  late GlobalKey<TvPagedGridState<String>> key;
  final ranges = <(int, int)>[];
  final played = <int>[];

  List<String> names(int n) => [for (var i = 0; i < n; i++) 'item$i'];

  Future<void> mount(WidgetTester tester, List<String> items) async {
    ranges.clear();
    played.clear();
    source = TvPagedSource<String>(loadPage: (o, n) async => throw StateError('in-memory source must not load'));
    addTearDown(source.dispose);
    source.replaceAll(items, keepFocus: false);
    key = GlobalKey();
    await pumpTvWidget(
      tester,
      TvPagedGrid<String>(
        key: key,
        source: source,
        columns: 6,
        cellWidth: 228,
        cellHeight: 390,
        keyOf: (item) => item,
        onVisibleRangeChanged: ranges.add,
        onPlayPause: played.add,
        itemBuilder: (_, i, item, focused) => Text(item ?? '', key: ValueKey<String>(item ?? '')),
      ),
    );
    key.currentState!.requestFocus();
    await tester.pumpAndSettle();
  }

  Future<void> focus(WidgetTester tester, int index) async {
    await key.currentState!.jumpTo(index);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'TV grid $index');
  }

  String focusedItem() => source[key.currentState!.focusedIndex]!;
  double topOf(WidgetTester tester, String item) => tester.getTopLeft(find.byKey(ValueKey(item))).dy;
  Finder skeleton() => find.byWidgetPredicate((w) => w is ColoredBox && w.color == TvTokens.color.bg.skeleton);

  testWidgets('inserting two items before focus keeps the item and its screen row (A13)', (tester) async {
    await mount(tester, names(120));
    await focus(tester, 40);
    final top = topOf(tester, 'item40');
    source.replaceAll(['new0', 'new1', ...names(120)], keepFocus: true);
    expect(skeleton(), findsNothing);
    await tester.pumpAndSettle();
    expect(focusedItem(), 'item40');
    expect(key.currentState!.focusedIndex, 42);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'TV grid 42');
    expect(topOf(tester, 'item40'), top);
    expect(skeleton(), findsNothing);
  });

  testWidgets('removing the focused item focuses the next; the last focuses the previous (A27)', (tester) async {
    await mount(tester, names(20));
    await focus(tester, 7);
    source.replaceAll(names(20)..remove('item7'), keepFocus: true);
    await tester.pumpAndSettle();
    expect(focusedItem(), 'item8');
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'TV grid 7');
    expect(skeleton(), findsNothing);

    await focus(tester, 18);
    expect(focusedItem(), 'item19');
    source.replaceAll(names(19)..remove('item7'), keepFocus: true);
    await tester.pumpAndSettle();
    expect(focusedItem(), 'item18');
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'TV grid 17');
    expect(skeleton(), findsNothing);
  });

  testWidgets('keepFocus false returns focus and scroll to the start', (tester) async {
    await mount(tester, names(120));
    await focus(tester, 60);
    source.replaceAll(names(120).reversed.toList(), keepFocus: false);
    expect(skeleton(), findsNothing);
    await tester.pumpAndSettle();
    expect(key.currentState!.focusedIndex, 0);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'TV grid 0');
    expect(tester.widget<GridView>(find.byType(GridView)).controller!.offset, 0);
    expect(skeleton(), findsNothing);
  });

  testWidgets('visible range is reported after scrolling', (tester) async {
    await mount(tester, names(120));
    expect(ranges.last.$1, 0);
    final initialLast = ranges.last.$2;
    expect(initialLast, greaterThanOrEqualTo(5));
    await focus(tester, 60);
    final (first, last) = ranges.last;
    expect(first, lessThanOrEqualTo(60));
    expect(last, greaterThanOrEqualTo(60));
    expect(first, greaterThan(0));
    expect(first % 6, 0);
    expect(last - first, initialLast);
  });

  testWidgets('Play/Pause calls onPlayPause with the focused index', (tester) async {
    await mount(tester, names(20));
    await focus(tester, 3);
    await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlayPause);
    await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlay);
    expect(played, [3, 3]);
  });
}
