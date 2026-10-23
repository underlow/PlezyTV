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
