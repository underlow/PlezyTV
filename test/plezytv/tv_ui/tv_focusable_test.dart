import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/plezytv/tv_ui/tv_focusable.dart';
import 'tv_theme_test_helper.dart';

Finder get surface => find.byKey(const ValueKey('surface'));
Widget box(BuildContext context, TvFocusState state) =>
    const RepaintBoundary(child: SizedBox(key: ValueKey('surface'), width: 216, height: 324));
double paintedScale(WidgetTester tester) {
  final opacity = tester.widget<Opacity>(
    find.descendant(of: find.byType(TvFocusable), matching: find.byType(Opacity)).first,
  );
  final render = tester.renderObject(find.byWidget(opacity.child!));
  final layer = (render as RenderObjectWithChildMixin<RenderBox>).debugLayer as TransformLayer;
  return layer.transform!.entry(0, 0);
}

void main() {
  testWidgets('ring geometry, bottom origin and layout stay fixed; focus timings', (tester) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    await pumpTvWidget(
      tester,
      Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TvFocusable(focusNode: node, scaleAlignment: Alignment.bottomCenter, builder: box),
            const SizedBox(key: ValueKey('neighbor'), width: 100, height: 100),
          ],
        ),
      ),
    );
    final rect = tester.getRect(surface);
    final neighbor = tester.getRect(find.byKey(const ValueKey('neighbor')));
    node.requestFocus();
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(paintedScale(tester), allOf(greaterThan(1), lessThan(1.08)));
    await tester.pump(const Duration(milliseconds: 60));
    expect(paintedScale(tester), closeTo(1.08, 0.00001));
    expect(tester.getRect(surface), rect);
    expect(tester.getRect(find.byKey(const ValueKey('neighbor'))), neighbor);
    final ring = tester
        .widgetList<DecoratedBox>(find.descendant(of: find.byType(TvFocusable), matching: find.byType(DecoratedBox)))
        .single;
    final decoration = ring.decoration as BoxDecoration;
    expect((decoration.border! as Border).top.width, 4);
    expect((decoration.border! as Border).top.color, Colors.white);
    final position = tester.widget<Positioned>(
      find.ancestor(of: find.byWidget(ring), matching: find.byType(Positioned)).first,
    );
    expect(position.left, -7);
    expect(decoration.borderRadius, BorderRadius.circular(17));
    final scaleRender = tester.renderObject(
      find
          .ancestor(of: surface, matching: find.byWidgetPredicate((w) => w.runtimeType.toString() == '_PaintScale'))
          .first,
    );
    final matrix = (scaleRender.debugLayer as TransformLayer).transform!;
    expect(matrix.entry(1, 3) + 324 * matrix.entry(1, 1), closeTo(324, 0.00001));
    node.unfocus();
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(paintedScale(tester), 1);
  });

  testWidgets('design geometry scales at half resolution and fill exposes state', (tester) async {
    TvFocusState? state;
    await pumpTvWidget(
      tester,
      Center(
        child: TvFocusable(
          autofocus: true,
          kind: TvFocusKind.fill,
          focusedScale: 1.05,
          builder: (context, value) {
            state = value;
            return box(context, value);
          },
        ),
      ),
      size: const Size(960, 540),
    );
    await tester.pumpAndSettle();
    expect(state!.focused, isTrue);
    expect(paintedScale(tester), closeTo(1.05, .00001));
    final fill =
        tester
                .widgetList<DecoratedBox>(
                  find.descendant(of: find.byType(TvFocusable), matching: find.byType(DecoratedBox)),
                )
                .single
                .decoration
            as BoxDecoration;
    expect(fill.color, const Color(0xFFF2F3F5));
    expect(fill.borderRadius, BorderRadius.circular(6));
  });

  testWidgets('press, release once and upstream long press', (tester) async {
    var selected = 0;
    var held = 0;
    TvFocusState? state;
    await pumpTvWidget(
      tester,
      Center(
        child: TvFocusable(
          autofocus: true,
          onSelect: () => selected++,
          onLongPress: () => held++,
          builder: (context, value) {
            state = value;
            return box(context, value);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(paintedScale(tester), allOf(greaterThan(1.08 * .97), lessThan(1.08)));
    await tester.pump(const Duration(milliseconds: 40));
    expect(state!.pressed, isTrue);
    expect(paintedScale(tester), closeTo(1.08 * .97, .00001));
    expect(selected, 0);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(paintedScale(tester), closeTo(1.08, .00001));
    expect(selected, 1);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.pump(const Duration(milliseconds: 501));
    expect(held, 1);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(selected, 1);
    expect(state!.pressed, isFalse);
  });

  for (final mode in TvDisabledFocus.values) {
    testWidgets('disabled $mode: traversal and inert activation', (tester) async {
      final first = FocusNode();
      final disabled = FocusNode();
      final last = FocusNode();
      addTearDown(() {
        first.dispose();
        disabled.dispose();
        last.dispose();
      });
      var calls = 0;
      TvFocusState? state;
      await pumpTvWidget(
        tester,
        Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TvFocusable(
                focusNode: first,
                autofocus: true,
                builder: (_, _) => const SizedBox(width: 100, height: 100),
              ),
              TvFocusable(
                focusNode: disabled,
                disabled: true,
                disabledFocus: mode,
                onSelect: () => calls++,
                onLongPress: () => calls++,
                builder: (context, value) {
                  state = value;
                  return box(context, value);
                },
              ),
              TvFocusable(focusNode: last, builder: (_, _) => const SizedBox(width: 100, height: 100)),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(mode == TvDisabledFocus.skip ? last.hasFocus : disabled.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(calls, 0);
      expect(state!.focused, isFalse);
      expect(state!.disabled, isTrue);
      final opacity = tester.widget<Opacity>(find.ancestor(of: surface, matching: find.byType(Opacity)).first);
      expect(opacity.opacity, .4);
    });
  }

  testWidgets('reduced focus and press are instant; outline never scales focus', (tester) async {
    await pumpTvWidget(
      tester,
      Center(
        child: TvFocusable(autofocus: true, kind: TvFocusKind.outline, builder: box),
      ),
      reduced: true,
    );
    await tester.pump();
    expect(paintedScale(tester), 1);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(paintedScale(tester), .97);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(paintedScale(tester), 1);
    expect(tester.binding.transientCallbackCount, 0);
  });
}
