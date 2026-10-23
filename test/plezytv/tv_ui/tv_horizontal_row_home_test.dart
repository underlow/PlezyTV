import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_cards.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_horizontal_row.dart';
import '../../test_helpers/media_items.dart';
import 'tv_theme_test_helper.dart';

void main() {
  for (final keyed in [false, true]) {
    testWidgets('row start reports status and left bubbles (keyed=$keyed)', (tester) async {
      final row = GlobalKey<TvHorizontalRowState>();
      final nodes = <int, FocusNode>{};
      var left = 0;
      await pumpTvWidget(
        tester,
        Align(
          alignment: Alignment.topLeft,
          child: Focus(
            onKeyEvent: (_, event) {
              if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                if (event is KeyDownEvent) left++;
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: TvHorizontalRow(
              key: row,
              title: 'Row',
              itemCount: 100,
              cardWidth: 216,
              cardHeight: 398,
              itemKey: keyed ? (i) => '$i' : null,
              cardBuilder: (_, i, node) {
                nodes[i] = node;
                return TvPoster(
                  item: testMediaItem(id: '$i'),
                  focusNode: node,
                );
              },
            ),
          ),
        ),
        reduced: true,
      );
      expect(nodes.length, lessThan(20));
      nodes[0]!.requestFocus();
      await tester.pumpAndSettle();
      expect(row.currentState!.focusStart(), isTrue);
      for (var i = 0; i < 15; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
      }
      expect(row.currentState!.focusedIndex, 15);
      expect(row.currentState!.focusStart(), isFalse);
      await tester.pumpAndSettle();
      expect(nodes[0]!.hasFocus, isTrue);
      expect(row.currentState!.focusStart(), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(left, 1);
    });
  }

  testWidgets('key memory survives lazy reorder, removal and outside refresh', (tester) async {
    final row = GlobalKey<TvHorizontalRowState>();
    final outside = FocusNode();
    addTearDown(outside.dispose);
    final data = ValueNotifier([for (var i = 0; i < 100; i++) '$i']);
    addTearDown(data.dispose);
    final nodes = <String, FocusNode>{};
    final focused = <String>[];
    await pumpTvWidget(
      tester,
      Align(
        alignment: Alignment.topLeft,
        child: Column(
          children: [
            Focus(focusNode: outside, child: const SizedBox(height: 20)),
            ValueListenableBuilder<List<String>>(
              valueListenable: data,
              builder: (_, ids, _) => TvHorizontalRow(
                key: row,
                title: 'Row',
                itemCount: ids.length,
                itemKey: (i) => ids[i],
                onItemFocused: (i) => focused.add(ids[i]),
                cardWidth: 216,
                cardHeight: 398,
                cardBuilder: (_, i, node) {
                  nodes[ids[i]] = node;
                  return TvPoster(
                    item: testMediaItem(id: ids[i]),
                    focusNode: node,
                  );
                },
              ),
            ),
          ],
        ),
      ),
      reduced: true,
    );
    nodes['0']!.requestFocus();
    await tester.pumpAndSettle();
    for (var i = 0; i < 15; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
    }
    data.value = [...data.value.where((id) => id != '15'), '15'];
    await tester.pumpAndSettle();
    expect(nodes['15']!.hasFocus, isTrue);
    expect(row.currentState!.focusedIndex, 99);
    expect(focused.last, '15');
    data.value = data.value.where((id) => id != '15').toList();
    await tester.pumpAndSettle();
    expect(nodes['99']!.hasFocus, isTrue);
    expect(focused.last, '99');
    outside.requestFocus();
    await tester.pumpAndSettle();
    data.value = data.value.reversed.toList();
    await tester.pumpAndSettle();
    expect(outside.hasFocus, isTrue);
    row.currentState!.requestFocus();
    await tester.pumpAndSettle();
    expect(nodes['99']!.hasFocus, isTrue);
    expect(row.currentState!.focusedIndex, 0);
  });
}
