import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../focus/key_event_utils.dart';
import '../../../navigation/navigation_tabs.dart';
import '../shell/tv_section_shell.dart';
import '../../../focus/dpad_navigator.dart';
import '../../../i18n/strings.g.dart';
import '../../../media/media_hub.dart';
import '../../../media/media_item.dart';
import '../../../mixins/refreshable.dart';
import '../../../mixins/tab_visibility_aware.dart';
import '../../../navigation/main_screen_scope.dart';
import '../../../providers/discover_provider.dart';
import '../../../providers/hidden_libraries_provider.dart';
import '../../../providers/watch_state_store.dart';
import '../../../services/device_performance.dart';
import '../../../services/settings_service.dart';
import '../../../utils/app_logger.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../utils/provider_extensions.dart';
import '../components/tv_all_card.dart';
import '../components/tv_button.dart';
import '../components/tv_hero.dart';
import '../components/tv_horizontal_row.dart';
import '../components/tv_skeletons.dart';
import '../tv_strings.dart';
import '../tv_theme.dart';
import '../tv_tint_service.dart';
import '../tv_tinted_background.dart';
import '../tv_tokens.dart';
import 'tv_home_card.dart';
import 'tv_home_ready.dart';
import 'tv_home_model.dart';
import 'tv_home_playback.dart';

/// Fork-owned Home. Provider updates rebuild content; focus updates only the
/// hero/background and the vertical viewport, leaving horizontal rails intact.
class TvHomeScreen extends StatefulWidget {
  const TvHomeScreen({super.key});

  @override
  State<TvHomeScreen> createState() => TvHomeScreenState();
}

class TvHomeScreenState extends State<TvHomeScreen>
    with Refreshable, ManualRefreshable, FullRefreshable, TabVisibilityAware, FocusableTab, WidgetsBindingObserver {
  final _builder = TvHomeModelBuilder();
  final _hero = ValueNotifier<MediaItem?>(null);
  final _compact = ValueNotifier(false);
  final _vertical = ScrollController();
  final _content = FocusScopeNode(debugLabel: 'TV Home');
  final _button = FocusNode(debugLabel: 'Home retry/refresh');
  final _viewport = GlobalKey();
  bool _readyLogged = false;
  bool _loadWasInFlight = false;
  Timer? _readyProbe;

  final _rowMemory = <String, TvHorizontalRowMemory>{};
  final _rows = <String, GlobalKey<TvHorizontalRowState>>{};
  late DiscoverProvider _provider;
  late TvHomePlayback _playback;
  late TvHomeModel _model;
  ModalRoute<dynamic>? _route;
  bool _routeWasCurrent = false;
  Timer? _skeletonTimer;
  bool _initialized = false, _visible = true, _showSkeleton = false;
  FocusNode? _loadingOwner;
  int _focusCommand = 0;
  String? _activeRow;
  ({String row, String item})? _returnPosition;

  String _rowKey(TvHomeRow row) => row.kind == TvHomeRowKind.continueWatching
      ? 'continue'
      : 'hub:${row.hub!.serverId}:${row.hub!.libraryId}:${row.hub!.id}';

  bool get _current => _visible && (_route?.isCurrent ?? true);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
    final routeCurrent = _route?.isCurrent ?? true;
    if (_initialized) {
      if (!routeCurrent && _routeWasCurrent) _rememberReturnPosition();
      if (routeCurrent && !_routeWasCurrent) _afterFrame(_restoreReturnedFocus);
      _routeWasCurrent = routeCurrent;
      return;
    }
    _routeWasCurrent = routeCurrent;
    _initialized = true;
    final shell = context.findAncestorStateOfType<TvSectionShellState>();
    _playback = TvHomePlayback.forContext(
      context,
      // Route coverage invokes onTabHidden too. Only section selection may
      // cancel the player after it commits its own route above Home.
      isCurrent: () => shell == null
          ? mounted
          : shell.mounted &&
                !shell.currentSection.isNoConnection &&
                shell.currentSection.tab == NavigationTabId.discover,
    );
    _provider = context.read<DiscoverProvider>();
    _model = _builder.build(_provider);
    _syncHero();
    WidgetsBinding.instance.addObserver(this);
    _provider.addListener(_changed);
    HardwareKeyboard.instance.addHandler(_observeKey);
    _updateSkeleton();
    _startReadyProbe();
    _afterFrame(focusActiveTabIfReady);
    unawaited(_loadInitially(context.read<HiddenLibrariesProvider>()));
  }

  Future<void> _loadInitially(HiddenLibrariesProvider hiddenLibraries) async {
    // Its initialization notification can start a full pass itself. Let that
    // notification run first, then avoid queuing a duplicate behind that pass.
    await hiddenLibraries.ensureInitialized();
    if (!mounted || _provider.isLoadInFlight || (!_provider.isLoading && !_provider.areHubsLoading)) return;
    await _provider.load();
  }

  void _startReadyProbe() {
    _readyProbe?.cancel();
    // Timers run between frames; do not drive extra frames while waiting for
    // network images (or indefinitely when artwork is unavailable).
    _readyProbe = Timer.periodic(const Duration(milliseconds: 100), (_) => _probeReady());
  }

  BuildContext? _firstPosterContext(TvHomeRow row) {
    final rail = _rows[_rowKey(row)]?.currentContext;
    if (rail == null) return null;
    Element? first;
    void visit(Element element) {
      if (first != null) return;
      if (element.widget case TvHomeHubCard(:final item)) {
        if (item.globalKey == row.items.first.globalKey) first = element;
      } else {
        element.visitChildren(visit);
      }
    }

    // Inspect the first card without a positional GlobalKey: such a key
    // would transplant focus visuals to a different item inserted at index 0.
    (rail as Element).visitChildren(visit);
    return first;
  }

  void _probeReady() {
    if (_readyLogged ||
        !_current ||
        _model.onDeckState == TvHomePartState.loading ||
        _model.hubsState == TvHomePartState.loading) {
      return;
    }
    final render = _viewport.currentContext?.findRenderObject();
    if (render is! RenderBox || !render.hasSize) return;
    final viewport = render.localToGlobal(Offset.zero) & render.size;
    var top = viewport.top - (_vertical.hasClients ? _vertical.offset : 0);
    final bounds = <Rect>[];
    for (final row in _model.rows) {
      final height = _rowExtent(row);
      bounds.add(Rect.fromLTWH(viewport.left, top, viewport.width, height));
      top += height;
    }
    final count = tvHomeReadyRows(viewport, [
      for (final row in _model.rows) _firstPosterContext(row),
    ], rowBounds: bounds);
    if (count == null) return;
    _readyLogged = true;
    _readyProbe?.cancel();
    appLogger.i('TV home rows ready: visibleRows=$count');
  }

  void _afterFrame(VoidCallback action) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) action();
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  // Even an arrow at the menu boundary is an explicit user choice to stay in
  // the menu. Comparing focus nodes alone would miss that ownership change.
  bool _observeKey(KeyEvent event) {
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      if (_loadingOwner != null && !_content.hasFocus) {
        _loadingOwner = null;
        _focusCommand++;
      }
    }
    return false;
  }

  void _updateSkeleton() {
    if (_model.state != TvHomeState.loading) {
      _skeletonTimer?.cancel();
      _skeletonTimer = null;
      _showSkeleton = false;
    } else {
      _skeletonTimer ??= Timer(const Duration(milliseconds: 300), () {
        if (mounted && _model.state == TvHomeState.loading) setState(() => _showSkeleton = true);
      });
    }
  }

  void _changed() {
    final owner = _button.hasFocus ? _button : _loadingOwner;
    final ownsLoading = owner != null && identical(owner, FocusManager.instance.primaryFocus);
    final ownedContent = _content.hasFocus;
    final previousRows = _model.rows;
    final previousKey = _activeRow;
    final previousCompact = _compact.value;
    double? anchorOffset(List<TvHomeRow> rows) {
      final index = rows.indexWhere((row) => _rowKey(row) == previousKey);
      return index < 0 ? null : rows.take(index).fold<double>(0, (sum, row) => sum + _rowExtent(row));
    }

    final oldAnchor = ownedContent ? anchorOffset(previousRows) : null;
    setState(() {
      _model = _builder.build(_provider);
      if (_model.isLoadInFlight && !_loadWasInFlight) {
        _readyLogged = false;
        _startReadyProbe();
      }
      _loadWasInFlight = _model.isLoadInFlight;
      final keys = _model.rows.map(_rowKey).toSet();
      _rowMemory.removeWhere((key, _) => !keys.contains(key));
      _rows.removeWhere((key, _) => !keys.contains(key));
      _syncHero();
      final newAnchor = ownedContent ? anchorOffset(_model.rows) : null;
      if (oldAnchor != null && newAnchor != null && _vertical.hasClients) {
        // Compensate before the sliver lays out: the same keyed rail stays
        // built and retains its FocusNode even when many rows precede it.
        _compact.value = previousCompact;
        final delta = newAnchor - oldAnchor;
        if (delta != 0) _vertical.jumpTo((_vertical.offset + delta).clamp(0.0, double.infinity));
      }
      _updateSkeleton();
    });
    if (!_current) {
      _loadingOwner = null;
      return;
    }
    if (_model.state == TvHomeState.loading) {
      if (ownedContent) _parkInMenu();
      return;
    }
    if (ownsLoading || _button.hasFocus) {
      final command = _focusCommand;
      _afterFrame(() {
        if (_current &&
            command == _focusCommand &&
            (identical(owner, FocusManager.instance.primaryFocus) ||
                (owner == _button && (FocusManager.instance.primaryFocus == null || _content.hasFocus)))) {
          _loadingOwner = null;
          _activeRow = null;
          _focusReady();
        }
      });
    } else if (ownedContent && !identical(previousRows, _model.rows)) {
      // Surviving rails restore their own item by identity. A removed rail
      // falls back to the first card, without stealing focus from another UI.
      final survives = _model.rows.any((row) => _rowKey(row) == previousKey);
      _afterFrame(() {
        if (_current && !survives) {
          _activeRow = null;
          _focusReady();
        }
      });
    }
  }

  // Hero selection is independent of focus ownership: the menu and covered
  // Home still display the remembered item (or its R9 fallback).
  void _syncHero() {
    if (_model.state != TvHomeState.content) {
      _hero.value = null;
      return;
    }
    final active = _model.rows.where((row) => _rowKey(row) == (_returnPosition?.row ?? _activeRow)).firstOrNull;
    final row = active ?? _model.rows.first;
    if (active == null) _activeRow = null;
    final same = row.items
        .where((item) => item.globalKey == (_returnPosition?.item ?? _hero.value?.globalKey))
        .firstOrNull;
    final index = active == null
        ? 0
        : (_rows[_rowKey(row)]?.currentState?.focusedIndex ?? _rowMemory[_rowKey(row)]?.index ?? 0).clamp(
            0,
            row.items.length - 1,
          );
    _hero.value = same ?? row.items[index];
    _compact.value = _model.rows.indexOf(row) > 1;
    if (_returnPosition != null) {
      _returnPosition = (
        row: _rowKey(row),
        item: active != null && _returnPosition!.item == 'all' && row.hasMore ? 'all' : _hero.value!.globalKey,
      );
    }
  }

  void _rememberReturnPosition() {
    if (!_content.hasFocus || _returnPosition != null) return;
    final row = _model.rows.where((row) => _rowKey(row) == _activeRow).firstOrNull;
    if (row == null) return;
    final index = (_rows[_activeRow]?.currentState?.focusedIndex ?? _rowMemory[_activeRow]?.index ?? 0).clamp(
      0,
      row.items.length - (row.hasMore ? 0 : 1),
    );
    _returnPosition = (row: _activeRow!, item: index == row.items.length ? 'all' : row.items[index].globalKey);
  }

  void _restoreReturnedFocus() {
    // Flutter can restore the Home scope after disposing a covered card/row.
    // Repair only focus already owned by Home; an explicit menu choice wins.
    if (!_current) return;
    final position = _returnPosition;
    _returnPosition = null;
    if (!_content.hasFocus) return;
    if (_model.state == TvHomeState.content && position != null) {
      _activeRow = position.row;
      _focusRow(position.row, itemKey: position.item);
    } else {
      _focusReady();
    }
    // Restoring an already-focused node emits no focus change. Rows above it
    // may have changed while covered, so reconcile its viewport explicitly.
    if (_model.state == TvHomeState.content) {
      final index = _model.rows.indexWhere((row) => _rowKey(row) == _activeRow);
      final rowIndex = index < 0 ? 0 : index;
      final key = _rowKey(_model.rows[rowIndex]);
      _activeRow = key;
      _compact.value = rowIndex > 1;
      _afterFrame(() {
        if (_current && _activeRow == key) _revealRow(key);
      });
    }
  }

  void _parkInMenu() {
    if (!_current) return;
    final command = ++_focusCommand;
    MainScreenFocusScope.focusSidebarOf(context);
    _afterFrame(() {
      if (_current && command == _focusCommand) _loadingOwner = FocusManager.instance.primaryFocus;
    });
  }

  void _focusReady() {
    if (_model.state == TvHomeState.content) {
      if (_activeRow != null && _model.rows.any((row) => _rowKey(row) == _activeRow)) {
        _focusRow(_activeRow!);
      } else {
        final first = _rows[_rowKey(_model.rows.first)]?.currentState;
        if (first?.focusStart() ?? false) first?.requestFocus();
      }
    } else if (_model.state != TvHomeState.loading) {
      _button.requestFocus();
    }
  }

  @override
  void focusActiveTabIfReady() {
    if (!_current) return;
    if (_model.state == TvHomeState.loading) {
      _parkInMenu();
    } else {
      _focusReady();
    }
  }

  @override
  void onTabHidden() {
    _rememberReturnPosition();
    _visible = false;
    _loadingOwner = null;
    _focusCommand++;
  }

  @override
  void onTabShown() {
    _visible = true;
    _provider.refreshIfStale();
    _afterFrame(_restoreReturnedFocus);
  }

  @override
  void refresh() {
    if (!_provider.refreshIfStale()) unawaited(_provider.refreshContinueWatching());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted || !_current) return;
    final startedFullPass = _provider.refreshIfStale();
    if (!startedFullPass &&
        (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS)) {
      unawaited(_provider.refreshContinueWatching());
    }
  }

  @override
  void fullRefresh() => unawaited(_provider.load());

  @override
  void primeRefresh() {
    if (!_provider.isLoadInFlight) fullRefresh();
  }

  @override
  void manualRefresh() => unawaited(_manualRefresh());

  Future<void> _manualRefresh() async {
    final outcome = await _provider.refreshNow();
    if (!mounted) return;
    switch (outcome) {
      case DiscoverRefreshOutcome.failed:
        showErrorSnackBar(context, t.errors.unableToLoad(context: t.discover.title));
      case DiscoverRefreshOutcome.degraded:
        appLogger.w('Discover refresh completed with partial server failures');
      case DiscoverRefreshOutcome.cancelled:
      case DiscoverRefreshOutcome.refreshed:
        break;
    }
  }

  void _retry() {
    if (_model.isLoadInFlight) return;
    _loadingOwner = _button.hasFocus ? _button : null;
    unawaited(_provider.load());
  }

  void _focused(TvHomeRow row, int index) {
    if (_returnPosition != null) return;
    final sameRow = _activeRow == _rowKey(row);
    _activeRow = _rowKey(row);
    _loadingOwner = null;
    _focusCommand++;
    if (index < row.items.length) _hero.value = row.items[index];
    if (sameRow) return;
    final rowIndex = _model.rows.indexOf(row);
    _compact.value = rowIndex > 1;
    final key = _activeRow!;
    _afterFrame(() {
      if (_current && _activeRow == key) _revealRow(key);
    });
  }

  double _cardHeight(TvHomeRow row) {
    final theme = TvTheme.of(context);
    final captions =
        (theme.px(TvTokens.type.body.lineHeight).ceilToDouble() +
            theme.px(TvTokens.type.caption.lineHeight).ceilToDouble()) /
        theme.scale;
    return (row.kind == TvHomeRowKind.continueWatching
            ? TvTokens.size.episode.h
            : row.layout == TvHomeRowLayout.music
            ? TvTokens.size.poster.w
            : TvTokens.size.poster.h) +
        20 +
        captions;
  }

  double _rowExtent(TvHomeRow row) {
    final px = TvTheme.of(context).px;
    return px(TvTokens.type.title.lineHeight).ceilToDouble() +
        px(TvTokens.space.rowHeaderToCards + TvTokens.space.cardFocusReserve + TvTokens.space.rowGap) +
        px(_cardHeight(row));
  }

  void _revealRow(String key, {bool immediate = false}) {
    if (!_vertical.hasClients) return;
    final index = _model.rows.indexWhere((row) => _rowKey(row) == key);
    if (index < 0) return;
    final offset = _model.rows.take(index).fold(0.0, (sum, row) => sum + _rowExtent(row));
    final target = offset.clamp(0.0, _vertical.position.maxScrollExtent);
    if (immediate || DevicePerformance.isReduced) {
      _vertical.jumpTo(target);
    } else {
      unawaited(
        _vertical.animateTo(
          target,
          duration: Duration(milliseconds: TvTokens.motion.rowScroll),
          curve: Curves.easeOutCubic,
        ),
      );
    }
  }

  void _focusRow(String key, {String? itemKey}) {
    final built = _rows[key]?.currentState;
    if (built != null) {
      built.requestFocus(itemKey: itemKey);
      return;
    }
    _revealRow(key, immediate: true);
    final command = ++_focusCommand;
    _afterFrame(() {
      if (_current && command == _focusCommand) _rows[key]?.currentState?.requestFocus(itemKey: itemKey);
    });
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      if (event is KeyDownEvent || event is KeyRepeatEvent) {
        _loadingOwner = null;
        _focusCommand++;
        MainScreenFocusScope.focusSidebarOf(context);
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp || event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (event is KeyDownEvent || event is KeyRepeatEvent) {
        final index = _model.rows.indexWhere((row) => _rowKey(row) == _activeRow);
        final next = index + (event.logicalKey == LogicalKeyboardKey.arrowDown ? 1 : -1);
        if (next >= 0 && next < _model.rows.length) _focusRow(_rowKey(_model.rows[next]));
      }
      return KeyEventResult.handled;
    }
    final row = _rows[_activeRow]?.currentState;
    if (event.logicalKey.isBackKey && row != null && row.focusedIndex > 0) {
      return handleBackKeyAction(event, () => row.focusStart());
    }
    return KeyEventResult.ignored;
  }

  Future<void> _openAll(TvHomeRow row) async {
    final continuing = row.kind == TvHomeRowKind.continueWatching;
    final hub =
        row.hub ??
        MediaHub(
          id: 'continue_watching',
          identifier: '_continue_watching_',
          title: row.title,
          type: 'mixed',
          items: _provider.onDeck,
          size: _provider.onDeck.length + (_provider.hasMoreContinueWatching ? 1 : 0),
          more: row.hasMore,
        );
    await openTvHubDetail(
      context,
      hub,
      loadItems: continuing ? _provider.loadAllContinueWatching : null,
      continuing: continuing,
      onRemoveFromContinueWatching: _provider.refreshContinueWatching,
    );
  }

  Widget _rail(TvHomeRow row) {
    final wide = row.kind == TvHomeRowKind.continueWatching;
    final music = row.layout == TvHomeRowLayout.music;
    final key = _rowKey(row);
    return TvHorizontalRow(
      key: _rows.putIfAbsent(key, () => GlobalKey<TvHorizontalRowState>()),
      title: row.title,
      counter: row.count?.toString(),
      itemCount: row.items.length + (row.hasMore ? 1 : 0),
      itemKey: (index) => index == row.items.length ? 'all' : TvHomeRow.itemKey(row.items[index]),
      cardWidth: (wide ? TvTokens.size.episode.w : TvTokens.size.poster.w).toDouble(),
      cardHeight: _cardHeight(row),
      positionMemory: _rowMemory.putIfAbsent(key, TvHorizontalRowMemory.new),
      onItemFocused: (index) => _focused(row, index),
      cardBuilder: (context, index, node) {
        if (index == row.items.length) {
          return TvAllCard(episode: wide, square: music, focusNode: node, onSelect: () => unawaited(_openAll(row)));
        }
        return TvHomeHubCard(
          item: row.items[index],
          focusNode: node,
          playback: _playback,
          wide: wide,
          playDirectly: wide || (row.hub?.usesContinueWatchingAction ?? false),
          isInContinueWatching: wide || (row.hub?.isContinueWatchingHub ?? false),
          onRefresh: _provider.updateItem,
          onRemoveFromContinueWatching: _provider.refreshContinueWatching,
        );
      },
    );
  }

  Widget _terminal() {
    final theme = TvTheme.of(context), px = TvTheme.of(context).px;
    final error = _model.state == TvHomeState.error;
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: px(64)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (error) ...[
              Icon(Icons.cloud_off, size: px(96), color: TvTokens.color.text.secondary),
              SizedBox(height: px(32)),
            ],
            Text(error ? TvStrings.noConnection : TvStrings.homeEmpty, style: theme.headline),
            if (error) ...[
              SizedBox(height: px(16)),
              Text(TvStrings.noConnectionHelp, style: theme.bodyLarge, textAlign: TextAlign.center),
            ],
            SizedBox(height: px(40)),
            TvButton(
              label: _model.isLoadInFlight
                  ? TvStrings.connecting
                  : error
                  ? TvStrings.retry
                  : TvStrings.refresh,
              focusNode: _button,
              disabled: _model.isLoadInFlight,
              onSelect: _retry,
              icon: Icons.refresh,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final px = TvTheme.of(context).px;
    Widget content;
    if (_model.state == TvHomeState.content) {
      // Cache widget instances across hero constraint changes, but construct
      // only the rails requested by the sliver's viewport and cache region.
      final railsByKey = <String, Widget>{};
      final loadingHubs =
          _model.hubsState == TvHomePartState.loading && !_model.rows.any((r) => r.kind == TvHomeRowKind.hub);
      final rails = LayoutBuilder(
        builder: (context, constraints) => ListView.builder(
          controller: _vertical,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          scrollCacheExtent: ScrollCacheExtent.pixels(constraints.maxHeight),
          addAutomaticKeepAlives: false,
          findChildIndexCallback: (key) {
            final index = _model.rows.indexWhere((row) => ValueKey(_rowKey(row)) == key);
            return index < 0 ? null : index;
          },
          itemCount: _model.rows.length + (loadingHubs ? 1 : 0) + 1,
          itemExtentBuilder: (index, _) => index < _model.rows.length
              ? _rowExtent(_model.rows[index])
              : index == _model.rows.length && loadingHubs
              ? px(80 + TvTokens.size.poster.h + 20 + TvTokens.type.body.lineHeight + TvTokens.type.caption.lineHeight)
              : constraints.maxHeight,
          itemBuilder: (context, index) {
            if (index >= _model.rows.length) {
              return index == _model.rows.length && loadingHubs
                  ? Padding(
                      padding: EdgeInsets.only(
                        left: (px(TvTokens.space.contentLeft) - MainScreenFocusScope.foregroundLeftOf(context)).clamp(
                          0.0,
                          double.infinity,
                        ),
                      ),
                      child: const TvRowSkeleton(),
                    )
                  : const SizedBox();
            }
            final row = _model.rows[index];
            final key = _rowKey(row);
            return railsByKey.putIfAbsent(
              key,
              () => Padding(
                key: ValueKey(key),
                padding: EdgeInsets.only(bottom: px(TvTokens.space.rowGap)),
                child: _rail(row),
              ),
            );
          },
        ),
      );
      content = Column(
        children: [
          ValueListenableBuilder<bool>(
            valueListenable: _compact,
            builder: (context, compact, _) => ValueListenableBuilder<MediaItem?>(
              valueListenable: _hero,
              builder: (context, item, _) => ListenableBuilder(
                listenable:
                    SettingsService.instanceOrNull?.listenable(SettingsService.hideSpoilers) ??
                    const AlwaysStoppedAnimation(false),
                builder: (context, _) {
                  final effective = item == null ? null : context.withFreshWatchState(item);
                  return Padding(
                    padding: EdgeInsets.only(
                      top: px(TvTokens.space.safeY),
                      left: (px(TvTokens.space.contentLeft) - MainScreenFocusScope.foregroundLeftOf(context)).clamp(
                        0.0,
                        double.infinity,
                      ),
                    ),
                    child: TvHero(
                      loadFullRatings: true,
                      item: effective,
                      compact: compact,
                      hideSpoilers: SettingsService.instanceOrNull?.read(SettingsService.hideSpoilers) ?? false,
                      client: effective == null ? null : context.getMediaClientForItemOrNull(effective),
                    ),
                  );
                },
              ),
            ),
          ),
          Expanded(
            child: SizedBox(key: _viewport, child: rails),
          ),
        ],
      );
    } else if (_model.state == TvHomeState.loading) {
      content = !_showSkeleton
          ? const SizedBox.expand()
          : SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsets.only(
                      top: px(TvTokens.space.safeY),
                      left: (px(TvTokens.space.contentLeft) - MainScreenFocusScope.foregroundLeftOf(context)).clamp(
                        0.0,
                        double.infinity,
                      ),
                    ),
                    child: const TvHeroSkeleton(),
                  ),
                  Padding(
                    padding: EdgeInsets.only(
                      left: (px(TvTokens.space.contentLeft) - MainScreenFocusScope.foregroundLeftOf(context)).clamp(
                        0.0,
                        double.infinity,
                      ),
                    ),
                    child: const TvRowSkeleton(episode: true),
                  ),
                  SizedBox(height: px(TvTokens.space.rowGap)),
                  Padding(
                    padding: EdgeInsets.only(
                      left: (px(TvTokens.space.contentLeft) - MainScreenFocusScope.foregroundLeftOf(context)).clamp(
                        0.0,
                        double.infinity,
                      ),
                    ),
                    child: const TvRowSkeleton(),
                  ),
                ],
              ),
            );
    } else {
      content = _terminal();
    }
    return FocusScope(
      node: _content,
      child: Focus(
        canRequestFocus: false,
        onKeyEvent: _key,
        child: ValueListenableBuilder<MediaItem?>(
          valueListenable: _hero,
          child: content,
          builder: (context, item, child) => Stack(
            fit: StackFit.expand,
            children: [
              if (item == null)
                const TvPlainBackground()
              else
                TvTintedBackground(
                  source: TvArtworkSource(item: item, client: context.getMediaClientForItemOrNull(item)),
                ),
              child!,
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _provider.removeListener(_changed);
    HardwareKeyboard.instance.removeHandler(_observeKey);
    _skeletonTimer?.cancel();
    _readyProbe?.cancel();
    _hero.dispose();
    _compact.dispose();
    _vertical.dispose();
    _content.dispose();
    _button.dispose();
    super.dispose();
  }
}
