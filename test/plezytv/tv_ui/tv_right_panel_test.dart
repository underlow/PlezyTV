import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_right_panel.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_settings_item.dart';
import 'package:plezy/plezytv/tv_ui/tv_focusable.dart';
import 'tv_theme_test_helper.dart';

void main() {
  testWidgets('nested Back restores page focus, live updates retain focus, closing restores anchor', (tester) async {
    final anchor = FocusNode();
    final changes = ValueNotifier(false);
    addTearDown(anchor.dispose);
    addTearDown(changes.dispose);
    Future<void>? closed;
    await pumpTvWidget(
      tester,
      Builder(
        builder: (context) {
          return Center(
            child: TextButton(
              focusNode: anchor,
              onPressed: () {
                closed = TvRightPanel.show(
                  context: context,
                  anchor: anchor,
                  root: TvRightPanelPage(
                    title: 'Root',
                    itemsBuilder: (context) => [
                      TvSettingsItem(
                        key: const ValueKey('child'),
                        icon: Icons.settings,
                        title: 'Child',
                        description: '',
                        value: '',
                        kind: TvSettingsItemKind.page,
                        onSelect: () => TvRightPanel.of(context).push(
                          TvRightPanelPage(
                            title: 'Child',
                            changes: changes,
                            itemsBuilder: (context) => [
                              TvSettingsItem(
                                key: const ValueKey('choice'),
                                icon: Icons.circle_outlined,
                                title: 'Choice',
                                description: '',
                                value: changes.value ? 'Yes' : 'No',
                                selected: changes.value,
                                kind: TvSettingsItemKind.multipleChoice,
                                onSelect: () => changes.value = !changes.value,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
              child: const Text('Open'),
            ),
          );
        },
      ),
    );
    anchor.requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Root'), findsOneWidget);
    expect(tester.getSize(find.byType(TvRightPanel)).width, 1920);
    expect(tester.getSize(find.byType(IndexedStack)).width, 600);
    expect(anchor.hasFocus, isFalse);
    final parentFocus = FocusManager.instance.primaryFocus;
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('‹ Child'), findsOneWidget);
    final choiceFocus = FocusManager.instance.primaryFocus;
    expect(choiceFocus, isNot(same(parentFocus)));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(changes.value, isTrue);
    expect(find.text('Yes'), findsOneWidget);
    expect(FocusManager.instance.primaryFocus, same(choiceFocus));
    // A server-driven update also keeps the focused row mounted.
    changes.value = false;
    await tester.pumpAndSettle();
    expect(find.text('No'), findsOneWidget);
    expect(FocusManager.instance.primaryFocus, same(choiceFocus));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Root'), findsOneWidget);
    expect(FocusManager.instance.primaryFocus, same(parentFocus));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await closed;
    expect(find.byType(TvRightPanel), findsNothing);
    expect(anchor.hasFocus, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('row variants activate, reorder with Left/Right and keep long lists visible', (tester) async {
    final anchor = FocusNode();
    addTearDown(anchor.dispose);
    var actions = 0;
    var moves = 0;
    await pumpTvWidget(
      tester,
      Builder(
        builder: (context) => TextButton(
          focusNode: anchor,
          onPressed: () => TvRightPanel.show(
            context: context,
            anchor: anchor,
            root: TvRightPanelPage(
              title: 'Rows',
              itemsBuilder: (context) => [
                for (var i = 0; i < 25; i++)
                  TvSettingsItem(
                    key: ValueKey(i),
                    icon: Icons.settings,
                    title: 'Row $i',
                    description: '',
                    value: '',
                    kind: i == 0 ? TvSettingsItemKind.reorder : TvSettingsItemKind.action,
                    onMoveUp: () => moves--,
                    onMoveDown: () => moves++,
                    onSelect: () => actions++,
                  ),
              ],
            ),
          ),
          child: const Text('Open'),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    expect(moves, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(moves, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(actions, 1);
    for (var i = 1; i < 25; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
    }
    final last = find.descendant(of: find.byKey(const ValueKey(24)), matching: find.byType(TvFocusable));
    expect(
      find.descendant(
        of: last,
        matching: find.byWidgetPredicate((widget) => widget is Focus && widget.focusNode?.hasPrimaryFocus == true),
      ),
      findsOneWidget,
    );
    expect(tester.getRect(last).bottom, lessThanOrEqualTo(1080));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(anchor.hasFocus, isFalse);
    // Android system Back follows the same page stack and anchor restoration.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(anchor.hasFocus, isTrue);
  });
}
