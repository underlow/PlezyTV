import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/plezytv/tv_ui/search/tv_search_keyboard.dart';

import '../tv_theme_test_helper.dart';

class _Log {
  final inputs = <String>[];
  final layouts = <TvSearchKeyboardLayout>[];
  int backspaces = 0, clears = 0, exitsLeft = 0, exitsRight = 0;
  bool rightLeaves = false;
}

final _keyboardKey = GlobalKey<TvSearchKeyboardState>();

Future<_Log> _pump(WidgetTester tester, {TvSearchKeyboardLayout layout = TvSearchKeyboardLayout.ru}) async {
  final log = _Log();
  var current = layout;
  await pumpTvWidget(
    tester,
    Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: StatefulBuilder(
          builder: (context, setState) => TvSearchKeyboard(
            key: _keyboardKey,
            layout: current,
            onLayoutChanged: (value) {
              log.layouts.add(value);
              setState(() => current = value);
            },
            onInput: log.inputs.add,
            onBackspace: () => log.backspaces++,
            onClear: () => log.clears++,
            onExitLeft: () => log.exitsLeft++,
            onExitRight: () {
              log.exitsRight++;
              return log.rightLeaves;
            },
          ),
        ),
      ),
    ),
  );
  _keyboardKey.currentState!.focusFirstKey();
  await tester.pumpAndSettle();
  return log;
}

Finder _key(String id) => find.byKey(ValueKey('tv-search-key-$id'));

bool _focused(WidgetTester tester, String id) =>
    Focus.of(tester.element(find.descendant(of: _key(id), matching: find.byType(Semantics)).first)).hasFocus;

Future<void> _press(WidgetTester tester, LogicalKeyboardKey key, [int times = 1]) async {
  for (var i = 0; i < times; i++) {
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }
}

/// Moves focus to [id] by arrows from the first key of the layout.
Future<void> _goTo(WidgetTester tester, int row, int col) async {
  _keyboardKey.currentState!.focusFirstKey();
  await tester.pumpAndSettle();
  await _press(tester, LogicalKeyboardKey.arrowDown, row);
  await _press(tester, LogicalKeyboardKey.arrowRight, col);
}

void main() {
  testWidgets('RU layout: 33 letters, dash, 0–9, service keys and switcher', (tester) async {
    await _pump(tester);
    const letters = 'абвгдеёжзийклмнопрстуфхцчшщъыьэюя';
    expect(letters.length, 33);
    for (final c in letters.split('')) {
      expect(_key('char:$c'), findsOneWidget, reason: c);
    }
    for (final id in ['char:-', 'toDigits', 'space', 'backspace', 'clear', 'layout:ru', 'layout:en', 'layout:digits']) {
      expect(_key(id), findsOneWidget, reason: id);
    }
    expect(find.byKey(const ValueKey('tv-search-layout-selected')), findsOneWidget);
    expect(_focused(tester, 'char:а'), isTrue);
  });

  testWidgets('OK on Д inputs д; 0–9 switches to 123', (tester) async {
    final log = await _pump(tester);
    await _goTo(tester, 0, 4);
    expect(_focused(tester, 'char:д'), isTrue);
    await _press(tester, LogicalKeyboardKey.select);
    expect(log.inputs, ['д']);

    await _goTo(tester, 5, 4); // Э Ю Я - [empty] 0–9: the empty cell is skipped.
    expect(_focused(tester, 'toDigits'), isTrue);
    await _press(tester, LogicalKeyboardKey.select);
    expect(log.layouts, [TvSearchKeyboardLayout.digits]);
    expect(_key('char:1'), findsOneWidget);
    expect(_key('char:а'), findsNothing);
    expect(_keyboardKey.currentState!.hasFocus, isTrue);
  });

  testWidgets('right from the right column and left from the left column exit', (tester) async {
    final log = await _pump(tester);
    await _press(tester, LogicalKeyboardKey.arrowLeft);
    expect(log.exitsLeft, 1);
    await _press(tester, LogicalKeyboardKey.arrowRight, 5);
    expect(_focused(tester, 'char:е'), isTrue);
    expect(log.exitsRight, 0);
    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(log.exitsRight, 1);
    expect(_focused(tester, 'char:е'), isTrue, reason: 'focus stays when onExitRight returns false');

    // Wide keys: right from Clear exits too.
    await _goTo(tester, 6, 2);
    expect(_focused(tester, 'clear'), isTrue);
    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(log.exitsRight, 2);
  });

  testWidgets('empty cells are skipped in ENG layout', (tester) async {
    await _pump(tester, layout: TvSearchKeyboardLayout.en);
    await _goTo(tester, 4, 2);
    expect(_focused(tester, 'char:-'), isTrue);
    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(_focused(tester, 'toDigits'), isTrue);
    await _press(tester, LogicalKeyboardKey.arrowLeft);
    expect(_focused(tester, 'char:-'), isTrue);
    // Down from W (col 4) skips the empty cell of the last letter row.
    await _goTo(tester, 3, 4);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(_focused(tester, 'clear'), isTrue);
  });

  testWidgets('focusLastKey returns to the last pressed key, else the first key', (tester) async {
    await _pump(tester);
    await _goTo(tester, 2, 5);
    _keyboardKey.currentState!.focusLastKey();
    await tester.pumpAndSettle();
    expect(_focused(tester, 'char:а'), isTrue, reason: 'nothing pressed yet');

    await _goTo(tester, 2, 2);
    expect(_focused(tester, 'char:н'), isTrue);
    await _press(tester, LogicalKeyboardKey.select);
    FocusManager.instance.primaryFocus!.unfocus();
    await tester.pumpAndSettle();
    expect(_keyboardKey.currentState!.hasFocus, isFalse);
    _keyboardKey.currentState!.focusLastKey();
    await tester.pumpAndSettle();
    expect(_focused(tester, 'char:н'), isTrue);
  });

  testWidgets('holding backspace repeats; Clear calls onClear', (tester) async {
    final log = await _pump(tester);
    await _goTo(tester, 6, 1);
    expect(_focused(tester, 'backspace'), isTrue);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.select);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.select);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(log.backspaces, 3);

    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(_focused(tester, 'clear'), isTrue);
    await _press(tester, LogicalKeyboardKey.select);
    expect(log.clears, 1);
    expect(log.inputs, isEmpty);
  });

  testWidgets('hardware keys: letters, space once, Enter presses the focused key once', (tester) async {
    final log = await _pump(tester);
    await _press(tester, LogicalKeyboardKey.keyA);
    expect(log.inputs, ['a']);
    await _press(tester, LogicalKeyboardKey.space);
    expect(log.inputs, ['a', ' ']);
    await _press(tester, LogicalKeyboardKey.backspace);
    expect(log.backspaces, 1);

    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(_focused(tester, 'char:б'), isTrue);
    log.inputs.clear();
    await _press(tester, LogicalKeyboardKey.enter);
    expect(log.inputs, ['б']);
    expect(_keyboardKey.currentState!.hasFocus, isTrue);
  });

  testWidgets('keys are 64×64 with a 12 px gap in design px', (tester) async {
    await _pump(tester);
    final a = tester.getRect(_key('char:а'));
    final b = tester.getRect(_key('char:б'));
    final yo = tester.getRect(_key('char:ё'));
    expect(a.size, const Size(64, 64));
    expect(b.left - a.right, 12);
    expect(yo.top - a.bottom, 12);
    expect(tester.getSize(_key('space')), const Size(140, 64));
    expect(tester.getRect(_key('char:е')).right - a.left, 444);
  });
}
