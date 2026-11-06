import 'dart:async';

import 'package:flutter/material.dart';

import '../../../i18n/strings.g.dart';
import '../../../media/media_item.dart';
import '../../../services/catalog/library_watchlist_candidates.dart';
import '../../../services/media_list_playback_launcher.dart';
import '../../../services/watch_actions.dart';
import '../../../utils/error_message_utils.dart';
import '../../../utils/platform_detector.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../widgets/media_context_menu.dart';
import '../../../widgets/watchlist_source_chooser.dart';
import '../components/tv_button.dart';
import '../tv_strings.dart';
import '../components/tv_action_row.dart';
import 'tv_show_controller.dart';
import 'tv_download_action.dart';

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
    final states = [
      for (final candidate in c.watchlistCandidates) candidate.source.isOnWatchlist(c.show.kind, candidate.ids),
    ];
    final onList = states.contains(true);
    Widget action(IconData icon, String caption, Future<void> Function() run, {bool disabled = false}) =>
        TvIconButton(icon: icon, caption: caption, disabled: _busy || disabled, onSelect: () => unawaited(_run(run)));
    final buttons = <Widget>[
      widget.primary,
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
      if (!PlatformDetector.isAppleTV()) TvDownloadAction(item: c.show, client: c.client, disabled: _busy),
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
    return TvActionRow(rowKey: const ValueKey('show-actions'), buttons: buttons);
  }
}
