import 'package:flutter/material.dart';

import '../tv_theme.dart';
import '../tv_tokens.dart';
import 'tv_cards.dart';

/// Static placeholders: no timers, tickers, image loads or focus nodes.
class TvPosterSkeleton extends StatelessWidget {
  const TvPosterSkeleton({super.key, this.size = TvPosterSize.row});
  final TvPosterSize size;
  @override
  Widget build(BuildContext context) => _CardSkeleton(dimensions: size.dimensions);
}

class TvEpisodeSkeleton extends StatelessWidget {
  const TvEpisodeSkeleton({super.key});
  @override
  Widget build(BuildContext context) =>
      _CardSkeleton(dimensions: Size(TvTokens.size.episode.w.toDouble(), TvTokens.size.episode.h.toDouble()));
}

class _CardSkeleton extends StatelessWidget {
  const _CardSkeleton({required this.dimensions});
  final Size dimensions;
  @override
  Widget build(BuildContext context) {
    final px = TvTheme.of(context).px;
    return SizedBox(
      width: px(dimensions.width),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: px(dimensions.width),
            height: px(dimensions.height),
            decoration: BoxDecoration(
              color: TvTokens.color.bg.skeleton,
              borderRadius: BorderRadius.circular(px(TvTokens.radius.card)),
            ),
          ),
          SizedBox(height: px(20)),
          _Line(width: dimensions.width * .8, height: TvTokens.type.body.lineHeight.toDouble()),
          _Line(width: dimensions.width * .5, height: TvTokens.type.caption.lineHeight.toDouble()),
        ],
      ),
    );
  }
}

class TvRowSkeleton extends StatelessWidget {
  const TvRowSkeleton({super.key, this.count = 7, this.episode = false});
  final int count;
  final bool episode;
  @override
  Widget build(BuildContext context) {
    final px = TvTheme.of(context).px;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Line(width: 280, height: 40),
        SizedBox(height: px(40)),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          child: Row(
            children: [
              for (var i = 0; i < count; i++) ...[
                if (i > 0) SizedBox(width: px(TvTokens.space.cardGap)),
                if (episode) const TvEpisodeSkeleton() else const TvPosterSkeleton(),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// One text line placeholder, [width] × [height] in design pixels.
class TvLineSkeleton extends StatelessWidget {
  const TvLineSkeleton({super.key, required this.width, required this.height});
  final double width, height;
  @override
  Widget build(BuildContext context) => _Line(width: width, height: height);
}

class _Line extends StatelessWidget {
  const _Line({required this.width, required this.height});
  final double width, height;
  @override
  Widget build(BuildContext context) {
    final px = TvTheme.of(context).px;
    return SizedBox(
      height: px(height),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          width: px(width),
          height: px(height * .5),
          decoration: BoxDecoration(
            color: TvTokens.color.bg.skeletonLine,
            borderRadius: BorderRadius.circular(px(TvTokens.radius.xs)),
          ),
        ),
      ),
    );
  }
}
