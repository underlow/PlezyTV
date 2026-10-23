import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    expect(logo.height, 200);
    compact.value = true;
    await tester.pump();
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
