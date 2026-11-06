import 'dart:async';
import 'package:flutter/material.dart';
import '../../../i18n/strings.g.dart';
import '../../../media/media_item.dart';
import '../../../services/watch_actions.dart';
import '../../../utils/error_message_utils.dart';
import '../../../utils/platform_detector.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../widgets/media_context_menu.dart';
import '../components/tv_action_row.dart';
import '../components/tv_button.dart';
import '../tv_strings.dart';
import 'tv_download_action.dart';
import 'tv_show_controller.dart';

class TvEpisodeActions extends StatefulWidget {
  const TvEpisodeActions({
    super.key,
    required this.controller,
    required this.item,
    required this.primaryFocus,
    required this.play,
    this.markWatched,
  });
  final TvShowController controller;
  final MediaItem item;
  final FocusNode primaryFocus;
  final Future<void> Function(MediaItem, {bool restart}) play;

  /// Test adapter; production uses WatchActions including tracker events.
  final Future<WatchMarkOutcome> Function(MediaItem, bool)? markWatched;

  @override
  State<TvEpisodeActions> createState() => _TvEpisodeActionsState();
}

class _TvEpisodeActionsState extends State<TvEpisodeActions> {
  final _menu = GlobalKey<MediaContextMenuState>();
  bool _busy = false;

  Future<void> _toggleWatched() async {
    if (_busy) return;
    final item = widget.item;
    setState(() => _busy = true);
    try {
      final outcome =
          await (widget.markWatched?.call(item, !item.isWatched) ??
              WatchActions.setWatched(context, item, watched: !item.isWatched, offline: false));
      if (!mounted || outcome == WatchMarkOutcome.skipped) return;
      widget.controller.watchStateChanged = true;
      await widget.controller.refresh();
    } catch (error) {
      if (mounted) showErrorSnackBar(context, t.messages.errorLoading(error: localizedErrorReason(error)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final progress = (item.viewOffsetMs ?? 0) > 0;
    final remaining = (item.durationMs ?? 0) - (item.viewOffsetMs ?? 0);
    return TvActionRow(
      rowKey: const ValueKey('episode-actions'),
      buttons: [
        TvButton(
          label: progress ? 'Continue${remaining > 0 ? ' · ${TvStrings.left(remaining)}' : ''}' : 'Play',
          icon: Icons.play_arrow,
          focusNode: widget.primaryFocus,
          onSelect: () => unawaited(widget.play(item, restart: false)),
        ),
        if (progress)
          TvButton(
            label: 'С начала',
            variant: TvButtonVariant.secondary,
            onSelect: () => unawaited(widget.play(item, restart: true)),
          ),
        TvIconButton(
          icon: item.isWatched ? Icons.remove_done : Icons.check,
          caption: item.isWatched ? t.tooltips.markAsUnwatched : t.tooltips.markAsWatched,
          disabled: _busy,
          onSelect: () => unawaited(_toggleWatched()),
        ),
        if (!PlatformDetector.isAppleTV()) TvDownloadAction(item: item, client: widget.controller.client),
        MediaContextMenu(
          key: _menu,
          item: item,
          onRefresh: (_) => unawaited(widget.controller.refresh()),
          child: TvIconButton(
            icon: Icons.more_horiz,
            caption: TvStrings.moreActions,
            onSelect: () {
              final menu = _menu.currentState;
              if (menu != null) menu.showContextMenu(menu.context);
            },
          ),
        ),
      ],
    );
  }
}
