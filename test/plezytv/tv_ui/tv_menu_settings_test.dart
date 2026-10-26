import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_side_menu.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_settings_item.dart';
import 'package:plezy/plezytv/tv_ui/tv_focusable.dart';
import 'package:plezy/plezytv/tv_ui/tv_tokens.dart';
import 'tv_theme_test_helper.dart';

Future<void> enter(WidgetTester tester, FocusNode node) async {
  node.requestFocus();
  await tester.pump();
  await tester.pump();
}

double scale(WidgetTester tester, Finder parent) {
  final opacity = tester.widget<Opacity>(find.descendant(of: parent, matching: find.byType(Opacity)).first);
  final dynamic render = tester.renderObject(find.byWidget(opacity.child!));
  return render.scale as double;
}

void main() {
  for (final reduced in [false, true]) {
    testWidgets('A12 width clip, fixed icon geometry, marker, scrim and collapse reduced=$reduced', (tester) async {
      final inside = FocusNode();
      final outside = FocusNode();
      addTearDown(inside.dispose);
      addTearDown(outside.dispose);
      await pumpTvWidget(
        tester,
        TvSideMenu(
          items: [TvSideMenuItem(icon: Icons.home, label: 'Home', focusNode: inside)],
          currentIndex: 0,
          child: Align(
            alignment: Alignment.centerRight,
            child: TextButton(focusNode: outside, onPressed: () {}, child: const Text('Outside')),
          ),
        ),
        reduced: reduced,
      );
      final panel = find.byType(AnimatedContainer);
      final icon = find.byIcon(Icons.home);
      expect(tester.getSize(panel).width, 136);
      expect(find.text('Home'), findsNothing);
      expect(tester.getSize(icon), const Size(32, 32));
      final marker = find.byWidgetPredicate((w) => w is ColoredBox && w.color == TvTokens.color.accent.normal);
      expect(tester.getSize(marker), const Size(4, 32));
      await enter(tester, inside);
      if (!reduced) {
        await tester.pump(const Duration(milliseconds: 90));
        expect(tester.getSize(panel).width, allOf(greaterThan(136), lessThan(392)));
        expect(tester.getSize(icon), const Size(32, 32));
        expect(scale(tester, find.byType(TvFocusable)), 1);
        await tester.pump(const Duration(milliseconds: 90));
      }
      expect(tester.getSize(panel).width, 392);
      expect(find.text('Home'), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w is ColoredBox && w.color == TvTokens.color.surface.scrim), findsOneWidget);
      await enter(tester, outside);
      await tester.pump(const Duration(milliseconds: 180));
      expect(tester.getSize(panel).width, 136);
      expect(find.text('Home'), findsNothing);
      expect(find.byWidgetPredicate((w) => w is ColoredBox && w.color == TvTokens.color.surface.scrim), findsNothing);
    });
  }

  testWidgets('A12 pressed fill, activation, disabled opacity and focus skip', (tester) async {
    final node = FocusNode();
    final disabled = FocusNode();
    final last = FocusNode();
    for (final n in [node, disabled, last]) {
      addTearDown(n.dispose);
    }
    var calls = 0;
    await pumpTvWidget(
      tester,
      TvSideMenu(
        items: [
          TvSideMenuItem(icon: Icons.home, label: 'Home', focusNode: node, onSelect: () => calls++),
          TvSideMenuItem(
            icon: Icons.block,
            label: 'Disabled',
            focusNode: disabled,
            disabled: true,
            onSelect: () => calls++,
          ),
          TvSideMenuItem(icon: Icons.settings, label: 'Settings', focusNode: last),
        ],
        currentIndex: 0,
        dividerBeforeIndex: 2,
        child: const SizedBox.expand(),
      ),
    );
    await enter(tester, node);
    await tester.pump(const Duration(milliseconds: 180));
    expect(disabled.canRequestFocus, isFalse);
    final disabledControl = find.byType(TvFocusable).at(1);
    expect(
      tester.widget<Opacity>(find.descendant(of: disabledControl, matching: find.byType(Opacity)).first).opacity,
      0.4,
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    final container = tester.widget<Container>(
      find.descendant(of: find.byType(TvFocusable).first, matching: find.byType(Container)),
    );
    expect((container.decoration! as BoxDecoration).color, TvTokens.color.text.secondary);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    expect(calls, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(last.hasFocus, isTrue);
    expect(find.byType(Divider), findsOneWidget);
  });

  for (final reduced in [false, true]) {
    testWidgets('long menu keeps last and first focused items visible reduced=$reduced', (tester) async {
      final nodes = List.generate(24, (_) => FocusNode());
      for (final node in nodes) {
        addTearDown(node.dispose);
      }
      await pumpTvWidget(
        tester,
        TvSideMenu(
          items: List.generate(
            nodes.length,
            (i) => TvSideMenuItem(key: ValueKey(i), icon: Icons.home, label: 'Item $i', focusNode: nodes[i]),
          ),
          child: const SizedBox.expand(),
        ),
        reduced: reduced,
      );
      await enter(tester, nodes.first);
      for (var i = 1; i < nodes.length; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(nodes[i].hasFocus, isTrue);
      }
      void visible(int i) {
        final rect = tester.getRect(find.byKey(ValueKey(i)));
        expect(rect.top, greaterThanOrEqualTo(0));
        expect(rect.bottom, lessThanOrEqualTo(1080));
      }

      visible(23);
      await enter(tester, nodes.first);
      if (!reduced) await tester.pumpAndSettle();
      visible(0);
      expect(find.byWidgetPredicate((w) => w is ColoredBox && w.color == TvTokens.color.accent.normal), findsNothing);
    });
  }

  for (final current in <int?>[null, 1]) {
    testWidgets('stable identities survive reorder and focused removal current=$current', (tester) async {
      final entry = FocusNode();
      addTearDown(entry.dispose);
      var labels = ['A', 'B', 'C'];
      late StateSetter rebuild;
      await pumpTvWidget(
        tester,
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return TvSideMenu(
              currentIndex: current,
              focusNode: entry,
              items: [for (final label in labels) TvSideMenuItem(key: ValueKey(label), icon: Icons.home, label: label)],
              child: const SizedBox.expand(),
            );
          },
        ),
      );
      FocusNode node(String label) => tester
          .widget<TvFocusable>(find.descendant(of: find.byKey(ValueKey(label)), matching: find.byType(TvFocusable)))
          .focusNode!;
      // Enter through the menu target rather than targeting an item.
      entry.requestFocus();
      await tester.pumpAndSettle();
      expect(node(current == null ? 'A' : 'B').hasFocus, isTrue);
      await enter(tester, node('B'));
      entry.requestFocus();
      await tester.pumpAndSettle();
      expect(node(current == null ? 'A' : 'B').hasFocus, isTrue);
      await enter(tester, node('B'));
      final original = node('B');
      rebuild(() => labels = ['C', 'A', 'B']);
      await tester.pumpAndSettle();
      expect(node('B'), same(original));
      expect(node('B').hasFocus, isTrue);
      rebuild(() => labels = ['C', 'A']);
      await tester.pumpAndSettle();
      expect(node(current == null ? 'C' : 'A').hasFocus, isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  for (final labels in [
    ['Search', 'Home', 'Library', 'Settings'],
    ['Downloads', 'Settings'],
  ]) {
    testWidgets('menu vertical boundaries retain focus and content: $labels', (tester) async {
      final nodes = List.generate(labels.length, (_) => FocusNode());
      final outside = FocusNode();
      final above = FocusNode();
      for (final node in [...nodes, outside, above]) {
        addTearDown(node.dispose);
      }
      var contentKeys = 0;
      var selections = 0;
      await pumpTvWidget(
        tester,
        TvSideMenu(
          items: [
            for (var i = 0; i < labels.length; i++)
              TvSideMenuItem(icon: Icons.home, label: labels[i], focusNode: nodes[i], onSelect: () => selections++),
          ],
          dividerBeforeIndex: labels.length - 1,
          child: Focus(
            onKeyEvent: (_, event) {
              if (event is KeyDownEvent || event is KeyRepeatEvent) contentKeys++;
              return KeyEventResult.ignored;
            },
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                TextButton(focusNode: above, onPressed: () {}, child: const Text('Above')),
                TextButton(focusNode: outside, onPressed: () {}, child: const Text('Content')),
              ],
            ),
          ),
        ),
      );
      await enter(tester, nodes.first);
      final contentRect = tester.getRect(find.text('Content'));
      Future<void> boundary(FocusNode node, LogicalKeyboardKey key) async {
        await tester.sendKeyDownEvent(key);
        await tester.pumpAndSettle();
        await tester.sendKeyRepeatEvent(key);
        await tester.sendKeyUpEvent(key);
        await tester.pumpAndSettle();
        expect(node.hasPrimaryFocus, isTrue);
        expect(tester.getSize(find.byType(AnimatedContainer)).width, TvTokens.size.sidebar.expandedW.toDouble());
        expect(tester.getRect(find.text('Content')), contentRect);
        expect(contentKeys, 0);
      }

      await boundary(nodes.first, LogicalKeyboardKey.arrowUp);
      for (var i = 1; i < nodes.length; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(nodes[i].hasPrimaryFocus, isTrue);
      }
      await boundary(nodes.last, LogicalKeyboardKey.arrowDown);
      expect(find.byType(Divider), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(selections, 1);
      for (var i = nodes.length - 2; i >= 0; i--) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pumpAndSettle();
        expect(nodes[i].hasPrimaryFocus, isTrue);
      }
    });
  }

  testWidgets('A13 geometry, outline without focus scale, pressed outline and disabled reason inert', (tester) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    var calls = 0;
    Widget item({String? reason}) => Center(
      child: TvSettingsItem(
        icon: Icons.settings,
        title: 'Audio',
        description: 'Audio track',
        value: 'Original',
        disabledReason: reason,
        focusNode: node,
        onSelect: () => calls++,
      ),
    );
    await pumpTvWidget(tester, item());
    expect(tester.getSize(find.byType(TvSettingsItem)), const Size(1200, 88));
    expect(tester.getSize(find.byIcon(Icons.settings)), const Size(36, 36));
    await enter(tester, node);
    await tester.pump(const Duration(milliseconds: 120));
    expect(scale(tester, find.byType(TvFocusable)), 1);
    BoxDecoration outline() => tester
        .widgetList<DecoratedBox>(find.descendant(of: find.byType(TvFocusable), matching: find.byType(DecoratedBox)))
        .map((w) => w.decoration)
        .whereType<BoxDecoration>()
        .firstWhere((d) => d.border != null);
    expect(outline().color, TvTokens.color.surface.level3);
    expect((outline().border! as Border).top, const BorderSide(color: Colors.white, width: 4));
    expect(outline().borderRadius, BorderRadius.circular(12));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(outline().color, TvTokens.color.surface.level2);
    expect((outline().border! as Border).top.width, 4);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    expect(calls, 1);
    await pumpTvWidget(tester, item(reason: 'Unsupported on this device'));
    await enter(tester, node);
    await tester.pump(const Duration(milliseconds: 120));
    expect(node.hasFocus, isTrue);
    expect(find.text('Unsupported on this device'), findsOneWidget);
    expect(find.text('Audio track'), findsNothing);
    expect(tester.widget<Opacity>(find.byType(Opacity).last).opacity, 0.4);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(calls, 1);
  });
}
