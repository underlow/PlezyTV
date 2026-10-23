import 'package:flutter/material.dart';

import '../../../focus/input_mode_tracker.dart';
import '../../../media/media_item.dart';
import '../../../media/media_server_client.dart';
import '../../../utils/formatters.dart';
import '../../../widgets/optimized_media_image.dart';
import '../tv_focusable.dart';
import '../tv_strings.dart';
import '../tv_theme.dart';
import '../tv_tokens.dart';

enum TvPosterSize {
  row,
  grid,
  season;

  Size get dimensions => switch (this) {
    row => Size(TvTokens.size.poster.w.toDouble(), TvTokens.size.poster.h.toDouble()),
    grid => Size(TvTokens.size.posterGrid.w.toDouble(), TvTokens.size.posterGrid.h.toDouble()),
    season => Size(TvTokens.size.seasonPoster.w.toDouble(), TvTokens.size.seasonPoster.h.toDouble()),
  };
}

/// Caption may be supplied already formatted by Plezy (for example a season
/// count). No catalog or watch-state policy lives in this visual component.
class TvPoster extends StatelessWidget {
  const TvPoster({
    super.key,
    required this.item,
    this.size = TvPosterSize.row,
    this.caption,
    this.client,
    this.localFilePath,
    this.onServer = false,
    this.disabled = false,
    this.focusNode,
    this.autofocus = false,
    this.onSelect,
    this.onLongPress,
    this.onFocusChange,
  });

  final MediaItem item;
  final TvPosterSize size;
  final String? caption, localFilePath;
  final MediaServerClient? client;
  final bool onServer, disabled, autofocus;
  final FocusNode? focusNode;
  final VoidCallback? onSelect, onLongPress;
  final ValueChanged<bool>? onFocusChange;

  @override
  Widget build(BuildContext context) => _MediaCard(
    item: item,
    dimensions: size.dimensions,
    title: item.displayTitle,
    caption: caption ?? item.year?.toString() ?? '',
    client: client,
    localFilePath: localFilePath,
    onServer: onServer,
    disabled: disabled,
    focusNode: focusNode,
    autofocus: autofocus,
    onSelect: onSelect,
    onLongPress: onLongPress,
    onFocusChange: onFocusChange,
  );
}

class TvEpisode extends StatelessWidget {
  const TvEpisode({
    super.key,
    required this.item,
    this.client,
    this.localFilePath,
    this.onServer = false,
    this.disabled = false,
    this.focusNode,
    this.autofocus = false,
    this.onSelect,
    this.onLongPress,
    this.onFocusChange,
  });
  final MediaItem item;
  final MediaServerClient? client;
  final String? localFilePath;
  final bool onServer, disabled, autofocus;
  final FocusNode? focusNode;
  final VoidCallback? onSelect, onLongPress;
  final ValueChanged<bool>? onFocusChange;

  @override
  Widget build(BuildContext context) {
    final label = formatSeasonEpisodeLabel(item.parentIndex, item.index);
    return _MediaCard(
      item: item,
      dimensions: Size(TvTokens.size.episode.w.toDouble(), TvTokens.size.episode.h.toDouble()),
      title: label == null
          ? item.title ?? ''
          : TvStrings.episode(season: item.parentIndex!, episode: item.index!, title: item.title ?? ''),
      caption: item.hasActiveProgress
          ? TvStrings.left(item.durationMs! - item.viewOffsetMs!)
          : item.durationMs == null
          ? ''
          : formatDurationTextual(item.durationMs!),
      episode: true,
      client: client,
      localFilePath: localFilePath,
      onServer: onServer,
      disabled: disabled,
      focusNode: focusNode,
      autofocus: autofocus,
      onSelect: onSelect,
      onLongPress: onLongPress,
      onFocusChange: onFocusChange,
    );
  }
}

class _MediaCard extends StatefulWidget {
  const _MediaCard({
    required this.item,
    required this.dimensions,
    required this.title,
    required this.caption,
    this.episode = false,
    this.client,
    this.localFilePath,
    required this.onServer,
    required this.disabled,
    this.focusNode,
    required this.autofocus,
    this.onSelect,
    this.onLongPress,
    this.onFocusChange,
  });
  final MediaItem item;
  final Size dimensions;
  final String title, caption;
  final bool episode, onServer, disabled, autofocus;
  final MediaServerClient? client;
  final String? localFilePath;
  final FocusNode? focusNode;
  final VoidCallback? onSelect, onLongPress;
  final ValueChanged<bool>? onFocusChange;
  @override
  State<_MediaCard> createState() => _MediaCardState();
}

class _MediaCardState extends State<_MediaCard> {
  bool _focused = false;
  @override
  Widget build(BuildContext context) {
    final theme = TvTheme.of(context);
    final px = theme.px;
    final width = px(widget.dimensions.width), height = px(widget.dimensions.height);
    final focused = _focused && !widget.disabled && InputModeTracker.isKeyboardMode(context);
    final count = widget.item.unwatchedCount;
    final showCount = !widget.episode && focused && count != null && count > 0;
    Widget placeholder(BuildContext context, String path) => ColoredBox(color: TvTokens.color.surface.level2);
    final image = widget.episode
        ? OptimizedMediaImage.thumb(
            client: widget.client,
            imagePath: widget.item.thumbPath,
            localFilePath: widget.localFilePath,
            width: width,
            height: height,
            fadeInDuration: Duration.zero,
            placeholder: placeholder,
            errorWidget: (context, path, error) => placeholder(context, path),
          )
        : OptimizedMediaImage.poster(
            client: widget.client,
            imagePath: widget.item.thumbPath,
            localFilePath: widget.localFilePath,
            width: width,
            height: height,
            fadeInDuration: Duration.zero,
            placeholder: placeholder,
            errorWidget: (context, path, error) => placeholder(context, path),
          );
    return SizedBox(
      width: width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TvFocusable(
            focusNode: widget.focusNode,
            autofocus: widget.autofocus,
            disabled: widget.disabled,
            scaleAlignment: Alignment.bottomCenter,
            focusedScale: widget.episode ? TvTokens.focus.episodeScale : TvTokens.focus.cardScale,
            onSelect: widget.onSelect,
            onLongPress: widget.onLongPress,
            semanticLabel: widget.title,
            semanticValue: showCount ? TvStrings.unwatched(count) : widget.caption,
            onFocusChange: (value) {
              setState(() => _focused = value);
              widget.onFocusChange?.call(value);
            },
            builder: (context, state) => RepaintBoundary(
              child: SizedBox(
                width: width,
                height: height,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(px(TvTokens.radius.card)),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(color: TvTokens.color.surface.level2),
                      image,
                      TvMediaBadges(item: widget.item, onServer: widget.onServer),
                      if (widget.item.hasActiveProgress)
                        Positioned(left: 0, right: 0, bottom: 0, child: TvMediaProgress(item: widget.item)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SizedBox(height: px(20)),
          Opacity(
            opacity: widget.disabled ? TvTokens.focus.disabledOpacity : 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.body.copyWith(
                    color: focused ? TvTokens.color.text.primary : TvTokens.color.text.secondary,
                    fontWeight: focused ? FontWeight.w600 : FontWeight.w400,
                    fontVariations: [FontVariation('wght', focused ? 600 : 400)],
                  ),
                ),
                Text(
                  showCount ? TvStrings.unwatched(count) : widget.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.caption.copyWith(
                    color: showCount ? TvTokens.color.accent.normal : TvTokens.color.text.tertiary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Non-focusable watch-state plates; precedence follows Plezy getters.
class TvMediaBadges extends StatelessWidget {
  const TvMediaBadges({super.key, required this.item, this.onServer = false});
  final MediaItem item;
  final bool onServer;
  @override
  Widget build(BuildContext context) {
    final theme = TvTheme.of(context);
    final px = theme.px;
    final count = item.unwatchedCount;
    Widget plate(Color color, Widget child, {bool square = false}) => Container(
      height: px(32),
      width: square ? px(32) : null,
      constraints: square ? null : BoxConstraints(minWidth: px(TvTokens.size.unwatchedBadge.minW)),
      padding: square ? EdgeInsets.zero : EdgeInsets.symmetric(horizontal: px(8)),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(px(TvTokens.radius.badge))),
      alignment: Alignment.center,
      child: child,
    );
    return Stack(
      children: [
        if (item.isWatched || (count != null && count > 0))
          Positioned(
            top: px(8),
            right: px(8),
            child: item.isWatched
                ? plate(
                    TvTokens.color.status.watched,
                    Icon(Icons.check, size: px(24), color: TvTokens.color.text.primary),
                    square: true,
                  )
                : plate(
                    TvTokens.color.accent.normal,
                    Text('$count', style: theme.badge.copyWith(color: TvTokens.color.text.onAccent)),
                  ),
          ),
        if (onServer)
          Positioned(
            top: px(8),
            left: px(8),
            child: plate(
              TvTokens.color.status.onServer,
              Text(TvStrings.onServer, style: theme.badge.copyWith(color: TvTokens.color.text.primary)),
            ),
          ),
      ],
    );
  }
}

class TvMediaProgress extends StatelessWidget {
  const TvMediaProgress({super.key, required this.item});
  final MediaItem item;
  @override
  Widget build(BuildContext context) => !item.hasActiveProgress
      ? const SizedBox.shrink()
      : SizedBox(
          height: TvTheme.of(context).px(TvTokens.size.progressBar.h),
          child: ColoredBox(
            color: TvTokens.color.status.progressTrack,
            child: Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: item.viewOffsetMs! / item.durationMs!,
                heightFactor: 1,
                child: ColoredBox(color: TvTokens.color.status.progressFill),
              ),
            ),
          ),
        );
}
