import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../i18n/strings.g.dart';
import '../../../media/ids.dart';
import '../../../media/media_item.dart';
import '../../../models/download_models.dart';
import '../../../providers/download_provider.dart';
import '../../../screens/downloads/downloads_screen.dart';
import '../../../services/catalog/library_watchlist_candidates.dart';
import '../../../services/device_performance.dart';
import '../../../services/media_list_playback_launcher.dart';
import '../../../services/watch_actions.dart';
import '../../../utils/dialogs.dart';
import '../../../utils/download_utils.dart';
import '../../../utils/error_message_utils.dart';
import '../../../utils/platform_detector.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../widgets/media_context_menu.dart';
import '../../../widgets/watchlist_source_chooser.dart';
import '../components/tv_button.dart';
import '../tv_strings.dart';
import '../tv_theme.dart';
import 'tv_show_controller.dart';

/// Public Plezy actions; private detail-screen handlers are intentionally not copied.
class TvShowActions extends StatefulWidget {
  const TvShowActions({
    super.key,
    required this.controller,
    required this.primary,
    required this.playExtra,
    this.markWatched,
  });
  final TvShowController controller;
  final Widget primary;
  final Future<void> Function(MediaItem) playExtra;

  /// Test adapter. Production always uses WatchActions, including tracker events.
  final Future<WatchMarkOutcome> Function(MediaItem, bool)? markWatched;
  @override
  State<TvShowActions> createState() => _TvShowActionsState();
}

class _TvShowActionsState extends State<TvShowActions> {
  final _menu = GlobalKey<MediaContextMenuState>();
  final _watchlist = GlobalKey();
  bool _busy = false;
  List<Listenable> _memberships = [];
  TvShowController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    c.addListener(_changed);
    _listenMemberships();
  }

  void _listenMemberships() {
    final next = [for (final candidate in c.watchlistCandidates) candidate.source.watchlistChanges];
    if (next.length == _memberships.length &&
        List.generate(next.length, (i) => identical(next[i], _memberships[i])).every((same) => same)) {
      return;
    }
    for (final source in _memberships) {
      source.removeListener(_membershipChanged);
    }
    _memberships = [for (final candidate in c.watchlistCandidates) candidate.source.watchlistChanges];
    for (final source in _memberships) {
      source.addListener(_membershipChanged);
    }
    for (final candidate in c.watchlistCandidates) {
      unawaited(candidate.source.ensureWatchlistLoaded());
    }
  }

  void _membershipChanged() {
    if (mounted) setState(() {});
  }

  void _changed() {
    _listenMemberships();
    _membershipChanged();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted) showErrorSnackBar(context, t.messages.errorLoading(error: localizedErrorReason(error)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleWatchlist() async {
    final candidates = c.watchlistCandidates;
    if (candidates.isEmpty) return;
    final box = _watchlist.currentContext?.findRenderObject() as RenderBox?;
    final candidate = candidates.length == 1
        ? candidates.single
        : await showWatchlistSourceChooser(
            context,
            kind: c.show.kind,
            candidates: candidates,
            anchorRect: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
            focusFirstItem: true,
          );
    if (!mounted || candidate == null) return;
    final current = candidate.source.isOnWatchlist(c.show.kind, candidate.ids);
    if (current == null) {
      await candidate.source.ensureWatchlistLoaded();
      return;
    }
    await mutateWatchlistMembership(c.show.kind, candidate, add: !current);
  }

  Future<void> _toggleWatched() async {
    final outcome =
        await (widget.markWatched?.call(c.show, !c.show.isWatched) ??
            WatchActions.setWatched(context, c.show, watched: !c.show.isWatched, offline: false));
    if (!mounted || outcome == WatchMarkOutcome.skipped) return;
    c.watchStateChanged = true;
    await c.refresh();
  }

  Future<void> _download(DownloadProvider provider, bool manage, bool downloaded) async {
    if (manage) {
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const DownloadsScreen()));
      return;
    }
    await queueDownloadWithFeedback(
      context,
      metadata: c.show,
      client: c.client,
      downloadProvider: provider,
      onDelete: !downloaded
          ? null
          : () async {
              final confirmed = await showDeleteConfirmation(
                context,
                title: t.downloads.deleteDownload,
                message: t.downloads.deleteConfirm(title: c.show.displayTitle),
              );
              if (confirmed && mounted) {
                await provider.deleteDownload(c.show.globalKey);
                if (mounted) showSuccessSnackBar(context, t.downloads.downloadDeleted);
              }
            },
    );
  }

  @override
  void dispose() {
    c.removeListener(_changed);
    for (final source in _memberships) {
      source.removeListener(_membershipChanged);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final downloads = context.watch<DownloadProvider?>();
    var progress = downloads?.getProgress(c.show.globalKey);
    // Plezy's show aggregate omits all-paused/all-cancelled leaves. Keep
    // those owned downloads manageable rather than offering a fresh queue.
    if (progress == null && downloads != null) {
      for (final entry in downloads.downloads.entries) {
        final item = downloads.getMetadata(entry.key);
        if (item?.serverId == c.show.serverId && item?.grandparentId == c.show.id) {
          progress = entry.value;
          break;
        }
      }
    }
    final downloaded = downloads?.isDownloaded(c.show.globalKey) ?? false;
    final rule =
        downloads?.hasSyncRule(
          downloads.syncRuleKeyForClient(
            c.client,
            c.show.id,
            serverId: c.show.serverId == null ? null : ServerId(c.show.serverId!),
          ),
        ) ??
        false;
    final queueing = downloads?.isQueueing(c.show.globalKey) ?? false;
    final manage = rule || (progress != null && progress.status != DownloadStatus.completed) || queueing;
    final states = [
      for (final candidate in c.watchlistCandidates) candidate.source.isOnWatchlist(c.show.kind, candidate.ids),
    ];
    final onList = states.contains(true);
    final icon = rule
        ? Icons.sync
        : queueing
        ? Icons.hourglass_top
        : switch (progress?.status) {
            DownloadStatus.queued => Icons.schedule,
            DownloadStatus.downloading => Icons.downloading,
            DownloadStatus.paused => Icons.pause_circle_outline,
            DownloadStatus.failed => Icons.error_outline,
            DownloadStatus.cancelled => Icons.cancel_outlined,
            DownloadStatus.partial => Icons.download_for_offline_outlined,
            DownloadStatus.completed => Icons.download_done,
            null => downloaded ? Icons.download_done : Icons.download,
          };
    Widget action(IconData icon, String caption, Future<void> Function() run, {bool disabled = false}) =>
        TvIconButton(icon: icon, caption: caption, disabled: _busy || disabled, onSelect: () => unawaited(_run(run)));
    final buttons = <Widget>[
      Padding(
        padding: EdgeInsets.only(bottom: TvTheme.of(context).px(34)),
        child: widget.primary,
      ),
      if (c.trailer != null) action(Icons.theaters, t.tooltips.playTrailer, () => widget.playExtra(c.trailer!)),
      action(Icons.shuffle, t.tooltips.shufflePlay, () async {
        await MediaListPlaybackLauncher.forItem(context, c.show).launchShuffledShow(metadata: c.show);
        if (mounted) await c.refresh();
      }),
      if (c.watchlistCandidates.isNotEmpty)
        KeyedSubtree(
          key: _watchlist,
          child: action(
            onList ? Icons.bookmark_added : Icons.bookmark_add,
            onList ? t.explore.removeFromWatchlist : t.explore.addToWatchlist,
            _toggleWatchlist,
            disabled: !states.any((state) => state != null),
          ),
        ),
      action(
        c.show.isWatched ? Icons.remove_done : Icons.check,
        c.show.isWatched ? t.tooltips.markAsUnwatched : t.tooltips.markAsWatched,
        _toggleWatched,
      ),
      if (!PlatformDetector.isAppleTV())
        action(icon, manage ? t.navigation.downloads : t.downloads.downloadNow, () async {
          if (downloads != null) await _download(downloads, manage, downloaded);
        }, disabled: downloads == null),
      MediaContextMenu(
        key: _menu,
        item: c.show,
        onRefresh: (_) => unawaited(c.refresh()),
        onPlayTrailer: c.trailer == null ? null : () => unawaited(widget.playExtra(c.trailer!)),
        child: action(Icons.more_horiz, TvStrings.moreActions, () async {
          final menu = _menu.currentState;
          if (menu != null) menu.showContextMenu(menu.context);
        }),
      ),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        key: const ValueKey('show-actions'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < buttons.length; i++) ...[
            if (i > 0) SizedBox(width: TvTheme.of(context).px(24)),
            Focus(
              canRequestFocus: false,
              onFocusChange: (inside) {
                if (!inside) return;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  final anchor = FocusManager.instance.primaryFocus?.context;
                  if (anchor != null) {
                    unawaited(
                      Scrollable.ensureVisible(
                        anchor,
                        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
                        duration: Duration(milliseconds: DevicePerformance.isReduced ? 0 : 150),
                      ),
                    );
                  }
                });
              },
              child: buttons[i],
            ),
          ],
        ],
      ),
    );
  }
}
