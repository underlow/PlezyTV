import '../../../navigation/main_screen_scope.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../focus/key_event_utils.dart';
import '../../../i18n/strings.g.dart';
import '../../../media/media_item.dart';
import '../../../media/media_item_types.dart';
import '../../../providers/catalog_sources_provider.dart';
import '../../../services/device_performance.dart';
import '../../../services/settings_service.dart';
import '../../../services/watch_actions.dart';
import '../../../utils/content_utils.dart';
import '../../../utils/formatters.dart';
import '../../../utils/media_navigation_helper.dart';
import '../../../utils/media_quality_labels.dart';
import '../../../utils/provider_extensions.dart';
import '../../../utils/video_player_navigation.dart';
import '../../../widgets/media_context_menu.dart';
import '../../../widgets/optimized_media_image.dart';
import '../components/tv_button.dart';
import '../components/tv_cards.dart';
import '../components/tv_chip.dart';
import '../components/tv_horizontal_row.dart';
import '../components/tv_person_card.dart';
import '../components/tv_ratings.dart';
import '../components/tv_skeletons.dart';
import '../tv_card_registry.dart';
import '../tv_strings.dart';
import '../tv_theme.dart';
import '../tv_tint_service.dart';
import '../tv_tinted_background.dart';
import '../tv_tokens.dart';
import 'tv_movie_actions.dart';
import 'tv_movie_controller.dart';
import 'tv_movie_logic.dart';
import 'tv_movie_review_card.dart';
import 'tv_movie_reviews.dart';

/// PlezyTV movie page (S8). The route pops with `true` when watch state changed.
class TvMovieScreen extends StatefulWidget {
  const TvMovieScreen({
    super.key,
    required this.metadata,
    this.controller,
    this.launchPlayer,
    this.playVersion,
    this.markWatched,
    this.serverOnline,
    this.hideSpoilers,
  });
  final MediaItem metadata;

  /// Optional borrowed controller and adapters for isolated screen tests.
  final TvMovieController? controller;

  /// Test adapter replacing only Plezy's `navigateToVideoPlayer` call.
  final Future<bool?> Function(BuildContext, MediaItem, TvMoviePlayerLaunch)? launchPlayer;
  final Future<void> Function(BuildContext, MediaItem)? playVersion;
  final Future<WatchMarkOutcome> Function(MediaItem, bool)? markWatched;
  final bool Function(MediaItem)? serverOnline;
  final bool? hideSpoilers;

  @override
  State<TvMovieScreen> createState() => _TvMovieScreenState();
}

class _TvMovieScreenState extends State<TvMovieScreen> {
  TvMovieController? _controller;
  final _primary = FocusNode(debugLabel: 'Movie primary');
  final _actionScope = FocusScopeNode(debugLabel: 'Movie actions');
  final _page = ScrollController();
  final _rowKeys = <String, GlobalKey<TvHorizontalRowState>>{};
  final _menus = <String, GlobalKey<MediaContextMenuState>>{};
  List<GlobalKey<TvHorizontalRowState>> _rowOrder = [];
  Object? _connectionError, _reportedError;
  bool _closing = false, _unavailable = false, _collapsed = false, _playing = false;

  /// The player returned while another route covered this one (R10).
  bool _refreshOnReturn = false;

  /// Watch state before the launch, compared after the return refresh.
  String? _launchState;

  bool get _isTop => ModalRoute.of(context)?.isCurrent != false;
  double _collapseAt = TvTokens.detail.collapseAt.toDouble(), _barHeight = TvTokens.detail.compactH.toDouble();

  @override
  void initState() {
    super.initState();
    _page.addListener(_scrolled);
  }

  /// This card on its route, for the post-play screen above (S14 C5).
  Route<dynamic>? _cardRoute;
  TvCardEntry? _cardEntry;

  void _registerCard(TvCardEntry Function() entry) {
    final route = ModalRoute.of(context);
    if (route == _cardRoute) return;
    _unregisterCard();
    if (route == null) return;
    _cardRoute = route;
    TvCardRegistry.register(route, _cardEntry = entry());
  }

  void _unregisterCard() {
    final route = _cardRoute, entry = _cardEntry;
    if (route != null && entry != null) TvCardRegistry.unregister(route, entry);
    _cardRoute = null;
    _cardEntry = null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _registerCard(() => TvCardEntry(itemKey: widget.metadata.globalKey));
    final top = ModalRoute.of(context)?.isCurrent == true;
    if (_refreshOnReturn && top && !_playing) _returnedToTop();
    if (_controller == null && _connectionError == null) _connect();
    if (top) _rereadAfterRatingSave();
  }

  bool _awaitingRating = false;

  /// S14 R6, R10: a post-play rating save for this movie may still be running
  /// when the card shows; reread once it finishes, without blocking the card.
  void _rereadAfterRatingSave() {
    if (_awaitingRating || _controller == null) return;
    _awaitingRating =
        TvPendingRatings.whenSaved(
          widget.metadata.globalKey,
          isCurrent: () => mounted,
          reread: () {
            _awaitingRating = false;
            final c = _controller!;
            final before = _watchFingerprint(c.movie);
            unawaited(
              c.refresh().then((_) {
                if (mounted && _watchFingerprint(c.movie) != before) c.watchStateChanged = true;
              }),
            );
          },
        ) !=
        null;
  }

  void _connect() {
    try {
      _controller = widget.controller;
      if (_controller == null) {
        final client = context.getMediaClientForItemOrNull(widget.metadata);
        if (client == null) throw StateError('Server unavailable');
        _controller = TvMovieController(
          client: client,
          metadata: widget.metadata,
          catalogSources: context.read<CatalogSourcesProvider?>(),
        );
      }
      _controller!.addListener(_changed);
      unawaited(_controller!.load());
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_closing) _primary.requestFocus();
      });
    } catch (error) {
      _connectionError = error;
    }
  }

  void _scrolled() {
    final first = _rowOrder.firstOrNull?.currentContext?.findRenderObject();
    final threshold = first == null
        ? _collapseAt
        : math.min(_collapseAt, RenderAbstractViewport.of(first).getOffsetToReveal(first, 0).offset - _barHeight);
    final collapsed = _page.hasClients && _page.offset > 0 && _page.offset >= threshold - 0.5;
    if (collapsed != _collapsed) setState(() => _collapsed = collapsed);
  }

  bool _reviewsVisible = false, _preservingReviewInsertion = false, _reviewPanelOpen = false;

  void _changed() {
    if (!mounted) return;
    final c = _controller!;
    if (c.deleted && !_closing) {
      _closing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _close());
    }
    if (c.error != null && c.metadataLoaded && !c.loading && !identical(_reportedError, c.error)) {
      _reportedError = c.error;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Unable to refresh. Check your connection.')));
        }
      });
    }
    if (!_reviewsVisible && c.reviews.isNotEmpty && _page.hasClients) {
      final focused = _rowOrder.indexWhere(_focusIn);
      final cast = _rowOrder.indexOf(_rowKey('cast'));
      if (focused >= 0 && focused > cast) {
        final offset = _page.offset;
        _preservingReviewInsertion = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final render = _rowKey('reviews').currentContext?.findRenderObject();
          if (_page.hasClients && render is RenderBox) {
            _page.jumpTo(
              (offset + render.size.height + TvTheme.of(context).px(TvTokens.space.sectionGap)).clamp(
                0.0,
                _page.position.maxScrollExtent,
              ),
            );
          }
          // Adjacent rows restore their existing focus in post-frame callbacks.
          // Do not let those callbacks apply the normal reveal rule here.
          WidgetsBinding.instance.addPostFrameCallback((_) => _preservingReviewInsertion = false);
        });
      }
    }
    setState(() {});
  }

  /// Plezy behaviour for a missing/deleted item: close, or show "unavailable"
  /// when this is the first route.
  void _close() {
    if (!mounted) return;
    final route = ModalRoute.of(context);
    final result = _controller?.watchStateChanged ?? false;
    if (route == null || route.isFirst) {
      setState(() => _unavailable = true);
    } else if (!route.isActive) {
      // Already leaving for another reason.
      return;
    } else if (route.isCurrent) {
      Navigator.of(context).pop(result);
    } else {
      Navigator.of(context).removeRoute(route, result);
    }
  }

  void _pop() {
    if (_unavailable && ModalRoute.of(context)?.isFirst == true) return;
    Navigator.of(context).pop(_controller?.watchStateChanged ?? false);
  }

  bool _canUseScreen() => mounted && !(_controller?.deleted ?? false);

  /// First-route "unavailable" leaves Back to the system, as Plezy does when
  /// nothing can be popped.
  bool get _exitable => _unavailable && ModalRoute.of(context)?.isFirst != false;

  Future<void> _play() async {
    final c = _controller!;
    if (_playing) return;
    _playing = true;
    final launch = tvMoviePlayerLaunch(c.primaryAction);
    _launchState = _watchFingerprint(c.movie);
    try {
      final changed = widget.launchPlayer != null
          ? await widget.launchPlayer!(context, c.movie, launch)
          : await navigateToVideoPlayer(
              context,
              metadata: c.movie,
              resolveWatchState: launch.resolveWatchState,
              initialPosition: launch.initialPosition,
              isLaunchCurrent: _canUseScreen,
            );
      if (changed == true) c.watchStateChanged = true;
      if (mounted && !_isTop) _refreshOnReturn = true;
      if (mounted) await c.refresh();
    } finally {
      _playing = false;
    }
    // The covering route may have closed while this method was refreshing.
    if (mounted && _refreshOnReturn && _isTop) _returnedToTop();
  }

  /// Rereads watch state and rating after the player left this card covered
  /// (post-play screen), marking the route result when anything changed.
  void _returnedToTop() {
    _refreshOnReturn = false;
    final c = _controller;
    if (c == null) return;
    final before = _launchState ?? _watchFingerprint(c.movie);
    _launchState = null;
    unawaited(
      c.refresh().then((_) {
        if (mounted && _watchFingerprint(c.movie) != before) c.watchStateChanged = true;
      }),
    );
  }

  static String _watchFingerprint(MediaItem m) => '${m.viewCount}:${m.viewOffsetMs}:${m.userRating}';

  Future<void> _playVersion() async {
    final c = _controller!;
    if (widget.playVersion != null) {
      await widget.playVersion!(context, c.movie);
    } else {
      final started = await promptAndPlayVersion(context, c.movie);
      if (!started) return;
    }
    if (mounted) await c.refresh();
  }

  Future<void> _playExtra(MediaItem item) async {
    _launchState = _watchFingerprint(_controller!.movie);
    final changed = await navigateToVideoPlayer(context, metadata: item, isLaunchCurrent: _canUseScreen);
    if (!mounted) return;
    if (changed == true) _controller!.watchStateChanged = true;
    if (!_isTop) _refreshOnReturn = true;
    await _controller!.refresh();
  }

  Duration get _duration => Duration(milliseconds: DevicePerformance.isReduced ? 0 : 150);

  void _scrollTo(double offset) {
    if (!_page.hasClients) return;
    final target = offset.clamp(0.0, _page.position.maxScrollExtent);
    if ((target - _page.offset).abs() < 0.5) return;
    if (DevicePerformance.isReduced) {
      _page.jumpTo(target);
    } else {
      unawaited(_page.animateTo(target, duration: _duration, curve: Curves.easeOutCubic));
    }
  }

  /// Keeps the focused row fully visible under the compact title bar; any row
  /// focus scrolls the header away, the last row also reveals the tech block.
  void _revealRow(GlobalKey<TvHorizontalRowState> key) {
    if (_preservingReviewInsertion || _reviewPanelOpen) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _preservingReviewInsertion || _reviewPanelOpen || !_page.hasClients || _rowOrder.isEmpty) return;
      final render = key.currentContext?.findRenderObject();
      final first = _rowOrder.first.currentContext?.findRenderObject();
      if (render == null || first == null) return;
      final viewport = RenderAbstractViewport.of(render);
      final floor = viewport.getOffsetToReveal(first, 0).offset - _barHeight;
      final start = viewport.getOffsetToReveal(render, 0).offset - _barHeight;
      final end = key == _rowOrder.last ? _page.position.maxScrollExtent : viewport.getOffsetToReveal(render, 1).offset;
      final target = math.max(_page.offset.clamp(math.min(start, end), start).toDouble(), floor);
      _scrollTo(target);
    });
  }

  bool _focusIn(GlobalKey<TvHorizontalRowState> key) =>
      FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<TvHorizontalRow>()?.key == key;

  KeyEventResult _contentKeys(FocusNode node, KeyEvent event) {
    final down = event is KeyDownEvent || event is KeyRepeatEvent;
    if (_actionScope.hasFocus) {
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        if (down) {
          if (_rowOrder.isNotEmpty) {
            _rowOrder.first.currentState?.requestFocus();
          } else if (_page.hasClients) {
            // No rows: reveal what is below the buttons (tech block).
            _scrollTo(_page.position.maxScrollExtent);
          }
        }
        return KeyEventResult.handled;
      }
      // Genres and ratings are not focusable (R2); Up stays on the buttons.
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        if (down) _scrollTo(0);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    final up = event.logicalKey == LogicalKeyboardKey.arrowUp;
    if (!up && event.logicalKey != LogicalKeyboardKey.arrowDown) return KeyEventResult.ignored;
    final index = _rowOrder.indexWhere(_focusIn);
    if (index < 0) return KeyEventResult.ignored;
    if (down) {
      if (up && index == 0) {
        // The scope restores the last focused button.
        _actionScope.requestFocus();
        _scrollTo(0);
      } else {
        final next = index + (up ? -1 : 1);
        if (next < _rowOrder.length) _rowOrder[next].currentState?.requestFocus();
      }
    }
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    _unregisterCard();
    _controller?.removeListener(_changed);
    if (widget.controller == null) _controller?.dispose();
    _primary.dispose();
    _actionScope.dispose();
    _page.removeListener(_scrolled);
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TvTheme(child: Builder(builder: _build));

  String _metaLine(MediaItem movie) => [
    if (movie.year != null) '${movie.year}',
    if ((movie.durationMs ?? 0) > 0) formatDurationTextual(movie.durationMs!),
    if (formatContentRating(movie.contentRating).isNotEmpty) formatContentRating(movie.contentRating),
  ].join(' · ');

  Widget _build(BuildContext context) {
    final theme = TvTheme.of(context), px = theme.px;
    _collapseAt = px(TvTokens.detail.collapseAt);
    _barHeight = px(TvTokens.detail.compactH);
    final c = _controller;
    final movie = c?.movie ?? widget.metadata;
    return PopScope<bool>(
      canPop: _exitable,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _pop();
      },
      child: Scaffold(
        body: Focus(
          canRequestFocus: false,
          onKeyEvent: (_, event) => _exitable ? KeyEventResult.ignored : handleBackKeyAction(event, _pop),
          child: TvTintedBackground(
            scrollController: _page,
            source: TvArtworkSource(item: movie, client: c?.client),
            child: _connectionError != null || _unavailable
                ? _message(context, _unavailable ? TvStrings.movieUnavailable : TvStrings.noConnection)
                : Stack(
                    children: [
                      SingleChildScrollView(
                        controller: _page,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _header(context, c!),
                            Focus(
                              canRequestFocus: false,
                              onKeyEvent: _contentKeys,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: EdgeInsets.only(
                                      left:
                                          (px(TvTokens.space.contentLeft) -
                                                  MainScreenFocusScope.foregroundLeftOf(context))
                                              .clamp(0.0, double.infinity),
                                      right: px(96),
                                    ),
                                    child: FocusScope(node: _actionScope, child: _actions(context, c)),
                                  ),
                                  SizedBox(height: px(TvTokens.space.sectionGap)),
                                  ..._lowerRows(context, c),
                                ],
                              ),
                            ),
                            _techInfo(context, c),
                            SizedBox(height: px(54)),
                          ],
                        ),
                      ),
                      if (_collapsed) _compactBar(context, movie),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _message(BuildContext context, String text) {
    final theme = TvTheme.of(context), px = theme.px;
    return Padding(
      padding: EdgeInsets.only(
        left: (px(TvTokens.space.contentLeft) - MainScreenFocusScope.foregroundLeftOf(context)).clamp(
          0.0,
          double.infinity,
        ),
        top: px(200),
        right: px(96),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text, key: const ValueKey('movie-message'), style: theme.headline),
          if (!_unavailable) ...[
            SizedBox(height: px(24)),
            TvButton(
              label: TvStrings.retry,
              autofocus: true,
              onSelect: () => setState(() {
                _connectionError = null;
                _connect();
              }),
            ),
          ],
        ],
      ),
    );
  }

  Widget _compactBar(BuildContext context, MediaItem movie) {
    final theme = TvTheme.of(context), px = theme.px;
    final meta = _metaLine(movie);
    return Positioned(
      key: const ValueKey('movie-compact-header'),
      left: 0,
      right: 0,
      top: 0,
      height: _barHeight,
      child: DecoratedBox(
        decoration: BoxDecoration(color: TvTokens.color.bg.base),
        child: Padding(
          padding: EdgeInsets.only(
            left: (px(TvTokens.space.contentLeft) - MainScreenFocusScope.foregroundLeftOf(context)).clamp(
              0.0,
              double.infinity,
            ),
            top: px(48),
            right: px(96),
          ),
          child: Align(
            alignment: Alignment.topLeft,
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: movie.displayTitle, style: theme.headline),
                  if (meta.isNotEmpty)
                    TextSpan(
                      text: '   $meta',
                      style: theme.body.copyWith(color: TvTokens.color.text.secondary),
                    ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context, TvMovieController c) {
    final theme = TvTheme.of(context), px = theme.px;
    final movie = c.movie;
    final meta = _metaLine(movie);
    final genres = movie.genres?.where((g) => g.trim().isNotEmpty).toList() ?? const <String>[];
    final director = c.director;
    final ratings = c.ratings;
    final chips = c.metadataLoaded ? buildMediaQualityLabels(movie, versionIndex: c.versionIndex) : const <String>[];
    final hide = widget.hideSpoilers ?? SettingsService.instanceOrNull?.read(SettingsService.hideSpoilers) ?? false;
    final summary = hide && movie.shouldHideSpoiler ? null : movie.summary?.trim();
    final edition = movie.editionTitle?.trim();
    final parts = <(double, Widget)>[
      (
        0,
        ClearLogoImage(
          client: c.client,
          logoPath: movie.clearLogoPath,
          fallbackWidth: px(TvTokens.detail.textMaxW),
          width: px(560),
          height: px(120),
          alignment: Alignment.centerLeft,
          fallbackBuilder: (_) =>
              Text(movie.displayTitle, style: theme.display, maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
      ),
      if (meta.isNotEmpty || genres.isNotEmpty)
        (
          TvTokens.detail.metadataGap.toDouble(),
          Text(
            [if (meta.isNotEmpty) meta, ...genres].join(' · '),
            key: const ValueKey('movie-meta'),
            style: theme.body,
          ),
        ),
      if (director != null) (TvTokens.detail.metadataGap.toDouble(), Text(director, style: theme.body)),
      if (edition != null && edition.isNotEmpty)
        (
          TvTokens.detail.metadataGap.toDouble(),
          Text(
            edition.toUpperCase(),
            key: const ValueKey('movie-edition'),
            style: theme.title.copyWith(color: TvTokens.color.text.secondary, letterSpacing: px(3)),
          ),
        ),
      if (ratings.isNotEmpty)
        (TvTokens.detail.metadataGap.toDouble(), TvRatings(item: movie.copyWith(ratings: ratings))),
      if (chips.isNotEmpty)
        (
          TvTokens.detail.summaryGap.toDouble(),
          Wrap(
            key: const ValueKey('movie-chips'),
            spacing: px(16),
            runSpacing: px(12),
            children: [for (final label in chips) TvChip.technical(label: label)],
          ),
        ),
      if (summary != null && summary.isNotEmpty)
        (
          TvTokens.detail.summaryGap.toDouble(),
          SizedBox(
            width: px(TvTokens.detail.textMaxW),
            child: Text(
              summary,
              key: const ValueKey('movie-summary'),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: theme.bodyLarge,
            ),
          ),
        ),
    ];
    return Padding(
      padding: EdgeInsets.only(
        left: (px(TvTokens.space.contentLeft) - MainScreenFocusScope.foregroundLeftOf(context)).clamp(
          0.0,
          double.infinity,
        ),
        top: px(TvTokens.space.safeY),
        right: px(96),
        bottom: px(TvTokens.detail.actionsGap),
      ),
      child: SizedBox(
        width: px(TvTokens.detail.textMaxW),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (gap, child) in parts) ...[if (gap > 0) SizedBox(height: px(gap)), child],
          ],
        ),
      ),
    );
  }

  Widget _actions(BuildContext context, TvMovieController c) {
    final action = c.primaryAction;
    return TvMovieActions(
      controller: c,
      playExtra: _playExtra,
      playVersion: _playVersion,
      markWatched: widget.markWatched,
      serverOnline: widget.serverOnline,
      primary: TvButton(
        label: action.label,
        icon: Icons.play_arrow,
        focusNode: _primary,
        onSelect: () => unawaited(_play()),
      ),
    );
  }

  Future<void> _openReview(BuildContext context, TvMovieReview review, FocusNode anchor) async {
    final offset = _page.hasClients ? _page.offset : 0.0;
    _reviewPanelOpen = true;
    try {
      await TvMovieReviewCard.showPanel(context, review, anchor);
    } finally {
      // Restoring the anchor is not row navigation. In particular, rows that
      // loaded behind the panel must not change the invoking card's position.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_page.hasClients) _page.jumpTo(offset.clamp(0.0, _page.position.maxScrollExtent));
        _reviewPanelOpen = false;
      });
    }
  }

  GlobalKey<TvHorizontalRowState> _rowKey(String id) =>
      _rowKeys.putIfAbsent(id, () => GlobalKey<TvHorizontalRowState>());

  List<Widget> _lowerRows(BuildContext context, TvMovieController c) {
    final px = TvTheme.of(context).px;
    if (!c.metadataLoaded && c.error == null) {
      _rowOrder = [];
      return [
        Padding(
          padding: EdgeInsets.only(
            left: (px(TvTokens.space.contentLeft) - MainScreenFocusScope.foregroundLeftOf(context)).clamp(
              0.0,
              double.infinity,
            ),
          ),
          child: const TvRowSkeleton(key: ValueKey('movie-rows-skeleton')),
        ),
      ];
    }
    final movie = c.movie;
    final roles = movie.roles ?? [];
    final hubs = c.relatedHubs.where((h) => h.items.isNotEmpty).toList();
    _reviewsVisible = c.reviews.isNotEmpty;
    final rows = <Widget>[
      if (roles.isNotEmpty)
        Builder(
          builder: (context) {
            final key = _rowKey('cast');
            return TvHorizontalRow(
              key: key,
              title: t.discover.cast,
              itemCount: roles.length,
              cardWidth: 200,
              cardHeight: tvCardHeight(context, TvPersonCard.photoSize),
              itemKey: (i) => '${roles[i].id}/${roles[i].tag}',
              onItemFocused: (_) => _revealRow(key),
              cardBuilder: (context, i, node) {
                final role = roles[i];
                return TvPersonCard(
                  client: c.client,
                  imagePath: role.thumbPath,
                  name: role.tag,
                  caption: role.role,
                  focusNode: node,
                  onSelect: role.id == null || movie.serverId == null
                      ? null
                      : () => unawaited(
                          navigateToPersonMedia(
                            context,
                            personId: role.id!,
                            name: role.tag,
                            thumbPath: role.thumbPath,
                            characterName: role.role,
                            serverId: movie.serverId!,
                            serverName: movie.serverName,
                            backend: movie.backend,
                          ),
                        ),
                );
              },
            );
          },
        ),
      if (c.reviews.isNotEmpty)
        TvHorizontalRow(
          key: _rowKey('reviews'),
          title: TvStrings.reviews,
          itemCount: c.reviews.length,
          cardWidth: 512,
          cardHeight: 256,
          onItemFocused: (_) => _revealRow(_rowKey('reviews')),
          cardBuilder: (context, i, node) => TvMovieReviewCard(
            review: c.reviews[i],
            focusNode: node,
            onSelect: () => unawaited(_openReview(context, c.reviews[i], node)),
          ),
        ),
      if (c.extras.isNotEmpty)
        Builder(
          builder: (context) {
            final key = _rowKey('extras');
            return TvHorizontalRow(
              key: key,
              title: t.discover.extras,
              itemCount: c.extras.length,
              cardWidth: 400,
              cardHeight: tvCardHeight(context, TvTokens.size.episode.h),
              itemKey: (i) => c.extras[i].globalKey,
              onItemFocused: (_) => _revealRow(key),
              cardBuilder: (context, i, node) => TvEpisode(
                item: c.extras[i],
                client: c.client,
                focusNode: node,
                onSelect: () => unawaited(_playExtra(c.extras[i])),
              ),
            );
          },
        ),
      for (final hub in hubs)
        Builder(
          builder: (context) {
            final key = _rowKey('related/${hub.id}');
            return TvHorizontalRow(
              key: key,
              title: hub.title.isEmpty ? t.discover.moreLikeThis : hub.title,
              itemCount: hub.items.length,
              cardWidth: 216,
              cardHeight: tvCardHeight(context, TvTokens.size.poster.h),
              itemKey: (i) => hub.items[i].globalKey,
              onItemFocused: (_) => _revealRow(key),
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
                    onSelect: () =>
                        unawaited(navigateToMediaItem(context, item, onRefresh: (_) => unawaited(c.refresh()))),
                    onLongPress: () {
                      final state = menu.currentState;
                      if (state != null) state.showContextMenu(state.context);
                    },
                  ),
                );
              },
            );
          },
        ),
    ];
    // Row order for Down/Up between the buttons and the first row.
    _rowOrder = [
      if (roles.isNotEmpty) _rowKey('cast'),
      if (c.reviews.isNotEmpty) _rowKey('reviews'),
      if (c.extras.isNotEmpty) _rowKey('extras'),
      for (final hub in hubs) _rowKey('related/${hub.id}'),
    ];
    return [
      for (var i = 0; i < rows.length; i++) ...[if (i > 0) SizedBox(height: px(TvTokens.space.sectionGap)), rows[i]],
    ];
  }

  Widget _techInfo(BuildContext context, TvMovieController c) {
    final lines = c.metadataLoaded ? c.techInfo : const [];
    if (lines.isEmpty) return const SizedBox.shrink();
    final theme = TvTheme.of(context), px = theme.px;
    return Padding(
      key: const ValueKey('movie-tech-info'),
      padding: EdgeInsets.only(
        left: (px(TvTokens.space.contentLeft) - MainScreenFocusScope.foregroundLeftOf(context)).clamp(
          0.0,
          double.infinity,
        ),
        top: px(8),
        right: px(96),
      ),
      child: Wrap(
        spacing: px(64),
        runSpacing: px(24),
        children: [
          for (final line in lines)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(line.label, style: theme.caption.copyWith(color: TvTokens.color.text.tertiary)),
                SizedBox(height: px(8)),
                Text(line.value, style: theme.body),
              ],
            ),
        ],
      ),
    );
  }
}
