import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:plezy/media/media_rating.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_all_card.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_hero.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_ratings.dart';
import 'package:plezy/plezytv/tv_ui/tv_focusable.dart';
import 'package:plezy/utils/formatters.dart';
import 'package:plezy/widgets/optimized_media_image.dart';
import '../../test_helpers/media_items.dart';
import 'tv_theme_test_helper.dart';

void main() {
  testWidgets('episode metadata, title fallback, ratings and description; no focus', (tester) async {
    await pumpTvWidget(
      tester,
      Align(
        alignment: Alignment.topLeft,
        child: TvHero(
          item: testMediaItem(
            kind: MediaKind.episode,
            parentIndex: 2,
            index: 3,
            title: 'Episode',
            grandparentTitle: 'Show',
            durationMs: 3000000,
            viewOffsetMs: 1200000,
            summary: 'Summary',
          ),
        ),
      ),
    );
    expect(find.text('Show'), findsOneWidget);
    expect(
      find.text('S2 E3 · Episode · ${formatDurationTextual(3000000)} · ${formatDurationTextual(1800000)} left'),
      findsOneWidget,
    );
    expect(tester.widget<Text>(find.text('Summary')).maxLines, 3);
    expect(find.byType(TvRatings), findsOneWidget);
    expect(find.descendant(of: find.byType(TvHero), matching: find.byType(Focus)), findsNothing);
    expect(find.byType(TvFocusable), findsNothing);
    expect(tester.getSize(find.byType(TvHero)).height, 600);
  });

  testWidgets('logo slot respects bounds; compact description and reduced height update', (tester) async {
    final compact = ValueNotifier(false);
    addTearDown(compact.dispose);
    final item = testMediaItem(title: 'Title', clearLogoPath: '/logo', summary: 'Summary');
    await pumpTvWidget(
      tester,
      Align(
        alignment: Alignment.topLeft,
        child: ValueListenableBuilder<bool>(
          valueListenable: compact,
          builder: (context, value, _) => TvHero(item: item, compact: value),
        ),
      ),
      reduced: true,
    );
    final logo = tester.widget<ClearLogoImage>(find.byType(ClearLogoImage));
    expect(logo.logoPath, '/logo');
    expect(logo.width, 560);
    expect(logo.height, lessThanOrEqualTo(200));
    final normalImage = tester.widget<OptimizedMediaImage>(find.byType(OptimizedMediaImage));
    final normalImageSize = Size(normalImage.width!, normalImage.height!);
    expect(normalImageSize, const Size(560, 128));
    compact.value = true;
    await tester.pump();
    final compactImage = tester.widget<OptimizedMediaImage>(find.byType(OptimizedMediaImage));
    final compactImageSize = Size(compactImage.width!, compactImage.height!);
    expect(compactImage.fit, BoxFit.contain);
    // Test the contained artwork, independent of a network response or fallback.
    for (final aspect in [1.0, 2.0, 3.0, 5.0]) {
      final source = Size(100 * aspect, 100);
      final normal = applyBoxFit(BoxFit.contain, source, normalImageSize).destination;
      final compact = applyBoxFit(BoxFit.contain, source, compactImageSize).destination;
      expect(compact.width, lessThan(normal.width));
      expect(compact.height, lessThan(normal.height));
    }
    expect(compactImageSize, const Size(392, 90));
    expect(compactImageSize.width, lessThan(normalImageSize.width));
    expect(compactImageSize.height, lessThan(normalImageSize.height));
    expect(tester.getSize(find.byKey(const ValueKey('hero-title-slot'))).height, 128);
    expect(
      tester.getRect(find.byType(OptimizedMediaImage)).bottom,
      tester.getRect(find.byKey(const ValueKey('hero-title-slot'))).bottom,
    );
    expect(tester.getSize(find.byType(TvHero)).height, 420);
    expect(tester.widget<Text>(find.text('Summary')).maxLines, 2);
    expect(tester.widget<ClearLogoImage>(find.byType(ClearLogoImage)).height, lessThan(200));
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('normal height transition animates; null item is empty', (tester) async {
    final compact = ValueNotifier(false);
    addTearDown(compact.dispose);
    await pumpTvWidget(
      tester,
      Align(
        alignment: Alignment.topLeft,
        child: ValueListenableBuilder<bool>(
          valueListenable: compact,
          builder: (context, value, _) => TvHero(item: null, compact: value),
        ),
      ),
    );
    expect(find.byType(ClearLogoImage), findsNothing);
    compact.value = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.getSize(find.byType(TvHero)).height, greaterThan(420));
    expect(tester.getSize(find.byType(TvHero)).height, lessThan(600));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(TvHero)).height, 420);
  });

  testWidgets('hero skeleton is static, non-focusable and loads no artwork', (tester) async {
    await pumpTvWidget(tester, const Align(alignment: Alignment.topLeft, child: TvHeroSkeleton()));
    expect(tester.getSize(find.byType(TvHeroSkeleton)).height, 600);
    expect(
      find.byType(Focus).evaluate().where((e) => e.findAncestorWidgetOfExactType<TvHeroSkeleton>() != null),
      isEmpty,
    );
    expect(find.byType(OptimizedMediaImage), findsNothing);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('F1 spoiler policy follows caller setting and Plezy watch state', (tester) async {
    final episode = testMediaItem(
      kind: MediaKind.episode,
      parentIndex: 1,
      index: 3,
      title: 'Title',
      summary: 'Secret',
      viewOffsetMs: 100,
      durationMs: 10000,
    );
    for (final hidden in [false, true]) {
      for (final watched in [false, true]) {
        await pumpTvWidget(
          tester,
          Align(
            alignment: Alignment.topLeft,
            child: TvHero(
              item: episode.copyWith(viewCount: watched ? 1 : 0),
              hideSpoilers: hidden,
            ),
          ),
        );
        expect(find.text('Secret'), hidden && !watched ? findsNothing : findsOneWidget);
        expect(find.text('S1, E3: Title'), hidden && !watched ? findsOneWidget : findsNothing);
      }
    }
    await pumpTvWidget(tester, TvHero(item: episode.copyWith(parentIndex: null), hideSpoilers: true));
    expect(find.text('Secret'), findsNothing);
    await pumpTvWidget(tester, TvHero(item: testMediaItem(summary: 'Movie'), hideSpoilers: true));
    expect(find.text('Movie'), findsOneWidget);
  });

  testWidgets('F2 F6 metadata formats ratings and uses type-specific mockup order', (tester) async {
    await pumpTvWidget(
      tester,
      TvHero(
        item: testMediaItem(
          kind: MediaKind.episode,
          parentIndex: 1,
          index: 3,
          title: 'Title',
          year: 2023,
          contentRating: 'ru/18+',
          durationMs: 3120000,
          viewOffsetMs: 1020000,
        ),
      ),
    );
    expect(
      find.text('S1 E3 · Title · ${formatDurationTextual(3120000)} · ${formatDurationTextual(2100000)} left · 18+'),
      findsOneWidget,
    );
    await pumpTvWidget(
      tester,
      TvHero(
        compact: true,
        item: testMediaItem(
          kind: MediaKind.show,
          year: 2023,
          childCount: 1,
          leafCount: 8,
          contentRating: 'ru/18+',
          genres: ['Drama', 'Crime'],
        ),
      ),
    );
    expect(find.text('2023 · 1 season · 8 episodes · 18+ · Drama, Crime'), findsOneWidget);
  });

  testWidgets('F3 dense content never overflows either height transition', (tester) async {
    final compact = ValueNotifier(false);
    addTearDown(compact.dispose);
    final item =
        testMediaItem(
          kind: MediaKind.episode,
          title: 'Episode',
          parentIndex: 1,
          index: 3,
          summary: 'First line\nSecond line\nThird line',
          contentRating: 'ru/18+',
          durationMs: 3120000,
          viewOffsetMs: 1020000,
          rating: 8,
        ).copyWith(
          title: 'First metadata line\nSecond metadata line',
          ratings: const [MediaRatingSource(source: 'imdb', value: 8)],
        );
    await pumpTvWidget(
      tester,
      Align(
        alignment: Alignment.topLeft,
        child: ValueListenableBuilder<bool>(
          valueListenable: compact,
          builder: (context, value, _) => TvHero(item: item, compact: value),
        ),
      ),
    );
    final metadata = find.byWidgetPredicate((w) => w is Text && (w.data?.startsWith('S1 E3') ?? false));
    expect(tester.getSize(metadata).height, 60);
    expect(tester.getSize(find.text(item.summary!)).height, 102);
    for (final value in [true, false]) {
      compact.value = value;
      await tester.pump();
      expect(tester.takeException(), isNull);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets('F4 F5 full two-line title, fixed top and bottom anchor in both modes', (tester) async {
    for (final compact in [false, true]) {
      double? metadataTop;
      for (final title in ['Short', 'First line\nSecond line gy']) {
        await pumpTvWidget(
          tester,
          Align(
            alignment: Alignment.topLeft,
            child: TvHero(
              compact: compact,
              item: testMediaItem(title: title, year: 2023, summary: title == 'Short' ? 'Brief' : 'Long\nSummary'),
            ),
          ),
        );
        final text = tester.renderObject<RenderParagraph>(find.text(title));
        expect(text.didExceedMaxLines, isFalse);
        if (title != 'Short') expect(text.size.height, 128);
        final logo = tester.getRect(find.byKey(const ValueKey('hero-title-slot')));
        final titleRect = tester.getRect(find.text(title));
        expect(logo.top, compact ? 72 : 110);
        expect(titleRect.bottom, logo.bottom);
        final current = tester.getTopLeft(find.text('2023')).dy;
        if (metadataTop != null) expect(current, metadataTop);
        metadataTop = current;
      }
    }
  });

  testWidgets('F7 skeleton matches reference geometry and fixed top', (tester) async {
    await pumpTvWidget(tester, const Align(alignment: Alignment.topLeft, child: TvHeroSkeleton()));
    final blocks = find.descendant(of: find.byType(TvHeroSkeleton), matching: find.byType(Container));
    expect(tester.getTopLeft(blocks.first).dy, 110);
    expect(
      [for (var i = 0; i < blocks.evaluate().length; i++) tester.getSize(blocks.at(i))],
      [
        const Size(420, 96),
        const Size(520, 24),
        const Size(240, 24),
        const Size(860, 22),
        const Size(820, 22),
        const Size(600, 22),
      ],
    );
  });

  testWidgets('All card matches both row sizes and selects with OK', (tester) async {
    var selected = 0;
    for (final episode in [false, true]) {
      await pumpTvWidget(
        tester,
        Center(
          child: TvAllCard(episode: episode, autofocus: true, onSelect: () => selected++),
        ),
      );
      await tester.pumpAndSettle();
      final surface = find.descendant(of: find.byType(TvFocusable), matching: find.byType(Container)).last;
      expect(tester.getSize(surface), episode ? const Size(400, 225) : const Size(216, 324));
      expect(find.text('All'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
    }
    expect(selected, 2);
  });
}
