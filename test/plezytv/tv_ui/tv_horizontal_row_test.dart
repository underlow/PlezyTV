import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_cards.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_horizontal_row.dart';
import '../../test_helpers/media_items.dart';
import 'tv_theme_test_helper.dart';

void main() {
  for (final reduced in [false, true]) {
    testWidgets('disabled run beyond lazy boundary (reduced=$reduced)', (tester) async {
      final nodes = <int, FocusNode>{};
      await pumpTvWidget(
        tester,
        Align(
          alignment: Alignment.topLeft,
          child: TvHorizontalRow(
            title: 'Sparse',
            itemCount: 40,
            cardWidth: 216,
            cardHeight: 404,
            cardBuilder: (context, index, node) {
              nodes[index] = node;
              return TvPoster(
                key: ValueKey(index),
                item: testMediaItem(title: '$index'),
                focusNode: node,
                disabled: index != 0 && index != 30,
              );
            },
          ),
        ),
        reduced: reduced,
      );
      expect(find.byType(TvPoster).evaluate().length, lessThan(20));
      nodes[0]!.requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(nodes[30]?.hasFocus, isTrue);
      expect(tester.getTopLeft(find.byKey(const ValueKey(30))).dx, 200);
      expect(find.byType(TvPoster).evaluate().length, lessThan(25));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(nodes[30]!.hasFocus, isTrue);
      expect(tester.getTopLeft(find.byKey(const ValueKey(30))).dx, 200);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(nodes[0]!.hasFocus, isTrue);
      expect(tester.widget<ListView>(find.byType(ListView)).controller!.offset, 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(nodes[0]!.hasFocus, isTrue);
    });
  }

  for (final reduced in [false, true]) {
    testWidgets('A7 lazy rail, geometry, memory and scroll timing (reduced=$reduced)', (tester) async {
      final key = GlobalKey<TvHorizontalRowState>();
      final outside = FocusNode();
      addTearDown(outside.dispose);
      final nodes = <int, FocusNode>{};
      final changes = <bool>[];
      await pumpTvWidget(
        tester,
        Align(
          alignment: Alignment.topLeft,
          child: Column(
            children: [
              Focus(focusNode: outside, child: const SizedBox(height: 50)),
              TvHorizontalRow(
                key: key,
                title: 'Recently added',
                counter: '20',
                itemCount: 20,
                cardWidth: 216,
                cardHeight: 404,
                onFocusInsideChanged: changes.add,
                cardBuilder: (context, index, node) {
                  nodes[index] = node;
                  return TvPoster(
                    key: ValueKey(index),
                    item: testMediaItem(title: 'Card $index'),
                    focusNode: node,
                  );
                },
              ),
            ],
          ),
        ),
        reduced: reduced,
      );
      final scroll = tester.widget<ListView>(find.byType(ListView)).controller!;
      expect(find.byType(TvPoster).evaluate().length, inInclusiveRange(8, 16));
      expect(tester.getTopLeft(find.text('Recently added')).dx, 200);
      expect(
        tester.getTopLeft(find.byKey(const ValueKey(0))).dy - tester.getBottomLeft(find.text('Recently added')).dy,
        40,
      );
      expect(
        tester.getTopLeft(find.byKey(const ValueKey(1))).dx - tester.getTopLeft(find.byKey(const ValueKey(0))).dx,
        240,
      );
      nodes[0]!.requestFocus();
      await tester.pumpAndSettle();
      expect(key.currentState!.focusInside.value, isTrue);
      for (var i = 1; i <= 6; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
        expect(nodes[i]!.hasFocus, isTrue);
        expect(scroll.offset, 0);
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      if (reduced) {
        expect(scroll.offset, 1680);
        expect(tester.hasRunningAnimations, isFalse);
      } else {
        expect(scroll.offset, 0);
        await tester.pump(const Duration(milliseconds: 75));
        expect(scroll.offset, greaterThan(0));
        expect(scroll.offset, lessThan(1680));
        await tester.pump(const Duration(milliseconds: 75));
        expect(scroll.offset, 1680);
      }
      expect(tester.getTopLeft(find.byKey(const ValueKey(7))).dx, 200);
      outside.requestFocus();
      await tester.pumpAndSettle();
      expect(key.currentState!.focusInside.value, isFalse);
      key.currentState!.requestFocus();
      await tester.pumpAndSettle();
      expect(nodes[7]!.hasFocus, isTrue);
      expect(changes, [true, false, true]);
      for (var i = 8; i < 20; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
        expect(nodes[i]!.hasFocus, isTrue);
        expect(tester.getTopLeft(find.byKey(ValueKey(i))).dx, 200);
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(nodes[19]!.hasFocus, isTrue);
      for (var i = 18; i >= 0; i--) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pumpAndSettle();
        expect(nodes[i]!.hasFocus, isTrue);
        expect(scroll.offset, i * 240);
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(nodes[0]!.hasFocus, isTrue);
    });
  }
}
