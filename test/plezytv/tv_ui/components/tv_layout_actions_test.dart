import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/media/media_rating.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_action_row.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_button.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_ratings.dart';
import 'package:plezy/plezytv/tv_ui/tv_strings.dart';
import '../tv_theme_test_helper.dart';

void main() {
  List<MediaRatingSource> scores(List<String> sources) => [
    for (final s in sources) MediaRatingSource(source: s, value: 7),
  ];
  test('R7 priority, limit, stable remaining order and unnamed scores last', () {
    expect(
      selectTvRatings(
        scores(['critic', 'tmdb', 'rottenTomatoesAudience', 'imdb', 'rottenTomatoesCritic']),
      ).map((r) => r.source),
      ['imdb', 'rottenTomatoesCritic', 'rottenTomatoesAudience'],
    );
    expect(selectTvRatings(scores(['audience', 'metacritic', 'tmdb', '', 'imdb'])).map((r) => r.source), [
      'imdb',
      'metacritic',
      'tmdb',
    ]);
    expect(selectTvRatings(scores(['rottenTomatoes', 'imdb'])).map((r) => r.source), ['imdb', 'rottenTomatoes']);
    expect(selectTvRatings([]), isEmpty);
  });
  testWidgets('R6 equal gaps, fixed icons and overlay caption without layout changes', (tester) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    await pumpTvWidget(
      tester,
      Align(
        alignment: Alignment.topLeft,
        child: TvActionRow(
          buttons: [
            TvButton(label: 'Play'),
            TvIconButton(
              key: const ValueKey('first'),
              icon: Icons.add,
              caption: 'A very long action caption',
              focusNode: node,
            ),
            const TvIconButton(key: ValueKey('second'), icon: Icons.more_horiz, caption: 'More'),
          ],
        ),
      ),
      size: const Size(1920, 1080),
    );
    final first = tester.getRect(find.byKey(const ValueKey('first')));
    final second = tester.getRect(find.byKey(const ValueKey('second')));
    final primary = tester.getRect(find.byType(TvButton));
    expect(first.size, const Size(64, 64));
    expect(first.left - primary.right, 24);
    expect(second.left - first.right, 24);
    node.requestFocus();
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(const ValueKey('first'))), first);
    expect(tester.getRect(find.byKey(const ValueKey('second'))), second);
    final caption = tester.getRect(find.text('A very long action caption'));
    expect(caption.top, greaterThanOrEqualTo(first.bottom));
    expect(caption.center.dx, first.center.dx);
    expect(tester.takeException(), isNull);
  });
  test('R15 date uses abbreviated text', () async {
    await initializeDateFormatting('en');
    await LocaleSettings.setLocale(AppLocale.en);
    expect(TvStrings.date('2026-09-16'), '16 Sep 2026');
    await initializeDateFormatting('ru');
    await LocaleSettings.setLocale(AppLocale.ru);
    expect(TvStrings.date('2026-09-16'), '16 сент. 2026');
    await LocaleSettings.setLocale(AppLocale.en);
  });
}
