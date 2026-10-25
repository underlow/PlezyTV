import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../focus/dpad_navigator.dart';
import '../../../focus/key_event_utils.dart';
import '../../../i18n/strings.g.dart';
import '../../../media/media_item.dart';
import '../../../media/media_server_client.dart';
import '../../../utils/formatters.dart';
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
import '../tv_tokens.dart';
import '../tv_ui.dart';
import 'tv_postplay_controller.dart';
import 'tv_postplay_logic.dart';

/// Starts playback of [item] in place of the post-play route.
typedef TvPostPlayLaunch = Future<void> Function(BuildContext context, MediaItem item, {required bool fromStart});

/// Opens a detail page; [replace] swaps it in place of the post-play route.
typedef TvPostPlayOpenDetail = Future<void> Function(BuildContext context, MediaItem item, {required bool replace});

/// PlezyTV post-play screen (S14 R3–R9).
class TvPostPlayScreen extends StatefulWidget {
  const TvPostPlayScreen({super.key, required this.args, this.controller, this.launchPlayer, this.openDetail});

  final TvPostPlayArgs args;

  /// Borrowed controller for tests; otherwise built from the item's client.
  final TvPostPlayController? controller;

  /// Test adapters replacing Plezy navigation.
  final TvPostPlayLaunch? launchPlayer;
  final TvPostPlayOpenDetail? openDetail;

  @override
  State<TvPostPlayScreen> createState() => _TvPostPlayScreenState();
}

Future<void> _defaultLaunch(BuildContext context, MediaItem item, {required bool fromStart}) async {
  await navigateToVideoPlayer(
    context,
    metadata: item,
    usePushReplacement: true,
    resolveWatchState: !fromStart,
    initialPosition: fromStart ? Duration.zero : null,
  );
}

Future<void> _defaultOpenDetail(BuildContext context, MediaItem item, {required bool replace, String? seasonId}) async {
  final route = TvUi.showDetailRoute(metadata: item, initialSeasonId: seasonId);
  final navigator = Navigator.of(context);
  if (route == null) {
    await navigateToMediaItem(context, item);
  } else if (replace) {
    unawaited(navigator.pushReplacement(route));
  } else {
    unawaited(navigator.push(route));
  }
}

class _TvPostPlayScreenState extends State<TvPostPlayScreen> {
  late final TvPostPlayController _c;
  late final bool _ownsController;
  final _primary = FocusNode(debugLabel: 'Post-play primary');
  final _detail = FocusNode(debugLabel: 'Post-play detail');
  final _stars = FocusNode(debugLabel: 'Post-play stars');
  final _buttons = FocusScopeNode(debugLabel: 'Post-play buttons');
  final _row = GlobalKey<TvHorizontalRowState>();
  bool _queued = false, _keyPressed = false, _started = false;

  MediaItem get _watched => widget.args.watched;
  TvPostPlayVariant get _variant => _c.variant;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
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
    _c.onRateError = (_) {
      if (mounted) showErrorSnackBar(context, t.errors.failedToRate);
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
  /// once (spec §3).
  void _afterPlayer(Future<void> Function() action) {
    if (_queued) return;
    _queued = true;
    unawaited(
      widget.args.playerRemoved.then<void>((_) {}, onError: (Object _) {}).then((_) async {
        if (!mounted) return;
        try {
          await action();
        } finally {
          _queued = false;
        }
      }),
    );
  }

  void _launch(MediaItem item, {bool fromStart = false}) => _afterPlayer(() {
    final launch = widget.launchPlayer ?? _defaultLaunch;
    return launch(context, item, fromStart: fromStart);
  });

  void _openDetail(MediaItem item, {required bool replace, String? seasonId}) => _afterPlayer(() {
    final open = widget.openDetail;
    if (open != null) return open(context, item, replace: replace);
    return _defaultOpenDetail(context, item, replace: replace, seasonId: seasonId);
  });

  void _toSubject() =>
      _openDetail(_c.subject, replace: true, seasonId: _variant == TvPostPlayVariant.movie ? null : _watched.parentId);

  void _back() => _afterPlayer(() async {
    final route = ModalRoute.of(context);
    if (route?.isCurrent ?? false) Navigator.of(context).pop();
  });

  KeyEventResult _keys(FocusNode _, KeyEvent event) {
    if (event is KeyDownEvent) _keyPressed = true;
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
      if (!up) act(_buttons.requestFocus);
      return KeyEventResult.handled;
    }
    if (_buttons.hasFocus) {
      if (up && starsShown) act(_stars.requestFocus);
      if (!up && hasRow) act(() => _row.currentState?.requestFocus());
      return KeyEventResult.handled;
    }
    if (hasRow && (_row.currentContext != null) && FocusScope.of(_row.currentContext!).hasFocus && up) {
      act(_buttons.requestFocus);
      return KeyEventResult.handled;
    }
    return KeyEventResult.handled;
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
                  if (_c.loading) ...[
                    SizedBox(height: px(20)),
                    const TvRowSkeleton(key: ValueKey('postplay-ratings-skeleton'), count: 1, episode: true),
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
