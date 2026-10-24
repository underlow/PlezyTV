import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../focus/dpad_navigator.dart';
import '../../../focus/key_event_utils.dart';
import '../../../i18n/strings.g.dart';
import '../../../media/media_hub.dart';
import '../../../media/media_item.dart';
import '../../../media/media_kind.dart';
import '../../../media/media_playlist.dart';
import '../../../media/media_server_client.dart';
import '../../../screens/hub_detail_screen.dart';
import '../../../screens/libraries/libraries_screen.dart';
import '../../../utils/media_navigation_helper.dart';
import '../../../utils/watch_state_notifier.dart';
import '../../../utils/deletion_notifier.dart';
import '../../../utils/library_content_notifier.dart';
import '../../../widgets/media_context_menu.dart';
import '../components/tv_all_card.dart';
import '../components/tv_button.dart';
import '../components/tv_cards.dart';
import '../components/tv_skeletons.dart';
import '../components/tv_horizontal_row.dart';
import '../components/tv_paged_grid.dart';
import '../components/tv_paged_source.dart';
import '../tv_strings.dart';
import '../tv_theme.dart';
import '../tv_tokens.dart';
import 'tv_library_controller.dart';

/// Library hubs and the two server-backed container grids. Browse settings
/// deliberately do not alter Plezy's collection/playlist queries.
class TvLibraryExtraTab extends StatefulWidget {
  const TvLibraryExtraTab({
    super.key,
    required this.controller,
    required this.tab,
    required this.onUp,
    required this.onLeft,
    required this.ownsTabFocus,
    this.openItem,
    this.autoFocusOnLoad = true,
    this.onLoaded,
  });
  final bool autoFocusOnLoad;
  final VoidCallback? onLoaded;
  final TvLibraryController controller;
  final LibraryTabType tab;
  final VoidCallback onUp, onLeft;
  final bool Function() ownsTabFocus;
  final Future<void> Function(BuildContext, Object)? openItem;

  @override
  State<TvLibraryExtraTab> createState() => TvLibraryExtraTabState();
}

class TvLibraryExtraTabState extends State<TvLibraryExtraTab> {
  final _subscriptions = <StreamSubscription<dynamic>>[];
  final _loadedIndices = <int>{};
  final _scope = FocusScopeNode(debugLabel: 'Library extra content');
  final _grid = GlobalKey<TvPagedGridState<Object>>();
  final _rows = <GlobalKey<TvHorizontalRowState>>[];
  final _scroll = ScrollController();
  final _menus = <int, GlobalKey<MediaContextMenuState>>{};
  late final TvPagedSource<Object> _source;
  List<MediaHub> _hubs = [];
  bool _loading = true, _failed = false, _opening = false;
  final _retry = FocusNode(debugLabel: 'Library extra retry');
  bool _retrying = false;
  Timer? _skeletonTimer;
  bool _skeleton = false;
  bool _firstLoad = true;
  int _index = 0, _row = 0, _epoch = 0;
  TvLibraryController get c => widget.controller;
  bool get _recommended => widget.tab == LibraryTabType.recommended;
  bool get _empty => _recommended ? _hubs.isEmpty : _source.totalCount == 0;

  @override
  void initState() {
    super.initState();
    _source = TvPagedSource<Object>(
      pageSize: widget.tab == LibraryTabType.playlists ? 200 : 36,
      loadPage: (offset, limit) async {
        if (widget.tab == LibraryTabType.playlists) {
          final page = await c.client.fetchPlaylistsPage(playlistType: 'video', start: offset, size: limit);
          for (var i = 0; i < page.items.length; i++) {
            _loadedIndices.add(offset + i);
          }
          return TvPage<Object>(page.items, page.totalCount);
        }
        final page = await c.client.fetchCollectionsPage(c.library.id, start: offset, size: limit);
        for (var i = 0; i < page.items.length; i++) {
          _loadedIndices.add(offset + i);
        }
        return TvPage<Object>(page.items, page.totalCount);
      },
    );
    _subscriptions.add(
      WatchStateNotifier().stream.listen((event) {
        if (event.serverId == c.library.serverId && _contains(event.itemId)) unawaited(refresh());
      }),
    );
    _subscriptions.add(
      DeletionNotifier().stream.listen((event) {
        if (!event.isDownloadOnly && event.serverId == c.library.serverId && _contains(event.itemId)) {
          unawaited(refresh());
        }
      }),
    );
    _subscriptions.add(
      LibraryContentNotifier().stream.listen((event) {
        if (event.serverId == c.library.serverId &&
            event.hasChanges &&
            (event.targetsWholeServer || event.libraryIds.contains(c.library.id))) {
          unawaited(refresh());
        }
      }),
    );
    unawaited(refresh());
  }

  bool _contains(String id) {
    if (!_recommended) {
      return _loadedIndices.any((i) {
        final item = _source[i];
        return item is MediaPlaylist
            ? item.id == id
            : item is MediaItem && (item.id == id || item.parentId == id || item.grandparentId == id);
      });
    }
    return _hubs
        .expand((hub) => hub.items)
        .any((item) => item.id == id || item.parentId == id || item.grandparentId == id);
  }

  Future<void> refresh() async {
    final epoch = ++_epoch;
    setState(() {
      _retrying = _failed;
      _loading = _recommended ? _hubs.isEmpty : (_source.totalCount ?? 0) == 0;
      _failed = false;
      _skeleton = false;
    });
    _skeletonTimer?.cancel();
    _skeletonTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted && epoch == _epoch && _loading) setState(() => _skeleton = true);
    });
    final autoFocus = _firstLoad && widget.autoFocusOnLoad;
    try {
      if (_recommended) {
        final diagnostics = HubFetchDiagnostics();
        final hubs = (await c.client.fetchLibraryHubs(
          c.library.id,
          diagnostics: diagnostics,
          libraryName: c.library.title,
          libraryKind: c.library.kind,
        )).where((h) => h.items.isNotEmpty).toList();
        if (!mounted || epoch != _epoch) return;
        if (diagnostics.failed || diagnostics.cancelled) throw StateError('Library hubs unavailable');
        final cw = hubs.indexWhere((h) => h.isContinueWatchingHub);
        if (cw > 0) hubs.insert(0, hubs.removeAt(cw));
        _hubs = hubs;
        while (_rows.length < hubs.length) {
          _rows.add(GlobalKey<TvHorizontalRowState>());
        }
      } else {
        if (_source.totalCount == null) {
          await _source.requestIndex(0);
        } else {
          _index = await _source.refresh(
            anchorIndex: _index,
            idOf: (item) => item is MediaItem ? item.globalKey : (item as MediaPlaylist).globalKey,
          );
        }
        if (_source.errors.isNotEmpty) {
          throw _source.errors.values.first;
        }
      }
      if (!mounted || epoch != _epoch) return;
      setState(() {
        _loading = false;
        _failed = false;
        _retrying = false;
      });
      _firstLoad = false;
      widget.onLoaded?.call();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
        if (_empty && (widget.ownsTabFocus() || _scope.hasFocus)) {
          widget.onUp();
        } else if ((autoFocus && widget.ownsTabFocus()) || (!_recommended && _scope.hasFocus)) {
          requestFocus();
        }
      });
    } catch (_) {
      if (mounted && epoch == _epoch) {
        setState(() {
          _loading = false;
          _failed = true;
          _retrying = false;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && (widget.ownsTabFocus() || _scope.hasFocus)) _retry.requestFocus();
        });
      }
    }
  }

  void requestFocus() {
    if (_failed || _retrying) {
      _retry.requestFocus();
    } else if (_recommended && _hubs.isNotEmpty) {
      _rows[_row.clamp(0, _hubs.length - 1)].currentState?.requestFocus();
    } else if (!_empty) {
      _grid.currentState?.jumpTo(_index, waitForLoad: false);
    }
  }

  Future<void> _open(Object item, {MediaHub? hub}) async {
    if (_opening) return;
    _opening = true;
    try {
      if (widget.openItem case final open?) {
        await open(context, item);
      } else {
        final result = await navigateToMediaItem(
          context,
          item,
          playDirectly: hub?.usesContinueWatchingAction ?? false,
          onRefresh: (_) => unawaited(refresh()),
        );
        if (mounted && result == MediaNavigationResult.listRefreshNeeded) await refresh();
      }
    } finally {
      _opening = false;
      if (mounted && (ModalRoute.of(context)?.isCurrent ?? true)) requestFocus();
    }
  }

  Widget _poster(
    Object item, {
    FocusNode? node,
    bool? focused,
    MediaHub? hub,
    GlobalKey<MediaContextMenuState>? menuKey,
  }) {
    final media = item is MediaItem
        ? item
        : MediaItem(
            id: (item as MediaPlaylist).id,
            backend: item.backend,
            kind: MediaKind.movie,
            title: item.title,
            thumbPath: item.displayImagePath,
            serverId: item.serverId,
          );
    return MediaContextMenu(
      key: menuKey,
      item: item,
      isInContinueWatching: hub?.isContinueWatchingHub ?? false,
      onRefresh: (_) => unawaited(refresh()),
      onListRefresh: () => unawaited(refresh()),
      child: Builder(
        builder: (context) {
          void menu() => context.findAncestorStateOfType<MediaContextMenuState>()?.showContextMenu(context);
          return Focus(
            canRequestFocus: false,
            onKeyEvent: (_, event) {
              if (!event.logicalKey.isContextMenuKey) return KeyEventResult.ignored;
              if (event is KeyDownEvent) menu();
              return KeyEventResult.handled;
            },
            child: hub?.isContinueWatchingHub == true
                ? TvEpisode(
                    item: media,
                    client: c.client,
                    focusNode: node,
                    onSelect: () => unawaited(_open(item, hub: hub)),
                    onLongPress: menu,
                  )
                : TvPoster(
                    item: media,
                    client: c.client,
                    size: _recommended ? TvPosterSize.row : TvPosterSize.grid,
                    focusNode: node,
                    externalFocus: focused,
                    onSelect: () => unawaited(_open(item, hub: hub)),
                    onLongPress: menu,
                  ),
          );
        },
      ),
    );
  }

  void _moveRow(int index) {
    if (index < 0) {
      widget.onUp();
      return;
    }
    if (index >= _hubs.length) return;
    _row = index;
    final ctx = _rows[index].currentContext;
    if (ctx != null) Scrollable.ensureVisible(ctx, alignment: 0);
    _rows[index].currentState?.requestFocus();
  }

  Widget _rail(int index) {
    final hub = _hubs[index];
    final wide = hub.isContinueWatchingHub;
    return Focus(
      canRequestFocus: false,
      onKeyEvent: (_, event) {
        final down = event is KeyDownEvent || event is KeyRepeatEvent;
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          if (down) widget.onLeft();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowUp || event.logicalKey == LogicalKeyboardKey.arrowDown) {
          if (down) _moveRow(index + (event.logicalKey == LogicalKeyboardKey.arrowUp ? -1 : 1));
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: TvHorizontalRow(
        key: _rows[index],
        title: hub.title,
        counter: hub.size.toString(),
        itemCount: hub.items.length + (hub.more || hub.size > hub.items.length ? 1 : 0),
        itemKey: (i) => i == hub.items.length ? 'all' : hub.items[i].globalKey,
        cardWidth: (wide ? TvTokens.size.episode.w : TvTokens.size.poster.w).toDouble(),
        cardHeight:
            (wide ? TvTokens.size.episode.h : TvTokens.size.poster.h) +
            20 +
            TvTokens.type.body.lineHeight +
            TvTokens.type.caption.lineHeight.toDouble(),
        onItemFocused: (_) => _row = index,
        cardBuilder: (context, i, node) => i < hub.items.length
            ? _poster(hub.items[i], node: node, hub: hub)
            : TvAllCard(
                episode: wide,
                focusNode: node,
                onSelect: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => HubDetailScreen(
                        hub: hub,
                        isInContinueWatching: hub.isContinueWatchingHub,
                        usesContinueWatchingAction: hub.usesContinueWatchingAction,
                      ),
                    ),
                  );
                  if (mounted) requestFocus();
                },
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => FocusScope(
    node: _scope,
    child: Focus(
      canRequestFocus: false,
      onKeyEvent: (_, event) {
        if (!_recommended && event.logicalKey.isContextMenuKey) {
          if (event is KeyDownEvent) _menus[_index]?.currentState?.showContextMenu(context);
          return KeyEventResult.handled;
        }
        if (event.logicalKey.isBackKey && !_opening) {
          if (_recommended && _rows.isNotEmpty && (_rows[_row].currentState?.focusedIndex ?? 0) > 0) {
            return handleBackKeyAction(event, () => _rows[_row].currentState?.focusStart());
          }
          if (!_recommended && _index > 0) {
            return handleBackKeyAction(event, () => _grid.currentState?.jumpTo(0));
          }
        }
        return KeyEventResult.ignored;
      },
      child: _content(context),
    ),
  );

  Widget _content(BuildContext context) {
    if (_loading && !_retrying) {
      return !_skeleton
          ? const SizedBox.expand()
          : GridView.count(
              crossAxisCount: 6,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: TvTheme.of(context).px(24),
              crossAxisSpacing: TvTheme.of(context).px(24),
              childAspectRatio: 228 / 414,
              children: List.generate(12, (_) => const TvPosterSkeleton(size: TvPosterSize.grid)),
            );
    }
    if (_failed || _retrying) {
      final theme = TvTheme.of(context), px = TvTheme.of(context).px;
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: px(96), color: TvTokens.color.text.secondary),
            SizedBox(height: px(32)),
            Text(TvStrings.noConnection, style: theme.headline),
            SizedBox(height: px(16)),
            Text(TvStrings.noConnectionHelp, style: theme.bodyLarge, textAlign: TextAlign.center),
            SizedBox(height: px(40)),
            TvButton(
              focusNode: _retry,
              label: _retrying ? TvStrings.connecting : TvStrings.retry,
              disabled: _retrying,
              onSelect: () => unawaited(refresh()),
            ),
          ],
        ),
      );
    }
    if (_empty) {
      return Center(
        child: Text(
          _recommended
              ? t.libraries.noRecommendations
              : widget.tab == LibraryTabType.collections
              ? t.libraries.noCollections
              : t.playlists.noPlaylists,
          style: TvTheme.of(context).body,
        ),
      );
    }
    if (_recommended) {
      return SingleChildScrollView(
        controller: _scroll,
        child: Column(children: [for (var i = 0; i < _hubs.length; i++) _rail(i)]),
      );
    }
    final size = TvPosterSize.grid.dimensions;
    return TvPagedGrid<Object>(
      key: _grid,
      source: _source,
      columns: 6,
      cellWidth: size.width,
      cellHeight: size.height + 20 + TvTokens.type.body.lineHeight + TvTokens.type.caption.lineHeight,
      gap: TvTokens.space.cardGap.toDouble(),
      decorateFocus: false,
      onUp: widget.onUp,
      onLeft: widget.onLeft,
      onItemFocused: (i) => _index = i,
      onSelect: (i) {
        final item = _source[i];
        if (item != null) unawaited(_open(item));
      },
      onLongPress: (i) => _menus[i]?.currentState?.showContextMenu(context),
      itemBuilder: (_, i, item, focused) =>
          _poster(item!, focused: focused, menuKey: _menus.putIfAbsent(i, () => GlobalKey<MediaContextMenuState>())),
    );
  }

  @override
  void dispose() {
    _epoch++;
    _skeletonTimer?.cancel();
    _retry.dispose();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _source.dispose();
    _scroll.dispose();
    _scope.dispose();
    super.dispose();
  }
}
