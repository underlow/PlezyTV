import 'dart:async';

import 'package:provider/provider.dart';

import 'package:flutter/material.dart';

import '../../../media/media_item.dart';
import '../../../media/media_backend.dart';
import '../../../media/media_item_types.dart';
import '../../../media/media_kind.dart';
import '../../../media/media_server_client.dart';
import '../../../services/device_performance.dart';
import '../../../services/plex_client.dart';
import '../../../providers/catalog_sources_provider.dart';
import '../../../media/media_rating.dart';
import '../../../services/catalog/community_ratings.dart';
import '../../../widgets/media_rating_badge.dart';
import '../../../utils/content_utils.dart';
import '../../../utils/formatters.dart';
import '../../../widgets/optimized_media_image.dart';
import '../tv_strings.dart';
import '../tv_theme.dart';
import '../tv_tokens.dart';
import 'tv_ratings.dart';

/// Text follows the selected item immediately. The screen owns backdrop debounce.
/// This component occupies the hero slot; its parent owns the content inset.
class TvHero extends StatefulWidget {
  const TvHero({
    super.key,
    required this.item,
    this.compact = false,
    this.hideSpoilers = false,
    this.client,
    this.loadFullRatings = false,
  });

  final MediaItem? item;
  final bool compact;

  /// Supplied by the screen; the hero never reads settings.
  final bool hideSpoilers;
  final MediaServerClient? client;

  /// Home opts in for Plex movies/shows: debounce like the backdrop, cache
  /// metadata per server/item, and hide ratings until a successful response.
  final bool loadFullRatings;

  @override
  State<TvHero> createState() => _TvHeroState();
}

class _TvHeroState extends State<TvHero> {
  // Keep only successful metadata; insertion order tracks the 100 most recent items.
  final _cache = <String, MediaItem>{};
  final _pending = <String, Future<MediaItem?>>{};
  StreamSubscription<List<MediaRatingSource>>? _ratingsSubscription;
  List<MediaRatingSource> _communityRatings = const [];
  Timer? _timer;
  int _generation = 0;
  MediaItem? _ratingsItem;
  bool _loadingFull = false;

  bool get _needsFull =>
      widget.loadFullRatings &&
      widget.item?.backend == MediaBackend.plex &&
      (widget.item?.kind == MediaKind.movie || widget.item?.kind == MediaKind.show);

  @override
  void initState() {
    super.initState();
    _select();
  }

  @override
  void didUpdateWidget(TvHero oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item?.globalKey != widget.item?.globalKey ||
        oldWidget.client != widget.client ||
        oldWidget.loadFullRatings != widget.loadFullRatings) {
      _select();
    }
  }

  void _select() {
    _timer?.cancel();
    unawaited(_ratingsSubscription?.cancel());
    _ratingsSubscription = null;
    _communityRatings = const [];
    final generation = ++_generation;
    _ratingsItem = null;
    _loadingFull = false;
    final item = widget.item;
    final client = widget.client;
    if (!_needsFull || item == null || client == null) return;
    final cached = _cache.remove(item.globalKey);
    if (cached != null) {
      _cache[item.globalKey] = cached;
      _ratingsItem = cached;
      _subscribe(cached, client, generation);
      return;
    }
    _loadingFull = true;
    _timer = Timer(Duration(milliseconds: TvTokens.motion.heroDebounce), () async {
      final key = item.globalKey;
      var full = _cache.remove(key);
      if (full != null) {
        _cache[key] = full;
      } else {
        final pending = _pending.putIfAbsent(key, () async {
          try {
            // Existing lightweight Plex metadata endpoint retains Rating[].
            return client is PlexClient ? await client.fetchEditableItem(item.id) : await client.fetchItem(item.id);
          } catch (_) {
            return null;
          }
        });
        full = await pending;
        if (identical(_pending[key], pending)) {
          unawaited(_pending.remove(key));
          if (full != null) {
            _cache[key] = full;
            while (_cache.length > 100) {
              _cache.remove(_cache.keys.first);
            }
          }
        }
      }
      if (!mounted || generation != _generation) return;
      setState(() {
        _ratingsItem = full;
        _loadingFull = false;
      });
      if (full == null) return;
      _subscribe(full, client, generation);
    });
  }

  void _subscribe(MediaItem full, MediaServerClient client, int generation) {
    _ratingsSubscription = context
        .read<CatalogSourcesProvider?>()
        ?.communityRatingsForLibraryItem(full, client: client)
        .listen((ratings) {
          if (!mounted || generation != _generation) return;
          setState(() => _communityRatings = ratings);
        }, onError: (Object _) {});
  }

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(_ratingsSubscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = TvTheme.of(context);
    final px = theme.px;
    final media = widget.item;
    final compact = widget.compact;
    final client = widget.client;
    final hideSpoilers = widget.hideSpoilers;
    final episode = media?.kind == MediaKind.episode;
    final show = media?.kind == MediaKind.show;
    final hidden = media != null && hideSpoilers && media.shouldHideSpoiler;
    final summary = (media?.summary?.isNotEmpty ?? false) ? media!.summary : _ratingsItem?.summary;
    final genres = (media?.genres?.isNotEmpty ?? false) ? media!.genres : _ratingsItem?.genres;
    final description = hidden
        ? (episode && media.parentIndex != null && media.index != null
              ? TvStrings.spoilerEpisode(season: media.parentIndex!, episode: media.index!, title: media.title ?? '')
              : null)
        : summary;
    final reserveRatings =
        _loadingFull ||
        (media != null &&
            (_needsFull
                ? (_ratingsItem != null &&
                      withCommunityRatings(mediaRatingsFor(_ratingsItem!), _communityRatings).isNotEmpty)
                : mediaRatingsFor(media).isNotEmpty));
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
            if (!show && !(episode && media!.hasActiveProgress) && media?.durationMs != null)
              formatDurationTextual(media!.durationMs!),
            if (episode && media!.hasActiveProgress) TvStrings.left(media.durationMs! - media.viewOffsetMs!),
            if (!episode && (media?.contentRating?.isNotEmpty ?? false)) formatContentRating(media!.contentRating),
            if (!episode && (genres?.isNotEmpty ?? false)) genres!.take(3).join(', '),
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
                padding: EdgeInsets.zero,
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
                            height: px(TvTokens.size.hero.logoMaxH),
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
                        SizedBox(height: px(TvTokens.space.sm)),
                        Text(
                          metadata.join(' · '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.body.copyWith(color: TvTokens.color.text.secondary),
                        ),
                      ],
                      if (!music) ...[
                        SizedBox(height: px(reserveRatings ? TvTokens.space.sm : 0)),
                        SizedBox(
                          height: px(reserveRatings ? TvTokens.type.body.lineHeight : 0),
                          child: (!_needsFull || _ratingsItem != null)
                              ? TvRatings(
                                  item: _needsFull ? _ratingsItem! : media,
                                  ratings: _needsFull
                                      ? withCommunityRatings(mediaRatingsFor(_ratingsItem!), _communityRatings)
                                      : null,
                                )
                              : null,
                        ),
                      ],
                      if (description?.isNotEmpty ?? false) ...[
                        SizedBox(height: px(TvTokens.space.md)),
                        Text(
                          description!,
                          maxLines: 2,
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
            padding: EdgeInsets.zero,
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
                for (final width in [860.0, 600.0]) ...[
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
