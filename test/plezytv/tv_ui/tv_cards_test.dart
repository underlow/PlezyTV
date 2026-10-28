import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_cards.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_skeletons.dart';
import 'package:plezy/plezytv/tv_ui/tv_focusable.dart';
import 'package:plezy/plezytv/tv_ui/tv_tokens.dart';
import 'package:plezy/utils/formatters.dart';
import 'package:plezy/widgets/optimized_media_image.dart';
import '../../test_helpers/media_items.dart';
import 'tv_theme_test_helper.dart';

Matrix4 artworkTransform(WidgetTester tester) {
  final opacity = tester.widget<Opacity>(
    find.descendant(of: find.byType(TvFocusable), matching: find.byType(Opacity)).first,
  );
  final render = tester.renderObject(find.byWidget(opacity.child!));
  return (render.debugLayer as TransformLayer).transform!;
}

void main() {
  testWidgets('A4 real poster: bottom-origin paint scale, ring, stationary labels and neighbor, press once', (
    tester,
  ) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    var selected = 0;
    await pumpTvWidget(
      tester,
      Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TvPoster(
              item: testMediaItem(title: 'Poster', year: 2020),
              focusNode: node,
              onSelect: () => selected++,
            ),
            const SizedBox(key: ValueKey('neighbor'), width: 100, height: 100),
          ],
        ),
      ),
    );
    final titleRect = tester.getRect(find.text('Poster'));
    final captionRect = tester.getRect(find.text('2020'));
    final neighborRect = tester.getRect(find.byKey(const ValueKey('neighbor')));
    final imageRect = tester.getRect(find.byType(OptimizedMediaImage));
    node.requestFocus();
    await tester.pumpAndSettle();
    final matrix = artworkTransform(tester);
    expect(matrix.entry(0, 0), closeTo(1.05, .00001));
    expect(matrix.entry(1, 3) + 324 * matrix.entry(1, 1), closeTo(324, .00001));
    expect(tester.getRect(find.text('Poster')), titleRect);
    expect(tester.getRect(find.text('2020')), captionRect);
    expect(tester.getRect(find.byKey(const ValueKey('neighbor'))), neighborRect);
    expect(tester.getRect(find.byType(OptimizedMediaImage)), imageRect);
    final title = tester.widget<Text>(find.text('Poster'));
    expect(title.style!.color, TvTokens.color.text.primary);
    expect(title.style!.fontWeight, FontWeight.w600);
    expect(title.maxLines, 1);
    expect(title.overflow, TextOverflow.ellipsis);
    expect(tester.widget<Text>(find.text('2020')).style!.color, TvTokens.color.text.tertiary);
    final ring = tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .where((w) => w.decoration is BoxDecoration && (w.decoration as BoxDecoration).border != null)
        .single;
    final border = (ring.decoration as BoxDecoration).border! as Border;
    expect(border.top.width, 4);
    expect(border.top.color, Colors.white);
    final position = tester.widget<Positioned>(
      find.ancestor(of: find.byWidget(ring), matching: find.byType(Positioned)).first,
    );
    expect(position.left, -7);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(artworkTransform(tester).entry(0, 0), closeTo(1.05 * .97, .00001));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(selected, 1);
  });

  testWidgets('poster dimensions, scaled image decode bounds, caller Plezy count caption', (tester) async {
    for (final size in TvPosterSize.values) {
      // The caller supplies an existing Plezy-formatted catalog/count caption.
      final caption = t.explore.badge.seasonsAvailable(available: 2, total: 3);
      await pumpTvWidget(
        tester,
        Center(
          child: TvPoster(
            item: testMediaItem(title: 'Title'),
            size: size,
            caption: caption,
          ),
        ),
        size: const Size(960, 540),
      );
      final image = tester.widget<OptimizedMediaImage>(find.byType(OptimizedMediaImage));
      expect(image.width, size.dimensions.width / 2);
      expect(image.height, size.dimensions.height / 2);
      expect(tester.getSize(find.byType(OptimizedMediaImage)), size.dimensions / 2);
      expect(find.text(caption), findsOneWidget);
    }
  });

  testWidgets('episode poster shows the series poster, falling back to its own thumb', (tester) async {
    for (final (series, expected) in [('/series', '/series'), (null, '/episode')]) {
      await pumpTvWidget(
        tester,
        Center(
          child: TvPoster(
            item: testMediaItem(kind: MediaKind.episode, thumbPath: '/episode', grandparentThumbPath: series),
            showSeriesTitle: true,
          ),
        ),
      );
      expect(tester.widget<OptimizedMediaImage>(find.byType(OptimizedMediaImage)).imagePath, expected);
    }
  });

  testWidgets('A11 watched, on-server and aggregate unwatched badges/captions use Plezy state', (tester) async {
    await pumpTvWidget(tester, Center(child: TvPoster(item: testMediaItem(viewCount: 1), onServer: true)));
    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(find.text('On server'), findsOneWidget);
    for (final count in [12, 1]) {
      await pumpTvWidget(
        tester,
        Center(
          child: TvPoster(
            item: testMediaItem(kind: MediaKind.show, leafCount: 20, viewedLeafCount: 20 - count),
            caption: 'Original',
            autofocus: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('$count'), findsOneWidget);
      expect(find.text('$count unwatched'), findsOneWidget);
      expect(tester.widget<Text>(find.text('$count unwatched')).style!.color, TvTokens.color.accent.normal);
    }
  });

  testWidgets('A14 episode progress and Plezy labels/durations; completed has no bar', (tester) async {
    final item = testMediaItem(
      kind: MediaKind.episode,
      parentIndex: 1,
      index: 3,
      title: 'Title',
      durationMs: 3000000,
      viewOffsetMs: 1200000,
    );
    await pumpTvWidget(tester, Center(child: TvEpisode(item: item, autofocus: true)));
    await tester.pumpAndSettle();
    expect(find.text('S1 E3 · Title'), findsOneWidget);
    expect(find.text('${formatDurationTextual(1800000)} left'), findsOneWidget);
    final fill = find.byWidgetPredicate((w) => w is ColoredBox && w.color == TvTokens.color.status.progressFill);
    expect(tester.getSize(fill), const Size(160, 6));
    final image = tester.getRect(find.byType(OptimizedMediaImage));
    expect(tester.getRect(fill).bottom, image.bottom);
    expect(artworkTransform(tester).entry(0, 0), closeTo(1.03, .00001));
    await pumpTvWidget(tester, Center(child: TvEpisode(item: item.copyWith(viewOffsetMs: 3000000))));
    expect(find.text(formatDurationTextual(3000000)), findsOneWidget);
    expect(fill, findsNothing);
  });

  testWidgets('disabled cards skip directional focus and do not activate', (tester) async {
    final nodes = List.generate(3, (_) => FocusNode());
    addTearDown(() {
      for (final node in nodes) {
        node.dispose();
      }
    });
    var selected = 0;
    await pumpTvWidget(
      tester,
      Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TvPoster(item: testMediaItem(), focusNode: nodes[0], autofocus: true),
            TvPoster(item: testMediaItem(), disabled: true, focusNode: nodes[1], onSelect: () => selected++),
            TvEpisode(item: testMediaItem(), disabled: true, focusNode: nodes[2], onSelect: () => selected++),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(nodes[1].canRequestFocus, isFalse);
    expect(nodes[2].canRequestFocus, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(nodes[1].hasFocus || nodes[2].hasFocus, isFalse);
    expect(tester.widgetList<Opacity>(find.byType(Opacity)).where((o) => o.opacity == .4).length, 4);
    expect(selected, 0);
  });

  testWidgets('A15 skeletons are static and do not own focus', (tester) async {
    await pumpTvWidget(
      tester,
      const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [TvPosterSkeleton(), TvEpisodeSkeleton()]),
            TvRowSkeleton(count: 2),
          ],
        ),
      ),
    );
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.hasRunningAnimations, isFalse);
    expect(find.byType(TvFocusable), findsNothing);
    expect(find.byType(OptimizedMediaImage), findsNothing);
  });

  testWidgets('TvFocusable default does not run upstream scroll when focused', (tester) async {
    final controller = ScrollController();
    final node = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(node.dispose);
    await pumpTvWidget(
      tester,
      Center(
        child: SizedBox(
          height: 200,
          width: 400,
          child: SingleChildScrollView(
            controller: controller,
            child: Column(
              children: [
                const SizedBox(height: 800),
                TvFocusable(focusNode: node, builder: (context, state) => const SizedBox(height: 100, width: 200)),
              ],
            ),
          ),
        ),
      ),
    );
    node.requestFocus();
    await tester.pumpAndSettle();
    expect(controller.offset, 0);
    expect(tester.widget<TvFocusable>(find.byType(TvFocusable)).autoScroll, isFalse);
  });
}
