import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_all_card.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_cards.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_hero.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_ratings.dart';
import 'package:plezy/plezytv/tv_ui/tv_focusable.dart';
import 'package:plezy/plezytv/tv_ui/tv_tokens.dart';
import 'package:plezy/utils/formatters.dart';
import 'package:plezy/widgets/optimized_media_image.dart';
import '../../test_helpers/media_items.dart';
import 'tv_theme_test_helper.dart';

void main() {
  testWidgets('C2 square artwork, caption geometry, circular artist and bottom scale', (tester) async {
    for (final kind in [MediaKind.artist, MediaKind.album, MediaKind.track]) {
      final item = testMediaItem(
        kind: kind,
        title: 'Title',
        parentTitle: 'Parent',
        grandparentTitle: 'Grandparent',
        originalTitle: 'Performer',
      );
      await pumpTvWidget(tester, Center(child: TvMusicCard(item: item, autofocus: true)));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(OptimizedMediaImage)), const Size(216, 216));
      final focus = tester.widget<TvFocusable>(find.byType(TvFocusable));
      expect(focus.radius, kind == MediaKind.artist ? 108 : null);
      expect(focus.scaleAlignment, Alignment.bottomCenter);
      expect(focus.focusedScale, TvTokens.focus.cardScale);
      final clip = tester.widget<ClipRRect>(find.byType(ClipRRect).first);
      expect(
        clip.borderRadius,
        BorderRadius.circular(kind == MediaKind.artist ? 108 : TvTokens.radius.card.toDouble()),
      );
      expect(
        find.text(switch (kind) {
          MediaKind.album => 'Parent',
          MediaKind.track => 'Performer · Parent',
          _ => '',
        }),
        findsOneWidget,
      );
      final musicHeight = tester.getSize(find.byType(TvMusicCard)).height;
      await pumpTvWidget(tester, Center(child: TvAllCard(square: true, onSelect: () {})));
      expect(tester.getSize(find.byType(TvAllCard)), Size(216, musicHeight));
      await pumpTvWidget(tester, Center(child: TvPoster(item: item)));
      expect(tester.getSize(find.byType(TvPoster)).height - musicHeight, 108);
    }
  });

  testWidgets('C2 missing caption parts and album artwork fallback; no watch state', (tester) async {
    for (final kind in [MediaKind.track, MediaKind.album]) {
      for (final complete in [false, true]) {
        final item = testMediaItem(
          kind: kind,
          title: 'Title',
          originalTitle: 'Performer',
          parentThumbPath: '/album',
          viewCount: complete ? 1 : 0,
          leafCount: 10,
          viewedLeafCount: complete ? 10 : 3,
          durationMs: 300000,
          viewOffsetMs: 100000,
        );
        await pumpTvWidget(tester, Center(child: TvMusicCard(item: item, externalFocus: true)));
        await tester.pumpAndSettle();
        expect(tester.widget<OptimizedMediaImage>(find.byType(OptimizedMediaImage)).imagePath, '/album');
        expect(find.text(kind == MediaKind.track ? 'Performer' : ''), findsOneWidget);
        expect(find.byType(TvMediaBadges), findsNothing);
        expect(find.byType(TvMediaProgress), findsNothing);
        expect(find.byIcon(Icons.check), findsNothing);
        expect(find.textContaining('unwatched'), findsNothing);
        expect(find.textContaining('·'), findsNothing);
      }
    }
  });

  testWidgets('R2/R6 track artist falls back to grandparent without originalTitle', (tester) async {
    final item = testMediaItem(
      kind: MediaKind.track,
      title: 'Track',
      originalTitle: null,
      grandparentTitle: 'Grandparent',
      parentTitle: 'Album',
      durationMs: 180000,
    );
    await pumpTvWidget(tester, Center(child: TvMusicCard(item: item)));
    expect(find.text('Grandparent · Album'), findsOneWidget);
    await pumpTvWidget(tester, TvHero(item: item));
    expect(find.text('Grandparent · Album · ${formatDurationTextual(180000)}'), findsOneWidget);
  });

  testWidgets('A20 album without genres retains artist and year', (tester) async {
    final item = testMediaItem(kind: MediaKind.album, title: 'Album', parentTitle: 'Parent', year: 2024, genres: null);
    await pumpTvWidget(tester, Center(child: TvMusicCard(item: item)));
    expect(find.text('Parent'), findsOneWidget);
    await pumpTvWidget(tester, TvHero(item: item));
    expect(find.text('Parent · 2024'), findsOneWidget);
  });

  testWidgets('C2 artist external ring, primary artwork and empty placeholder', (tester) async {
    for (final path in ['/own', null]) {
      await pumpTvWidget(
        tester,
        Center(
          child: TvMusicCard(
            item: testMediaItem(kind: MediaKind.artist, title: 'Artist', thumbPath: path),
            externalFocus: true,
          ),
        ),
      );
      final visual = tester.widget<TvFocusVisual>(find.byType(TvFocusVisual));
      expect(visual.radius, 108);
      expect(visual.alignment, Alignment.bottomCenter);
      expect(tester.widget<OptimizedMediaImage>(find.byType(OptimizedMediaImage)).imagePath, path);
      expect(find.byWidgetPredicate((w) => w is ColoredBox && w.color == TvTokens.color.surface.level2), findsWidgets);
    }
  });

  testWidgets('C3 movie metadata and ratings remain unchanged', (tester) async {
    await pumpTvWidget(
      tester,
      TvHero(
        item: testMediaItem(
          title: 'Movie',
          year: 2024,
          durationMs: 5400000,
          contentRating: 'ru/18+',
          genres: ['Drama'],
        ),
      ),
    );
    expect(find.text('2024 · ${formatDurationTextual(5400000)} · 18+ · Drama'), findsOneWidget);
    expect(find.byType(TvRatings), findsOneWidget);
  });

  testWidgets('C3 music hero metadata order and no ratings or empty separators', (tester) async {
    for (final kind in [MediaKind.artist, MediaKind.album, MediaKind.track]) {
      for (final sparse in [false, true]) {
        final item = testMediaItem(
          kind: kind,
          title: 'Title',
          parentTitle: sparse ? null : 'Parent',
          grandparentTitle: 'Grandparent',
          originalTitle: 'Performer',
          year: sparse ? null : 2024,
          genres: sparse ? null : ['Jazz', 'Soul'],
          contentRating: 'ru/18+',
          rating: 9,
          durationMs: 180000,
        );
        await pumpTvWidget(tester, TvHero(item: item));
        final expected = switch (kind) {
          MediaKind.album => sparse ? '' : 'Parent · 2024 · Jazz, Soul',
          MediaKind.track => '${sparse ? 'Performer' : 'Performer · Parent'} · ${formatDurationTextual(180000)}',
          _ => sparse ? '' : 'Jazz, Soul',
        };
        if (expected.isNotEmpty) expect(find.text(expected), findsOneWidget);
        expect(find.byType(TvRatings), findsNothing);
        expect(find.textContaining('18+'), findsNothing);
        expect(
          find.byWidgetPredicate(
            (w) => w is Text && ((w.data?.startsWith(' · ') ?? false) || (w.data?.endsWith(' · ') ?? false)),
          ),
          findsNothing,
        );
      }
    }
  });
}
