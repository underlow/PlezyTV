import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_rating.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_button.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_chip.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_ratings.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_tabs.dart';
import 'package:plezy/plezytv/tv_ui/tv_focusable.dart';
import 'package:plezy/plezytv/tv_ui/tv_tokens.dart';
import 'package:plezy/widgets/media_rating_badge.dart';
import 'tv_theme_test_helper.dart';

Future<void> focus(WidgetTester tester, FocusNode node) async {
  node.requestFocus();
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 120));
}

Color? fill(WidgetTester tester, Finder parent) =>
    (tester
                .widget<Container>(
                  find
                      .descendant(
                        of: parent,
                        matching: find.byWidgetPredicate((w) => w is Container && w.decoration is BoxDecoration),
                      )
                      .first,
                )
                .decoration!
            as BoxDecoration)
        .color;

double paintedScale(WidgetTester tester, Finder parent) {
  final opacity = tester.widget<Opacity>(find.descendant(of: parent, matching: find.byType(Opacity)).first);
  final dynamic render = tester.renderObject(find.byWidget(opacity.child!));
  return render.scale as double;
}

void main() {
  testWidgets('disabled non-focusable genre chip has opacity 0.4', (tester) async {
    await pumpTvWidget(tester, const TvChip.genre(label: 'Drama', disabled: true));
    expect(
      tester.widget<Opacity>(find.descendant(of: find.byType(TvChip), matching: find.byType(Opacity))).opacity,
      .4,
    );
  });

  test('primary requires a nonempty label', () {
    expect(() => TvButton(label: ''), throwsAssertionError);
    expect(() => TvButton(label: '  '), throwsAssertionError);
  });

  testWidgets('A8 primary geometry, press color and single activation; disabled inert', (tester) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    var calls = 0;
    await pumpTvWidget(
      tester,
      Center(
        child: TvButton(label: 'Play', icon: Icons.play_arrow, focusNode: node, onSelect: () => calls++),
      ),
    );
    final button = find.byType(TvButton);
    expect(tester.getSize(button).height, 64);
    expect(tester.getSize(button).width, greaterThanOrEqualTo(200));
    expect(fill(tester, button), TvTokens.color.accent.normal);
    await focus(tester, node);
    expect(fill(tester, button), TvTokens.color.focus.fill);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(fill(tester, button), TvTokens.color.accent.pressed);
    expect(paintedScale(tester, button), closeTo(1.05 * 0.97, 0.00001));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(calls, 1);
    await pumpTvWidget(
      tester,
      Center(
        child: TvButton(label: 'Disabled', disabled: true, focusNode: node, onSelect: () => calls++),
      ),
    );
    await focus(tester, node);
    expect(node.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(calls, 1);
    expect(fill(tester, find.byType(TvButton)), TvTokens.color.disabled.fill);
  });

  testWidgets('secondary sizes and TV scaling use design units', (tester) async {
    await pumpTvWidget(
      tester,
      Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TvButton(label: 'Secondary', variant: TvButtonVariant.secondary),
            TvButton(label: 'Small', variant: TvButtonVariant.smallSecondary),
          ],
        ),
      ),
      size: const Size(960, 540),
    );
    expect(tester.getSize(find.byType(TvButton).first).height, 32);
    expect(tester.getSize(find.byType(TvButton).last).height, 26);
    expect(fill(tester, find.byType(TvButton).first), TvTokens.color.surface.level3);
    expect(fill(tester, find.byType(TvButton).last), TvTokens.color.surface.level3);
    final containers = tester
        .widgetList<Container>(find.descendant(of: find.byType(TvButton), matching: find.byType(Container)))
        .toList();
    expect(containers.first.padding, const EdgeInsets.symmetric(horizontal: 16));
    expect(containers.last.padding, const EdgeInsets.symmetric(horizontal: 12));
  });

  testWidgets('A8 icon caption reserves layout and only appears on focus', (tester) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    await pumpTvWidget(
      tester,
      Center(
        child: TvIconButton(icon: Icons.add, caption: 'Watchlist', focusNode: node),
      ),
    );
    final before = tester.getSize(find.byType(TvIconButton));
    expect(tester.widget<Visibility>(find.byType(Visibility)).visible, isFalse);
    expect(find.text('Watchlist', skipOffstage: false), findsOneWidget);
    await focus(tester, node);
    expect(tester.widget<Visibility>(find.byType(Visibility)).visible, isTrue);
    expect(tester.getSize(find.byType(TvIconButton)), before);
    expect(before.height, 98);
  });

  testWidgets('A9 Plezy ratings preserve entries, order, values and bare fallback', (tester) async {
    for (final item in [
      MediaItem(
        id: 'a',
        backend: MediaBackend.plex,
        kind: MediaKind.movie,
        ratings: const [
          MediaRatingSource(source: 'imdb', value: 7.1),
          MediaRatingSource(source: 'rottenTomatoesCritic', value: 8.5),
          MediaRatingSource(source: 'letterboxd', value: 8),
          MediaRatingSource(source: 'imdb', value: 6.2),
          MediaRatingSource(source: 'unknown', value: 3),
        ],
      ),
      MediaItem(id: 'b', backend: MediaBackend.plex, kind: MediaKind.movie, rating: 7.3),
      MediaItem(id: 'c', backend: MediaBackend.plex, kind: MediaKind.movie),
    ]) {
      await pumpTvWidget(tester, Center(child: TvRatings(item: item)));
      final texts = tester.widgetList<Text>(find.descendant(of: find.byType(TvRatings), matching: find.byType(Text)));
      expect(texts.map((text) => text.data), mediaRatingsFor(item).map(mediaRatingLabel));
      expect(find.byType(TvFocusable), findsNothing);
      for (final text in texts) {
        expect(text.style!.fontWeight, FontWeight.w600);
      }
    }
  });

  testWidgets('A15 technical and passive genre have no focus node; opt-in genre scales', (tester) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    await pumpTvWidget(
      tester,
      Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const TvChip.technical(label: 'HDR10'),
            const TvChip.genre(label: 'Drama'),
            TvChip.genre(label: 'Action', focusable: true, focusNode: node),
          ],
        ),
      ),
    );
    expect(find.descendant(of: find.byType(TvChip).at(0), matching: find.byType(Focus)), findsNothing);
    expect(find.descendant(of: find.byType(TvChip).at(1), matching: find.byType(Focus)), findsNothing);
    final decoration =
        tester
                .widget<Container>(find.descendant(of: find.byType(TvChip).first, matching: find.byType(Container)))
                .decoration!
            as BoxDecoration;
    expect(decoration.color, isNull);
    expect((decoration.border! as Border).top.width, 1.5);
    await focus(tester, node);
    expect(node.hasFocus, isTrue);
    expect(paintedScale(tester, find.byType(TvChip).last), closeTo(1.05, 0.00001));
    expect(fill(tester, find.byType(TvChip).last), TvTokens.color.focus.fill);
  });

  testWidgets('A10 debounce, cancellation, OK, disabled skip and selected re-entry', (tester) async {
    final outside = FocusNode();
    addTearDown(outside.dispose);
    final selected = <int>[];
    await pumpTvWidget(
      tester,
      Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TvButton(label: 'Outside', focusNode: outside),
            TvTabs(
              tabs: const [
                TvTab(label: 'One'),
                TvTab(label: 'Disabled', disabled: true),
                TvTab(label: 'Three'),
              ],
              selectedIndex: 0,
              onSelected: selected.add,
            ),
          ],
        ),
      ),
    );
    final controls = tester
        .widgetList<TvFocusable>(find.descendant(of: find.byType(TvTabs), matching: find.byType(TvFocusable)))
        .toList();
    await focus(tester, controls[2].focusNode!);
    expect(controls[0].focusNode!.hasFocus, isTrue);
    await tester.pump(const Duration(milliseconds: 299 - 120));
    expect(selected, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    expect(selected, [0]);
    selected.clear();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.pump();
    expect(controls[2].focusNode!.hasFocus, isTrue);
    expect(controls[1].focusNode!.hasFocus, isFalse);
    await tester.pump(const Duration(milliseconds: 200));
    controls[0].focusNode!.requestFocus();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(selected, isEmpty);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(selected, [0]);
    await tester.pump(const Duration(milliseconds: 400));
    expect(selected, [0]);
    await focus(tester, outside);
    await focus(tester, controls[2].focusNode!);
    expect(controls[0].focusNode!.hasFocus, isTrue);
    final opacity = tester.widget<Opacity>(
      find.descendant(of: find.byWidget(controls[1]), matching: find.byType(Opacity)).first,
    );
    expect(opacity.opacity, 0.4);
  });
}
