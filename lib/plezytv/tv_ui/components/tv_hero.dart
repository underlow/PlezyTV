import 'package:flutter/material.dart';

import '../../../media/media_item.dart';
import '../../../media/media_item_types.dart';
import '../../../media/media_kind.dart';
import '../../../media/media_server_client.dart';
import '../../../services/device_performance.dart';
import '../../../utils/content_utils.dart';
import '../../../utils/formatters.dart';
import '../../../widgets/optimized_media_image.dart';
import '../tv_strings.dart';
import '../tv_theme.dart';
import '../tv_tokens.dart';
import 'tv_ratings.dart';

/// Text follows the selected item immediately. The screen owns backdrop debounce.
/// This component occupies the hero slot; its parent owns the content inset.
class TvHero extends StatelessWidget {
  const TvHero({super.key, required this.item, this.compact = false, this.hideSpoilers = false, this.client});

  final MediaItem? item;
  final bool compact;

  /// Supplied by the screen; the hero never reads settings.
  final bool hideSpoilers;
  final MediaServerClient? client;

  @override
  Widget build(BuildContext context) {
    final theme = TvTheme.of(context);
    final px = theme.px;
    final media = item;
    final episode = media?.kind == MediaKind.episode;
    final show = media?.kind == MediaKind.show;
    final hidden = media != null && hideSpoilers && media.shouldHideSpoiler;
    final description = hidden
        ? (episode && media.parentIndex != null && media.index != null
              ? TvStrings.spoilerEpisode(season: media.parentIndex!, episode: media.index!, title: media.title ?? '')
              : null)
        : media?.summary;
    final music = media?.kind == MediaKind.artist || media?.kind == MediaKind.album || media?.kind == MediaKind.track;
    final metadata = music
        ? <String?>[
            if (media!.kind == MediaKind.album) ...[media.albumArtistTitle, media.year?.toString()],
            if (media.kind == MediaKind.track) ...[
              media.trackArtistTitle,
              media.albumTitle,
              if (media.durationMs != null) formatDurationTextual(media.durationMs!),
            ] else
              media.genres?.where((genre) => genre.isNotEmpty).join(', '),
          ].whereType<String>().where((part) => part.isNotEmpty).toList()
        : <String>[
            if (episode && media!.parentIndex != null && media.index != null)
              TvStrings.episode(season: media.parentIndex!, episode: media.index!, title: media.title ?? ''),
            if (!episode && media?.year != null) '${media!.year}',
            if (show && media!.childCount != null) TvStrings.seasons(media.childCount!),
            if (show && media!.leafCount != null) TvStrings.episodes(media.leafCount!),
            if (!show && media?.durationMs != null) formatDurationTextual(media!.durationMs!),
            if (episode && media!.hasActiveProgress) TvStrings.left(media.durationMs! - media.viewOffsetMs!),
            if (media?.contentRating?.isNotEmpty ?? false) formatContentRating(media!.contentRating),
            if (!episode && (media?.genres?.isNotEmpty ?? false)) media!.genres!.join(', '),
          ];
    return AnimatedContainer(
      height: px(compact ? TvTokens.size.hero.compactH : TvTokens.size.hero.h),
      duration: Duration(milliseconds: DevicePerformance.isReduced ? 0 : TvTokens.motion.heroCrossfade),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topLeft,
      clipBehavior: Clip.hardEdge,
      decoration: const BoxDecoration(),
      child: media == null
          ? null
          // Lay out text at its natural height while the outer slot animates.
          // The slot clips excess paint without squeezing the Column.
          : OverflowBox(
              alignment: Alignment.topLeft,
              minHeight: 0,
              maxHeight: double.infinity,
              child: Padding(
                padding: EdgeInsets.only(top: px(compact ? 72 : 110)),
                child: SizedBox(
                  width: px(TvTokens.size.hero.textMaxW),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Keep the title baseline fixed while the artwork box shrinks.
                      SizedBox(
                        key: const ValueKey('hero-title-slot'),
                        height: px(TvTokens.type.display.lineHeight * 2),
                        child: Align(
                          alignment: Alignment.bottomLeft,
                          child: ClearLogoImage(
                            client: client,
                            logoPath: media.clearLogoPath,
                            width: px(TvTokens.size.hero.logoMaxW * (compact ? .7 : 1)),
                            height: px(compact ? 90 : 128),
                            alignment: Alignment.bottomLeft,
                            fallbackWidth: px(TvTokens.size.hero.textMaxW),
                            fadeInDuration: Duration.zero,
                            // A missing or failed image still gets two full title lines.
                            fallbackBuilder: (context) => OverflowBox(
                              alignment: Alignment.bottomLeft,
                              minHeight: px(TvTokens.type.display.lineHeight * 2),
                              maxHeight: px(TvTokens.type.display.lineHeight * 2),
                              child: Align(
                                alignment: Alignment.bottomLeft,
                                child: Text(
                                  media.displayTitle,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.display,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (metadata.isNotEmpty) ...[
                        SizedBox(height: px(compact ? 20 : 28)),
                        Text(
                          metadata.join(' · '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.body.copyWith(color: TvTokens.color.text.secondary),
                        ),
                      ],
                      SizedBox(height: px(14)),
                      if (!music) TvRatings(item: media),
                      if (description?.isNotEmpty ?? false) ...[
                        SizedBox(height: px(compact ? 14 : 20)),
                        Text(
                          description!,
                          maxLines: compact ? 2 : 3,
                          overflow: TextOverflow.ellipsis,
                          style: theme.bodyLarge.copyWith(color: TvTokens.color.text.secondary),
                        ),
                      ],
                    ],
                  ),
                ),
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
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minHeight: 0,
          maxHeight: double.infinity,
          child: Padding(
            padding: EdgeInsets.only(top: px(compact ? 72 : 110)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                block(420, 96, TvTokens.color.bg.skeleton),
                SizedBox(height: px(32)),
                block(520, 24, TvTokens.color.bg.skeletonLine),
                SizedBox(height: px(16)),
                block(240, 24, TvTokens.color.bg.skeletonLine),
                SizedBox(height: px(28)),
                for (final width in (compact ? [860.0, 600.0] : [860.0, 820.0, 600.0])) ...[
                  block(width, 22, TvTokens.color.bg.skeletonLine),
                  SizedBox(height: px(12)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
