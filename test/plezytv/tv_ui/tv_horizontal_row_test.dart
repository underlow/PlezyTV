import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/plezytv/tv_ui/tv_tokens.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_cards.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_horizontal_row.dart';
import '../../test_helpers/media_items.dart';
import 'tv_theme_test_helper.dart';

void main() {
  for (final reduced in [false, true]) {
    testWidgets('held arrow moves across enabled cards (reduced=$reduced)', (tester) async {
      final nodes = <int, FocusNode>{};
      await pumpTvWidget(
        tester,
        Align(
          alignment: Alignment.topLeft,
          child: TvHorizontalRow(
            title: 'Enabled',
            itemCount: 4,
            cardWidth: TvTokens.size.poster.w.toDouble(),
            cardHeight: TvTokens.size.poster.h + 80.0,
            cardBuilder: (context, index, node) {
              nodes[index] = node;
              return TvPoster(
                item: testMediaItem(title: '$index'),
                focusNode: node,
              );
            },
          ),
        ),
        reduced: reduced,
      );
      nodes[0]!.requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(nodes[1]!.hasFocus, isTrue);
      for (var index = 2; index < 4; index++) {
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
        expect(nodes[index]!.hasFocus, isTrue);
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    });
    for (final opposite in [false, true]) {
      testWidgets(
        'pending seek preserves origin across ${opposite ? "opposite arrow" : "repeats"} (reduced=$reduced)',
        (tester) async {
          final nodes = <int, FocusNode>{};
          await pumpTvWidget(
            tester,
            Align(
              alignment: Alignment.topLeft,
              child: TvHorizontalRow(
                title: 'Sparse',
                itemCount: 40,
                cardWidth: TvTokens.size.poster.w.toDouble(),
                cardHeight: TvTokens.size.poster.h + 80.0,
                cardBuilder: (context, index, node) {
                  nodes[index] = node;
                  return TvPoster(
                    key: ValueKey(index),
                    item: testMediaItem(title: '$index'),
                    focusNode: node,
                    disabled: index != 0,
                  );
                },
              ),
            ),
            reduced: reduced,
          );
          nodes[0]!.requestFocus();
          await tester.pumpAndSettle();
          final scroll = tester.widget<ListView>(find.byType(ListView)).controller!;
          expect(scroll.offset, 0);
          await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
          expect(scroll.offset, greaterThan(0));
          // No frame between these keys: the reveal continuation is pending.
          await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
          await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
          if (opposite) {
            await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
          }
          await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
          await tester.pumpAndSettle();
          expect(scroll.offset, 0);
          expect(nodes[0]!.hasFocus, isTrue);
        },
      );
    }
    for (final origin in [0, 2]) {
      testWidgets('unsuccessful seek restores initial viewport $origin (reduced=$reduced)', (tester) async {
        final nodes = <int, FocusNode>{};
        await pumpTvWidget(
          tester,
          Align(
            alignment: Alignment.topLeft,
            child: TvHorizontalRow(
              title: 'Sparse',
              itemCount: 40,
              cardWidth: TvTokens.size.poster.w.toDouble(),
              cardHeight: TvTokens.size.poster.h + 80.0,
              cardBuilder: (context, index, node) {
                nodes[index] = node;
                return TvPoster(
                  key: ValueKey(index),
                  item: testMediaItem(title: '$index'),
                  focusNode: node,
                  disabled: index != origin,
                );
              },
            ),
          ),
          reduced: reduced,
        );
        nodes[origin]!.requestFocus();
        await tester.pumpAndSettle();
        final scroll = tester.widget<ListView>(find.byType(ListView)).controller!;
        final originalOffset = scroll.offset;
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
        expect(scroll.offset, originalOffset);
        expect(nodes[origin]!.hasFocus, isTrue);
      });
    }
  }

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
            cardWidth: TvTokens.size.poster.w.toDouble(),
            cardHeight: TvTokens.size.poster.h + 80.0,
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
      final card30 = tester.getRect(find.byKey(const ValueKey(30)));
      expect(card30.left, greaterThanOrEqualTo(TvTokens.space.contentLeft));
      expect(card30.right, lessThanOrEqualTo(1920));
      expect(find.byType(TvPoster).evaluate().length, lessThan(25));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(nodes[30]!.hasFocus, isTrue);
      final held = tester.getRect(find.byKey(const ValueKey(30)));
      expect(held.left, card30.left);
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
                cardWidth: TvTokens.size.poster.w.toDouble(),
                cardHeight: TvTokens.size.poster.h + 80.0,
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
      final pitch = (TvTokens.size.poster.w + TvTokens.space.cardGap).toDouble();
      final viewport = 1920.0 - TvTokens.space.contentLeft;
      final slots = ((viewport + TvTokens.space.cardGap) / pitch).floor();
      // The list ends with the content inset before and the safe margin after.
      final maxOffset = 20 * pitch - TvTokens.space.cardGap + TvTokens.space.safeX - viewport;
      final visible = ((1920 - TvTokens.space.contentLeft) / (TvTokens.size.poster.w + TvTokens.space.cardGap)).ceil();
      expect(find.byType(TvPoster).evaluate().length, inInclusiveRange(visible, 16));
      expect(tester.getTopLeft(find.text('Recently added')).dx, TvTokens.space.contentLeft);
      expect(
        tester.getTopLeft(find.byKey(const ValueKey(0))).dy - tester.getBottomLeft(find.text('Recently added')).dy,
        40,
      );
      expect(
        tester.getTopLeft(find.byKey(const ValueKey(1))).dx - tester.getTopLeft(find.byKey(const ValueKey(0))).dx,
        pitch,
      );
      nodes[0]!.requestFocus();
      await tester.pumpAndSettle();
      expect(key.currentState!.focusInside.value, isTrue);
      for (var i = 1; i < slots; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
        expect(nodes[i]!.hasFocus, isTrue);
        expect(scroll.offset, 0);
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      if (reduced) {
        expect(scroll.offset, pitch);
        expect(tester.hasRunningAnimations, isFalse);
      } else {
        expect(scroll.offset, 0);
        await tester.pump(const Duration(milliseconds: 75));
        expect(scroll.offset, greaterThan(0));
        expect(scroll.offset, lessThan(pitch));
        await tester.pump(const Duration(milliseconds: 75));
        expect(scroll.offset, pitch);
      }
      expect(tester.getTopLeft(find.byKey(ValueKey(slots))).dx, TvTokens.space.contentLeft + (slots - 1) * pitch);
      expect(tester.getTopLeft(find.byKey(ValueKey(slots + 1))).dx, TvTokens.space.contentLeft + slots * pitch);
      outside.requestFocus();
      await tester.pumpAndSettle();
      expect(key.currentState!.focusInside.value, isFalse);
      key.currentState!.requestFocus();
      await tester.pumpAndSettle();
      expect(nodes[slots]!.hasFocus, isTrue);
      expect(changes, [true, false, true]);
      for (var i = slots + 1; i < 20; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
        expect(nodes[i]!.hasFocus, isTrue);
        expect(scroll.offset, math.min((i - slots + 1) * pitch, maxOffset));
      }
      expect(tester.getBottomRight(find.byKey(const ValueKey(19))).dx, 1824);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(nodes[19]!.hasFocus, isTrue);
      for (var i = 18; i >= 0; i--) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pumpAndSettle();
        expect(nodes[i]!.hasFocus, isTrue);
        expect(scroll.offset, math.min(i * pitch, maxOffset));
        expect(tester.getTopLeft(find.byKey(ValueKey(i))).dx, greaterThanOrEqualTo(TvTokens.space.contentLeft));
      }
      expect(scroll.offset, 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(nodes[0]!.hasFocus, isTrue);
    });
  }
}
