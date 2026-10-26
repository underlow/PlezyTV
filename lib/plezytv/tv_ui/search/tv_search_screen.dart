import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../focus/dpad_navigator.dart';
import '../../../focus/key_event_utils.dart';
import '../../../i18n/strings.g.dart';
import '../../../media/ids.dart';
import '../../../media/media_item.dart';
import '../../../media/media_item_merge.dart';
import '../../../media/media_kind.dart';
import '../../../media/media_person.dart';
import '../../../mixins/refreshable.dart';
import '../../../mixins/tab_visibility_aware.dart';
import '../../../navigation/main_screen_scope.dart';
import '../../../navigation/navigation_tabs.dart';
import '../../../navigation/profile_navigation_scope.dart';
import '../../../providers/discover_provider.dart';
import '../../../providers/hidden_libraries_provider.dart';
import '../../../providers/multi_server_provider.dart';
import '../../../providers/watch_state_store.dart';
import '../../../services/data_aggregation_service.dart';
import '../../../services/music/music_playback_service.dart';
import '../../../services/settings_service.dart';
import '../../../services/storage_service.dart';
import '../../../utils/media_navigation_helper.dart';
import '../../../utils/media_server_http_client.dart';
import '../../../utils/provider_extensions.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../widgets/media_context_menu.dart';
import '../components/tv_all_card.dart';
import '../components/tv_button.dart';
import '../components/tv_cards.dart';
import '../components/tv_horizontal_row.dart';
import '../components/tv_paged_grid.dart';
import '../components/tv_paged_source.dart';
import '../components/tv_person_card.dart';
import '../components/tv_skeletons.dart';
import '../components/tv_tabs.dart';
import '../home/tv_home_card.dart';
import '../home/tv_home_model.dart';
import '../home/tv_home_playback.dart';
import '../shell/tv_section_shell.dart';
import '../tv_settings.dart';
import '../tv_strings.dart';
import '../tv_theme.dart';
import '../tv_tokens.dart';
import 'tv_search_controller.dart';
import 'tv_search_history.dart';
import 'tv_search_keyboard.dart';

enum _FocusRepair { arrival, replaced }

abstract final class TvSearchStrings {
  static const placeholder = 'Search';
  static const tabAll = 'All';
  static const tabMovies = 'Movies';
  static const tabShows = 'Shows';
  static const tabEpisodes = 'Episodes';
  static const tabPeople = 'People';
  static const rowMovies = 'Movies';
  static const rowShows = 'Shows';
  static const rowEpisodes = 'Episodes';
  static const rowPeople = 'Actors & directors';
  static const nothingFound = 'Nothing found';
  static String nothingFoundHelp(String query) =>
      'No results for “$query”. Check the spelling or the keyboard layout (РУС / ENG).';
  static const unavailable = 'Search unavailable';
  static const recentSearches = 'Recent searches';
}

/// Production history: the profile-scoped store, opened lazily.
class _StorageHistory implements TvSearchHistoryStore {
  Future<TvStorageSearchHistory> get _store async => TvStorageSearchHistory(await StorageService.getInstance());
  @override
  Future<List<String>> load() async => (await _store).load();
  @override
  Future<void> save(List<String> history) async => (await _store).save(history);
}

/// S11 TV search screen (C5): keyboard on the left, results on the right.
class TvSearchScreen extends StatefulWidget {
  const TvSearchScreen({super.key, this.searchForTesting, this.fetchForTesting, this.historyForTesting});

  final TvSearchFn? searchForTesting;
  final TvFetchItemFn? fetchForTesting;
  final TvSearchHistoryStore? historyForTesting;

  @override
  State<TvSearchScreen> createState() => TvSearchScreenState();
}

class TvSearchScreenState extends State<TvSearchScreen>
    with
        Refreshable,
        FullRefreshable,
        FocusableTab,
        TabVisibilityAware,
        SearchInputFocusable,
        WidgetsBindingObserver,
        RouteAware {
  late final TvSearchController controller = TvSearchController(
    search: widget.searchForTesting ?? _productionSearch,
    fetchItem: widget.fetchForTesting ?? _productionFetch,
  );
  late final TvSearchHistoryStore _historyStore = widget.historyForTesting ?? _StorageHistory();
  final _screen = FocusScopeNode(debugLabel: 'TV Search');
  final _content = FocusScopeNode(debugLabel: 'TV Search results');
  final _keyboard = GlobalKey<TvSearchKeyboardState>();
  final _tabs = GlobalKey<TvTabsState>();
  final _retry = FocusNode(debugLabel: 'TV Search retry');
  final _rows = {for (final kind in TvSearchKind.values) kind: GlobalKey<TvHorizontalRowState>()};
  final _grids = {for (final kind in TvSearchKind.values) kind: GlobalKey<TvPagedGridState<Object>>()};
  final _menus = <String, GlobalKey<MediaContextMenuState>>{};
  final _vertical = ScrollController();
  late final Map<TvSearchKind, TvPagedSource<Object>> _sources = {
    for (final kind in TvSearchKind.values)
      kind: TvPagedSource<Object>(
        loadPage: (offset, limit) async {
          final all = controller.allOf(kind);
          return TvPage(all.skip(offset).take(limit).toList(), all.length);
        },
      ),
  };
  final _sourceLists = <TvSearchKind, List<Object>>{};

  late TvSearchKeyboardLayout _layout;
  ValueNotifier<String>? _layoutPreference;
  late TvHomePlayback _playback;
  List<String>? _history;
  int _historyGeneration = 0;
  Future<void> _historyOp = Future.value();
  HiddenLibrariesProvider? _hidden;
  Set<String> _lastHiddenKeys = const {};
  RouteObserver<PageRoute<dynamic>>? _observer;
  PageRoute<dynamic>? _route;
  bool _initialized = false, _visible = true;
  int _seenPartialRevision = 0;
  TvSearchState _lastState = TvSearchState.idle;

  /// No key was pressed since the query came from history, a link or the
  /// companion remote: ← returns to the first key of the layout (R10).
  bool _keyless = false;

  /// Focus the first result once the submitted query answers (R10).
  bool _focusOnArrival = false;

  /// A focus repair whose answer arrived while search was not current.
  _FocusRepair? _pendingRepair;
  ({TvSearchKind kind, String key})? _pendingActive;
  ({TvSearchKind kind, String key})? _active;

  // ---------- Idle discover rows (R7) ----------
  DiscoverProvider? _discover;
  final _homeBuilder = TvHomeModelBuilder();
  TvHomeModel? _homeModel;
  final _hubRows = <String, GlobalKey<TvHorizontalRowState>>{};
  final _recentNodes = <FocusNode>[];
  int _activeHub = 0;

  /// Up to two poster Home hubs (no Continue Watching or music).
  List<TvHomeRow> get _hubs => [
    ...?_homeModel?.rows.where((row) => row.kind == TvHomeRowKind.hub && row.layout == TvHomeRowLayout.posters).take(2),
  ];

  bool get _hubsLoading {
    final discover = _discover;
    return discover != null && _hubs.isEmpty && discover.areHubsLoading && discover.errorMessage == null;
  }

  @visibleForTesting
  List<String> get hubTitles => [for (final row in _hubs) row.title];

  @visibleForTesting
  List<String>? get history => _history;

  bool get _current => mounted && _visible && (ModalRoute.of(context)?.isCurrent ?? true);

  // ---------- Production dependencies ----------

  Future<SearchAggregationResult> _productionSearch(String query, AbortController abort) async {
    final servers = context.read<MultiServerProvider>();
    if (!servers.hasConnectedServers) throw const TvSearchUnavailable();
    final hidden = context.read<HiddenLibrariesProvider>();
    await hidden.ensureInitialized();
    return servers.aggregationService.searchAcrossServers(
      query,
      hiddenLibraryKeys: hidden.hiddenLibraryKeys,
      abort: abort,
    );
  }

  Future<MediaItem?> _productionFetch(MediaItem source) async {
    final serverId = source.serverId;
    if (serverId == null || !mounted) return null;
    final client = context.read<MultiServerProvider>().getClientForServer(ServerId(serverId));
    final fetched = await client?.fetchItem(source.id);
    if (fetched == null) return null;
    return mergeFetchedMediaItem(fetched: fetched, fallbackServerId: ServerId(serverId), existing: source);
  }

  // ---------- Lifecycle ----------

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final observer = ProfileNavigationScope.maybeOf(context)?.routeObserver;
    final route = ModalRoute.of(context);
    final pageRoute = route is PageRoute ? route : null;
    if (observer != _observer || pageRoute != _route) {
      _observer?.unsubscribe(this);
      _observer = observer;
      _route = pageRoute;
      if (pageRoute != null) observer?.subscribe(this, pageRoute);
    }
    _bindDiscover(context.read<DiscoverProvider?>());
    if (_initialized) return;
    _initialized = true;
    // load() may notify synchronously; never during this build.
    _afterFrame(_ensureDiscoverLoaded);
    _layout = TvSearchKeyboardLayout.fromPref(SettingsService.instanceOrNull?.read(TvSettings.searchKeyboardLayout));
    _layoutPreference = SettingsService.instanceOrNull?.listenable(TvSettings.searchKeyboardLayout);
    _layoutPreference?.addListener(_layoutChanged);
    final shell = context.findAncestorStateOfType<TvSectionShellState>();
    _playback = TvHomePlayback.forContext(
      context,
      isCurrent: () => shell == null
          ? mounted
          : shell.mounted && !shell.currentSection.isNoConnection && shell.currentSection.tab == NavigationTabId.search,
    );
    controller.addListener(_changed);
    WidgetsBinding.instance.addObserver(this);
    _loadHistory();
    unawaited(_bindHiddenLibraries());
    _afterFrame(focusActiveTabIfReady);
  }

  Future<void> _bindHiddenLibraries() async {
    final hidden = context.read<HiddenLibrariesProvider?>();
    if (hidden == null) return;
    await hidden.ensureInitialized();
    if (!mounted) return;
    _lastHiddenKeys = Set.of(hidden.hiddenLibraryKeys);
    _hidden = hidden..addListener(_hiddenChanged);
  }

  void _hiddenChanged() {
    final keys = _hidden?.hiddenLibraryKeys;
    if (keys == null || !mounted) return;
    if (keys.length == _lastHiddenKeys.length && keys.containsAll(_lastHiddenKeys)) return;
    _lastHiddenKeys = Set.of(keys);
    if (controller.query.trim().isNotEmpty) controller.searchNow();
  }

  void _bindDiscover(DiscoverProvider? discover) {
    if (identical(discover, _discover)) return;
    _discover?.removeListener(_discoverChanged);
    _discover = discover?..addListener(_discoverChanged);
    _homeModel = discover == null ? null : _homeBuilder.build(discover);
  }

  void _discoverChanged() {
    final discover = _discover;
    if (discover == null || !mounted) return;
    setState(() => _homeModel = _homeBuilder.build(discover));
  }

  /// R7: load only when hubs never loaded (initial) or failed, and no load runs.
  void _ensureDiscoverLoaded() {
    final discover = _discover;
    if (discover == null || discover.isLoadInFlight) return;
    if (discover.areHubsLoading || discover.errorMessage != null) unawaited(discover.load());
  }

  void _loadHistory() {
    final generation = ++_historyGeneration;
    _history = null;
    _historyOp = _historyOp
        .then((_) async {
          final loaded = await _historyStore.load();
          if (mounted && generation == _historyGeneration) setState(() => _history = loaded);
        })
        .catchError((_) {});
  }

  /// R9: record the query of shown results, only when there are results.
  void _recordHistory() {
    if (controller.state != TvSearchState.results) return;
    final query = controller.shownQuery;
    final generation = _historyGeneration;
    _historyOp = _historyOp
        .then((_) async {
          if (generation != _historyGeneration) return;
          final updated = TvSearchHistory.add(_history ?? await _historyStore.load(), query);
          if (generation != _historyGeneration) return;
          if (mounted) {
            setState(() => _history = updated);
          } else {
            _history = updated;
          }
          await _historyStore.save(updated);
        })
        .catchError((_) {});
  }

  void _afterFrame(VoidCallback action) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) action();
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) _recordHistory();
  }

  @override
  void didPushNext() => _recordHistory();

  @override
  void didPopNext() => _afterFrame(_resumeFocus);

  @override
  void dispose() {
    _layoutPreference?.removeListener(_layoutChanged);
    _observer?.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    _hidden?.removeListener(_hiddenChanged);
    _discover?.removeListener(_discoverChanged);
    for (final node in _recentNodes) {
      node.dispose();
    }
    controller.removeListener(_changed);
    controller.dispose();
    for (final source in _sources.values) {
      source.dispose();
    }
    _vertical.dispose();
    _retry.dispose();
    _content.dispose();
    _screen.dispose();
    super.dispose();
  }

  // ---------- Shell capabilities ----------

  @override
  void focusSearchInput() {
    if (!mounted) return;
    _dropDeferredRepair();
    _focusKeyboard();
  }

  @override
  void submitSearchQuery(String query) {
    if (!mounted) return;
    _dropDeferredRepair();
    controller.setQuery(query);
    controller.searchNow();
    _keyless = true;
    _focusOnArrival = true;
    _afterFrame(() => _keyboard.currentState?.focusFirstKey());
  }

  @override
  void refresh() => controller.searchNow();

  @override
  void primeRefresh() {
    _ensureDiscoverLoaded();
    controller.searchNow();
  }

  @override
  void fullRefresh() {
    _ensureDiscoverLoaded();
    controller.clear();
    _keyless = false;
    _focusOnArrival = false;
    _pendingRepair = _pendingActive = null;
    _loadHistory();
  }

  @override
  void focusActiveTabIfReady() {
    if (!_current) return;
    if (_pendingRepair != null) {
      _screen.requestFocus();
      _resumeFocus();
    } else if (_screen.focusedChild != null) {
      _screen.requestFocus();
    } else {
      _keyboard.currentState?.focusFirstKey();
    }
  }

  @override
  void onTabHidden() {
    _recordHistory();
    _visible = false;
  }

  @override
  void onTabShown() {
    _visible = true;
    _afterFrame(_resumeFocus);
  }

  // ---------- Keyboard ----------

  void _focusKeyboard() {
    final keyboard = _keyboard.currentState;
    if (keyboard == null) return;
    if (_keyless) {
      keyboard.focusFirstKey();
    } else {
      keyboard.focusLastKey();
    }
  }

  void _typed() {
    _keyless = false;
    _focusOnArrival = false;
    if (_pendingRepair == _FocusRepair.arrival) _pendingRepair = null;
  }

  void _input(String text) {
    _typed();
    controller.setQuery(controller.query + text);
  }

  void _backspace() {
    _typed();
    final chars = controller.query.characters;
    if (chars.isEmpty) return;
    controller.setQuery(chars.skipLast(1).toString());
  }

  void _clear() {
    _typed();
    controller.clear();
  }

  void _layoutChanged() {
    final layout = TvSearchKeyboardLayout.fromPref(_layoutPreference?.value);
    if (mounted && layout != _layout) setState(() => _layout = layout);
  }

  void _setLayout(TvSearchKeyboardLayout layout) {
    _typed();
    setState(() => _layout = layout);
    unawaited(SettingsService.instanceOrNull?.write(TvSettings.searchKeyboardLayout, layout.prefValue));
  }

  bool _exitRight() {
    switch (controller.state) {
      case TvSearchState.results:
        return _focusFirstCard();
      case TvSearchState.unavailable:
        _retry.requestFocus();
        return true;
      case TvSearchState.idle:
        if (_recentNodes.isNotEmpty && (_history?.isNotEmpty ?? false)) {
          _recentNodes.first.requestFocus();
          return true;
        }
        return _focusHub(0);
      case TvSearchState.empty:
        return _focusHub(0);
      case TvSearchState.loading:
        return false;
    }
  }

  // ---------- Idle / nothing-found rows ----------

  String _hubKey(TvHomeRow row) => '${row.hub!.serverId}:${row.hub!.libraryId}:${row.hub!.id}';

  bool _focusHub(int index) {
    final hubs = _hubs;
    if (index < 0 || index >= hubs.length) return false;
    final key = _hubKey(hubs[index]);
    final row = _hubRows[key]?.currentState;
    if (row == null) return false;
    row.requestFocus();
    _revealHub(key);
    return true;
  }

  void _revealHub(String key) {
    final ctx = _hubRows[key]?.currentContext;
    if (ctx != null) unawaited(Scrollable.ensureVisible(ctx, alignment: 0));
  }

  bool get _showRecent => controller.state == TvSearchState.idle && (_history?.isNotEmpty ?? false);

  void _focusRecent() {
    if (_showRecent && _recentNodes.isNotEmpty) _recentNodes.first.requestFocus();
  }

  Widget _hubRail(TvHomeRow row, int index) {
    final key = _hubKey(row);
    final hub = row.hub!;
    final discover = _discover;
    return TvHorizontalRow(
      key: _hubRows.putIfAbsent(key, () => GlobalKey<TvHorizontalRowState>()),
      title: row.title,
      counter: row.count?.toString(),
      contentLeft: 0,
      itemCount: row.items.length + (row.hasMore ? 1 : 0),
      itemKey: (i) => i == row.items.length ? 'all' : TvHomeRow.itemKey(row.items[i]),
      cardWidth: TvTokens.size.poster.w.toDouble(),
      cardHeight:
          TvTokens.size.poster.h + 20 + TvTokens.type.body.lineHeight + TvTokens.type.caption.lineHeight.toDouble(),
      onItemFocused: (_) {
        _activeHub = index;
        _revealHub(key);
      },
      cardBuilder: (context, i, node) {
        if (i == row.items.length) {
          return TvAllCard(
            focusNode: node,
            onSelect: () => unawaited(
              openTvHubDetail(context, hub, onRemoveFromContinueWatching: discover?.refreshContinueWatching),
            ),
          );
        }
        return TvHomeHubCard(
          item: row.items[i],
          focusNode: node,
          playback: _playback,
          playDirectly: hub.usesContinueWatchingAction,
          isInContinueWatching: hub.isContinueWatchingHub,
          onRefresh: discover?.updateItem,
          onRemoveFromContinueWatching: discover?.refreshContinueWatching,
        );
      },
    );
  }

  void _syncRecentNodes(int count) {
    while (_recentNodes.length < count) {
      _recentNodes.add(FocusNode(debugLabel: 'TV Search recent ${_recentNodes.length}'));
    }
    while (_recentNodes.length > count) {
      _recentNodes.removeLast().dispose();
    }
  }

  Widget _recent(List<String> queries) {
    final theme = TvTheme.of(context), px = theme.px;
    _syncRecentNodes(queries.length);
    return Column(
      key: const ValueKey('tv-search-recent'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(TvSearchStrings.recentSearches, style: theme.title),
        SizedBox(height: px(16)),
        Wrap(
          spacing: px(12),
          runSpacing: px(12),
          children: [
            for (var i = 0; i < queries.length; i++)
              TvButton(
                label: queries[i],
                icon: Icons.history,
                variant: TvButtonVariant.smallSecondary,
                focusNode: _recentNodes[i],
                onSelect: () => submitSearchQuery(queries[i]),
                onNavigateLeft: i == 0 ? _focusKeyboard : () => _recentNodes[i - 1].requestFocus(),
                onNavigateRight: i + 1 < queries.length ? () => _recentNodes[i + 1].requestFocus() : () {},
                onNavigateUp: () {},
                onNavigateDown: () => _focusHub(0),
              ),
          ],
        ),
      ],
    );
  }

  /// R7 rows: recent queries (idle only) and up to two Home hubs.
  Widget _discoverBlock({Widget? header}) {
    final px = TvTheme.of(context).px;
    final hubs = _hubs;
    final history = _history ?? const <String>[];
    final showRecent = controller.state == TvSearchState.idle && history.isNotEmpty;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (header != null) ...[header, SizedBox(height: px(48))],
            if (showRecent) ...[_recent(history), SizedBox(height: px(48))],
            for (var i = 0; i < hubs.length; i++) ...[
              _hubRail(hubs[i], i),
              SizedBox(height: px(TvTokens.space.rowGap)),
            ],
            if (_hubsLoading) ...[
              const TvRowSkeleton(),
              SizedBox(height: px(TvTokens.space.rowGap)),
              const TvRowSkeleton(),
            ],
            SizedBox(height: constraints.maxHeight),
          ],
        ),
      ),
    );
  }

  // ---------- Results ----------

  static String _keyOf(Object item) => item is MediaItem ? item.globalKey : (item as MediaPerson).globalKey;

  static TvSearchKind? _kindOfTab(TvSearchTab tab) => switch (tab) {
    TvSearchTab.all => null,
    TvSearchTab.movies => TvSearchKind.movies,
    TvSearchTab.shows => TvSearchKind.shows,
    TvSearchTab.episodes => TvSearchKind.episodes,
    TvSearchTab.people => TvSearchKind.people,
  };

  List<TvSearchKind> get _rowKinds => [
    for (final kind in TvSearchKind.values)
      if (controller.allOf(kind).isNotEmpty) kind,
  ];

  bool _focusFirstCard() {
    if (controller.state != TvSearchState.results) return false;
    final kind = _kindOfTab(controller.selectedTab);
    if (kind != null) {
      unawaited(_grids[kind]!.currentState?.jumpTo(0, waitForLoad: false));
      return _grids[kind]!.currentState != null;
    }
    final kinds = _rowKinds;
    if (kinds.isEmpty) return false;
    final row = _rows[kinds.first]!.currentState;
    if (row == null) return false;
    row.requestFocus(itemKey: _keyOf(controller.rowOf(kinds.first).first));
    _reveal(kinds.first);
    return true;
  }

  void _syncSources() {
    for (final kind in TvSearchKind.values) {
      final list = controller.allOf(kind);
      if (identical(_sourceLists[kind], list)) continue;
      _sourceLists[kind] = list;
      _sources[kind]!.replaceAll(list, keepFocus: true);
    }
  }

  void _changed() {
    final state = controller.state;
    // While search is hidden, the scope history tells whether the results
    // held focus when the user left.
    final hadContent = _content.hasFocus || (!_current && _screen.focusedChild == _content);
    final active = _active;
    final listsChanged = TvSearchKind.values.any((kind) => !identical(_sourceLists[kind], controller.allOf(kind)));
    setState(_syncSources);
    if (controller.partialFailureRevision != _seenPartialRevision) {
      _seenPartialRevision = controller.partialFailureRevision;
      showAppSnackBar(context, t.messages.searchPartialResults);
    }
    final answered = state != _lastState || listsChanged;
    _lastState = state;
    if (!answered || state == TvSearchState.loading) return;
    _FocusRepair? repair;
    if (_focusOnArrival && state != TvSearchState.idle) {
      _focusOnArrival = false;
      repair = _FocusRepair.arrival;
    } else if (hadContent) {
      repair = _FocusRepair.replaced;
    }
    if (repair == null) return;
    if (!_current) {
      // Applied once the screen is current again (R10).
      if (_pendingRepair != _FocusRepair.arrival) {
        // Keep the item focused before the first deferred answer.
        if (_pendingRepair == null) _pendingActive = active;
        _pendingRepair = repair;
      }
      return;
    }
    _pendingRepair = null;
    if (repair == _FocusRepair.arrival) {
      _afterFrame(() => _repairFocus(_FocusRepair.arrival, active));
    } else {
      // Components restore a surviving item themselves; repair the rest after
      // they settle (R10).
      _afterFrame(() => _afterFrame(() => _repairFocus(_FocusRepair.replaced, active)));
    }
  }

  /// Bumped by explicit focus requests so an already scheduled deferred
  /// repair does not override them.
  int _explicitFocus = 0;

  /// An explicit focus request wins over a repair deferred while search was
  /// hidden or covered, including one already scheduled.
  void _dropDeferredRepair() {
    _pendingRepair = _pendingActive = null;
    _explicitFocus++;
  }

  /// Runs a repair deferred while search was hidden or covered.
  void _resumeFocus() {
    final repair = _pendingRepair, active = _pendingActive;
    if (repair == null || !_current) return;
    _pendingRepair = _pendingActive = null;
    final epoch = _explicitFocus;
    _afterFrame(() {
      if (epoch == _explicitFocus) _repairFocus(repair, active, restore: true);
    });
  }

  /// R10 after an answer: on arrival, the first card, else the first key. When
  /// results were replaced under focus, the same item, else the first card,
  /// else the keyboard ("Retry" when search is unavailable). [restore] also
  /// re-focuses a surviving item, since the shell's restore may miss it.
  void _repairFocus(_FocusRepair repair, ({TvSearchKind kind, String key})? active, {bool restore = false}) {
    if (!_current) return;
    final state = controller.state;
    if (repair == _FocusRepair.arrival) {
      if (state != TvSearchState.results || !_focusFirstCard()) _keyboard.currentState?.focusFirstKey();
      return;
    }
    if (state == TvSearchState.loading) return;
    if (state == TvSearchState.unavailable) {
      _retry.requestFocus();
      return;
    }
    if (state != TvSearchState.results) {
      _focusKeyboard();
      return;
    }
    if (_tabs.currentState?.focusedIndex != null) return;
    final tabKind = _kindOfTab(controller.selectedTab);
    final list = active == null
        ? const <Object>[]
        : tabKind == null
        ? controller.rowOf(active.kind)
        : (tabKind == active.kind ? controller.allOf(tabKind) : const <Object>[]);
    final index = active == null ? -1 : list.indexWhere((item) => _keyOf(item) == active.key);
    if (index < 0) {
      if (!_focusFirstCard()) _focusKeyboard();
      return;
    }
    // The scope node itself holds focus when the focused node unmounted.
    if (!restore && FocusManager.instance.primaryFocus != _content) return;
    if (tabKind == null) {
      _rows[active!.kind]!.currentState?.requestFocus(itemKey: active.key);
      _reveal(active.kind);
    } else {
      unawaited(_grids[tabKind]!.currentState?.jumpTo(index, waitForLoad: false));
    }
  }

  void _reveal(TvSearchKind kind) {
    final ctx = _rows[kind]!.currentContext;
    if (ctx != null) unawaited(Scrollable.ensureVisible(ctx, alignment: 0));
  }

  KeyEventResult _contentKey(FocusNode node, KeyEvent event) {
    final down = event is KeyDownEvent || event is KeyRepeatEvent;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (down) _focusKeyboard();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowDown) {
      final state = controller.state;
      if (state == TvSearchState.idle || state == TvSearchState.empty) {
        if (!down) return KeyEventResult.handled;
        final next = _activeHub + (key == LogicalKeyboardKey.arrowDown ? 1 : -1);
        if (next < 0) {
          _focusRecent();
        } else {
          _focusHub(next);
        }
        return KeyEventResult.handled;
      }
      if (state != TvSearchState.results) return KeyEventResult.ignored;
      if (!down) return KeyEventResult.handled;
      final isDown = key == LogicalKeyboardKey.arrowDown;
      if (_tabs.currentState?.focusedIndex != null) {
        if (isDown) _focusFirstCard();
        return KeyEventResult.handled;
      }
      if (controller.selectedTab == TvSearchTab.all) {
        final kinds = _rowKinds;
        final index = _active == null ? 0 : kinds.indexOf(_active!.kind);
        final next = index + (isDown ? 1 : -1);
        if (next < 0) {
          _tabs.currentState?.requestFocus();
        } else if (next < kinds.length) {
          _rows[kinds[next]]!.currentState?.requestFocus();
          _reveal(kinds[next]);
        }
      }
      return KeyEventResult.handled;
    }
    return handleBackKeyAction(event, _focusKeyboard);
  }

  KeyEventResult _screenKey(FocusNode node, KeyEvent event) {
    if (event.logicalKey.isBackKey && event is KeyDownEvent && (_keyboard.currentState?.hasFocus ?? false)) {
      _recordHistory();
    }
    return KeyEventResult.ignored;
  }

  Future<void> _open(Object item) async {
    _recordHistory();
    if (item is MediaPerson) {
      await navigateToPersonMedia(
        context,
        personId: item.id,
        name: item.name,
        thumbPath: item.thumbPath,
        serverId: item.serverId,
        serverName: item.serverName,
        backend: item.backend,
      );
      return;
    }
    await navigateToMediaItem(
      context,
      item as MediaItem,
      onRefresh: (source) => unawaited(controller.refreshItem(source)),
      playDirectly: false,
    );
  }

  void _showMenu(MediaItem item) {
    final menu = _menus[item.globalKey]?.currentState;
    final ctx = _menus[item.globalKey]?.currentContext;
    if (menu != null && ctx != null) menu.showContextMenu(ctx);
  }

  String _caption(MediaItem item, {required bool multiServer}) {
    final base = item.kind == MediaKind.show && item.childCount != null
        ? TvStrings.seasons(item.childCount!)
        : item.year?.toString() ?? '';
    final server = multiServer ? item.serverName : null;
    return [if (base.isNotEmpty) base, ?server].join(' · ');
  }

  static String? _credit(MediaPerson person) => switch (person.credit) {
    PersonCredit.actor => t.explore.creditRole.actor,
    PersonCredit.director => t.explore.creditRole.director,
    null => null,
  };

  bool get _multiServer => (Provider.of<MultiServerProvider?>(context)?.totalServerCount ?? 0) > 1;

  Widget _mediaMenu(MediaItem item, Widget Function(BuildContext context, VoidCallback menu) child) => MediaContextMenu(
    key: _menus.putIfAbsent(item.globalKey, GlobalKey<MediaContextMenuState>.new),
    item: item,
    onRefresh: (source) => unawaited(controller.refreshItem(source)),
    child: Builder(
      builder: (menuContext) => child(
        menuContext,
        () => menuContext.findAncestorStateOfType<MediaContextMenuState>()?.showContextMenu(menuContext),
      ),
    ),
  );

  KeyEventResult _cardKeys(MediaItem item, KeyEvent event, VoidCallback menu) => tvHomeCardKeys(
    _playback,
    item,
    event,
    menu,
    musicActive: () => context.read<MusicPlaybackService?>()?.currentTrack != null,
  );

  (double, double) _cardSize(TvSearchKind kind, {bool grid = false}) {
    final captions = TvTokens.type.body.lineHeight + TvTokens.type.caption.lineHeight.toDouble();
    return switch (kind) {
      TvSearchKind.episodes => (TvTokens.size.episode.w.toDouble(), TvTokens.size.episode.h + 20 + captions),
      TvSearchKind.people => (TvPersonCard.photoSize, TvPersonCard.photoSize + TvPersonCard.captionGap + captions),
      _ =>
        grid
            ? (TvTokens.size.posterGrid.w.toDouble(), TvTokens.size.posterGrid.h + 20 + captions)
            : (TvTokens.size.poster.w.toDouble(), TvTokens.size.poster.h + 20 + captions),
    };
  }

  Widget _row(TvSearchKind kind, bool multiServer) {
    final items = controller.rowOf(kind);
    final (width, height) = _cardSize(kind);
    return TvHorizontalRow(
      key: _rows[kind],
      title: switch (kind) {
        TvSearchKind.movies => TvSearchStrings.rowMovies,
        TvSearchKind.shows => TvSearchStrings.rowShows,
        TvSearchKind.episodes => TvSearchStrings.rowEpisodes,
        TvSearchKind.people => TvSearchStrings.rowPeople,
      },
      counter: controller.countOf(kind).toString(),
      contentLeft: 0,
      itemCount: items.length,
      itemKey: (index) => _keyOf(items[index]),
      cardWidth: width,
      cardHeight: height,
      onItemFocused: (index) {
        if (index < items.length) _active = (kind: kind, key: _keyOf(items[index]));
        _reveal(kind);
      },
      cardBuilder: (context, index, node) {
        final source = items[index];
        if (source is MediaPerson) {
          return TvPersonCard(
            client: context.tryGetMediaClientForServer(source.serverId),
            imagePath: source.thumbPath,
            name: source.name,
            caption: _credit(source),
            focusNode: node,
            onSelect: () => unawaited(_open(source)),
          );
        }
        return Builder(
          builder: (context) {
            final item = context.withFreshWatchState(source as MediaItem);
            final client = context.getMediaClientForItemOrNull(item);
            return _mediaMenu(
              item,
              (menuContext, menu) => Focus(
                canRequestFocus: false,
                onKeyEvent: (_, event) => _cardKeys(item, event, menu),
                child: kind == TvSearchKind.episodes
                    ? TvEpisode(
                        item: item,
                        client: client,
                        showSeriesTitle: true,
                        focusNode: node,
                        onSelect: () => unawaited(_open(item)),
                        onLongPress: menu,
                      )
                    : TvPoster(
                        item: item,
                        client: client,
                        caption: _caption(item, multiServer: multiServer),
                        focusNode: node,
                        onSelect: () => unawaited(_open(item)),
                        onLongPress: menu,
                      ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _grid(TvSearchKind kind, bool multiServer, double maxWidth) {
    final (width, height) = _cardSize(kind, grid: true);
    final gap = TvTokens.space.cardGap.toDouble();
    final px = TvTheme.of(context).px;
    final columns = ((maxWidth / px(1) + gap) / (width + gap)).floor().clamp(1, 12);
    Object? focused() {
      final index = _grids[kind]!.currentState?.focusedIndex;
      return index == null ? null : _sources[kind]![index];
    }

    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (_, event) {
        final item = focused();
        if (item is! MediaItem) return KeyEventResult.ignored;
        final fresh = context.readFreshWatchState(item);
        return _cardKeys(fresh, event, () => _showMenu(item));
      },
      child: TvPagedGrid<Object>(
        key: _grids[kind],
        source: _sources[kind]!,
        decorateFocus: false,
        columns: columns,
        cellWidth: width,
        cellHeight: height,
        gap: gap,
        keyOf: _keyOf,
        onUp: () => _tabs.currentState?.requestFocus(),
        onLeft: _focusKeyboard,
        onItemFocused: (index) {
          final item = _sources[kind]![index];
          if (item != null) _active = (kind: kind, key: _keyOf(item));
        },
        onSelect: (index) {
          final item = _sources[kind]![index];
          if (item != null) unawaited(_open(item));
        },
        onLongPress: (index) {
          final item = _sources[kind]![index];
          if (item is MediaItem) _showMenu(item);
        },
        itemBuilder: (context, index, source, isFocused) {
          if (source == null) return const SizedBox.shrink();
          if (source is MediaPerson) {
            return TvPersonCard(
              client: context.tryGetMediaClientForServer(source.serverId),
              imagePath: source.thumbPath,
              name: source.name,
              caption: _credit(source),
              externalFocus: isFocused,
            );
          }
          final item = context.withFreshWatchState(source as MediaItem);
          final client = context.getMediaClientForItemOrNull(item);
          return _mediaMenu(
            item,
            (_, _) => kind == TvSearchKind.episodes
                ? TvEpisode(item: item, client: client, showSeriesTitle: true, externalFocus: isFocused)
                : TvPoster(
                    item: item,
                    client: client,
                    size: TvPosterSize.grid,
                    caption: _caption(item, multiServer: multiServer),
                    externalFocus: isFocused,
                  ),
          );
        },
      ),
    );
  }

  Widget _results(bool multiServer) {
    final px = TvTheme.of(context).px;
    final tabs = controller.tabs;
    final selected = controller.selectedTab;
    final kind = _kindOfTab(selected);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TvTabs(
          key: _tabs,
          tabs: [
            for (final tab in tabs)
              TvTab(
                label: switch (tab) {
                  TvSearchTab.all => TvSearchStrings.tabAll,
                  TvSearchTab.movies => TvSearchStrings.tabMovies,
                  TvSearchTab.shows => TvSearchStrings.tabShows,
                  TvSearchTab.episodes => TvSearchStrings.tabEpisodes,
                  TvSearchTab.people => TvSearchStrings.tabPeople,
                },
              ),
          ],
          selectedIndex: tabs.indexOf(selected),
          onSelected: (index) => controller.selectTab(tabs[index]),
        ),
        SizedBox(height: px(32)),
        Expanded(
          child: kind != null
              ? LayoutBuilder(builder: (context, constraints) => _grid(kind, multiServer, constraints.maxWidth))
              : LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    controller: _vertical,
                    physics: const NeverScrollableScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final rowKind in _rowKinds) ...[
                          _row(rowKind, multiServer),
                          SizedBox(height: px(TvTokens.space.rowGap)),
                        ],
                        SizedBox(height: constraints.maxHeight),
                      ],
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _message(String title, String body, {Widget? action}) {
    final theme = TvTheme.of(context), px = theme.px;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.headline),
        SizedBox(height: px(16)),
        Text(body, style: theme.bodyLarge.copyWith(color: TvTokens.color.text.secondary)),
        if (action != null) ...[SizedBox(height: px(40)), action],
      ],
    );
  }

  Widget _right(bool multiServer) {
    final px = TvTheme.of(context).px;
    switch (controller.state) {
      case TvSearchState.idle:
        return _discoverBlock();
      case TvSearchState.loading:
        if (!controller.showSkeleton) return const SizedBox.shrink();
        return SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const TvRowSkeleton(),
              SizedBox(height: px(TvTokens.space.rowGap)),
              const TvRowSkeleton(),
            ],
          ),
        );
      case TvSearchState.results:
        return _results(multiServer);
      case TvSearchState.empty:
        return _discoverBlock(
          header: _message(TvSearchStrings.nothingFound, TvSearchStrings.nothingFoundHelp(controller.shownQuery)),
        );
      case TvSearchState.unavailable:
        return _message(
          TvSearchStrings.unavailable,
          controller.errorMessage ?? '',
          action: TvButton(
            label: TvStrings.retry,
            icon: Icons.refresh,
            focusNode: _retry,
            onSelect: controller.searchNow,
          ),
        );
    }
  }

  Widget _queryField() {
    final theme = TvTheme.of(context), px = theme.px;
    final query = controller.query;
    return Container(
      key: const ValueKey('tv-search-query'),
      width: px(TvTokens.size.keyboard.panelW),
      height: px(TvTokens.size.keyboard.key),
      padding: EdgeInsets.symmetric(horizontal: px(20)),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: TvTokens.color.bg.skeleton,
        borderRadius: BorderRadius.circular(px(TvTokens.radius.button)),
      ),
      child: Row(
        children: [
          Icon(Icons.search, size: px(32), color: TvTokens.color.text.secondary),
          SizedBox(width: px(16)),
          Expanded(
            child: Text(
              query.isEmpty ? TvSearchStrings.placeholder : query,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.bodyLarge.copyWith(
                color: query.isEmpty ? TvTokens.color.text.secondary : TvTokens.color.text.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final px = TvTheme.of(context).px;
    final size = TvTokens.size.keyboard;
    final multiServer = _multiServer;
    return FocusScope(
      node: _screen,
      onKeyEvent: _screenKey,
      child: Padding(
        padding: EdgeInsets.only(top: px(80)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: (px(TvTokens.space.contentLeft) - MainScreenFocusScope.foregroundLeftOf(context)).clamp(
                0.0,
                double.infinity,
              ),
            ),
            SizedBox(
              width: px(size.panelW),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _queryField(),
                  SizedBox(height: px(32)),
                  TvSearchKeyboard(
                    key: _keyboard,
                    layout: _layout,
                    onLayoutChanged: _setLayout,
                    onInput: _input,
                    onBackspace: _backspace,
                    onClear: _clear,
                    onExitLeft: () => MainScreenFocusScope.focusSidebarOf(context),
                    onExitRight: _exitRight,
                  ),
                ],
              ),
            ),
            SizedBox(width: px(size.resultsX - size.panelX - size.panelW)),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: px(80)),
                // The handler sits on the scope node itself: focus falls back to
                // it when the focused card or button unmounts (loading, retry).
                child: FocusScope(node: _content, onKeyEvent: _contentKey, child: _right(multiServer)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
