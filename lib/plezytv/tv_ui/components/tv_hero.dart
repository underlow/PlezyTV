import 'package:flutter/material.dart';

import '../../../media/media_item.dart';
import '../../../media/media_kind.dart';
import '../../../media/media_server_client.dart';
import '../../../services/device_performance.dart';
import '../../../utils/formatters.dart';
import '../../../widgets/optimized_media_image.dart';
import '../tv_strings.dart';
import '../tv_theme.dart';
import '../tv_tokens.dart';
import 'tv_ratings.dart';

/// Text follows the selected item immediately. The screen owns backdrop debounce.
/// This component occupies the hero slot; its parent owns the content inset.
class TvHero extends StatelessWidget {
  const TvHero({super.key, required this.item, this.compact = false, this.client});

  final MediaItem? item;
  final bool compact;
  final MediaServerClient? client;

  @override
  Widget build(BuildContext context) {
    final theme = TvTheme.of(context);
    final px = theme.px;
    final media = item;
    final episode = media?.kind == MediaKind.episode;
    final metadata = <String>[
      if (episode && media!.parentIndex != null && media.index != null)
        TvStrings.episode(season: media.parentIndex!, episode: media.index!, title: media.title ?? ''),
      if (media?.year != null) '${media!.year}',
      if (media?.contentRating?.isNotEmpty ?? false) media!.contentRating!,
      if (media?.durationMs != null) formatDurationTextual(media!.durationMs!),
      if (episode && media!.hasActiveProgress) TvStrings.left(media.durationMs! - media.viewOffsetMs!),
    ];
    return AnimatedContainer(
      height: px(compact ? TvTokens.size.hero.compactH : TvTokens.size.hero.h),
      duration: Duration(milliseconds: DevicePerformance.isReduced ? 0 : TvTokens.motion.heroCrossfade),
      curve: Curves.easeOutCubic,
      alignment: Alignment.centerLeft,
      child: media == null
          ? null
          : SizedBox(
              width: px(TvTokens.size.hero.textMaxW),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClearLogoImage(
                    client: client,
                    logoPath: media.clearLogoPath,
                    width: px(TvTokens.size.hero.logoMaxW * (compact ? .7 : 1)),
                    height: px(TvTokens.size.hero.logoMaxH * (compact ? .6 : 1)),
                    fallbackWidth: px(TvTokens.size.hero.textMaxW),
                    fadeInDuration: Duration.zero,
                    fallbackBuilder: (context) => Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        media.displayTitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.display,
                      ),
                    ),
                  ),
                  if (metadata.isNotEmpty) ...[
                    SizedBox(height: px(TvTokens.space.md)),
                    Text(
                      metadata.join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.body.copyWith(color: TvTokens.color.text.secondary),
                    ),
                  ],
                  SizedBox(height: px(TvTokens.space.md)),
                  TvRatings(item: media),
                  if (media.summary?.isNotEmpty ?? false) ...[
                    SizedBox(height: px(TvTokens.space.md)),
                    Text(
                      media.summary!,
                      maxLines: compact ? 2 : 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.bodyLarge.copyWith(color: TvTokens.color.text.secondary),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}

/// Static, non-focusable loading placeholder with the same hero slot dimensions.
class TvHeroSkeleton extends StatelessWidget {
  const TvHeroSkeleton({super.key, this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final px = TvTheme.of(context).px;
    Widget block(double width, double height, Color color) => Container(
      width: px(width),
      height: px(height),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(px(TvTokens.radius.xs))),
    );
    return SizedBox(
      height: px(compact ? TvTokens.size.hero.compactH : TvTokens.size.hero.h),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            block(
              TvTokens.size.hero.logoMaxW * (compact ? .7 : 1),
              TvTokens.size.hero.logoMaxH * (compact ? .6 : 1),
              TvTokens.color.bg.skeleton,
            ),
            SizedBox(height: px(TvTokens.space.lg)),
            block(480, 16, TvTokens.color.bg.skeletonLine),
            SizedBox(height: px(TvTokens.space.lg)),
            for (var i = 0; i < (compact ? 2 : 3); i++) ...[
              block(
                i == (compact ? 1 : 2) ? 600 : TvTokens.size.hero.textMaxW.toDouble(),
                16,
                TvTokens.color.bg.skeletonLine,
              ),
              SizedBox(height: px(TvTokens.space.md)),
            ],
          ],
        ),
      ),
    );
  }
}
