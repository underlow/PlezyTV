import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../focus/key_event_utils.dart';
import '../../../focus/dpad_navigator.dart';
import '../../../i18n/strings.g.dart';
import '../../../media/media_hub.dart';
import '../../../media/media_item.dart';
import '../../../mixins/refreshable.dart';
import '../../../mixins/tab_visibility_aware.dart';
import '../../../navigation/main_screen_scope.dart';
import '../../../providers/discover_provider.dart';
import '../../../screens/hub_detail_screen.dart';
import '../../../services/device_performance.dart';
import '../../../services/settings_service.dart';
import '../../../utils/media_navigation_helper.dart';
import '../../../utils/app_logger.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../utils/provider_extensions.dart';
import '../components/tv_all_card.dart';
import '../components/tv_button.dart';
import '../components/tv_cards.dart';
import '../components/tv_hero.dart';
import '../components/tv_horizontal_row.dart';
import '../components/tv_skeletons.dart';
import '../tv_strings.dart';
import '../tv_theme.dart';
import '../tv_tint_service.dart';
import '../tv_tinted_background.dart';
import '../tv_tokens.dart';
import 'tv_home_model.dart';

/// Fork-owned Home. Provider updates rebuild content; focus updates only the
/// hero/background and the vertical viewport, leaving horizontal rails intact.
class TvHomeScreen extends StatefulWidget {
  const TvHomeScreen({super.key});

  @override
  State<TvHomeScreen> createState() => TvHomeScreenState();
}

class TvHomeScreenState extends State<TvHomeScreen>
    with Refreshable, ManualRefreshable, FullRefreshable, TabVisibilityAware, FocusableTab {
  final _builder = TvHomeModelBuilder();
  final _hero = ValueNotifier<MediaItem?>(null);
  final _compact = ValueNotifier(false);
  final _vertical = ScrollController();
  final _content = FocusScopeNode(debugLabel: 'TV Home');
  final _button = FocusNode(debugLabel: 'Home retry/refresh');
  final _rows = <String, GlobalKey<TvHorizontalRowState>>{};
  late DiscoverProvider _provider;
  late TvHomeModel _model;
  ModalRoute<dynamic>? _route;
  Timer? _skeletonTimer;
  bool _initialized = false, _visible = true, _showSkeleton = false;
  FocusNode? _loadingOwner;
  int _focusCommand = 0;
  String? _activeRow;

  String _rowKey(TvHomeRow row) => row.kind == TvHomeRowKind.continueWatching
      ? 'continue'
      : 'hub:${row.hub!.serverId}:${row.hub!.libraryId}:${row.hub!.id}';

  bool get _current => _visible && (_route?.isCurrent ?? true);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
    if (_initialized) return;
    _initialized = true;
    _provider = context.read<DiscoverProvider>();
    _model = _builder.build(_provider);
    _provider.addListener(_changed);
    HardwareKeyboard.instance.addHandler(_observeKey);
    _updateSkeleton();
    _afterFrame(focusActiveTabIfReady);
    unawaited(_provider.load());
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
    setState(() {
      _model = _builder.build(_provider);
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
      final remembered = _rows[_activeRow]?.currentState;
      if (remembered != null) {
        remembered.requestFocus();
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
    _visible = false;
    _loadingOwner = null;
    _focusCommand++;
  }

  @override
  void onTabShown() {
    _visible = true;
    _provider.refreshIfStale();
  }

  @override
  void refresh() {
    if (!_provider.refreshIfStale()) unawaited(_provider.refreshContinueWatching());
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
    manualRefresh();
  }

  void _focused(TvHomeRow row, int index) {
    _activeRow = _rowKey(row);
    _loadingOwner = null;
    _focusCommand++;
    if (index < row.items.length) _hero.value = row.items[index];
    final rowIndex = _model.rows.indexOf(row);
    _compact.value = rowIndex > 1;
    _afterFrame(() => _revealRow(_activeRow!));
  }

  void _revealRow(String key) {
    final render = _rows[key]?.currentContext?.findRenderObject();
    if (render == null || !_vertical.hasClients) return;
    unawaited(
      _vertical.position.ensureVisible(
        render,
        alignment: 0,
        duration: Duration(milliseconds: DevicePerformance.isReduced ? 0 : TvTokens.motion.rowScroll),
        curve: Curves.easeOutCubic,
      ),
    );
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
        if (next >= 0 && next < _model.rows.length) _rows[_rowKey(_model.rows[next])]?.currentState?.requestFocus();
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
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => HubDetailScreen(
          hub: hub,
          loadItems: continuing ? _provider.loadAllContinueWatching : null,
          isInContinueWatching: continuing || hub.isContinueWatchingHub,
          usesContinueWatchingAction: continuing || hub.usesContinueWatchingAction,
          onRemoveFromContinueWatching: _provider.refreshContinueWatching,
        ),
      ),
    );
  }

  Widget _rail(TvHomeRow row) {
    final wide = row.kind == TvHomeRowKind.continueWatching;
    final key = _rowKey(row);
    return TvHorizontalRow(
      key: _rows.putIfAbsent(key, () => GlobalKey<TvHorizontalRowState>()),
      title: row.title,
      counter: row.count?.toString(),
      itemCount: row.items.length + (row.hasMore ? 1 : 0),
      itemKey: (index) => index == row.items.length ? 'all' : TvHomeRow.itemKey(row.items[index]),
      cardWidth: (wide ? TvTokens.size.episode.w : TvTokens.size.poster.w).toDouble(),
      cardHeight:
          (wide ? TvTokens.size.episode.h : TvTokens.size.poster.h) +
          20 +
          TvTokens.type.body.lineHeight +
          TvTokens.type.caption.lineHeight.toDouble(),
      onItemFocused: (index) => _focused(row, index),
      cardBuilder: (context, index, node) {
        if (index == row.items.length) {
          return TvAllCard(episode: wide, focusNode: node, onSelect: () => unawaited(_openAll(row)));
        }
        final item = row.items[index];
        final client = context.getMediaClientForItemOrNull(item);
        void select() => unawaited(
          navigateToMediaItem(
            context,
            item,
            onRefresh: (_) => refresh(),
            playDirectly: wide || (row.hub?.usesContinueWatchingAction ?? false),
          ),
        );
        return wide
            ? TvEpisode(item: item, client: client, focusNode: node, onSelect: select)
            : TvPoster(item: item, client: client, focusNode: node, onSelect: select);
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
              Text(
                _model.errorMessage ?? TvStrings.noConnectionHelp,
                style: theme.bodyLarge,
                textAlign: TextAlign.center,
              ),
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
      // Built only on provider/dependency changes. ValueListenableBuilder's
      // child preserves these exact widget instances during hero updates.
      final rails = LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          controller: _vertical,
          physics: const NeverScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final row in _model.rows) ...[_rail(row), SizedBox(height: px(TvTokens.space.rowGap))],
              if (_model.hubsState == TvHomePartState.loading && !_model.rows.any((r) => r.kind == TvHomeRowKind.hub))
                Padding(
                  padding: EdgeInsets.only(left: px(TvTokens.space.contentLeft)),
                  child: const TvRowSkeleton(),
                ),
              SizedBox(height: constraints.maxHeight),
            ],
          ),
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
                builder: (context, _) => Padding(
                  padding: EdgeInsets.only(left: px(TvTokens.space.contentLeft)),
                  child: TvHero(
                    item: item,
                    compact: compact,
                    hideSpoilers: SettingsService.instanceOrNull?.read(SettingsService.hideSpoilers) ?? false,
                    client: item == null ? null : context.getMediaClientForItemOrNull(item),
                  ),
                ),
              ),
            ),
          ),
          Expanded(child: rails),
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
                    padding: EdgeInsets.only(left: px(TvTokens.space.contentLeft)),
                    child: const TvHeroSkeleton(),
                  ),
                  Padding(
                    padding: EdgeInsets.only(left: px(TvTokens.space.contentLeft)),
                    child: const TvRowSkeleton(episode: true),
                  ),
                  SizedBox(height: px(TvTokens.space.rowGap)),
                  Padding(
                    padding: EdgeInsets.only(left: px(TvTokens.space.contentLeft)),
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
    _provider.removeListener(_changed);
    HardwareKeyboard.instance.removeHandler(_observeKey);
    _skeletonTimer?.cancel();
    _hero.dispose();
    _compact.dispose();
    _vertical.dispose();
    _content.dispose();
    _button.dispose();
    super.dispose();
  }
}
