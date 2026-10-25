import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../focus/dpad_navigator.dart';
import '../../../focus/key_event_utils.dart';
import '../../../i18n/strings.g.dart';
import '../../../media/media_item.dart';
import '../../../media/media_server_client.dart';
import '../../../utils/app_logger.dart';
import '../../../utils/formatters.dart';
import '../../../utils/layout_constants.dart';
import '../../../utils/media_navigation_helper.dart';
import '../../../utils/provider_extensions.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../utils/video_player_navigation.dart';
import '../../../widgets/optimized_media_image.dart';
import '../components/tv_button.dart';
import '../components/tv_cards.dart';
import '../components/tv_horizontal_row.dart';
import '../components/tv_rating_stars.dart';
import '../components/tv_ratings.dart';
import '../components/tv_skeletons.dart';
import '../tv_theme.dart';
import '../tv_card_registry.dart';
import '../tv_tokens.dart';
import '../tv_ui.dart';
import 'tv_postplay_controller.dart';
import 'tv_postplay_logic.dart';

/// Plezy's `navigateToVideoPlayer`, narrowed to the arguments post-play sets.
typedef TvPostPlayLaunch =
    Future<void> Function(
      BuildContext context, {
      required MediaItem metadata,
      required bool usePushReplacement,
      required bool resolveWatchState,
      Duration? initialPosition,
    });

/// `TvUi.showDetailRoute`, narrowed to the arguments post-play sets.
typedef TvPostPlayDetailRoute = PageRoute<dynamic>? Function({required MediaItem metadata, String? initialSeasonId});

/// PlezyTV post-play screen (S14 R3–R9).
class TvPostPlayScreen extends StatefulWidget {
  const TvPostPlayScreen({super.key, required this.args, this.controller, this.launchPlayer, this.detailRoute});

  final TvPostPlayArgs args;

  /// Borrowed controller for tests; otherwise built from the item's client.
  final TvPostPlayController? controller;

  /// Test adapters at the Plezy / TV navigation boundary.
  final TvPostPlayLaunch? launchPlayer;
  final TvPostPlayDetailRoute? detailRoute;

  @override
  State<TvPostPlayScreen> createState() => _TvPostPlayScreenState();
}

Future<void> _plezyLaunch(
  BuildContext context, {
  required MediaItem metadata,
  required bool usePushReplacement,
  required bool resolveWatchState,
  Duration? initialPosition,
}) => navigateToVideoPlayer(
  context,
  metadata: metadata,
  usePushReplacement: usePushReplacement,
  resolveWatchState: resolveWatchState,
  initialPosition: initialPosition,
);

PageRoute<dynamic>? _tvDetailRoute({required MediaItem metadata, String? initialSeasonId}) =>
    TvUi.showDetailRoute(metadata: metadata, initialSeasonId: initialSeasonId);

class _TvPostPlayScreenState extends State<TvPostPlayScreen> {
  late final TvPostPlayController _c;
  late final bool _ownsController;
  final _primary = FocusNode(debugLabel: 'Post-play primary');
  final _detail = FocusNode(debugLabel: 'Post-play detail');
  final _stars = FocusNode(debugLabel: 'Post-play stars');
  final _buttons = FocusScopeNode(debugLabel: 'Post-play buttons');
  final _row = GlobalKey<TvHorizontalRowState>();
  bool _queued = false, _keyPressed = false, _started = false;

  /// Any key-down while the screen is up, whoever handles it (R9 exception).
  bool _onAnyKey(KeyEvent event) {
    if (event is KeyDownEvent) _keyPressed = true;
    return false;
  }

  MediaItem get _watched => widget.args.watched;
  TvPostPlayVariant get _variant => _c.variant;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    HardwareKeyboard.instance.addHandler(_onAnyKey);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (_ownsController) {
      MediaServerClient? client;
      try {
        client = context.getMediaClientForItemOrNull(_watched);
      } catch (_) {
        client = null;
      }
      _c = TvPostPlayController(client: client, watched: _watched, next: widget.args.next);
    } else {
      _c = widget.controller!;
    }
    _c.onRateError = (error) {
      // Once leaving has started the save is retried silently (R6); Plezy's
      // messenger would show the message over the next screen.
      if (mounted && !_queued && (ModalRoute.isCurrentOf(context) ?? true)) {
        showErrorSnackBar(context, t.errors.failedToRate);
      } else {
        appLogger.w('Post-play rating save failed while leaving', error: error);
      }
    };
    _c.addListener(_changed);
    if (_ownsController) unawaited(_c.load());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _entryFocus().requestFocus();
    });
  }

  /// Chosen from player data (R4, R5, R9).
  FocusNode _entryFocus() {
    if (_variant == TvPostPlayVariant.episode) return _primary;
    return _c.showsRating && _c.rating == 0 ? _stars : _detail;
  }

  bool _starsShown = false;

  void _changed() {
    if (!mounted) return;
    final wasShown = _starsShown;
    final starsFocused = _stars.hasFocus;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (starsFocused && !_c.showsRating) {
        // Ratings hidden after a failed load: keep focus on the screen.
        _detail.requestFocus();
      } else if (!wasShown &&
          _c.showsRating &&
          !_keyPressed &&
          _variant == TvPostPlayVariant.showEnded &&
          _c.rating == 0 &&
          _detail.hasFocus) {
        // The series' own rating is only known after it loads.
        _stars.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onAnyKey);
    _c.removeListener(_changed);
    _c.onRateError = null;
    if (_ownsController) _c.dispose();
    _primary.dispose();
    _detail.dispose();
    _stars.dispose();
    _buttons.dispose();
    super.dispose();
  }

  /// Route-changing actions wait until Plezy removed the old player, then run
  /// once (spec §3). They do not wait for the rating: the press starts its
  /// save in the background and the card of the item rereads when it
  /// finishes (R6, R10); from the press on, a failed save shows no message.
  void _afterPlayer(Future<void> Function() action) {
    if (_queued) return;
    _queued = true;
    unawaited(_c.leave());
    unawaited(() async {
      try {
        await widget.args.playerRemoved.then<void>((_) {}, onError: (Object _) {});
        if (!mounted) return;
        await action();
      } finally {
        _queued = false;
      }
    }());
  }

  void _launch(MediaItem item, {bool fromStart = false}) => _afterPlayer(() {
    final launch = widget.launchPlayer ?? _plezyLaunch;
    return launch(
      context,
      metadata: item,
      usePushReplacement: true,
      resolveWatchState: !fromStart,
      initialPosition: fromStart ? Duration.zero : null,
    );
  });

  /// [replace] swaps the card in place of this screen; otherwise it opens
  /// over it.
  Future<void> _showDetail(MediaItem item, {required bool replace, String? seasonId}) async {
    final route = (widget.detailRoute ?? _tvDetailRoute)(metadata: item, initialSeasonId: seasonId);
    final navigator = Navigator.of(context);
    if (route == null) {
      await navigateToMediaItem(context, item);
    } else if (replace) {
      unawaited(navigator.pushReplacement(route));
    } else {
      unawaited(navigator.push(route));
    }
  }

  void _openDetail(MediaItem item, {required bool replace}) => _afterPlayer(() => _showDetail(item, replace: replace));

  /// R8, C5: returns to this item's card when it is right underneath (checked
  /// once the player is gone), otherwise replaces this screen with the card.
  void _toSubject() {
    final seasonId = _variant == TvPostPlayVariant.movie ? null : _watched.parentId;
    _afterPlayer(() async {
      final route = ModalRoute.of(context);
      final below = route is TvPostPlayRoute ? TvCardRegistry.of(route.previous) : null;
      if (below != null && route!.isCurrent && below.itemKey == _c.subject.globalKey) {
        if (seasonId != null) below.showSeason?.call(seasonId);
        Navigator.of(context).pop();
        return;
      }
      return _showDetail(_c.subject, replace: true, seasonId: seasonId);
    });
  }

  void _back() => _afterPlayer(() async {
    final route = ModalRoute.of(context);
    if (route?.isCurrent ?? false) Navigator.of(context).pop();
  });

  KeyEventResult _keys(FocusNode _, KeyEvent event) {
    final key = event.logicalKey;
    if (key.isBackKey) return handleBackKeyAction(event, _back);
    if (key == LogicalKeyboardKey.mediaPlayPause || key == LogicalKeyboardKey.mediaPlay) {
      if (event is KeyDownEvent && _variant == TvPostPlayVariant.episode) _launch(widget.args.next!);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Up/Down between the stars, the buttons and the row.
  KeyEventResult _verticalKeys(FocusNode _, KeyEvent event) {
    final up = event.logicalKey == LogicalKeyboardKey.arrowUp;
    if (!up && event.logicalKey != LogicalKeyboardKey.arrowDown) return KeyEventResult.ignored;
    final down = event is KeyDownEvent || event is KeyRepeatEvent;
    final hasRow = _row.currentState != null;
    final starsShown = _c.showsRating;
    void act(VoidCallback f) {
      if (down) f();
    }

    if (_stars.hasFocus) {
      if (!up) act(_focusButtons);
      return KeyEventResult.handled;
    }
    if (_buttons.hasFocus) {
      if (up && starsShown) act(_stars.requestFocus);
      if (!up && hasRow) act(() => _row.currentState?.requestFocus());
      return KeyEventResult.handled;
    }
    if (up && (_row.currentState?.focusInside.value ?? false)) act(_focusButtons);
    return KeyEventResult.handled;
  }

  /// The button last focused in the row, else the variant's main button: the
  /// scope alone would take focus itself with no button highlighted.
  void _focusButtons() {
    if (_buttons.focusedChild != null) {
      _buttons.requestFocus();
    } else {
      (_variant == TvPostPlayVariant.episode ? _primary : _detail).requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) => TvTheme(child: Builder(builder: _build));

  Widget _build(BuildContext context) {
    final px = TvTheme.of(context).px;
    _starsShown = _c.showsRating;
    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // The rest of the press that opened this screen must not close it.
        if (BackKeyCoordinator.consumeIfHandled()) return;
        _back();
      },
      child: Scaffold(
        backgroundColor: TvTokens.color.bg.base,
        body: Focus(
          canRequestFocus: false,
          onKeyEvent: _keys,
          child: Focus(
            canRequestFocus: false,
            onKeyEvent: _verticalKeys,
            child: SingleChildScrollView(
              padding: EdgeInsets.only(left: px(96), top: px(54), bottom: px(54)),
              child: _variant == TvPostPlayVariant.episode ? _episodeLayout(context) : _subjectLayout(context),
            ),
          ),
        ),
      ),
    );
  }

  TextStyle _overline(BuildContext context) {
    final theme = TvTheme.of(context);
    return theme.label.copyWith(color: TvTokens.color.text.tertiary, letterSpacing: theme.px(2));
  }

  Widget _buttonRow(BuildContext context, List<Widget> buttons) {
    final px = TvTheme.of(context).px;
    return FocusScope(
      node: _buttons,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < buttons.length; i++) ...[if (i > 0) SizedBox(width: px(24)), buttons[i]],
        ],
      ),
    );
  }

  Widget _episodeLayout(BuildContext context) {
    final theme = TvTheme.of(context), px = theme.px;
    final next = widget.args.next!;
    final meta = [
      if (next.grandparentTitle?.trim().isNotEmpty ?? false) next.grandparentTitle!.trim(),
      if ((next.durationMs ?? 0) > 0) formatDurationTextual(next.durationMs!),
      if (next.year != null) '${next.year}',
    ].join(' · ');
    final summary = next.summary?.trim();
    final postplay = TvTokens.player.postplay;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          TvPostPlayStrings.youWatchedEpisode(_watched).toUpperCase(),
          key: const ValueKey('postplay-watched'),
          style: _overline(context),
        ),
        SizedBox(height: px(24)),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(px(TvTokens.radius.card)),
              child: OptimizedMediaImage(
                client: _c.client,
                imagePath: next.thumbPath,
                width: px(postplay.stillW),
                height: px(postplay.stillH),
                fit: BoxFit.cover,
                fallbackIcon: Icons.movie,
              ),
            ),
            SizedBox(width: px(48)),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: px(96)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      TvPostPlayStrings.upNext.toUpperCase(),
                      style: theme.label.copyWith(color: TvTokens.color.accent.normal, letterSpacing: px(2)),
                    ),
                    SizedBox(height: px(8)),
                    Text(
                      tvPostPlayEpisodeLabel(next),
                      key: const ValueKey('postplay-next-title'),
                      style: theme.headline,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (meta.isNotEmpty) ...[
                      SizedBox(height: px(12)),
                      Text(meta, style: theme.body.copyWith(color: TvTokens.color.text.secondary)),
                    ],
                    if (summary != null && summary.isNotEmpty) ...[
                      SizedBox(height: px(16)),
                      Text(summary, maxLines: 3, overflow: TextOverflow.ellipsis, style: theme.bodyLarge),
                    ],
                    SizedBox(height: px(32)),
                    _buttonRow(context, [
                      TvButton(
                        label: TvPostPlayStrings.watchEpisode(next),
                        icon: Icons.play_arrow,
                        focusNode: _primary,
                        onSelect: () => _launch(next),
                      ),
                      TvButton(
                        label: TvPostPlayStrings.toShow,
                        variant: TvButtonVariant.secondary,
                        focusNode: _detail,
                        onSelect: _toSubject,
                      ),
                    ]),
                  ],
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: px(64)),
        _seasonRow(context, next),
      ],
    );
  }

  Widget _seasonRow(BuildContext context, MediaItem next) {
    if (_c.loading) return const TvRowSkeleton(key: ValueKey('postplay-row-skeleton'), episode: true);
    final episodes = _c.seasonRest;
    if (_c.failed || episodes.isEmpty) return const SizedBox.shrink();
    return TvHorizontalRow(
      key: _row,
      contentLeft: 0,
      title: TvPostPlayStrings.season(next.parentIndex),
      counter: TvPostPlayStrings.moreEpisodes(episodes.length),
      itemCount: episodes.length,
      cardWidth: 400,
      cardHeight: 315,
      itemKey: (i) => episodes[i].globalKey,
      cardBuilder: (context, i, node) =>
          TvEpisode(item: episodes[i], client: _c.client, focusNode: node, onSelect: () => _launch(episodes[i])),
    );
  }

  Widget _subjectLayout(BuildContext context) {
    final theme = TvTheme.of(context), px = theme.px;
    final movie = _variant == TvPostPlayVariant.movie;
    final subject = _c.subject;
    final title = movie ? (subject.title ?? _watched.title ?? '') : (subject.title ?? _watched.grandparentTitle ?? '');
    final watchedMark = movie && subject.isWatched && _c.subjectLoaded;
    final ratingsItem = _c.subjectLoaded && !_c.failed ? subject : null;
    final poster = TvPosterSize.row.dimensions;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(px(TvTokens.radius.card)),
                  child: OptimizedMediaImage(
                    client: _c.client,
                    imagePath: subject.thumbPath,
                    width: px(poster.width),
                    height: px(poster.width * 1.5),
                    fit: BoxFit.cover,
                    fallbackIcon: Icons.movie,
                  ),
                ),
                if (watchedMark)
                  Positioned(
                    key: const ValueKey('postplay-watched-badge'),
                    top: px(8),
                    right: px(8),
                    child: Container(
                      padding: EdgeInsets.all(px(2)),
                      decoration: BoxDecoration(
                        color: TvTokens.color.status.watched,
                        borderRadius: BorderRadius.circular(px(6)),
                      ),
                      child: Icon(Icons.check, size: px(28), color: Colors.black),
                    ),
                  ),
              ],
            ),
            SizedBox(width: px(48)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(TvPostPlayStrings.youWatched.toUpperCase(), style: _overline(context)),
                  SizedBox(height: px(8)),
                  Text(
                    title,
                    key: const ValueKey('postplay-title'),
                    style: theme.headline,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (watchedMark) ...[
                    SizedBox(height: px(12)),
                    Row(
                      key: const ValueKey('postplay-marked-watched'),
                      children: [
                        Icon(Icons.check, size: px(28), color: TvTokens.color.status.watched),
                        SizedBox(width: px(12)),
                        Text(
                          TvPostPlayStrings.markedWatched(subject.durationMs),
                          style: theme.body.copyWith(color: TvTokens.color.text.secondary),
                        ),
                      ],
                    ),
                  ],
                  if (_c.subjectLoading) ...[
                    SizedBox(height: px(20)),
                    TvLineSkeleton(
                      key: const ValueKey('postplay-ratings-skeleton'),
                      width: 360,
                      height: TvTokens.type.body.lineHeight.toDouble(),
                    ),
                  ] else if (ratingsItem != null) ...[
                    SizedBox(height: px(20)),
                    TvRatings(item: ratingsItem),
                  ],
                  if (_c.showsRating) ...[
                    SizedBox(height: px(28)),
                    Text(TvPostPlayStrings.yourRating, style: theme.body),
                    SizedBox(height: px(12)),
                    TvRatingStars(
                      key: const ValueKey('postplay-stars'),
                      value: _c.rating,
                      focusNode: _stars,
                      semanticLabel: TvPostPlayStrings.yourRating,
                      onChanged: _c.setRating,
                      onSubmit: (_) => unawaited(_c.submit()),
                    ),
                  ],
                  SizedBox(height: px(32)),
                  _buttonRow(context, [
                    TvButton(
                      label: movie ? TvPostPlayStrings.backToMovie : TvPostPlayStrings.toShow,
                      variant: TvButtonVariant.secondary,
                      focusNode: _detail,
                      onSelect: _toSubject,
                    ),
                    if (movie)
                      TvButton(
                        label: TvPostPlayStrings.watchAgain,
                        icon: Icons.play_arrow,
                        variant: TvButtonVariant.secondary,
                        focusNode: _primary,
                        onSelect: () => _launch(_c.subject, fromStart: true),
                      ),
                  ]),
                ],
              ),
            ),
          ],
        ),
        SizedBox(height: px(64)),
        _similarRow(context),
      ],
    );
  }

  Widget _similarRow(BuildContext context) {
    if (_c.loading) return const TvRowSkeleton(key: ValueKey('postplay-row-skeleton'));
    final hub = _c.similar;
    if (_c.failed || hub == null) return const SizedBox.shrink();
    return TvHorizontalRow(
      key: _row,
      contentLeft: 0,
      title: TvPostPlayStrings.similar,
      itemCount: hub.items.length,
      cardWidth: 216,
      cardHeight: 414,
      itemKey: (i) => hub.items[i].globalKey,
      cardBuilder: (context, i, node) => TvPoster(
        item: hub.items[i],
        client: _c.client,
        focusNode: node,
        onSelect: () => _openDetail(hub.items[i], replace: false),
      ),
    );
  }
}

/// The post-play route; tracks the route directly underneath it (S14 C5).
///
/// It appears at once, like `VideoPlayerRoute`: a route is painted see-through
/// while its entrance runs, and Plezy may remove the player under it within a
/// frame, which would show the screen below through a fade (R2). Leaving
/// fades out to the destination.
class TvPostPlayRoute extends PageRouteBuilder<void> {
  TvPostPlayRoute({required WidgetBuilder builder})
    : super(
        opaque: true,
        pageBuilder: (context, _, _) => builder(context),
        transitionsBuilder: (_, animation, _, child) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic),
          child: child,
        ),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: AppDurations.animMedium,
      );

  /// The route right below; the player until Plezy removes it.
  Route<dynamic>? get previous => _previous;
  Route<dynamic>? _previous;

  @override
  void didChangePrevious(Route<dynamic>? previousRoute) {
    _previous = previousRoute;
    super.didChangePrevious(previousRoute);
  }
}
