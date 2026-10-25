import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../focus/dpad_navigator.dart';
import '../../../focus/key_event_utils.dart';
import '../../../i18n/strings.g.dart';
import '../../../media/media_item.dart';
import '../../../mixins/refreshable.dart';
import '../../../mixins/tab_visibility_aware.dart';
import '../../../models/catalog/catalog_item.dart';
import '../../../navigation/main_screen_scope.dart';
import '../../../providers/catalog_sources_provider.dart';
import '../../../providers/multi_server_provider.dart';
import '../../../services/catalog/catalog_library_matcher.dart';
import '../../../services/catalog/catalog_source.dart';
import '../../../services/storage_service.dart';
import '../../../utils/formatters.dart';
import '../components/tv_button.dart';
import '../components/tv_cards.dart';
import '../components/tv_paged_grid.dart';
import '../components/tv_paged_source.dart';
import '../components/tv_right_panel.dart';
import '../components/tv_settings_item.dart';
import '../components/tv_skeletons.dart';
import '../components/tv_tabs.dart';
import '../home/tv_home_playback.dart';
import '../tv_strings.dart';
import '../tv_theme.dart';
import '../tv_tokens.dart';
import 'tv_catalog_item_screen.dart';
import 'tv_watchlist_availability.dart';
import 'tv_watchlist_controller.dart';

/// Builds the Play/Pause adapter; [isCurrent] fences section changes.
typedef TvWatchlistPlaybackFactory = TvHomePlayback Function(BuildContext context, bool Function() isCurrent);

/// The TV «Список» section (S10, T4). Owns its controller (C3) and
/// availability service (C2) while mounted.
class TvWatchlistScreen extends StatefulWidget {
  const TvWatchlistScreen({
    super.key,
    required this.onOpenSearch,
    this.matcher,
    this.multiServer,
    this.sourcesListenable,
    this.readSources,
    this.preferences,
    this.playbackFactory,
    this.openCatalogItem,
    this.now,
  });

  /// «Перейти к поиску» on the empty screen.
  final VoidCallback onOpenSearch;

  /// Dependencies default to the session providers; tests inject fakes.
  final CatalogLibraryMatcher? matcher;
  final MultiServerProvider? multiServer;
  final Listenable? sourcesListenable;
  final List<CatalogSource> Function()? readSources;
  final TvWatchlistPreferencesStore? preferences;
  final TvWatchlistPlaybackFactory? playbackFactory;

  /// Opens the catalog card; defaults to pushing [tvCatalogItemRoute].
  final Future<void> Function(BuildContext context, TvCatalogItemArgs args)? openCatalogItem;

  /// Clock for the availability service (tests).
  final DateTime Function()? now;

  @override
  State<TvWatchlistScreen> createState() => TvWatchlistScreenState();
}

class TvWatchlistScreenState extends State<TvWatchlistScreen>
    with Refreshable, FullRefreshable, TabVisibilityAware, FocusableTab {
  static const _skeletonDelay = Duration(milliseconds: 300);
  static const _columns = 6;

  late final TvWatchlistAvailability availability;
  late final TvWatchlistController controller;
  TvHomePlayback? _playback;
  final _items = TvPagedSource<CatalogItem>(loadPage: (_, _) async => const TvPage([], 0), pageSize: 120);
  final _grid = GlobalKey<TvPagedGridState<CatalogItem>>();
  final _tabBar = GlobalKey<TvTabsState>();
  final _root = FocusNode(debugLabel: 'Watchlist', canRequestFocus: false, skipTraversal: true);
  final _tabs = FocusScopeNode(debugLabel: 'Watchlist tabs');
  final _sourceButton = FocusNode(debugLabel: 'Watchlist source');
  final _sortButton = FocusNode(debugLabel: 'Watchlist sort');
  final _filtersButton = FocusNode(debugLabel: 'Watchlist filters');
  final _action = FocusNode(debugLabel: 'Watchlist state action');
  final _media = <String, MediaItem>{};

  Timer? _skeletonTimer;
  bool _skeleton = false, _retrying = false, _opening = false, _inGrid = false;
  bool _shown = true;
  int _revision = -1;
  TvWatchlistPhase? _phase;
  String? _terminal;

  TvWatchlistController get c => controller;

  @override
  void initState() {
    super.initState();
    final matcher = widget.matcher ?? context.read<CatalogLibraryMatcher>();
    final servers = widget.multiServer ?? context.read<MultiServerProvider>();
    final Listenable sources;
    final List<CatalogSource> Function() read;
    if (widget.sourcesListenable case final listenable?) {
      sources = listenable;
      read = widget.readSources!;
    } else {
      final provider = context.read<CatalogSourcesProvider>();
      sources = provider;
      read = widget.readSources ?? () => provider.watchlistCapableSources;
    }
    availability = TvWatchlistAvailability(matcher, servers, now: widget.now);
    controller = TvWatchlistController(
      availability: availability,
      sourcesListenable: sources,
      readSources: read,
      preferences: widget.preferences ?? _LazyStoragePreferences(),
    );
    controller.addListener(_changed);
    _startSkeletonTimer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_current) _focusTabs();
      unawaited(controller.load());
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // One adapter per state; it reads the enclosing route.
    _playback ??= (widget.playbackFactory ?? _defaultPlayback)(context, _sectionCurrent);
  }

  static TvHomePlayback _defaultPlayback(BuildContext context, bool Function() isCurrent) =>
      TvHomePlayback.forContext(context, isCurrent: isCurrent);

  /// Section-level currency: the shell reports section changes through
  /// [onTabHidden]/[onTabShown]; route coverage is checked by the playback.
  bool _sectionCurrent() => mounted && _shown;

  bool get _current => mounted && _shown && (ModalRoute.of(context)?.isCurrent ?? true);

  bool get _ownsFocus {
    final primary = FocusManager.instance.primaryFocus;
    return primary == null || _root.hasFocus;
  }

  void _after(VoidCallback action) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_current) action();
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void _startSkeletonTimer() {
    _skeletonTimer?.cancel();
    _skeleton = false;
    _skeletonTimer = Timer(_skeletonDelay, () {
      if (mounted && c.phase == TvWatchlistPhase.loading) setState(() => _skeleton = true);
    });
  }

  // ---------- Controller changes ----------

  void _changed() {
    if (!mounted) return;
    final previous = _phase;
    final phase = c.phase;
    _phase = phase;
    if (phase == TvWatchlistPhase.loading && previous != TvWatchlistPhase.loading) _startSkeletonTimer();
    if (phase != TvWatchlistPhase.loading) {
      _skeletonTimer?.cancel();
      _skeleton = false;
    }
    if (c.viewRevision != _revision) {
      _revision = c.viewRevision;
      _items.replaceAll(c.view, keepFocus: c.lastChange == TvWatchlistChange.keepFocus);
    }
    final terminal = phase == TvWatchlistPhase.error
        ? 'error'
        : phase == TvWatchlistPhase.ready && c.all.isEmpty
        ? 'empty'
        : null;
    if (terminal != _terminal) {
      _terminal = terminal;
      if (terminal != null && _ownsFocus) _after(_action.requestFocus);
    }
    if (previous == TvWatchlistPhase.loading && phase == TvWatchlistPhase.ready && c.view.isNotEmpty && !_opening) {
      // First card after a load, unless the user already left the screen.
      if (_ownsFocus && !_inGrid) _after(() => _grid.currentState?.jumpTo(0, waitForLoad: false));
    }
    if (c.view.isEmpty && _inGrid) {
      _inGrid = false;
      _after(_focusTabs);
    }
    setState(() {});
  }

  // ---------- Shell interface ----------

  @override
  void refresh() => unawaited(c.backgroundRefresh());

  @override
  void fullRefresh() => unawaited(c.fullReset());

  @override
  void onTabHidden() => _shown = false;

  @override
  void onTabShown() {
    _shown = true;
    availability.sectionOpened();
  }

  @override
  void focusActiveTabIfReady() {
    if (!_current) return;
    if (_terminal != null) {
      _action.requestFocus();
    } else if (c.phase == TvWatchlistPhase.ready && c.view.isNotEmpty) {
      _grid.currentState?.requestFocus();
    } else {
      _focusTabs();
    }
  }

  // ---------- Focus ----------

  bool get _showsControls =>
      c.phase == TvWatchlistPhase.loading || (_terminal == null && c.phase == TvWatchlistPhase.ready);

  void _focusTabs() {
    if (_showsControls) {
      _tabBar.currentState?.requestFocus();
    } else if (_terminal != null) {
      _action.requestFocus();
    }
  }

  void _sidebar() => MainScreenFocusScope.focusSidebarOf(context);

  void _down() {
    if (_terminal != null) {
      _action.requestFocus();
    } else if (c.phase == TvWatchlistPhase.ready && c.view.isNotEmpty) {
      _grid.currentState?.requestFocus();
    } else {
      _focusTabs();
    }
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    final down = event is KeyDownEvent || event is KeyRepeatEvent;
    if (key.isBackKey && _inGrid && !_opening && (_grid.currentState?.focusedIndex ?? 0) > 0) {
      return handleBackKeyAction(event, () => _grid.currentState?.jumpTo(0));
    }
    if (!_tabs.hasFocus) return KeyEventResult.ignored;
    if (key == LogicalKeyboardKey.arrowLeft && (_tabBar.currentState?.focusedIndex ?? 0) == 0) {
      if (down) _sidebar();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      if (down) (c.hasMultipleSources ? _sourceButton : _sortButton).requestFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      if (down && c.view.isNotEmpty) _grid.currentState?.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ---------- Actions ----------

  Future<void> _open(int index) async {
    final item = _items[index];
    if (item == null || _opening) return;
    _opening = true;
    try {
      final status = availability.statusOf(item);
      if (status is TvAvailabilityFound) {
        await openWatchlistCopy(context, status.copies);
      } else {
        final source = c.source;
        if (source == null) return;
        final args = TvCatalogItemArgs(
          item: item,
          source: source,
          availability: availability,
          onRemoved: c.itemRemoved,
          onRestored: c.itemRestored,
        );
        if (widget.openCatalogItem case final open?) {
          await open(context, args);
        } else {
          await Navigator.of(context).push(tvCatalogItemRoute(args));
        }
      }
    } finally {
      _opening = false;
      // The grid kept the item's key across any removal while away.
      if (_current && c.view.isNotEmpty) {
        _after(() => _grid.currentState?.requestFocus());
      } else if (_current) {
        _after(_focusTabs);
      }
    }
  }

  void _playPause(int index) {
    final item = _items[index];
    if (item == null) return;
    final status = availability.statusOf(item);
    if (status is! TvAvailabilityFound || status.copies.isEmpty) return;
    unawaited(_playback!.activate(status.copies.first));
  }

  void _visibleRange((int, int) range) {
    final view = c.view;
    if (view.isEmpty) return;
    final margin = _columns * 2;
    final first = math.max(0, range.$1 - margin);
    final last = math.min(view.length, range.$2 + margin + 1);
    if (first >= last) return;
    availability.prioritize(view.sublist(first, last));
  }

  Future<void> _retry() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    try {
      await c.retry();
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  Future<void> _chooseSource() async {
    CatalogSource? chosen;
    await TvRightPanel.show(
      context: context,
      anchor: _sourceButton,
      root: TvRightPanelPage(
        title: TvStrings.watchlistSource,
        changes: c,
        itemsBuilder: (panel) => [
          for (final source in c.sources)
            _row(
              'source:${source.id.name}',
              source.displayName,
              selected: identical(source, c.source) || source.id == c.source?.id,
              () {
                chosen = source;
                TvRightPanel.of(panel).close();
              },
            ),
        ],
      ),
    );
    final source = chosen;
    if (!mounted || source == null || source.id == c.source?.id) return;
    await c.selectSource(source);
    if (!_current || !_sourceButton.hasFocus) return;
    if (_terminal != null) {
      _action.requestFocus();
    } else if (c.phase == TvWatchlistPhase.ready && c.view.isNotEmpty) {
      _after(() => _grid.currentState?.jumpTo(0, waitForLoad: false));
    }
  }

  Future<void> _chooseSort() => TvRightPanel.show(
    context: context,
    anchor: _sortButton,
    root: TvRightPanelPage(
      title: t.libraries.sortBy,
      changes: c,
      itemsBuilder: (_) => [
        for (final sort in TvWatchlistSort.values)
          _row('sort:${sort.name}', _sortLabel(sort), selected: c.sort == sort, () => c.setSort(sort)),
      ],
    ),
  );

  Future<void> _chooseFilters() => TvRightPanel.show(
    context: context,
    anchor: _filtersButton,
    root: TvRightPanelPage(
      title: t.libraries.filters,
      changes: c,
      itemsBuilder: (panel) => [
        if (c.genreOptions.isNotEmpty)
          _row(
            'genres',
            TvStrings.watchlistGenres,
            kind: TvSettingsItemKind.page,
            value: c.filters.genres.isEmpty ? '' : '${c.filters.genres.length}',
            () => TvRightPanel.of(panel).push(
              TvRightPanelPage(
                title: TvStrings.watchlistGenres,
                changes: c,
                itemsBuilder: (_) => [
                  for (final genre in c.genreOptions)
                    _row(
                      'genre:$genre',
                      genre,
                      kind: TvSettingsItemKind.multipleChoice,
                      selected: c.filters.genres.contains(genre),
                      () => c.setFilters(
                        TvWatchlistFilters(genres: _toggle(c.filters.genres, genre), decades: c.filters.decades),
                      ),
                    ),
                ],
              ),
            ),
          ),
        if (c.decadeOptions.isNotEmpty)
          _row(
            'decades',
            TvStrings.watchlistDecades,
            kind: TvSettingsItemKind.page,
            value: c.filters.decades.isEmpty ? '' : '${c.filters.decades.length}',
            () => TvRightPanel.of(panel).push(
              TvRightPanelPage(
                title: TvStrings.watchlistDecades,
                changes: c,
                itemsBuilder: (_) => [
                  for (final decade in c.decadeOptions)
                    _row(
                      'decade:$decade',
                      TvStrings.watchlistDecade(decade),
                      kind: TvSettingsItemKind.multipleChoice,
                      selected: c.filters.decades.contains(decade),
                      () => c.setFilters(
                        TvWatchlistFilters(genres: c.filters.genres, decades: _toggle(c.filters.decades, decade)),
                      ),
                    ),
                ],
              ),
            ),
          ),
        if (!c.filters.isEmpty) _row('reset', t.common.reset, () => c.setFilters(TvWatchlistFilters.none)),
      ],
    ),
  );

  static Set<V> _toggle<V>(Set<V> values, V value) =>
      values.contains(value) ? ({...values}..remove(value)) : {...values, value};

  static Widget _row(
    String id,
    String title,
    VoidCallback action, {
    bool? selected,
    String value = '',
    TvSettingsItemKind? kind,
  }) => TvSettingsItem(
    key: ValueKey(id),
    title: title,
    description: '',
    value: value,
    kind: kind ?? (selected == null ? TvSettingsItemKind.action : TvSettingsItemKind.singleChoice),
    selected: selected ?? false,
    onSelect: action,
  );

  static String _sortLabel(TvWatchlistSort sort) => switch (sort) {
    TvWatchlistSort.added => TvStrings.watchlistSortAdded,
    TvWatchlistSort.title => TvStrings.watchlistSortTitle,
    TvWatchlistSort.year => TvStrings.watchlistSortYear,
    TvWatchlistSort.rating => TvStrings.watchlistSortRating,
  };

  static String _tabLabel(TvWatchlistTab tab) => switch (tab) {
    TvWatchlistTab.all => TvStrings.watchlistTabAll,
    TvWatchlistTab.movies => TvStrings.watchlistTabMovies,
    TvWatchlistTab.shows => TvStrings.watchlistTabShows,
    TvWatchlistTab.onServer => TvStrings.watchlistTabOnServer,
  };

  /// Plezy's compact catalog card caption: rating, year, runtime.
  static String catalogCaption(MediaItem item) => [
    if (item.rating case final rating?) '${formatRating(rating)}★',
    if (item.year case final year?) '$year',
    if (item.durationMs case final durationMs?) formatDurationTextual(durationMs),
  ].join(' • ');

  // ---------- Build ----------

  Widget _tile(BuildContext context, int index, CatalogItem? item, bool focused) {
    if (item == null) return const SizedBox.shrink();
    final media = _media.putIfAbsent(TvWatchlistAvailability.keyOf(item), item.toMediaItem);
    return ListenableBuilder(
      listenable: availability,
      builder: (context, _) {
        final found = availability.statusOf(item) is TvAvailabilityFound;
        final caption = catalogCaption(media);
        return TvPoster(
          item: media,
          size: TvPosterSize.grid,
          onServer: found,
          caption: found && focused ? TvStrings.watchlistOnServerCaption(caption) : caption,
          externalFocus: focused,
        );
      },
    );
  }

  Widget _gridView() {
    final size = TvPosterSize.grid.dimensions;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (value) => _inGrid = value,
      child: TvPagedGrid<CatalogItem>(
        key: _grid,
        source: _items,
        decorateFocus: false,
        columns: _columns,
        cellWidth: size.width,
        cellHeight: size.height + 20 + TvTokens.type.body.lineHeight + TvTokens.type.caption.lineHeight,
        gap: TvTokens.space.cardGap.toDouble(),
        onUp: _focusTabs,
        onLeft: _sidebar,
        onSelect: (index) => unawaited(_open(index)),
        onPlayPause: _playPause,
        onVisibleRangeChanged: _visibleRange,
        keyOf: TvWatchlistAvailability.keyOf,
        itemBuilder: _tile,
      ),
    );
  }

  Widget _skeletonGrid(double Function(num) px) => GridView.count(
    crossAxisCount: _columns,
    mainAxisSpacing: px(TvTokens.space.cardGap),
    crossAxisSpacing: px(TvTokens.space.cardGap),
    childAspectRatio:
        TvTokens.size.posterGrid.w /
        (TvTokens.size.posterGrid.h + 20 + TvTokens.type.body.lineHeight + TvTokens.type.caption.lineHeight),
    physics: const NeverScrollableScrollPhysics(),
    children: List.generate(12, (_) => const TvPosterSkeleton(size: TvPosterSize.grid)),
  );

  Widget _message(TvThemeData theme, String text) => Center(
    child: Text(text, style: theme.bodyLarge, textAlign: TextAlign.center),
  );

  Widget _emptyTab(TvThemeData theme) {
    if (c.tab == TvWatchlistTab.onServer && c.filters.isEmpty) {
      return _message(theme, availability.checking ? TvStrings.watchlistChecking : TvStrings.watchlistNothingOnServer);
    }
    if (!c.filters.isEmpty) return _message(theme, TvStrings.libraryNoMatches);
    return _message(theme, switch (c.tab) {
      TvWatchlistTab.movies => TvStrings.watchlistNoMovies,
      TvWatchlistTab.shows => TvStrings.watchlistNoShows,
      TvWatchlistTab.onServer => TvStrings.watchlistNothingOnServer,
      TvWatchlistTab.all => TvStrings.libraryNoMatches,
    });
  }

  Widget _terminalView(TvThemeData theme) {
    final px = theme.px;
    final error = _terminal == 'error' || _retrying;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: px(96),
            height: px(96),
            decoration: BoxDecoration(
              color: TvTokens.color.surface.level2,
              borderRadius: BorderRadius.circular(px(24)),
            ),
            child: Icon(
              error ? Icons.cloud_off : Icons.bookmark_border,
              size: px(48),
              color: TvTokens.color.text.secondary,
            ),
          ),
          SizedBox(height: px(40)),
          Text(error ? TvStrings.watchlistLoadFailed : TvStrings.watchlistEmpty, style: theme.headline),
          SizedBox(height: px(16)),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: px(800)),
            child: Text(
              error ? TvStrings.watchlistLoadFailedHelp : TvStrings.watchlistEmptyHelp,
              style: theme.bodyLarge.copyWith(color: TvTokens.color.text.secondary),
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(height: px(40)),
          TvButton(
            focusNode: _action,
            icon: error ? null : Icons.search,
            label: !error
                ? TvStrings.watchlistGoToSearch
                : _retrying
                ? TvStrings.connecting
                : TvStrings.retry,
            disabled: _retrying,
            onNavigateUp: c.hasMultipleSources ? _sourceButton.requestFocus : () {},
            onNavigateLeft: _sidebar,
            onNavigateRight: () {},
            onNavigateDown: () {},
            onSelect: error ? () => unawaited(_retry()) : widget.onOpenSearch,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = TvTheme.of(context), px = theme.px;
    final controls = _showsControls && !_retrying;
    final showSource = c.hasMultipleSources;
    final showHeader = controls || showSource;
    Widget content;
    if (_retrying || _terminal != null) {
      content = _terminalView(theme);
    } else if (c.phase == TvWatchlistPhase.ready) {
      content = c.view.isNotEmpty ? _gridView() : _emptyTab(theme);
    } else {
      content = _skeleton ? _skeletonGrid(px) : const SizedBox.expand();
    }
    final firstHeaderButton = showSource ? _sourceButton : _sortButton;
    VoidCallback leftOf(FocusNode node) => identical(node, firstHeaderButton) ? _sidebar : () {};
    return Focus(
      focusNode: _root,
      onKeyEvent: _key,
      child: ColoredBox(
        color: TvTokens.color.bg.base,
        child: Padding(
          padding: EdgeInsets.only(
            left: (px(TvTokens.space.contentLeft) - MainScreenFocusScope.foregroundLeftOf(context)).clamp(
              0.0,
              double.infinity,
            ),
            top: px(54),
            right: px(96),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: px(64),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        TvStrings.watchlist,
                        style: theme.headline,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (showHeader && showSource) ...[
                      TvButton(
                        label: c.source?.displayName ?? TvStrings.watchlistSource,
                        focusNode: _sourceButton,
                        variant: TvButtonVariant.secondary,
                        onNavigateLeft: leftOf(_sourceButton),
                        onNavigateUp: () {},
                        onNavigateDown: _down,
                        onNavigateRight: controls ? _sortButton.requestFocus : () {},
                        onSelect: () => unawaited(_chooseSource()),
                      ),
                      if (controls) SizedBox(width: px(16)),
                    ],
                    if (controls) ...[
                      TvButton(
                        label:
                            '${_sortLabel(c.sort)}'
                            '${c.phase == TvWatchlistPhase.ready ? ' · ${c.view.length}' : ''}',
                        focusNode: _sortButton,
                        icon: Icons.swap_vert,
                        variant: TvButtonVariant.secondary,
                        onNavigateLeft: showSource ? _sourceButton.requestFocus : _sidebar,
                        onNavigateUp: () {},
                        onNavigateDown: _down,
                        onNavigateRight: _filtersButton.requestFocus,
                        onSelect: () => unawaited(_chooseSort()),
                      ),
                      SizedBox(width: px(16)),
                      TvButton(
                        label: '${t.libraries.filters}${c.filters.isEmpty ? '' : ' · ${c.filters.count}'}',
                        focusNode: _filtersButton,
                        icon: Icons.filter_alt,
                        variant: TvButtonVariant.secondary,
                        onNavigateLeft: _sortButton.requestFocus,
                        onNavigateUp: () {},
                        onNavigateDown: _down,
                        onNavigateRight: () {},
                        onSelect: () => unawaited(_chooseFilters()),
                      ),
                    ],
                  ],
                ),
              ),
              if (controls) ...[
                SizedBox(height: px(24)),
                FocusScope(
                  node: _tabs,
                  child: TvTabs(
                    key: _tabBar,
                    tabs: [for (final tab in TvWatchlistTab.values) TvTab(label: _tabLabel(tab))],
                    selectedIndex: TvWatchlistTab.values.indexOf(c.tab),
                    onSelected: (index) => c.setTab(TvWatchlistTab.values[index]),
                  ),
                ),
                SizedBox(height: px(38)),
              ],
              Expanded(child: content),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _skeletonTimer?.cancel();
    controller.removeListener(_changed);
    controller.dispose();
    availability.dispose();
    _items.dispose();
    for (final node in [_root, _tabs, _sourceButton, _sortButton, _filtersButton, _action]) {
      node.dispose();
    }
    super.dispose();
  }
}

/// Resolves the storage-backed store on first use (StorageService is async).
class _LazyStoragePreferences implements TvWatchlistPreferencesStore {
  Future<TvStorageWatchlistPreferences>? _store;
  Future<TvStorageWatchlistPreferences> get _resolved =>
      _store ??= StorageService.getInstance().then(TvStorageWatchlistPreferences.new);

  @override
  Future<TvWatchlistPreferences> load() async => (await _resolved).load();

  @override
  Future<void> save(TvWatchlistPreferences value) async => (await _resolved).save(value);
}
