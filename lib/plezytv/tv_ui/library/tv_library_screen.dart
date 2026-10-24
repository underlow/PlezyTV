import 'dart:async';
import '../../../media/media_library.dart';
import '../../../media/media_server_client.dart';
import '../../../media/library_query.dart';
import '../../../services/storage_service.dart';
import 'tv_library_preferences.dart';
import 'tv_library_query.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../focus/dpad_navigator.dart';
import '../../../data/ducet_order.dart';
import '../../../focus/key_event_utils.dart';
import '../../../i18n/strings.g.dart';
import '../../../media/media_item.dart';
import '../../../mixins/refreshable.dart';
import '../../../mixins/tab_visibility_aware.dart';
import '../../../navigation/main_screen_scope.dart';
import '../../../screens/libraries/libraries_screen.dart';
import '../../../utils/media_navigation_helper.dart';
import '../../../widgets/media_context_menu.dart';
import '../components/tv_alpha_column.dart';
import '../components/tv_button.dart';
import '../components/tv_cards.dart';
import '../components/tv_paged_grid.dart';
import '../components/tv_skeletons.dart';
import '../components/tv_tabs.dart';
import '../tv_strings.dart';
import '../tv_theme.dart';
import '../tv_tokens.dart';
import 'tv_library_controller.dart';
import 'tv_library_extra_tab.dart';
import 'tv_library_panels.dart';
import 'tv_library_more.dart';
import 'tv_folder_list.dart';

/// Host for one library. The switch owns the controller's lifetime. Header
/// callbacks receive stable anchors for the panels supplied by T5/T7.
class TvLibraryScreen extends StatefulWidget {
  const TvLibraryScreen({super.key, required this.controller, this.onSort, this.onFilters, this.onMore, this.openItem});

  /// A route-local owner: edits never write library or shell selection settings.
  static Widget filtered({
    required MediaLibrary library,
    required MediaServerClient client,
    required LibraryFilter filter,
  }) => _FilteredLibrary(library: library, client: client, filter: filter);
  final TvLibraryController controller;
  final ValueChanged<FocusNode>? onSort, onFilters, onMore;
  final Future<void> Function(BuildContext, MediaItem)? openItem;

  @override
  State<TvLibraryScreen> createState() => TvLibraryScreenState();
}

class TvLibraryScreenState extends State<TvLibraryScreen>
    with Refreshable, ManualRefreshable, FullRefreshable, TabVisibilityAware, FocusableTab {
  final _extras = <LibraryTabType, GlobalKey<TvLibraryExtraTabState>>{};
  final _folders = GlobalKey<TvFolderListState>();
  final _grid = GlobalKey<TvPagedGridState<MediaItem>>();
  final _alpha = GlobalKey<TvAlphaColumnState>();
  final _tabBar = GlobalKey<TvTabsState>();
  void _focusTabs() => _tabBar.currentState?.requestFocus();
  final _tabs = FocusScopeNode(debugLabel: 'Library tabs');
  final _sort = FocusNode(debugLabel: 'Library sort');
  final _filters = FocusNode(debugLabel: 'Library filters');
  final _more = FocusNode(debugLabel: 'Library more');
  final _action = FocusNode(debugLabel: 'Library state action');
  final _position = ValueNotifier(0);
  final _menus = <int, GlobalKey<MediaContextMenuState>>{};
  Timer? _timer;
  Widget? _gridWidget;
  bool? _episodeGrid;
  bool _skeleton = false, _visible = true, _retrying = false, _opening = false;
  bool _wasLoading = true;
  bool _inGrid = false;
  String? _terminalState;
  int _selection = 0;
  TvLibraryController get c => widget.controller;
  List<LibraryTabType> get tabs => visibleLibraryTabs(c.library);
  LibraryTabType get tab => tabs.firstWhere((t) => t.name == c.preferences.tab, orElse: () => LibraryTabType.browse);
  bool get _failed => c.error != null || (c.totalCount == null && c.source.errors.containsKey(0));
  bool get _filtered => c.preferences.filters.isNotEmpty || c.alphaPrefix != null;
  bool get _ready => (c.totalCount ?? 0) > 0;
  bool get _current => mounted && _visible && (ModalRoute.of(context)?.isCurrent ?? true);

  @override
  void initState() {
    super.initState();
    _selection = c.generation;
    c.addListener(_changed);
    _startTimer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_current) return;
      _focusTabs();
      if (c.totalCount == null && !c.loading) {
        unawaited(c.initialize());
      } else {
        _changed();
      }
    });
  }

  void _startTimer() {
    _timer?.cancel();
    _skeleton = false;
    _timer = Timer(const Duration(milliseconds: 300), () {
      if (mounted && c.loading) setState(() => _skeleton = true);
    });
  }

  void _after(VoidCallback callback) => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_current) callback();
  });

  void _changed() {
    if (!mounted) return;
    final loading = c.loading;
    if (loading && !_wasLoading) _startTimer();
    final completed = _wasLoading && !loading;
    _wasLoading = loading;
    if (c.generation != _selection && c.totalCount == null) {
      _selection = c.generation;
      _position.value = 0;
    }
    if (completed && c.grouping == 'folders' && _tabs.hasFocus) {
      _after(() => _folders.currentState?.requestFocus());
    }
    final terminal = tab != LibraryTabType.browse
        ? 'tab'
        : _failed
        ? 'error'
        : !loading && c.totalCount == 0
        ? 'empty'
        : null;
    if (terminal != _terminalState) {
      _terminalState = terminal;
      if (terminal != null) _after(() => terminal == 'tab' ? _focusTabs() : _action.requestFocus());
    }
    setState(() {});
    if (_inGrid &&
        !_opening &&
        !(_grid.currentState?.isJumping ?? false) &&
        _ready &&
        _grid.currentState?.focusedIndex != c.focusedIndex) {
      _after(() => _grid.currentState?.jumpTo(c.focusedIndex));
    }
    if (completed && _ready && tab == LibraryTabType.browse) {
      final owner = FocusManager.instance.primaryFocus;
      final owned = _tabs.hasFocus || _action.hasFocus;
      _after(() {
        if (owned &&
            (owner == FocusManager.instance.primaryFocus ||
                owner?.context?.mounted != true && !_sort.hasFocus && !_filters.hasFocus && !_more.hasFocus)) {
          _grid.currentState?.jumpTo(c.focusedIndex);
        }
      });
    }
  }

  @override
  void refresh() => unawaited(_refresh());
  Future<void> _refresh() async {
    if (tab != LibraryTabType.browse) {
      await _extras[tab]?.currentState?.refresh();
      return;
    }
    if (c.loading) return;
    final restore = _inGrid;
    if (c.totalCount == 0 && c.grouping != 'folders') {
      c.source.reset();
      await c.initialize();
    } else {
      await c.refresh();
    }
    if (_current && restore && !(_grid.currentState?.isJumping ?? false)) {
      await _grid.currentState?.jumpTo(c.focusedIndex);
    }
    if (mounted) _changed();
  }

  @override
  void manualRefresh() => refresh();
  @override
  void fullRefresh() => refresh();
  @override
  void primeRefresh() {
    if (!c.loading) refresh();
  }

  @override
  void onTabHidden() => _visible = false;
  @override
  void onTabShown() {
    _visible = true;
  }

  @override
  void focusActiveTabIfReady() {
    if (!_current) return;
    if (tab != LibraryTabType.browse) {
      _extras[tab]?.currentState?.requestFocus();
      return;
    }
    if (tab == LibraryTabType.browse && c.grouping == 'folders') {
      _folders.currentState?.requestFocus();
    } else if (tab == LibraryTabType.browse && _ready) {
      _grid.currentState?.jumpTo(c.focusedIndex, waitForLoad: false);
    } else if (_terminalState == 'empty' || _terminalState == 'error') {
      _action.requestFocus();
    } else {
      _focusTabs();
    }
  }

  void _sidebar() => MainScreenFocusScope.focusSidebarOf(context);
  void _down() {
    if (tab != LibraryTabType.browse) {
      _extras[tab]?.currentState?.requestFocus();
      return;
    }
    if (c.grouping == 'folders' && tab == LibraryTabType.browse) {
      _folders.currentState?.requestFocus();
      return;
    }
    if (tab == LibraryTabType.browse && _ready) {
      _grid.currentState?.jumpTo(c.focusedIndex, waitForLoad: false);
    } else if (_terminalState == 'empty' || _terminalState == 'error') {
      _action.requestFocus();
    }
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    final down = event is KeyDownEvent || event is KeyRepeatEvent;
    if (key.isContextMenuKey && tab == LibraryTabType.browse && _inGrid) {
      if (event is KeyDownEvent) _menu(c.focusedIndex);
      return KeyEventResult.handled;
    }
    if (key.isBackKey && !_opening && (_grid.currentState?.focusedIndex ?? 0) > 0 && _inGrid) {
      return handleBackKeyAction(event, () => _grid.currentState?.jumpTo(0));
    }
    if (key == LogicalKeyboardKey.arrowLeft &&
        ((_tabs.hasFocus && (_tabBar.currentState?.focusedIndex ?? 0) == 0) || _action.hasFocus || _sort.hasFocus)) {
      if (down) _sidebar();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown &&
        (_tabs.hasFocus || _sort.hasFocus || _filters.hasFocus || _more.hasFocus)) {
      if (down) _down();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp && _tabs.hasFocus) {
      if (down) _sort.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _selectTab(int index) async {
    if (tabs[index] == tab) return;
    await c.select(tab: tabs[index].name);
    if (mounted) _changed();
  }

  void _menu(int index) {
    final state = _menus[index]?.currentState;
    if (state != null) state.showContextMenu(state.context);
  }

  Future<void> _open(int index) async {
    final item = c.source[index];
    if (item == null || _opening) return;
    _opening = true;
    try {
      if (widget.openItem case final open?) {
        await open(context, item);
      } else {
        var changed = false;
        final result = await navigateToMediaItem(context, item, onRefresh: (_) => changed = true);
        if (mounted && (changed || result == MediaNavigationResult.listRefreshNeeded)) await _refresh();
      }
    } finally {
      _opening = false;
      if (_current) await _grid.currentState?.jumpTo(c.focusedIndex);
    }
  }

  Future<void> _jump(int index) async {
    final grid = _grid.currentState;
    if (grid == null) return;
    await grid.jumpTo(index);
    // TvPagedGrid completes loading before its post-frame focus attaches.
    // Keep the controller's refresh barrier until that attachment completes.
    while (mounted && grid.mounted && grid.isJumping) {
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  Future<void> _letter(String letter) async {
    final index = c.alphaHelper.indexForLetter(letter);
    if (index == null) return;
    if (c.library.backend.usesMediaBrowserApi) {
      await c.setAlphaPrefix(c.alphaPrefix == letter ? null : letter);
      if (_current) {
        if (_ready) {
          await _grid.currentState?.jumpTo(0);
        } else {
          _action.requestFocus();
        }
      }
    } else {
      c.setJumping(true);
      try {
        await _jump(index);
        if (mounted) c.focusedIndex = _grid.currentState?.focusedIndex ?? index;
      } finally {
        c.setJumping(false);
      }
    }
  }

  List<String> get _letters {
    final letters = {'#', ...c.characters.map((c) => c.title.toUpperCase())}.toList()..sort(ducetCompare);
    return c.preferences.descending ? letters.reversed.toList() : letters;
  }

  Widget _gridContent() {
    final episodes = c.grouping == 'episodes';
    if (_gridWidget == null || _episodeGrid != episodes) {
      _episodeGrid = episodes;
      final size = episodes
          ? Size(TvTokens.size.episode.w.toDouble(), TvTokens.size.episode.h.toDouble())
          : TvPosterSize.grid.dimensions;
      _gridWidget = TvPagedGrid<MediaItem>(
        key: _grid,
        source: c.source,
        decorateFocus: false,
        columns: episodes ? 4 : 6,
        cellWidth: size.width,
        cellHeight: size.height + 20 + TvTokens.type.body.lineHeight + TvTokens.type.caption.lineHeight,
        gap: TvTokens.space.cardGap.toDouble(),
        onUp: _focusTabs,
        onLeft: _sidebar,
        onRight: () => _alpha.currentState?.requestFocus(),
        onItemFocused: (index) {
          unawaited(c.source.requestIndex(index));
          c.focusedIndex = index;
          _position.value = index;
        },
        onSelect: (index) => unawaited(_open(index)),
        onLongPress: _menu,
        itemBuilder: (context, index, item, focused) => MediaContextMenu(
          key: _menus.putIfAbsent(index, () => GlobalKey<MediaContextMenuState>()),
          item: item!,
          onRefresh: (_) => refresh(),
          child: episodes
              ? TvEpisode(item: item, client: c.client, externalFocus: focused)
              : TvPoster(item: item, client: c.client, size: TvPosterSize.grid, externalFocus: focused),
        ),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Focus(canRequestFocus: false, onFocusChange: (value) => _inGrid = value, child: _gridWidget!),
        ),
        if (c.showAlpha)
          ValueListenableBuilder<int>(
            valueListenable: _position,
            builder: (context, index, _) => TvAlphaColumn(
              key: _alpha,
              letters: [
                for (final letter in _letters)
                  TvAlphaLetter(letter, empty: (c.alphaHelper.letterSizes[letter] ?? 0) == 0),
              ],
              highlighted: c.strategy.currentLetter(index, c.alphaHelper, mediaBrowserAlphaPrefix: c.alphaPrefix),
              onSelect: (letter) => unawaited(_letter(letter)),
              onLeft: () => _grid.currentState?.jumpTo(c.focusedIndex, waitForLoad: false),
            ),
          ),
      ],
    );
  }

  Future<void> _retry() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    try {
      await c.initialize();
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  Widget _terminal() {
    final theme = TvTheme.of(context), px = TvTheme.of(context).px;
    final error = _failed || _retrying;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (error) ...[
            Icon(Icons.cloud_off, size: px(96), color: TvTokens.color.text.secondary),
            SizedBox(height: px(32)),
          ],
          Text(
            error
                ? TvStrings.noConnection
                : _filtered
                ? TvStrings.libraryNoMatches
                : TvStrings.libraryEmpty(c.library.title),
            style: theme.headline,
          ),
          if (error) ...[
            SizedBox(height: px(16)),
            Text(TvStrings.noConnectionHelp, style: theme.bodyLarge, textAlign: TextAlign.center),
          ],
          SizedBox(height: px(40)),
          TvButton(
            focusNode: _action,
            label: _retrying
                ? TvStrings.connecting
                : error
                ? TvStrings.retry
                : _filtered
                ? t.libraries.resetFilters
                : TvStrings.refreshLibrary,
            disabled: _retrying,
            onSelect: () {
              if (error) {
                unawaited(_retry());
              } else if (_filtered) {
                unawaited(c.resetFilters());
              } else {
                refresh();
              }
            },
          ),
        ],
      ),
    );
  }

  String _tabLabel(LibraryTabType type) => switch (type) {
    LibraryTabType.browse => t.libraries.tabs.browse,
    LibraryTabType.recommended => t.libraries.tabs.recommended,
    LibraryTabType.collections => t.libraries.tabs.collections,
    LibraryTabType.playlists => t.libraries.tabs.playlists,
  };
  @override
  Widget build(BuildContext context) {
    final theme = TvTheme.of(context), px = TvTheme.of(context).px;
    final fields = c.preferences.filters.map((f) => f.field).toSet().length;
    Widget content;
    if (tab != LibraryTabType.browse) {
      content = KeyedSubtree(
        key: ValueKey(tab),
        child: TvLibraryExtraTab(
          key: _extras.putIfAbsent(tab, () => GlobalKey<TvLibraryExtraTabState>()),
          controller: c,
          tab: tab,
          onUp: _focusTabs,
          onLeft: _sidebar,
          ownsTabFocus: () => _tabs.hasFocus,
        ),
      );
    } else if (c.grouping == 'folders') {
      content = TvFolderList(
        key: _folders,
        controller: c,
        onUp: _focusTabs,
        onLeft: _sidebar,
        openItem: (item) async {
          if (widget.openItem case final open?) {
            await open(context, item);
          } else {
            final result = await navigateToMediaItem(context, item, onRefresh: (_) => refresh());
            if (mounted && result == MediaNavigationResult.listRefreshNeeded) await _refresh();
          }
        },
      );
    } else if (_ready) {
      content = _gridContent();
    } else if (_failed || _retrying || (!c.loading && c.totalCount == 0)) {
      content = _terminal();
    } else {
      content = !_skeleton
          ? const SizedBox.expand()
          : GridView.count(
              crossAxisCount: 6,
              mainAxisSpacing: px(TvTokens.space.cardGap),
              crossAxisSpacing: px(TvTokens.space.cardGap),
              childAspectRatio:
                  TvTokens.size.posterGrid.w /
                  (TvTokens.size.posterGrid.h + 20 + TvTokens.type.body.lineHeight + TvTokens.type.caption.lineHeight),
              physics: const NeverScrollableScrollPhysics(),
              children: List.generate(12, (_) => const TvPosterSkeleton(size: TvPosterSize.grid)),
            );
    }
    return Focus(
      canRequestFocus: false,
      onKeyEvent: _key,
      child: ColoredBox(
        color: TvTokens.color.bg.base,
        child: Padding(
          padding: EdgeInsets.only(
            left: px(TvTokens.space.contentLeft),
            top: px(54),
            right: px(c.grouping == 'episodes' ? 24 : 96),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(c.library.title, style: theme.headline, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  TvButton(
                    label:
                        '${c.selectedSort?.title ?? TvStrings.defaultSort}${c.totalCount == null ? '' : ' · ${c.totalCount}'}',
                    focusNode: _sort,
                    icon: Icons.swap_vert,
                    variant: TvButtonVariant.secondary,
                    onSelect: () {
                      if (widget.onSort case final callback?) {
                        callback(_sort);
                      } else {
                        unawaited(showTvLibrarySort(context, _sort, c));
                      }
                    },
                  ),
                  SizedBox(width: px(16)),
                  TvButton(
                    label: '${t.libraries.filters}${fields == 0 ? '' : ' · $fields'}',
                    focusNode: _filters,
                    icon: Icons.filter_alt,
                    variant: TvButtonVariant.secondary,
                    disabled: c.filtersLoading,
                    onSelect: () {
                      if (widget.onFilters case final callback?) {
                        callback(_filters);
                      } else {
                        unawaited(showTvLibraryFilters(context, _filters, c));
                      }
                    },
                  ),
                  SizedBox(width: px(16)),
                  TvButton(
                    label: TvStrings.moreLibraries,
                    focusNode: _more,
                    variant: TvButtonVariant.secondary,
                    onSelect: () => widget.onMore != null
                        ? widget.onMore!(_more)
                        : unawaited(showTvLibraryMore(context, _more, c.library, c.client)),
                  ),
                ],
              ),
              SizedBox(height: px(24)),
              FocusScope(
                node: _tabs,
                child: TvTabs(
                  key: _tabBar,
                  tabs: [for (final type in tabs) TvTab(label: _tabLabel(type))],
                  selectedIndex: tabs.indexOf(tab),
                  onSelected: (index) => unawaited(_selectTab(index)),
                ),
              ),
              SizedBox(height: px(38)),
              Expanded(child: content),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    c.removeListener(_changed);
    _timer?.cancel();
    _position.dispose();
    for (final node in [_sort, _filters, _more, _action, _tabs]) {
      node.dispose();
    }
    super.dispose();
  }
}

class _FilteredLibrary extends StatefulWidget {
  const _FilteredLibrary({required this.library, required this.client, required this.filter});
  final MediaLibrary library;
  final MediaServerClient client;
  final LibraryFilter filter;
  @override
  State<_FilteredLibrary> createState() => _FilteredLibraryState();
}

class _FilteredLibraryState extends State<_FilteredLibrary> {
  TvLibraryController? _controller;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (!isTvVideoLibrary(widget.library)) return;
    final saved = await TvStorageLibraryPreferences(await StorageService.getInstance()).load(widget.library.globalKey);
    if (!mounted) return;
    setState(
      () => _controller = TvLibraryController(
        library: widget.library,
        client: widget.client,
        store: TvMemoryLibraryPreferences.filtered(saved, widget.filter),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => TvTheme(
    child: Scaffold(body: _controller == null ? const SizedBox.expand() : TvLibraryScreen(controller: _controller!)),
  );
  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }
}
