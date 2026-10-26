import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../components/tv_right_panel.dart';
import '../tv_focusable.dart';
import '../tv_theme.dart';
import '../tv_tokens.dart';
import 'tv_movie_reviews.dart';

/// Critic review surface in the S8 rail. The rail owns its focus node.
class TvMovieReviewCard extends StatelessWidget {
  const TvMovieReviewCard({super.key, required this.review, required this.focusNode, required this.onSelect});

  final TvMovieReview review;
  final FocusNode focusNode;
  final VoidCallback onSelect;

  static Future<void> showPanel(BuildContext context, TvMovieReview review, FocusNode anchor) => TvRightPanel.show(
    context: context,
    anchor: anchor,
    root: TvRightPanelPage(
      title: (review.source ?? review.tag)!,
      singleLineTitle: true,
      bodyBuilder: (_) => _ReviewBody(review: review),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = TvTheme.of(context), px = theme.px;
    return TvFocusable(
      focusNode: focusNode,
      semanticLabel: '${review.source ?? review.tag}: ${review.text}',
      focusedScale: TvTokens.focus.cardScale,
      scaleAlignment: Alignment.bottomCenter,
      onSelect: onSelect,
      builder: (context, state) => Container(
        width: px(512),
        height: px(256),
        padding: EdgeInsets.all(px(24)),
        decoration: BoxDecoration(
          color: TvTokens.color.surface.level2,
          borderRadius: BorderRadius.circular(px(TvTokens.radius.card)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (review.freshness != null) ...[_Freshness(value: review.freshness!), SizedBox(width: px(16))],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        review.source ?? review.tag!,
                        style: theme.body,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (review.source != null && review.tag != null)
                        Text(
                          review.tag!,
                          style: theme.caption.copyWith(color: TvTokens.color.text.secondary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: px(16)),
            Expanded(
              child: Text(review.text, style: theme.bodyLarge, maxLines: 4, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }
}

class _Freshness extends StatelessWidget {
  const _Freshness({required this.value});
  final TvMovieReviewFreshness value;

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    'assets/rating_icons/rt_${value.name}.svg',
    width: TvTheme.of(context).px(40),
    height: TvTheme.of(context).px(40),
  );
}

class _ReviewBody extends StatefulWidget {
  const _ReviewBody({required this.review});
  final TvMovieReview review;

  @override
  State<_ReviewBody> createState() => _ReviewBodyState();
}

class _ReviewBodyState extends State<_ReviewBody> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = TvTheme.of(context), px = theme.px;
    final review = widget.review;
    return Focus(
      autofocus: true,
      onKeyEvent: (_, event) {
        final key = event.logicalKey;
        if (![
          LogicalKeyboardKey.arrowUp,
          LogicalKeyboardKey.arrowDown,
          LogicalKeyboardKey.arrowLeft,
          LogicalKeyboardKey.arrowRight,
        ].contains(key)) {
          return KeyEventResult.ignored;
        }
        if ((event is KeyDownEvent || event is KeyRepeatEvent) &&
            _scroll.hasClients &&
            (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowDown)) {
          final step = px(102) * (key == LogicalKeyboardKey.arrowUp ? -1 : 1);
          _scroll.jumpTo((_scroll.offset + step).clamp(0.0, _scroll.position.maxScrollExtent));
        }
        return KeyEventResult.handled;
      },
      child: SingleChildScrollView(
        controller: _scroll,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (review.freshness != null || (review.source != null && review.tag != null)) ...[
              Row(
                children: [
                  if (review.freshness != null) ...[_Freshness(value: review.freshness!), SizedBox(width: px(16))],
                  if (review.source != null && review.tag != null)
                    Expanded(
                      child: Text(review.tag!, style: theme.caption.copyWith(color: TvTokens.color.text.secondary)),
                    ),
                ],
              ),
              SizedBox(height: px(24)),
            ],
            Text(review.text, style: theme.bodyLarge),
          ],
        ),
      ),
    );
  }
}
