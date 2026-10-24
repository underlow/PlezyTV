import 'package:flutter/material.dart';

import '../../../media/media_source_info.dart';
import '../../../mpv/mpv.dart';
import '../../../services/scrub_preview_source.dart';
import '../../../utils/formatters.dart';
import '../tv_theme.dart';
import '../tv_tokens.dart';

/// The progress bar of the TV player panel (design-system §6.1): track,
/// buffered ranges, watched part, chapter ticks, the seek range while a
/// keyboard burst is pending, and the thumb while focused. Paint only; input
/// belongs to the panel.
class TvPlayerProgressBar extends StatelessWidget {
  const TvPlayerProgressBar({
    super.key,
    required this.player,
    required this.position,
    required this.duration,
    required this.pendingPosition,
    required this.focused,
    required this.inactive,
    required this.chapters,
  });

  final Player player;
  final Duration position;
  final Duration duration;
  final Duration? pendingPosition;
  final bool focused;

  /// Buffering or no playback control: no thumb, faded (§6.1).
  final bool inactive;

  /// Chapter ticks; empty when Plezy hides chapter markers on the timeline.
  final List<MediaChapter> chapters;

  @override
  Widget build(BuildContext context) {
    final px = TvTheme.of(context).px;
    final bar = TvTokens.player.bar;
    return StreamBuilder<List<BufferRange>>(
      stream: player.streams.bufferRanges,
      initialData: player.state.bufferRanges,
      builder: (context, snapshot) => Opacity(
        opacity: inactive ? TvTokens.focus.disabledOpacity : 1,
        child: CustomPaint(
          size: Size.infinite,
          painter: _BarPainter(
            position: position,
            duration: duration,
            pending: pendingPosition,
            buffered: snapshot.data ?? const [],
            chapters: chapters,
            trackHeight: px(focused && !inactive ? bar.focusedH : bar.h),
            thumb: focused && !inactive ? px(bar.thumb) : 0,
            thumbBorder: px(4),
            tick: px(bar.chapterTick),
          ),
        ),
      ),
    );
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter({
    required this.position,
    required this.duration,
    required this.pending,
    required this.buffered,
    required this.chapters,
    required this.trackHeight,
    required this.thumb,
    required this.thumbBorder,
    required this.tick,
  });

  final Duration position;
  final Duration duration;
  final Duration? pending;
  final List<BufferRange> buffered;
  final List<MediaChapter> chapters;
  final double trackHeight;
  final double thumb;
  final double thumbBorder;
  final double tick;

  double _fraction(Duration value) {
    final total = duration.inMilliseconds;
    if (total <= 0) return 0;
    return (value.inMilliseconds / total).clamp(0.0, 1.0);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final bar = TvTokens.player.bar;
    final centerY = size.height / 2;
    final top = centerY - trackHeight / 2;
    final radius = Radius.circular(trackHeight / 2);
    RRect segment(double from, double to) =>
        RRect.fromLTRBR(size.width * from, top, size.width * to, top + trackHeight, radius);

    canvas.drawRRect(segment(0, 1), Paint()..color = bar.track);
    final bufferedPaint = Paint()..color = bar.buffered;
    for (final range in buffered) {
      canvas.drawRRect(segment(_fraction(range.start), _fraction(range.end)), bufferedPaint);
    }
    final watched = _fraction(position);
    canvas.drawRRect(segment(0, watched), Paint()..color = TvTokens.color.accent.normal);
    final target = pending == null ? watched : _fraction(pending!);
    if (pending != null && target != watched) {
      final from = target < watched ? target : watched;
      final to = target < watched ? watched : target;
      canvas.drawRect(
        Rect.fromLTRB(size.width * from, top, size.width * to, top + trackHeight),
        Paint()..color = bar.seekRange,
      );
    }
    final tickPaint = Paint()..color = Colors.white.withValues(alpha: 0.7);
    for (final chapter in chapters) {
      final start = chapter.startTimeOffset;
      if (start == null || start <= 0) continue;
      final x = size.width * _fraction(Duration(milliseconds: start));
      canvas.drawRect(Rect.fromLTWH(x - tick / 2, top, tick, trackHeight), tickPaint);
    }
    if (thumb > 0) {
      final center = Offset(size.width * target, centerY);
      canvas.drawCircle(center, thumb / 2 + thumbBorder, Paint()..color = TvTokens.color.bg.base);
      canvas.drawCircle(center, thumb / 2, Paint()..color = TvTokens.color.focus.fill);
    }
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.position != position ||
      old.duration != duration ||
      old.pending != pending ||
      old.buffered != buffered ||
      old.chapters != chapters ||
      old.trackHeight != trackHeight ||
      old.thumb != thumb;
}

/// The seek preview above the thumb (design-system §6.2, `10-player-seek`):
/// the frame when the server has thumbnails, the target time and the offset
/// from the current position.
class TvPlayerSeekPreview extends StatelessWidget {
  const TvPlayerSeekPreview({super.key, required this.target, required this.current, this.frame});

  final Duration target;
  final Duration current;
  final ScrubFrame? frame;

  @override
  Widget build(BuildContext context) {
    final theme = TvTheme.of(context);
    final px = theme.px;
    final preview = TvTokens.player.seekPreview;
    final delta = target - current;
    final deltaText = '${delta.isNegative ? '−' : '+'}${formatDurationTimestamp(delta.abs())}';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (frame != null) ...[
          Container(
            key: const ValueKey('tv-player-seek-frame'),
            padding: EdgeInsets.all(px(TvTokens.size.focusRing.offset)),
            decoration: BoxDecoration(
              border: Border.all(color: TvTokens.color.focus.ring, width: px(TvTokens.size.focusRing.width)),
              borderRadius: BorderRadius.circular(px(TvTokens.radius.card + TvTokens.size.focusRing.offset)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(px(TvTokens.radius.card)),
              child: SizedBox(
                width: px(preview.w),
                height: px(preview.h),
                child: _FrameView(frame: frame!),
              ),
            ),
          ),
          SizedBox(height: px(12)),
        ],
        Container(
          height: px(preview.bubbleH),
          padding: EdgeInsets.symmetric(horizontal: px(16)),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: TvTokens.color.focus.fill,
            borderRadius: BorderRadius.circular(px(TvTokens.radius.sm)),
          ),
          child: Text(
            formatDurationTimestamp(target),
            style: TextStyle(
              fontFamily: TvTokens.font.family,
              fontFamilyFallback: TvTokens.font.fallback,
              fontSize: px(26),
              fontWeight: FontWeight.w700,
              color: TvTokens.color.text.onFocus,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        SizedBox(height: px(4)),
        Text(deltaText, style: theme.caption.copyWith(color: Colors.white)),
      ],
    );
  }
}

/// One scrub frame at 320 × 180 (decoded no larger, per `player.md`).
class _FrameView extends StatelessWidget {
  const _FrameView({required this.frame});

  final ScrubFrame frame;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final ratio = MediaQuery.devicePixelRatioOf(context);
      int? cache(double size) => size.isFinite && size > 0 ? (size * ratio).round().clamp(1, 8192) : null;
      final f = frame;
      switch (f) {
        case BytesScrubFrame():
          return Image.memory(
            f.bytes,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            cacheWidth: cache(constraints.maxWidth),
            cacheHeight: cache(constraints.maxHeight),
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          );
        case SheetScrubFrame():
          final tileW = constraints.maxWidth;
          final tileH = constraints.maxHeight;
          final sheetW = tileW * f.sheetColumns;
          final sheetH = tileH * f.sheetRows;
          return ClipRect(
            child: OverflowBox(
              maxWidth: sheetW,
              maxHeight: sheetH,
              alignment: Alignment.topLeft,
              child: Transform.translate(
                offset: Offset(-f.tileColumn * tileW, -f.tileRow * tileH),
                child: Image(
                  image: ResizeImage.resizeIfNeeded(cache(sheetW), cache(sheetH), f.sheet),
                  width: sheetW,
                  height: sheetH,
                  fit: BoxFit.fill,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ),
          );
      }
    },
  );
}
