import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../focus/key_event_utils.dart';
import '../../../i18n/strings.g.dart';
import '../../../media/media_item.dart';
import '../../../providers/catalog_sources_provider.dart';
import '../../../services/device_performance.dart';
import '../../../utils/deletion_notifier.dart';
import '../../../utils/formatters.dart';
import '../../../utils/media_navigation_helper.dart';
import '../../../utils/provider_extensions.dart';
import '../../../utils/video_player_navigation.dart';
import '../../../widgets/media_context_menu.dart';
import '../../../widgets/optimized_media_image.dart';
import '../components/tv_button.dart';
import '../components/tv_cards.dart';
import '../components/tv_chip.dart';
import '../components/tv_hero.dart';
import '../components/tv_horizontal_row.dart';
import '../components/tv_ratings.dart';
import '../components/tv_tabs.dart';
import '../tv_focusable.dart';
import '../tv_strings.dart';
import '../tv_theme.dart';
import '../tv_tint_service.dart';
import '../tv_tinted_background.dart';
import 'tv_show_actions.dart';
import 'tv_show_controller.dart';
import 'tv_show_logic.dart';

class TvShowScreen extends StatefulWidget {
  const TvShowScreen({
    super.key,
    required this.metadata,
    this.initialSeasonIndex,
    this.initialSeasonId,
    this.initialEpisodeId,
    this.controller,
    this.playEpisode,
  });
  final MediaItem metadata;
  final int? initialSeasonIndex;
  final String? initialSeasonId;
  final String? initialEpisodeId;

  /// Optional borrowed controller and playback adapter for isolated screen tests.
  final TvShowController? controller;
  final Future<void> Function(BuildContext, MediaItem, bool restart)? playEpisode;

  @override
  State<TvShowScreen> createState() => _TvShowScreenState();
}

class _TvShowScreenState extends State<TvShowScreen> {
  TvShowController? _controller;
  final _tabs = GlobalKey<TvTabsState>();
  final _episodes = GlobalKey<TvHorizontalRowState>();
  final _seasons = GlobalKey<TvHorizontalRowState>();
  final _actionScope = FocusScopeNode(debugLabel: 'Show actions');
  final _lowerKeys = <String, GlobalKey<TvHorizontalRowState>>{};
  final _primary = FocusNode(debugLabel: 'Show primary');
  final _retry = FocusNode(debugLabel: 'Show retry');
  final _page = ScrollController();
  final _tabScope = FocusScopeNode(debugLabel: 'Show tabs');
  final _lastEpisode = <String, String>{};
  final _menus = <String, GlobalKey<MediaContextMenuState>>{};
  StreamSubscription<DeletionEvent>? _deletions;
  Timer? _skeletonTimer, _heroTimer;
  bool _skeleton = false, _ready = false, _initialFocus = false;
  bool _playing = false, _pendingEntryFocus = false;
  int _tab = 0, _selection = 0;
  MediaItem? _hero, _backdropEpisode;
  Object? _connectionError, _reportedError;
  String? _selectedSeasonKey;
  bool _wasLoading = false, _restoreEpisodeFocus = false;

  bool get _episodeHasFocus =>
      FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<TvHorizontalRow>()?.key == _episodes;

  String get _key => _controller!.flattened ? _controller!.flattenedKey : _controller!.seasons[_tab - 1].id;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null || _connectionError != null) return;
    _connect();
  }

  void _connect() {
    try {
      _controller = widget.controller;
      if (_controller == null) {
        final client = context.getMediaClientForItemOrNull(widget.metadata);
        if (client == null) throw StateError('Server unavailable');
        _controller = TvShowController(
          client: client,
          metadata: widget.metadata,
          catalogSources: context.read<CatalogSourcesProvider?>(),
        );
      }
      _controller!.addListener(_changed);
      _deletions = DeletionNotifier().stream.listen((event) {
        if (!mounted) return;
        final c = _controller!;
        if (event.isDownloadOnly || event.serverId.toString() != c.show.serverId) return;
        if (event.itemId == c.show.id) {
          final route = ModalRoute.of(context);
          if (route?.isCurrent == true) {
            Navigator.of(context).pop(c.watchStateChanged);
          } else if (route != null) {
            Navigator.of(context).removeRoute(route, c.watchStateChanged);
          }
        } else if (event.parentChain.contains(c.show.id)) {
          unawaited(c.refresh());
        }
      });
      _startLoad();
    } catch (error) {
      _connectionError = error;
    }
  }

  void _startLoad() {
    _skeletonTimer?.cancel();
    _skeleton = false;
    _skeletonTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _skeleton = true);
    });
    unawaited(_controller!.load());
  }

  void _changed() {
    if (!mounted) return;
    final c = _controller!;
    if (c.loading && !_wasLoading) _restoreEpisodeFocus = _episodeHasFocus;
    final finishedRefresh = _wasLoading && !c.loading;
    _wasLoading = c.loading;
    if (_ready && _tab > 0) {
      final index = c.flattened
          ? (_selectedSeasonKey == c.flattenedKey ? 1 : 0)
          : c.seasons.indexWhere((season) => season.id == _selectedSeasonKey) + 1;
      if (_tab != index) {
        _tab = index;
        ++_selection;
        _heroTimer?.cancel();
        if (index == 0) {
          _hero = _backdropEpisode = null;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _primary.requestFocus();
          });
        }
      }
    }
    if (!c.loading) {
      _skeletonTimer?.cancel();
      if (!_ready && c.error == null) {
        _ready = true;
        _tab = tvShowInitialTab(
          c.seasons,
          flattened: c.flattened,
          seasonId: widget.initialSeasonId,
          seasonIndex: widget.initialSeasonIndex,
          episodeId: widget.initialEpisodeId,
        );
        _selectedSeasonKey = _tab > 0 ? _key : null;
        final selection = ++_selection;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || selection != _selection) return;
          if (_tab > 0) {
            unawaited(_enterSeason(focus: true, initialId: widget.initialEpisodeId));
          } else {
            _focusPrimaryOnce();
          }
        });
      } else if (_ready && !_initialFocus && c.primaryAction != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _focusPrimaryOnce());
      }
      if (_ready && c.error != null && !identical(_reportedError, c.error)) {
        _reportedError = c.error;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('Unable to refresh. Check your connection.')));
          }
        });
      }
      if (c.error != null && !_ready) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _retry.requestFocus();
        });
      }
    }
    if (_ready && _tab > 0 && !c.loading) {
      final updated = c.episodesFor(_key).where((e) => e.id == _hero?.id).firstOrNull;
      if (updated != null) _hero = updated;
      if (finishedRefresh &&
          !_playing &&
          (_restoreEpisodeFocus || _episodeHasFocus) &&
          ModalRoute.of(context)?.isCurrent == true) {
        _restoreEpisodeFocus = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _tab > 0) unawaited(_enterSeason(focus: true));
        });
      }
      if (_pendingEntryFocus && !c.isLoadingEpisodes(_key)) {
        _pendingEntryFocus = false;
        final selection = _selection;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && selection == _selection) unawaited(_enterSeason(focus: true));
        });
      }
    }
    setState(() {});
  }

  void _focusPrimaryOnce() {
    if (!mounted || _initialFocus || _tab != 0 || _controller?.primaryAction == null) return;
    _initialFocus = true;
    if (!_tabScope.hasFocus) _primary.requestFocus();
  }

  void _select(int index, {bool focus = false}) {
    ++_selection;
    _pendingEntryFocus = false;
    _heroTimer?.cancel();
    setState(() {
      _tab = index;
      _selectedSeasonKey = index > 0 ? _key : null;
      _hero = null;
      _backdropEpisode = null;
    });
    if (index > 0) {
      unawaited(_enterSeason(focus: focus));
    } else if (focus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _tab == 0) _primary.requestFocus();
      });
    }
  }

  Future<void> _enterSeason({required bool focus, String? initialId}) async {
    final c = _controller!;
    final selection = _selection;
    final key = _key;
    final wanted = _lastEpisode[key] ?? initialId;
    bool current() => mounted && selection == _selection && _tab > 0;
    while (current()) {
      final items = c.episodesFor(key);
      final found = wanted == null ? items.any((e) => !e.isWatched) : items.any((e) => e.id == wanted);
      if (found || c.isComplete(key) || c.pageErrors.containsKey(key)) break;
      if (c.loading || c.isLoadingEpisodes(key)) {
        _pendingEntryFocus = _pendingEntryFocus || focus;
        return;
      }
      await c.loadMoreEpisodes(key);
    }
    if (!current()) return;
    final episode = tvShowFocusEpisode(c.episodesFor(key), initialEpisodeId: wanted);
    setState(() {
      _hero = episode;
      _backdropEpisode = episode;
    });
    if (episode == null) return;
    _lastEpisode[key] = episode.id;
    if (focus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (current()) _episodes.currentState?.requestFocus(itemKey: episode.id);
      });
    }
  }

  void _focusedEpisode(int index) {
    final key = _key;
    final items = _controller!.episodesFor(key);
    if (index >= items.length) return;
    final episode = items[index];
    _lastEpisode[key] = episode.id;
    _heroTimer?.cancel();
    if (_hero?.id != episode.id) {
      _heroTimer = Timer(const Duration(milliseconds: 300), () {
        if (mounted && _tab > 0 && _key == key) {
          setState(() {
            _hero = episode;
            _backdropEpisode = episode;
          });
        }
      });
    }
    if (!_playing && index >= items.length - 5) unawaited(_controller!.loadMoreEpisodes(key));
  }

  Future<void> _play(MediaItem episode, {bool restart = false}) async {
    if (_playing) return;
    _playing = true;
    final c = _controller!;
    final seasonKey = _tab > 0 ? _key : null;
    try {
      if (widget.playEpisode != null) {
        await widget.playEpisode!(context, episode, restart);
      } else {
        // Explicit restart bypasses the session's saved resume position.
        final changed = await navigateToVideoPlayer(
          context,
          metadata: episode,
          resolveWatchState: !restart,
          initialPosition: restart ? Duration.zero : null,
        );
        if (changed == true) c.watchStateChanged = true;
      }
      if (!mounted) return;
      await c.refresh();
      if (!mounted) return;
      if (seasonKey != null && _tab > 0 && _key == seasonKey) {
        var items = c.episodesFor(seasonKey);
        var index = items.indexWhere((e) => e.id == episode.id);
        if (index >= 0 && items[index].isWatched) {
          while (!items.skip(index + 1).any((e) => !e.isWatched) && !c.isComplete(seasonKey)) {
            await c.loadMoreEpisodes(seasonKey);
            if (!mounted || c.pageErrors.containsKey(seasonKey)) break;
            items = c.episodesFor(seasonKey);
            index = items.indexWhere((e) => e.id == episode.id);
          }
          final next = items.skip(index + 1).where((e) => !e.isWatched).firstOrNull;
          if (next != null) _lastEpisode[seasonKey] = next.id;
        }
        if (mounted) await _enterSeason(focus: true);
      } else {
        _primary.requestFocus();
      }
    } finally {
      _playing = false;
    }
  }

  void _back() {
    if (_tab > 0) {
      _select(0, focus: true);
      return;
    }
    Navigator.of(context).pop(_controller?.watchStateChanged ?? false);
  }

  KeyEventResult _contentKeys(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent || event is KeyRepeatEvent) _revealContent();
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (event is KeyDownEvent || event is KeyRepeatEvent) {
        _tabs.currentState?.requestFocus();
        _scrollTop();
      }
      return KeyEventResult.handled;
    }
    if (_actionScope.hasFocus && event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (event is KeyDownEvent || event is KeyRepeatEvent) {
        final c = _controller!;
        if (!c.flattened && c.seasons.isNotEmpty) {
          _seasons.currentState?.requestFocus();
        } else {
          for (final key in _lowerKeys.values) {
            if (key.currentState != null) {
              key.currentState!.requestFocus();
              break;
            }
          }
        }
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _revealFocusedTab() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_tabScope.hasFocus) return;
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
  }

  void _scrollTop() {
    if (!_page.hasClients) return;
    if (DevicePerformance.isReduced) {
      _page.jumpTo(0);
    } else {
      unawaited(_page.animateTo(0, duration: const Duration(milliseconds: 150), curve: Curves.easeOutCubic));
    }
  }

  @override
  void dispose() {
    ++_selection;
    _skeletonTimer?.cancel();
    _heroTimer?.cancel();
    unawaited(_deletions?.cancel());
    _controller?.removeListener(_changed);
    if (widget.controller == null) _controller?.dispose();
    _actionScope.dispose();
    _primary.dispose();
    _retry.dispose();
    _tabScope.dispose();
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TvTheme(child: Builder(builder: _build));

  Widget _build(BuildContext context) {
    final theme = TvTheme.of(context), px = TvTheme.of(context).px;
    final c = _controller;
    final show = c?.show ?? widget.metadata;
    final episode = _tab > 0 ? _backdropEpisode : null;
    final artwork = episode == null ? show : episode.copyWith(artPath: episode.thumbPath);
    return PopScope<bool>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        body: Focus(
          canRequestFocus: false,
          onKeyEvent: (_, event) => handleBackKeyAction(event, _back),
          child: TvTintedBackground(
            source: TvArtworkSource(item: artwork, client: c?.client),
            child: SingleChildScrollView(
              controller: _page,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsets.only(left: px(200), top: px(72), right: px(96)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClearLogoImage(
                          client: c?.client,
                          logoPath: show.clearLogoPath,
                          fallbackWidth: px(900),
                          width: px(560),
                          height: px(100),
                          alignment: Alignment.centerLeft,
                          fallbackBuilder: (_) => Text(
                            show.displayTitle,
                            style: theme.display,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        SizedBox(height: px(16)),
                        SizedBox(
                          height: px(40),
                          child: Text(tvShowMetadata(show, c?.seasons ?? []), style: theme.body),
                        ),
                        SizedBox(height: px(24)),
                        if (_ready)
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: FocusScope(
                              node: _tabScope,
                              onFocusChange: (inside) {
                                if (inside) _revealFocusedTab();
                              },
                              onKeyEvent: (_, event) {
                                if ((event is KeyDownEvent || event is KeyRepeatEvent) &&
                                    (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
                                        event.logicalKey == LogicalKeyboardKey.arrowRight)) {
                                  _revealFocusedTab();
                                }
                                if (event.logicalKey != LogicalKeyboardKey.arrowDown) return KeyEventResult.ignored;
                                if (event is KeyDownEvent || event is KeyRepeatEvent) {
                                  final pending = _tabs.currentState?.focusedIndex;
                                  if (pending != null && pending != _tab) _select(pending);
                                  if (_tab == 0) {
                                    _primary.requestFocus();
                                  } else {
                                    unawaited(_enterSeason(focus: true));
                                  }
                                }
                                return KeyEventResult.handled;
                              },
                              child: TvTabs(
                                key: _tabs,
                                tabs: [
                                  const TvTab(label: 'Show'),
                                  if (c!.flattened)
                                    const TvTab(label: 'Episodes')
                                  else
                                    for (final season in c.seasons) TvTab(label: season.displayTitle),
                                ],
                                selectedIndex: _tab,
                                onSelected: _select,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (_connectionError != null || (c?.error != null && !_ready))
                    Padding(
                      padding: EdgeInsets.all(px(64)),
                      child: Column(
                        children: [
                          Text('Unable to connect to the server. Check your connection.', style: theme.body),
                          SizedBox(height: px(24)),
                          TvButton(
                            label: 'Retry',
                            focusNode: _retry,
                            autofocus: true,
                            onSelect: () {
                              if (_controller != null) {
                                _startLoad();
                              } else {
                                setState(() {
                                  _connectionError = null;
                                  _connect();
                                });
                              }
                            },
                          ),
                        ],
                      ),
                    )
                  else if (!_ready)
                    Padding(
                      padding: EdgeInsets.only(left: px(200)),
                      child: _skeleton ? const TvHeroSkeleton() : SizedBox(height: px(600)),
                    )
                  else
                    Focus(
                      canRequestFocus: false,
                      onKeyEvent: _contentKeys,
                      child: _tab == 0 ? _overview(context) : _season(context),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _overview(BuildContext context) {
    final c = _controller!, theme = TvTheme.of(context), px = TvTheme.of(context).px;
    final action = c.primaryAction;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(left: px(200), top: px(32), right: px(96)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final genre in c.show.genres ?? <String>[])
                      Padding(
                        padding: EdgeInsets.only(right: px(12)),
                        child: TvChip.genre(label: genre),
                      ),
                    TvRatings(item: c.show.copyWith(ratings: c.ratings)),
                  ],
                ),
              ),
              SizedBox(height: px(20)),
              SizedBox(
                height: px(112),
                width: px(900),
                child: Text(c.show.summary ?? '', maxLines: 3, overflow: TextOverflow.ellipsis, style: theme.bodyLarge),
              ),
              SizedBox(height: px(28)),
              FocusScope(
                node: _actionScope,
                child: TvShowActions(
                  controller: c,
                  playExtra: _playExtra,
                  primary: TvButton(
                    label: action?.label ?? 'Watch',
                    icon: Icons.play_arrow,
                    focusNode: _primary,
                    disabled: action == null,
                    onSelect: action == null ? null : () => unawaited(_play(action.episode, restart: action.restart)),
                  ),
                ),
              ),
              SizedBox(height: px(26)),
            ],
          ),
        ),
        if (!c.flattened && c.seasons.isNotEmpty)
          TvHorizontalRow(
            key: _seasons,
            title: 'Seasons',
            onItemFocused: (_) => _revealContent(),
            counter: '${c.seasons.length}',
            itemCount: c.seasons.length,
            cardWidth: 160,
            cardHeight: 330,
            itemKey: (i) => c.seasons[i].id,
            cardBuilder: (context, i, node) => TvPoster(
              item: c.seasons[i],
              client: c.client,
              size: TvPosterSize.season,
              caption: c.seasons[i].leafCount == null ? '' : TvStrings.episodes(c.seasons[i].leafCount!),
              focusNode: node,
              onSelect: () => _select(i + 1, focus: true),
            ),
          ),
        ..._lowerRows(context),
        SizedBox(height: px(54)),
      ],
    );
  }

  Future<void> _playExtra(MediaItem item) async {
    final changed = await navigateToVideoPlayer(context, metadata: item);
    if (!mounted) return;
    if (changed == true) _controller!.watchStateChanged = true;
    await _controller!.refresh();
  }

  void _revealContent() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final anchor = FocusManager.instance.primaryFocus?.context;
      if (anchor == null || _tabScope.hasFocus) return;
      unawaited(
        Scrollable.ensureVisible(
          anchor,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
          duration: Duration(milliseconds: DevicePerformance.isReduced ? 0 : 150),
        ),
      );
    });
  }

  List<Widget> _lowerRows(BuildContext context) {
    final c = _controller!, px = TvTheme.of(context).px;
    final roles = c.show.roles ?? [];
    return [
      if (roles.isNotEmpty)
        TvHorizontalRow(
          key: _lowerKeys.putIfAbsent('cast', () => GlobalKey<TvHorizontalRowState>()),
          title: t.discover.cast,
          itemCount: roles.length,
          cardWidth: 200,
          cardHeight: 290,
          itemKey: (i) => '${roles[i].id}/${roles[i].tag}',
          onItemFocused: (_) => _revealContent(),
          cardBuilder: (context, i, node) {
            final role = roles[i];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TvFocusable(
                  focusNode: node,
                  semanticLabel: role.tag,
                  onSelect: role.id == null || c.show.serverId == null
                      ? null
                      : () => unawaited(
                          navigateToPersonMedia(
                            context,
                            personId: role.id!,
                            name: role.tag,
                            thumbPath: role.thumbPath,
                            characterName: role.role,
                            serverId: c.show.serverId!,
                            serverName: c.show.serverName,
                            backend: c.show.backend,
                          ),
                        ),
                  builder: (_, _) => ClipOval(
                    child: OptimizedMediaImage(
                      client: c.client,
                      imagePath: role.thumbPath,
                      width: px(200),
                      height: px(200),
                      fallbackIcon: Icons.person,
                    ),
                  ),
                ),
                SizedBox(height: px(20)),
                Text(role.tag, maxLines: 1, overflow: TextOverflow.ellipsis, style: TvTheme.of(context).body),
                Text(role.role ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: TvTheme.of(context).caption),
              ],
            );
          },
        ),
      if (c.extras.isNotEmpty)
        TvHorizontalRow(
          key: _lowerKeys.putIfAbsent('extras', () => GlobalKey<TvHorizontalRowState>()),
          title: t.discover.extras,
          itemCount: c.extras.length,
          cardWidth: 400,
          cardHeight: 315,
          itemKey: (i) => c.extras[i].globalKey,
          onItemFocused: (_) => _revealContent(),
          cardBuilder: (context, i, node) => TvEpisode(
            item: c.extras[i],
            client: c.client,
            focusNode: node,
            onSelect: () => unawaited(_playExtra(c.extras[i])),
          ),
        ),
      for (final hub in c.relatedHubs.where((h) => h.items.isNotEmpty))
        TvHorizontalRow(
          key: _lowerKeys.putIfAbsent('related/${hub.id}', () => GlobalKey<TvHorizontalRowState>()),
          title: hub.title.isEmpty ? t.discover.moreLikeThis : hub.title,
          itemCount: hub.items.length,
          cardWidth: 216,
          cardHeight: 414,
          itemKey: (i) => hub.items[i].globalKey,
          onItemFocused: (_) => _revealContent(),
          cardBuilder: (context, i, node) {
            final item = hub.items[i];
            final menu = _menus.putIfAbsent(
              'related/${hub.id}/${item.globalKey}',
              () => GlobalKey<MediaContextMenuState>(),
            );
            return MediaContextMenu(
              key: menu,
              item: item,
              onRefresh: (_) => unawaited(c.refresh()),
              child: TvPoster(
                item: item,
                client: c.client,
                focusNode: node,
                onSelect: () => unawaited(navigateToMediaItem(context, item, onRefresh: (_) => unawaited(c.refresh()))),
                onLongPress: () {
                  final state = menu.currentState;
                  if (state != null) state.showContextMenu(state.context);
                },
              ),
            );
          },
        ),
    ];
  }

  Widget _season(BuildContext context) {
    final c = _controller!, theme = TvTheme.of(context), px = TvTheme.of(context).px;
    final key = _key, items = c.episodesFor(_key), episode = _hero;
    final title = c.flattened ? 'Episodes' : c.seasons[_tab - 1].displayTitle;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(left: px(200), top: px(32)),
          child: SizedBox(
            height: px(340),
            width: px(900),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  episode == null
                      ? ''
                      : TvStrings.episode(
                          season: episode.parentIndex ?? 1,
                          episode: episode.index ?? 1,
                          title: episode.displayTitle,
                        ),
                  style: theme.headline,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: px(12)),
                Text(
                  [
                    if (episode?.durationMs != null) formatDurationTextual(episode!.durationMs!),
                    if (episode?.originallyAvailableAt != null) episode!.originallyAvailableAt!,
                    if (episode != null && tvShowWatchedProgress(episode) != null) tvShowWatchedProgress(episode)!,
                  ].join(' · '),
                  style: theme.body,
                ),
                SizedBox(height: px(16)),
                if (episode != null) TvRatings(item: episode),
                SizedBox(height: px(20)),
                Text(episode?.summary ?? '', maxLines: 3, overflow: TextOverflow.ellipsis, style: theme.bodyLarge),
              ],
            ),
          ),
        ),
        TvHorizontalRow(
          key: _episodes,
          title: title,
          counter: c.episodeTotal(key) == null ? null : TvStrings.episodes(c.episodeTotal(key)!),
          itemCount: items.length,
          cardWidth: 400,
          cardHeight: 315,
          itemKey: (i) => items[i].id,
          onItemFocused: _focusedEpisode,
          cardBuilder: (context, i, node) {
            final item = items[i];
            final menu = _menus.putIfAbsent(item.id, () => GlobalKey<MediaContextMenuState>());
            return MediaContextMenu(
              key: menu,
              item: item,
              onRefresh: (_) => unawaited(c.refresh()),
              child: TvEpisode(
                item: item,
                client: c.client,
                focusNode: node,
                onSelect: () => unawaited(_play(item)),
                onLongPress: () {
                  final state = menu.currentState;
                  if (state != null) state.showContextMenu(state.context);
                },
              ),
            );
          },
        ),
        if (c.pageErrors.containsKey(key))
          Padding(
            padding: EdgeInsets.only(left: px(200)),
            child: TvButton(
              label: 'Retry episodes',
              onSelect: () async {
                await c.loadMoreEpisodes(key);
                if (mounted) await _enterSeason(focus: true);
              },
            ),
          ),
        SizedBox(height: px(54)),
      ],
    );
  }
}
