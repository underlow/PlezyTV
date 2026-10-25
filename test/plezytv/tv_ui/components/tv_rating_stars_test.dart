import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_rating_stars.dart';
import 'package:plezy/plezytv/tv_ui/tv_focusable.dart';
import 'package:plezy/plezytv/tv_ui/tv_tokens.dart';

import '../tv_theme_test_helper.dart';

void main() {
  List<Icon> stars(WidgetTester tester) => List.generate(
    5,
    (i) => tester.widget<Icon>(
      find.descendant(of: find.byKey(ValueKey('tv-rating-star-$i')), matching: find.byType(Icon)),
    ),
  );

  String kinds(WidgetTester tester) => stars(tester).map((icon) {
    if (icon.icon == Symbols.star_half_rounded) return 'h';
    return icon.fill == 1 ? 'f' : 'e';
  }).join();

  Future<void> pumpStars(
    WidgetTester tester, {
    required int value,
    ValueChanged<int>? onChanged,
    ValueChanged<int>? onSubmit,
    FocusNode? focusNode,
  }) async {
    await pumpTvWidget(
      tester,
      Center(
        child: TvRatingStars(
          value: value,
          onChanged: onChanged ?? (_) {},
          onSubmit: onSubmit,
          focusNode: focusNode,
          autofocus: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('values 0..10 draw full, half and empty stars with accent / muted colors', (tester) async {
    const expected = {0: 'eeeee', 1: 'heeee', 2: 'feeee', 3: 'fheee', 5: 'ffhee', 6: 'fffee', 9: 'ffffh', 10: 'fffff'};
    for (final entry in expected.entries) {
      await pumpStars(tester, value: entry.key);
      expect(kinds(tester), entry.value, reason: 'value ${entry.key}');
      for (final icon in stars(tester)) {
        final lit = icon.icon == Symbols.star_half_rounded || icon.fill == 1;
        expect(icon.color, lit ? TvTokens.color.accent.normal : TvTokens.color.text.tertiary);
      }
    }
  });

  testWidgets('left/right step by 1 within 0..10 and report the change', (tester) async {
    final changes = <int>[];
    var value = 0;
    await pumpTvWidget(
      tester,
      Center(
        child: StatefulBuilder(
          builder: (context, setState) => TvRatingStars(
            value: value,
            autofocus: true,
            onChanged: (v) {
              changes.add(v);
              setState(() => value = v);
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(changes, isEmpty);
    for (var i = 0; i < 3; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
    }
    expect(changes, [1, 2, 3]);
    expect(kinds(tester), 'fheee');
    for (var i = 0; i < 9; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
    }
    expect(value, 10);
    expect(changes.last, 10);
    expect(changes.where((v) => v > 10), isEmpty);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(changes.last, 9);
  });

  testWidgets('OK reports submit with the current value', (tester) async {
    final submits = <int>[];
    await pumpStars(tester, value: 7, onSubmit: submits.add);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(submits, [7]);
  });

  testWidgets('focus draws a white ring around the row and scales 1.05; stars have no pads', (tester) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    await pumpStars(tester, value: 4, focusNode: node);
    expect(node.hasFocus, isTrue);
    final rowRect = tester.getRect(find.byType(Row));
    final rings = tester
        .widgetList<DecoratedBox>(find.descendant(of: find.byType(TvRatingStars), matching: find.byType(DecoratedBox)))
        .map((b) => b.decoration)
        .whereType<BoxDecoration>()
        .where((d) => d.border != null)
        .toList();
    expect(rings, hasLength(1));
    expect((rings.single.border! as Border).top.color, TvTokens.color.focus.ring);
    final ringBox = find.descendant(
      of: find.byType(TvRatingStars),
      matching: find.byWidgetPredicate(
        (w) => w is DecoratedBox && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).border != null,
      ),
    );
    final ringRect = tester.getRect(ringBox);
    expect(ringRect.left, lessThan(rowRect.left));
    expect(ringRect.right, greaterThan(rowRect.right));
    // No filled pads anywhere inside the control.
    final fills = tester
        .widgetList<DecoratedBox>(find.descendant(of: find.byType(TvRatingStars), matching: find.byType(DecoratedBox)))
        .map((b) => b.decoration)
        .whereType<BoxDecoration>()
        .where((d) => d.color != null);
    expect(fills, isEmpty);
    expect(
      find.descendant(
        of: find.byType(TvRatingStars),
        matching: find.byWidgetPredicate((w) => w is Container || w is ColoredBox || w is Material),
      ),
      findsNothing,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('tv-rating-star-0'))),
      Size.square(TvTokens.player.postplay.star.toDouble()),
    );
    // Painted scale itself is covered by tv_focusable_test; here the row must request ×1.05 with a ring.
    final visual = tester.widget<TvFocusVisual>(find.byType(TvFocusVisual));
    expect(visual.state.focused, isTrue);
    expect(visual.kind, TvFocusKind.ring);
    expect(visual.focusedScale, TvTokens.focus.buttonScale);
  });

  testWidgets('up/down are not consumed so focus can leave the row', (tester) async {
    final reached = <LogicalKeyboardKey>[];
    final changes = <int>[];
    await pumpTvWidget(
      tester,
      Focus(
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) reached.add(event.logicalKey);
          return KeyEventResult.ignored;
        },
        child: Center(child: TvRatingStars(value: 2, onChanged: changes.add, autofocus: true)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(reached, [LogicalKeyboardKey.arrowDown, LogicalKeyboardKey.arrowUp]);
    expect(changes, [3]);
  });
}
