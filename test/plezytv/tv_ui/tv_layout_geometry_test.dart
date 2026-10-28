import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/plezytv/tv_ui/tv_tokens.dart';
import 'package:plezy/navigation/main_screen_scope.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_cards.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_horizontal_row.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_person_card.dart';
import 'package:plezy/plezytv/tv_ui/tv_focusable.dart';
import '../../test_helpers/media_items.dart';
import 'tv_theme_test_helper.dart';

// Read actual painted ring bounds, including the paint-only transform which
// intentionally does not affect layout, hit testing or localToGlobal.
Rect paintedRing(WidgetTester tester) {
  final ring = find.descendant(
    of: find.byType(TvFocusVisual),
    matching: find.byWidgetPredicate(
      (w) => w is DecoratedBox && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).border != null,
    ),
  );
  final box = tester.renderObject<RenderBox>(ring);
  RenderObject? ancestor = box;
  while (ancestor != null && ancestor.runtimeType.toString() != '_RenderPaintScale') {
    ancestor = ancestor.parent;
  }
  final paintBox = ancestor! as RenderBox;
  // Non-composited person photos apply the same transform to the canvas
  // without retaining a TransformLayer. Read the actual render parameters.
  final dynamic paint = paintBox;
  final double scale = paint.scale as double;
  final Alignment alignment = paint.alignment as Alignment;
  final origin = alignment.alongSize(paintBox.size);
  final matrix = paintBox.debugLayer is TransformLayer
      ? (paintBox.debugLayer as TransformLayer).transform!
      : (Matrix4.diagonal3Values(scale, scale, 1)
          ..setTranslationRaw(origin.dx * (1 - scale), origin.dy * (1 - scale), 0));
  final offset = box.localToGlobal(Offset.zero, ancestor: paintBox);
  return MatrixUtils.transformRect(matrix, offset & box.size).shift(paintBox.localToGlobal(Offset.zero));
}

void main() {
  for (final shape in ['poster', 'square', 'person', 'episode']) {
    for (final reduced in [false, true]) {
      testWidgets('$shape painted focus clears neighbors, header and caption (reduced=$reduced)', (tester) async {
        final nodes = <int, FocusNode>{};
        final width = shape == 'episode'
            ? 400.0
            : shape == 'person'
            ? 200.0
            : 216.0;
        await pumpTvWidget(
          tester,
          Align(
            alignment: Alignment.topLeft,
            child: TvHorizontalRow(
              title: 'Section',
              itemCount: 3,
              cardWidth: width,
              cardHeight: shape == 'poster'
                  ? 404
                  : shape == 'episode'
                  ? 305
                  : 296,
              cardBuilder: (_, i, node) {
                nodes[i] = node;
                final item = testMediaItem(title: 'Card $i');
                return switch (shape) {
                  'person' => TvPersonCard(client: null, imagePath: null, name: 'Card $i', focusNode: node),
                  'square' => TvMusicCard(item: item, focusNode: node),
                  'episode' => TvEpisode(item: item, focusNode: node),
                  _ => TvPoster(item: item, focusNode: node),
                };
              },
            ),
          ),
          reduced: reduced,
        );
        // No shell/scope here: the default inset must still be the content inset.
        expect(tester.getTopLeft(find.text('Section')).dx, TvTokens.space.contentLeft);
        nodes[1]!.requestFocus();
        await tester.pumpAndSettle();
        final ring = paintedRing(tester);
        final cards = find.byType(
          shape == 'person'
              ? TvPersonCard
              : shape == 'square'
              ? TvMusicCard
              : shape == 'episode'
              ? TvEpisode
              : TvPoster,
        );
        final first = tester.getRect(cards.at(0));
        final third = tester.getRect(cards.at(2));
        expect(ring.left, greaterThan(first.right));
        expect(ring.right, lessThan(third.left));
        expect(ring.top, greaterThan(tester.getBottomLeft(find.text('Section')).dy));
        final caption = find.descendant(of: cards.at(1), matching: find.byType(Text)).first;
        expect(ring.bottom, lessThan(tester.getTopLeft(caption).dy));
        final artHeight = shape == 'poster'
            ? 324.0
            : shape == 'episode'
            ? 225.0
            : shape == 'person'
            ? 200.0
            : 216.0;
        final scale = shape == 'episode' ? 1.03 : 1.05;
        expect(ring.width, closeTo((width + 14) * scale, .001));
        expect(ring.height, closeTo((artHeight + 14) * scale, .001));
        expect(tester.takeException(), isNull);
      });
    }
  }
  for (final offset in [0.0, (TvTokens.size.sidebar.collapsedW - TvTokens.space.cardFocusReserve).toDouble()]) {
    testWidgets('row visible content starts at the content inset with foreground offset $offset', (tester) async {
      await pumpTvWidget(
        tester,
        MainScreenFocusScope(
          focusSidebar: () {},
          sideNavigationWidth: offset,
          foregroundLeft: offset,
          child: Padding(
            padding: EdgeInsets.only(left: offset),
            child: Align(
              alignment: Alignment.topLeft,
              child: TvHorizontalRow(
                title: 'Section',
                itemCount: 1,
                cardWidth: 216,
                cardHeight: 404,
                cardBuilder: (_, i, node) => TvPoster(
                  item: testMediaItem(title: 'Card'),
                  focusNode: node,
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.getTopLeft(find.text('Section')).dx, TvTokens.space.contentLeft);
      expect(tester.getTopLeft(find.byType(TvPoster)).dx, TvTokens.space.contentLeft);
    });
  }
}
