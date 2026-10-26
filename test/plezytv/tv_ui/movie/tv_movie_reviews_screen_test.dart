import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/media_hub.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_role.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_horizontal_row.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_right_panel.dart';
import 'package:plezy/plezytv/tv_ui/movie/tv_movie_controller.dart';
import 'package:plezy/plezytv/tv_ui/movie/tv_movie_review_card.dart';
import 'package:plezy/plezytv/tv_ui/movie/tv_movie_reviews.dart';
import 'package:plezy/plezytv/tv_ui/movie/tv_movie_screen.dart';

import '../tv_theme_test_helper.dart';
import 'tv_movie_reviews_test.dart' show ReviewPlex, payload;
import 'tv_movie_screen_test.dart' show movieItem;

class DelayedRelatedPlex extends ReviewPlex {
  DelayedRelatedPlex(this.gate);
  final Completer<List<MediaHub>> gate;
  @override
  Future<List<MediaHub>> fetchRelatedHubs(String id, {int count = 10}) => gate.future;
}

String? focusedRow() =>
    FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<TvHorizontalRow>()?.title;
ScrollPosition page(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first,
    )
    .position;
Future<void> key(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
}

Future<Completer<List<TvMovieReview>>> mountReviews(
  WidgetTester tester, {
  bool cast = false,
  bool extras = false,
  bool related = false,
  bool reduced = false,
  Completer<List<MediaHub>>? relatedGate,
}) async {
  final client = (relatedGate == null ? ReviewPlex() : DelayedRelatedPlex(relatedGate))
    ..show = movieItem().copyWith(
      roles: cast ? [const MediaRole(id: 'actor', tag: 'Actor')] : [],
    );
  if (extras) client.extras = [client.show.copyWith(id: 'trailer', kind: MediaKind.clip)];
  if (related) {
    client.relatedHubs = [
      MediaHub(
        id: 'similar',
        title: 'Similar',
        type: 'movie',
        items: [movieItem(id: 'other')],
      ),
    ];
  }
  final gate = Completer<List<TvMovieReview>>();
  final c = TvMovieController(
    client: client,
    metadata: client.show,
    reviewsLoader: (_, _) => gate.future,
    versionPreference: (_) async => null,
    watchEvents: const Stream.empty(),
    deletionEvents: const Stream.empty(),
  );
  addTearDown(c.dispose);
  await pumpTvWidget(
    tester,
    TvMovieScreen(metadata: client.show, controller: c, serverOnline: (_) => true),
    reduced: reduced,
  );
  await tester.pumpAndSettle();
  return gate;
}

const review = TvMovieReview(
  source: 'Paper',
  tag: 'Critic',
  text: 'Review text',
  freshness: TvMovieReviewFreshness.fresh,
);

void main() {
  testWidgets('A1 A7 A11 A12 server order, field fallbacks, icons and filtering', (tester) async {
    final gate = await mountReviews(tester, cast: true, extras: true, related: true);
    final reviews = parseTvMovieReviews(
      payload([
        {'source': 'Paper', 'tag': 'Critic', 'text': 'First', 'image': 'x.review.fresh'},
        {'source': 'Publication only', 'text': 'Second', 'image': 'x.review.rotten'},
        {'tag': 'Critic only', 'text': 'Third', 'image': 'unknown'},
        {'source': 'Missing text'},
        {'text': 'Missing author'},
        for (var i = 3; i < 9; i++) {'source': 'Paper $i', 'text': 'Review $i'},
      ]),
    );
    gate.complete(reviews);
    await tester.pumpAndSettle();
    expect(tester.widgetList<TvHorizontalRow>(find.byType(TvHorizontalRow)).map((w) => w.title), [
      'Cast',
      'Reviews',
      t.discover.extras,
      'Similar',
    ]);
    final row = tester.widget<TvHorizontalRow>(
      find.byWidgetPredicate((w) => w is TvHorizontalRow && w.title == 'Reviews'),
    );
    expect(row.itemCount, 9);
    expect((row.cardWidth, row.cardHeight), (512, 256));
    await key(tester, LogicalKeyboardKey.arrowDown);
    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(focusedRow(), 'Reviews');
    for (var i = 0; i < 9; i++) {
      final card = FocusManager.instance.primaryFocus!.context!.findAncestorWidgetOfExactType<TvMovieReviewCard>()!;
      expect(card.review.text, reviews[i].text);
      final subtree = find.byWidget(card);
      expect(find.descendant(of: subtree, matching: find.byType(SvgPicture)), i < 2 ? findsOneWidget : findsNothing);
      if (i < 2) {
        final icon = tester.widget<SvgPicture>(find.descendant(of: subtree, matching: find.byType(SvgPicture)));
        expect(
          (icon.bytesLoader as SvgAssetLoader).assetName,
          'assets/rating_icons/rt_${i == 0 ? 'fresh' : 'rotten'}.svg',
        );
        expect((icon.width, icon.height), (40, 40));
      }
      if (i == 2) {
        final title = tester.widget<Text>(find.descendant(of: subtree, matching: find.text('Critic only')));
        expect(title.style!.fontSize, 22);
        expect(title.maxLines, 1);
      }
      await key(tester, LogicalKeyboardKey.arrowRight);
    }
    expect(focusedRow(), 'Reviews');
    expect(tester.takeException(), isNull);
  });

  testWidgets('A4 A8 A13 late insertion on actions preserves offset and Down reaches reviews', (tester) async {
    final gate = await mountReviews(tester);
    final focus = FocusManager.instance.primaryFocus;
    final before = page(tester).pixels;
    gate.complete([review]);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus, same(focus));
    expect(page(tester).pixels, before);
    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(focusedRow(), 'Reviews');
    await key(tester, LogicalKeyboardKey.arrowUp);
    expect(FocusManager.instance.primaryFocus, same(focus));
    expect(page(tester).pixels, 0);
  });

  for (final reduced in [false, true]) {
    testWidgets('A9 late insertion preserves related card focus and global position reduced=$reduced', (tester) async {
      final gate = await mountReviews(tester, cast: true, related: true, reduced: reduced);
      await key(tester, LogicalKeyboardKey.arrowDown);
      await key(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedRow(), 'Similar');
      final focus = FocusManager.instance.primaryFocus!;
      final before = (focus.context!.findRenderObject()! as RenderBox).localToGlobal(Offset.zero);
      final oldOffset = page(tester).pixels;
      gate.complete([review]);
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus, same(focus));
      final after = (focus.context!.findRenderObject()! as RenderBox).localToGlobal(Offset.zero);
      expect(after.dy, closeTo(before.dy, 0.01));
      final row = find.byWidgetPredicate((w) => w is TvHorizontalRow && w.title == 'Reviews');
      expect(page(tester).pixels - oldOffset, closeTo(tester.getSize(row).height, 0.01));
      await key(tester, LogicalKeyboardKey.arrowUp);
      expect(focusedRow(), 'Reviews');
    });
  }

  testWidgets('A2 A10 single-line title, full text, 102px scrolling, edges and Back restoration', (tester) async {
    final gate = await mountReviews(tester);
    final title = List.filled(30, 'Long publication').join(' ');
    final text = List.generate(250, (i) => 'Sentence $i of the complete review.').join(' ');
    gate.complete([TvMovieReview(source: title, tag: 'Critic', text: text, freshness: TvMovieReviewFreshness.rotten)]);
    await tester.pumpAndSettle();
    await key(tester, LogicalKeyboardKey.arrowDown);
    final focus = FocusManager.instance.primaryFocus;
    final before = page(tester).pixels;
    await key(tester, LogicalKeyboardKey.enter);
    expect(find.byType(TvRightPanel), findsOneWidget);
    final heading = tester.widget<Text>(find.descendant(of: find.byType(TvRightPanel), matching: find.text(title)));
    expect(heading.maxLines, 1);
    expect(heading.overflow, TextOverflow.ellipsis);
    expect(find.descendant(of: find.byType(TvRightPanel), matching: find.text(text)), findsOneWidget);
    final body = tester
        .state<ScrollableState>(find.descendant(of: find.byType(TvRightPanel), matching: find.byType(Scrollable)))
        .position;
    expect(body.pixels, 0);
    await key(tester, LogicalKeyboardKey.arrowUp);
    expect(body.pixels, 0);
    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(body.pixels, 102);
    await key(tester, LogicalKeyboardKey.arrowLeft);
    await key(tester, LogicalKeyboardKey.arrowRight);
    expect(body.pixels, 102);
    while (body.pixels < body.maxScrollExtent) {
      final previous = body.pixels;
      await key(tester, LogicalKeyboardKey.arrowDown);
      expect(body.pixels, (previous + 102).clamp(0, body.maxScrollExtent));
    }
    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(body.pixels, body.maxScrollExtent);
    while (body.pixels > 0) {
      final previous = body.pixels;
      await key(tester, LogicalKeyboardKey.arrowUp);
      expect(body.pixels, (previous - 102).clamp(0, body.maxScrollExtent));
    }
    await key(tester, LogicalKeyboardKey.escape);
    expect(find.byType(TvRightPanel), findsNothing);
    expect(FocusManager.instance.primaryFocus, same(focus));
    expect(page(tester).pixels, before);
  });

  testWidgets('R4 Back preserves review position when related rows arrive behind the panel', (tester) async {
    final related = Completer<List<MediaHub>>();
    final gate = await mountReviews(tester, cast: true, relatedGate: related);
    gate.complete([review]);
    await tester.pumpAndSettle();
    await key(tester, LogicalKeyboardKey.arrowDown);
    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(focusedRow(), 'Reviews');
    final focus = FocusManager.instance.primaryFocus!;
    final before = page(tester).pixels;
    final y = (focus.context!.findRenderObject()! as RenderBox).localToGlobal(Offset.zero).dy;
    await key(tester, LogicalKeyboardKey.enter);
    related.complete([
      MediaHub(
        id: 'similar',
        title: 'Similar',
        type: 'movie',
        items: [movieItem(id: 'other')],
      ),
    ]);
    await tester.pumpAndSettle();
    expect(page(tester).pixels, before);
    await key(tester, LogicalKeyboardKey.escape);
    expect(FocusManager.instance.primaryFocus, same(focus));
    expect(page(tester).pixels, before);
    expect((focus.context!.findRenderObject()! as RenderBox).localToGlobal(Offset.zero).dy, closeTo(y, 0.01));
    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(focusedRow(), 'Similar');
    expect(page(tester).pixels, greaterThan(before));
  });

  testWidgets('A7 A12 critic-only panel uses critic as title without duplicated author or icon', (tester) async {
    final gate = await mountReviews(tester);
    gate.complete([const TvMovieReview(tag: 'Only critic', text: 'Complete text')]);
    await tester.pumpAndSettle();
    await key(tester, LogicalKeyboardKey.arrowDown);
    await key(tester, LogicalKeyboardKey.enter);
    final panel = find.byType(TvRightPanel);
    expect(find.descendant(of: panel, matching: find.text('Only critic')), findsOneWidget);
    expect(find.descendant(of: panel, matching: find.text('Complete text')), findsOneWidget);
    expect(find.descendant(of: panel, matching: find.byType(SvgPicture)), findsNothing);
    final body = tester.state<ScrollableState>(find.descendant(of: panel, matching: find.byType(Scrollable))).position;
    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(body.pixels, 0);
    await key(tester, LogicalKeyboardKey.escape);
    expect(focusedRow(), 'Reviews');
  });

  for (final fails in [false, true]) {
    testWidgets('A3 A16 empty/error reviews preserve rows and navigation error=$fails', (tester) async {
      final gate = await mountReviews(tester, cast: true, related: true);
      final titles = tester.widgetList<TvHorizontalRow>(find.byType(TvHorizontalRow)).map((w) => w.title).toList();
      if (fails) {
        gate.completeError(StateError('offline'));
      } else {
        gate.complete([]);
      }
      await tester.pumpAndSettle();
      expect(tester.widgetList<TvHorizontalRow>(find.byType(TvHorizontalRow)).map((w) => w.title), titles);
      expect(find.byType(TvMovieReviewCard), findsNothing);
      await key(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedRow(), titles.first);
      await key(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedRow(), titles.last);
      await key(tester, LogicalKeyboardKey.arrowUp);
      expect(focusedRow(), titles.first);
      expect(tester.takeException(), isNull);
    });
  }
}
