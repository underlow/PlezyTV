import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../i18n/strings.g.dart';
import '../../../media/ids.dart';
import '../../../media/media_item.dart';
import '../../../models/download_models.dart';
import '../../../providers/download_provider.dart';
import '../../../providers/multi_server_provider.dart';
import '../../../screens/downloads/downloads_screen.dart';
import '../../../services/catalog/library_watchlist_candidates.dart';
import '../../../services/device_performance.dart';
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
import 'tv_movie_controller.dart';

/// Movie action row built only from public Plezy helpers (visibility rules
/// follow `lib/screens/media_detail/action_buttons.dart`).
class TvMovieActions extends StatefulWidget {
  const TvMovieActions({
    super.key,
    required this.controller,
    required this.primary,
    required this.playExtra,
    required this.playVersion,
    this.markWatched,
    this.serverOnline,
  });
  final TvMovieController controller;
  final Widget primary;
  final Future<void> Function(MediaItem) playExtra;

  /// Opens Plezy's version picker and plays the chosen version.
  final Future<void> Function() playVersion;

  /// Test adapter. Production always uses WatchActions, including tracker events.
  final Future<WatchMarkOutcome> Function(MediaItem, bool)? markWatched;

  /// Test adapter for Plezy's reachable-server check of the version segment.
  final bool Function(MediaItem)? serverOnline;
  @override
  State<TvMovieActions> createState() => _TvMovieActionsState();
}

class _TvMovieActionsState extends State<TvMovieActions> {
  final _menu = GlobalKey<MediaContextMenuState>();
  final _watchlist = GlobalKey();
  bool _busy = false;
  List<Listenable> _memberships = [];
  TvMovieController get c => widget.controller;

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
    _memberships = next;
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

  bool _versionSplit() {
    final movie = c.movie;
    if (c.versions.length < 2) return false;
    if (widget.serverOnline != null) return widget.serverOnline!(movie);
    final id = serverIdOrNull(movie.serverId);
    if (id == null) return false;
    return context.read<MultiServerProvider?>()?.serverManager.isClientOnline(id) ?? false;
  }

  Future<void> _toggleWatchlist() async {
    final candidates = c.watchlistCandidates;
    if (candidates.isEmpty) return;
    final box = _watchlist.currentContext?.findRenderObject() as RenderBox?;
    final candidate = candidates.length == 1
        ? candidates.single
        : await showWatchlistSourceChooser(
            context,
            kind: c.movie.kind,
            candidates: candidates,
            anchorRect: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
            focusFirstItem: true,
          );
    if (!mounted || candidate == null) return;
    final current = candidate.source.isOnWatchlist(c.movie.kind, candidate.ids);
    if (current == null) {
      await candidate.source.ensureWatchlistLoaded();
      return;
    }
    await mutateWatchlistMembership(c.movie.kind, candidate, add: !current);
  }

  Future<void> _toggleWatched() async {
    final movie = c.movie;
    final outcome =
        await (widget.markWatched?.call(movie, !movie.isWatched) ??
            WatchActions.setWatched(context, movie, watched: !movie.isWatched, offline: false));
    if (!mounted || outcome == WatchMarkOutcome.skipped) return;
    c.watchStateChanged = true;
    await c.refresh();
  }

  Future<void> _download(DownloadProvider provider, bool manage, bool downloaded) async {
    if (manage) {
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const DownloadsScreen()));
      return;
    }
    final movie = c.movie;
    if (downloaded) {
      // Plezy action_buttons: a downloaded movie cannot download more, so the
      // button goes straight to the delete confirmation.
      final confirmed = await showDeleteConfirmation(
        context,
        title: t.downloads.deleteDownload,
        message: t.downloads.deleteConfirm(title: movie.displayTitle),
      );
      if (confirmed && mounted) {
        await provider.deleteDownload(movie.globalKey);
        if (mounted) showSuccessSnackBar(context, t.downloads.downloadDeleted);
      }
      return;
    }
    await queueDownloadWithFeedback(context, metadata: movie, client: c.client, downloadProvider: provider);
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
    final movie = c.movie;
    final downloads = context.watch<DownloadProvider?>();
    final progress = downloads?.getProgress(movie.globalKey);
    final downloaded = downloads?.isDownloaded(movie.globalKey) ?? false;
    final queueing = downloads?.isQueueing(movie.globalKey) ?? false;
    // S7 D3: unfinished, queued, paused or failed downloads open Downloads.
    final manage = (progress != null && progress.status != DownloadStatus.completed) || queueing;
    final states = [
      for (final candidate in c.watchlistCandidates) candidate.source.isOnWatchlist(movie.kind, candidate.ids),
    ];
    final onList = states.contains(true);
    final downloadIcon = queueing
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
    final trailer = c.trailer;
    Widget action(IconData icon, String caption, Future<void> Function() run, {bool disabled = false, Key? key}) =>
        TvIconButton(
          key: key,
          icon: icon,
          caption: caption,
          disabled: _busy || disabled,
          onSelect: () => unawaited(_run(run)),
        );
    final buttons = <Widget>[
      widget.primary,
      if (_versionSplit()) action(Icons.video_library, t.mediaMenu.playVersion, widget.playVersion),
      if (c.watchlistCandidates.isNotEmpty)
        KeyedSubtree(
          key: _watchlist,
          child: action(
            onList ? Icons.bookmark_added : Icons.bookmark_add,
            onList ? t.explore.removeFromWatchlist : t.explore.addToWatchlist,
            _toggleWatchlist,
            disabled: c.watchlistLoading || !states.any((state) => state != null),
          ),
        ),
      action(
        movie.isWatched ? Icons.remove_done : Icons.check,
        movie.isWatched ? t.tooltips.markAsUnwatched : t.tooltips.markAsWatched,
        _toggleWatched,
      ),
      if (trailer != null) action(Icons.theaters, t.tooltips.playTrailer, () => widget.playExtra(trailer)),
      if (!PlatformDetector.isAppleTV())
        action(downloadIcon, manage ? t.navigation.downloads : t.downloads.downloadNow, () async {
          if (downloads != null) await _download(downloads, manage, downloaded);
        }, disabled: downloads == null),
      MediaContextMenu(
        key: _menu,
        item: movie,
        onRefresh: (_) => unawaited(c.refresh()),
        onPlayTrailer: trailer == null ? null : () => unawaited(widget.playExtra(trailer)),
        child: action(Icons.more_horiz, TvStrings.moreActions, () async {
          final menu = _menu.currentState;
          if (menu != null) menu.showContextMenu(menu.context);
        }),
      ),
    ];
    final px = TvTheme.of(context).px;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        key: const ValueKey('movie-actions'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < buttons.length; i++) ...[
            if (i > 0) SizedBox(width: px(24)),
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
