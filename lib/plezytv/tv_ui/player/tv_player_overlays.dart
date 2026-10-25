import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../i18n/strings.g.dart';
import '../../../media/ids.dart';
import '../../../media/media_item.dart';
import '../../../media/media_item_types.dart';
import '../../../media/media_source_info.dart';
import '../../../mpv/mpv.dart';
import '../../../screens/video_player/widgets/player_prompt_overlays.dart';
import '../../../services/download_artwork_service.dart';
import '../../../services/download_storage_service.dart';
import '../../../services/pip_service.dart';
import '../../../services/settings_service.dart';
import '../../../utils/formatters.dart';
import '../../../utils/platform_detector.dart';
import '../../../utils/provider_extensions.dart';
import '../../../widgets/app_icon.dart';
import '../../../widgets/optimized_media_image.dart';
import '../../../widgets/settings_builder.dart';
import '../../../widgets/video_controls/player_chrome_controller.dart';
import '../../../widgets/video_controls/video_controls.dart'
    show PlayerNavigationKey, PlexVideoControls, classifyPlayerNavigationKey, handlePlayerNavigationKeyAction;
import '../../../widgets/video_controls/widgets/skip_marker_button.dart';
import '../components/tv_button.dart';
import '../tv_focusable.dart';
import '../tv_strings.dart';
import '../tv_theme.dart';
import '../tv_tokens.dart';
import 'tv_player_hooks.dart';
import 'tv_player_session.dart';

// ---- H2: skip intro / credits (R17) ----

/// The skip-marker button in the TV style (H2, R17, `10-player-skip-intro`).
///
/// When and whether it shows, auto-skip and OK stay Plezy's
/// ([SkipMarkerButton]). This widget draws it, lifts it above the panel's
/// icons while the panel is up (D3), hides it while the right panel is open,
/// moves ↓ to the icons, and on Back with the panel up hides it for the rest
/// of that showing (Plezy's own dismissal only acts with the chrome down).
class TvSkipButton extends StatefulWidget {
  const TvSkipButton({super.key, required this.plezy, required this.player, required this.chromeController});

  final SkipMarkerButton plezy;
  final Player player;
  final PlayerChromeController chromeController;

  /// The H2 builder: null (Plezy's button) outside `PlexVideoControls`.
  static Widget? build(BuildContext context, SkipMarkerButton plezy) {
    final controls = context.findAncestorWidgetOfExactType<PlexVideoControls>();
    if (controls == null) return null;
    return TvSkipButton(plezy: plezy, player: controls.player, chromeController: controls.chromeController);
  }

  @override
  State<TvSkipButton> createState() => _TvSkipButtonState();
}

class _TvSkipButtonState extends State<TvSkipButton> {
  /// The marker hidden by Back while the panel was up; cleared when the panel
  /// hides (Plezy then dismisses the button itself) or the marker changes.
  MediaMarker? _dismissed;

  /// Back pressed here with the panel up: the release must land here too.
  bool _backOwned = false;

  TvPlayerSession get _session => TvPlayerSession.of(widget.player);
  PlayerChromeController get _chrome => widget.chromeController;

  // Where Plezy places the button (video_controls.dart, the skip button's
  // AnimatedPositioned on a non-mobile layout): right 24 and these bottoms.
  static const _plezyRight = 24.0;
  static const _plezyBottomHidden = 24.0;
  static const _plezyBottomShown = 115.0;
  static const _plezyBottomStrip = 180.0;

  // Design positions (1920 × 1080): right edge on the icons' right edge,
  // 24 above the icons (y = 840, and 400 higher over the queue row).
  static const _right = 96;
  static const _bottomHidden = 54;
  static const _bottomShown = 1080 - 840 + 24;
  static const _bottomOverQueue = _bottomShown + 400;

  @override
  void initState() {
    super.initState();
    _chrome.addListener(_onChrome);
  }

  @override
  void didUpdateWidget(TvSkipButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.chromeController != widget.chromeController) {
      oldWidget.chromeController.removeListener(_onChrome);
      widget.chromeController.addListener(_onChrome);
    }
    if (_dismissed != null && !_sameMarker(_dismissed!, widget.plezy.marker)) _dismissed = null;
  }

  @override
  void dispose() {
    _chrome.removeListener(_onChrome);
    super.dispose();
  }

  static bool _sameMarker(MediaMarker a, MediaMarker b) =>
      a.type == b.type && a.startTimeOffset == b.startTimeOffset && a.endTimeOffset == b.endTimeOffset;

  void _onChrome() {
    if (!_chrome.controlsVisible && _dismissed != null && mounted) setState(() => _dismissed = null);
  }

  FocusNode? get _icons {
    final node = _session.iconsFocusNode;
    return node != null && (node.context?.mounted ?? false) ? node : null;
  }

  void _dismiss() {
    if (!mounted) return;
    final hadFocus = widget.plezy.focusNode.hasFocus;
    setState(() => _dismissed = widget.plezy.marker);
    if (hadFocus) _icons?.requestFocus();
  }

  /// ↓ to the icons and Back with the panel up; with the panel down the keys
  /// go on to Plezy (Back declines the marker there, ↑/↓ raise the panel).
  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    final navigationKey = classifyPlayerNavigationKey(event, isAppleTV: PlatformDetector.isAppleTV());
    if (navigationKey == PlayerNavigationKey.back || navigationKey == PlayerNavigationKey.physicalEscape) {
      if (event is KeyDownEvent) _backOwned = _chrome.controlsVisible;
      if (!_backOwned) return KeyEventResult.ignored;
      if (event is KeyUpEvent) _backOwned = false;
      return handlePlayerNavigationKeyAction(event, navigationKey, _dismiss);
    }
    if (!_chrome.controlsVisible) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      if (event is! KeyUpEvent) _icons?.requestFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight) {
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_chrome, _session.sidePanelOpen]),
      builder: (context, _) {
        // The right panel takes the place above the icons (R11, A25).
        if (_session.sidePanelOpen.value) return const SizedBox.shrink();
        final dismissed = _dismissed;
        if (dismissed != null && _sameMarker(dismissed, widget.plezy.marker)) return const SizedBox.shrink();
        final shown = _chrome.controlsVisible;
        final strip = shown && _chrome.contentStripVisible;
        final plezyBottom = !shown
            ? _plezyBottomHidden
            : strip
            ? _plezyBottomStrip
            : _plezyBottomShown;
        return TvTheme(
          child: Builder(
            builder: (context) {
              final px = TvTheme.of(context).px;
              final bottom = px(
                !shown
                    ? _bottomHidden
                    : strip
                    ? _bottomOverQueue
                    : _bottomShown,
              );
              return Transform.translate(
                offset: Offset(-(px(_right) - _plezyRight), -(bottom - plezyBottom)),
                child: Focus(canRequestFocus: false, skipTraversal: true, onKeyEvent: _onKey, child: _button(context)),
              );
            },
          ),
        );
      },
    );
  }

  Widget _button(BuildContext context) {
    final theme = TvTheme.of(context);
    final px = theme.px;
    final plezy = widget.plezy;
    final marker = plezy.marker;
    final creditsAtEnd =
        marker.isCredits &&
        plezy.playerDuration > Duration.zero &&
        (plezy.playerDuration - marker.endTime).inMilliseconds <= 1000;
    final nextEpisode = creditsAtEnd && plezy.hasNextEpisode;
    final base = nextEpisode
        ? t.videoControls.nextEpisode
        : marker.isCredits
        ? t.videoControls.skipCredits
        : t.videoControls.skipIntro;
    final counting = plezy.isAutoSkipActive && plezy.shouldShowAutoSkip;
    final remaining = counting
        ? (plezy.autoSkipDelay - plezy.autoSkipProgress * plezy.autoSkipDelay).ceil().clamp(0, plezy.autoSkipDelay)
        : 0;
    final label = counting && remaining > 0 ? '$base ($remaining)' : base;
    final radius = BorderRadius.circular(px(TvTokens.radius.button));
    return TvFocusable(
      kind: TvFocusKind.fill,
      focusedScale: TvTokens.focus.buttonScale,
      radius: TvTokens.radius.button.toDouble(),
      focusNode: plezy.focusNode,
      onSelect: plezy.onActivate,
      semanticLabel: label,
      builder: (context, state) {
        final foreground = state.focused ? TvTokens.color.text.onFocus : TvTokens.color.text.primary;
        return Container(
          height: px(TvTokens.size.button.h),
          padding: EdgeInsets.symmetric(horizontal: px(TvTokens.size.button.padX)),
          decoration: BoxDecoration(
            color: state.pressed
                ? TvTokens.color.text.secondary
                : state.focused
                ? TvTokens.color.focus.fill
                : TvTokens.color.surface.level3,
            borderRadius: radius,
          ),
          foregroundDecoration: counting
              ? BoxDecoration(
                  borderRadius: radius,
                  gradient: LinearGradient(
                    colors: [TvTokens.color.accent.subtle, TvTokens.color.accent.subtle, Colors.transparent],
                    stops: [0, plezy.autoSkipProgress.clamp(0.0, 1.0), plezy.autoSkipProgress.clamp(0.0, 1.0)],
                  ),
                )
              : null,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(
                nextEpisode ? Symbols.skip_next_rounded : Symbols.fast_forward_rounded,
                fill: 1,
                size: px(TvTokens.size.button.iconSize),
                color: foreground,
              ),
              SizedBox(width: px(TvTokens.size.button.iconGap)),
              Text(label, style: theme.label.copyWith(color: foreground)),
            ],
          ),
        );
      },
    );
  }
}

// ---- H7: pause indicator and pause from the remote (R5, R18) ----

/// Pause layer in the player stack (H7, D2).
///
/// A pause by the remote's Play/Pause key with the panel hidden and no prompt
/// up (Plezy pauses without raising the chrome) raises the panel with focus on
/// play (R5, R7, design flow 5). While paused with the panel down, a mini
/// indicator sits bottom left (R18, `10-player-hidden-paused`); it goes away
/// 5 minutes after the pause began and stays away until playback resumes.
class TvPauseIndicator extends StatefulWidget {
  const TvPauseIndicator({super.key, required this.player, required this.chromeController, required this.promptOpen});

  final Player player;
  final PlayerChromeController chromeController;

  /// Plezy's play-next or still-watching prompt is up: the panel stays inert
  /// (R11a), so a pause neither raises it nor shows the indicator.
  final bool promptOpen;

  @override
  State<TvPauseIndicator> createState() => _TvPauseIndicatorState();
}

class _TvPauseIndicatorState extends State<TvPauseIndicator> {
  StreamSubscription<bool>? _playingSubscription;
  late bool _playing;

  /// Paused after playing; false before playback ever started.
  bool _paused = false;
  bool _expired = false;
  Timer? _expiry;

  /// A Play/Pause key went down since the last playing change: only such a
  /// pause raises the panel; others (end of the episode, background) do not.
  bool _pauseKey = false;
  static final _pauseKeys = {LogicalKeyboardKey.mediaPlayPause, LogicalKeyboardKey.mediaPause};

  bool _observeKey(KeyEvent event) {
    if (event is KeyDownEvent && _pauseKeys.contains(event.logicalKey)) _pauseKey = true;
    return false;
  }

  @override
  void initState() {
    super.initState();
    _subscribe();
    widget.chromeController.addListener(_onChrome);
    HardwareKeyboard.instance.addHandler(_observeKey);
  }

  @override
  void didUpdateWidget(TvPauseIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.player != widget.player) {
      _playingSubscription?.cancel();
      _resume();
      _subscribe();
    }
    if (oldWidget.chromeController != widget.chromeController) {
      oldWidget.chromeController.removeListener(_onChrome);
      widget.chromeController.addListener(_onChrome);
    }
  }

  @override
  void dispose() {
    _playingSubscription?.cancel();
    _expiry?.cancel();
    widget.chromeController.removeListener(_onChrome);
    HardwareKeyboard.instance.removeHandler(_observeKey);
    super.dispose();
  }

  void _subscribe() {
    _playing = widget.player.state.playing;
    _playingSubscription = widget.player.streams.playing.listen(_onPlaying);
  }

  void _onChrome() {
    if (mounted) setState(() {});
  }

  void _resume() {
    _paused = false;
    _expired = false;
    _expiry?.cancel();
    _expiry = null;
  }

  void _onPlaying(bool playing) {
    if (!mounted || playing == _playing) return;
    _playing = playing;
    if (playing) {
      _pauseKey = false;
      setState(_resume);
      return;
    }
    setState(() {
      _paused = true;
      _expired = false;
    });
    _expiry?.cancel();
    _expiry = Timer(Duration(milliseconds: TvTokens.player.pausedIndicatorHide), () {
      if (mounted) setState(() => _expired = true);
    });
    final chrome = widget.chromeController;
    final byKey = _pauseKey;
    _pauseKey = false;
    if (byKey && !chrome.controlsVisible && !widget.promptOpen) {
      // The panel consumes the flag when it mounts on this showing.
      TvPlayerSession.of(widget.player).focusPlayOnNextShow = true;
      chrome.show();
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _paused && !_expired && !widget.promptOpen && !widget.chromeController.controlsVisible;
    if (!visible) return const SizedBox.shrink();
    final player = widget.player;
    return Positioned.fill(
      child: IgnorePointer(
        child: TvTheme(
          child: Builder(
            builder: (context) {
              final theme = TvTheme.of(context);
              final px = theme.px;
              final mini = TvTokens.player.miniPause;
              return Align(
                alignment: Alignment.bottomLeft,
                child: Padding(
                  padding: EdgeInsets.only(left: px(TvTokens.space.safeX), bottom: px(TvTokens.space.safeY)),
                  child: Container(
                    height: px(mini.h),
                    padding: EdgeInsets.symmetric(horizontal: px(TvTokens.space.lg)),
                    decoration: BoxDecoration(
                      color: mini.bg,
                      borderRadius: BorderRadius.circular(px(TvTokens.radius.sm)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AppIcon(Symbols.pause_rounded, fill: 1, size: px(28), color: TvTokens.color.text.primary),
                        SizedBox(width: px(TvTokens.space.md)),
                        Text(TvStrings.playerPaused, style: theme.body),
                        SizedBox(width: px(TvTokens.space.md)),
                        StreamBuilder<Duration>(
                          stream: player.streams.position,
                          initialData: player.state.position,
                          builder: (context, snapshot) => Text(
                            '${formatDurationTimestamp(snapshot.data ?? player.state.position)} / '
                            '${formatDurationTimestamp(player.state.duration)}',
                            style: theme.body.copyWith(color: TvTokens.color.text.secondary),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

// ---- H4: play-next card (R19) ----

/// The play-next card's content inside Plezy's prompt shell (H4, D9, R19,
/// `10-player-next-countdown`). Position, PiP, the focus hold, the countdown
/// and both actions stay Plezy's; Watch and Cancel use Plezy's focus nodes.
class TvUpNextCard extends StatefulWidget {
  const TvUpNextCard({super.key, required this.plezy});

  final VideoPlayerPlayNextOverlay plezy;

  @override
  State<TvUpNextCard> createState() => _TvUpNextCardState();
}

class _TvUpNextCardState extends State<TvUpNextCard> {
  /// The countdown's starting value, for the bar under the still.
  int _total = 0;

  @override
  Widget build(BuildContext context) {
    final plezy = widget.plezy;
    final episode = plezy.nextEpisode;
    if (episode == null) return const SizedBox.shrink();
    return TvTheme(
      child: Builder(
        builder: (context) {
          final theme = TvTheme.of(context);
          final px = theme.px;
          final card = TvTokens.player.upNextCard;
          final subtitle = [
            if (episode.grandparentTitle case final show? when show.isNotEmpty) show,
            if (episode.durationMs case final ms? when ms > 0) formatDurationTextual(ms),
          ].join(' · ');
          return ValueListenableBuilder<int>(
            valueListenable: plezy.autoPlayCountdown,
            builder: (context, countdown, _) {
              if (countdown > _total) _total = countdown;
              final counting = countdown > 0;
              return Container(
                width: px(card.w),
                padding: EdgeInsets.all(px(TvTokens.space.lg)),
                decoration: BoxDecoration(color: card.bg, borderRadius: BorderRadius.circular(px(card.radius))),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _still(context, episode, counting && _total > 0 ? countdown / _total : null),
                    SizedBox(width: px(TvTokens.space.lg)),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (counting ? TvStrings.playerNextEpisodeIn(countdown) : t.videoControls.nextEpisode)
                                .toUpperCase(),
                            style: theme.caption.copyWith(color: TvTokens.color.text.tertiary, letterSpacing: px(1)),
                          ),
                          SizedBox(height: px(TvTokens.space.xs)),
                          Text(
                            episode.parentIndex != null && episode.index != null
                                ? 'S${episode.parentIndex} E${episode.index} · ${episode.title ?? ''}'
                                : episode.title ?? '',
                            style: theme.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (subtitle.isNotEmpty)
                            Text(subtitle, style: theme.caption.copyWith(color: TvTokens.color.text.secondary)),
                          SizedBox(height: px(TvTokens.space.md)),
                          Wrap(
                            spacing: px(TvTokens.space.sm),
                            runSpacing: px(TvTokens.space.sm),
                            children: [
                              TvButton(
                                label: t.common.play,
                                icon: Symbols.play_arrow_rounded,
                                variant: TvButtonVariant.smallSecondary,
                                minWidth: 0,
                                focusNode: plezy.confirmFocusNode,
                                onSelect: plezy.onPlayNext,
                                onNavigateLeft: () {},
                                onNavigateRight: plezy.cancelFocusNode.requestFocus,
                                onNavigateUp: () {},
                                onNavigateDown: () {},
                              ),
                              TvButton(
                                label: t.common.cancel,
                                variant: TvButtonVariant.smallSecondary,
                                minWidth: 0,
                                focusNode: plezy.cancelFocusNode,
                                onSelect: plezy.onCancel,
                                onNavigateLeft: plezy.confirmFocusNode.requestFocus,
                                onNavigateRight: () {},
                                onNavigateUp: () {},
                                onNavigateDown: () {},
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  /// The next episode's still, blurred for hide-spoilers like Plezy's card,
  /// with the countdown bar along its bottom.
  Widget _still(BuildContext context, MediaItem episode, double? progress) {
    final px = TvTheme.of(context).px;
    final card = TvTokens.player.upNextCard;
    final placeholder = ColoredBox(color: TvTokens.color.surface.level2);
    Widget image = placeholder;
    final thumbPath = episode.thumbPath;
    final serverId = serverIdOrNull(episode.serverId);
    if (thumbPath != null) {
      final client = context.tryGetMediaClientForServer(serverId);
      final localFilePath = serverId == null
          ? null
          : DownloadArtworkService.localPathSync(DownloadStorageService.instance, serverId, thumbPath);
      if (client != null || localFilePath != null) {
        image = OptimizedMediaImage.thumb(
          client: client,
          imagePath: thumbPath,
          localFilePath: localFilePath,
          fit: BoxFit.cover,
          placeholder: (_, _) => placeholder,
          errorWidget: (_, _, _) => placeholder,
        );
      }
    }
    return SizedBox(
      width: px(card.thumbW),
      height: px(card.thumbH),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(px(TvTokens.radius.sm)),
        child: Stack(
          fit: StackFit.expand,
          children: [
            placeholder,
            SettingValueBuilder<bool>(
              pref: SettingsService.hideSpoilers,
              builder: (context, hideSpoilers, _) => hideSpoilers && episode.shouldHideSpoiler
                  ? ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: 12, sigmaY: 12), child: image)
                  : image,
            ),
            if (progress != null)
              Align(
                alignment: Alignment.bottomLeft,
                child: SizedBox(
                  height: px(TvTokens.size.progressBar.h),
                  child: Stack(
                    children: [
                      Positioned.fill(child: ColoredBox(color: TvTokens.color.status.progressTrack)),
                      FractionallySizedBox(
                        widthFactor: progress.clamp(0.0, 1.0),
                        heightFactor: 1,
                        child: ColoredBox(color: TvTokens.color.status.progressFill),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---- H5: buffering (R20) ----

/// Three dots pulsing in opacity in place of Plezy's spinner (H5, R20,
/// `10-player-buffering`); shown exactly when Plezy shows its spinner.
class TvBufferingDots extends StatelessWidget {
  const TvBufferingDots({super.key, required this.plezy});

  final VideoPlayerBufferingOverlay plezy;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: PipService().isPipActive,
      builder: (context, isInPip, _) {
        if (isInPip) return const SizedBox.shrink();
        return ValueListenableBuilder<bool>(
          valueListenable: plezy.isBuffering,
          builder: (context, buffering, _) => ValueListenableBuilder<bool>(
            valueListenable: plezy.hasFirstFrame,
            builder: (context, hasFrame, _) {
              if ((!buffering && hasFrame) || plezy.isExiting.value) return const SizedBox.shrink();
              return Positioned.fill(
                child: IgnorePointer(
                  child: TvTheme(
                    child: Center(
                      child: Semantics(label: t.videoControls.loadingVideo, child: const _TvDots()),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _TvDots extends StatefulWidget {
  const _TvDots();

  @override
  State<_TvDots> createState() => _TvDotsState();
}

class _TvDotsState extends State<_TvDots> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final px = TvTheme.of(context).px;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) SizedBox(width: px(TvTokens.space.md)),
            Opacity(
              // Each dot peaks a third of a cycle after the previous one.
              opacity: 0.3 + 0.7 * (1 - (((_controller.value - i / 3) % 1.0) * 2 - 1).abs()),
              child: Container(
                width: px(18),
                height: px(18),
                decoration: BoxDecoration(color: TvTokens.color.text.primary, shape: BoxShape.circle),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---- H6: playback error (R21) ----

/// Plezy's playback-failure screen in the TV style (H6, R21,
/// `10-player-error`): Plezy's message, Retry (Plezy's focus node, which the
/// screen focuses) and Back.
class TvPlaybackError extends StatefulWidget {
  const TvPlaybackError({super.key, required this.args});

  final TvPlaybackErrorArgs args;

  @override
  State<TvPlaybackError> createState() => _TvPlaybackErrorState();
}

class _TvPlaybackErrorState extends State<TvPlaybackError> {
  final _back = FocusNode(debugLabel: 'TvPlaybackError.back');

  @override
  void dispose() {
    _back.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: TvTheme(child: Builder(builder: _body)),
    );
  }

  Widget _body(BuildContext context) {
    final args = widget.args;
    final theme = TvTheme.of(context);
    final px = theme.px;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: px(720)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: px(96),
              height: px(96),
              decoration: BoxDecoration(
                color: TvTokens.color.surface.level2,
                borderRadius: BorderRadius.circular(px(TvTokens.radius.panel)),
              ),
              child: AppIcon(Symbols.error_rounded, fill: 1, size: px(44), color: TvTokens.color.text.secondary),
            ),
            SizedBox(height: px(TvTokens.space.xl)),
            Text(args.message, textAlign: TextAlign.center, style: theme.bodyLarge),
            SizedBox(height: px(TvTokens.space.xl)),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TvButton(
                  label: t.common.retry,
                  icon: Symbols.refresh_rounded,
                  variant: TvButtonVariant.secondary,
                  focusNode: args.retryFocusNode,
                  onSelect: args.onRetry,
                  onNavigateLeft: () {},
                  onNavigateRight: _back.requestFocus,
                  onNavigateUp: () {},
                  onNavigateDown: () {},
                ),
                SizedBox(width: px(TvTokens.space.sm)),
                TvButton(
                  label: t.common.back,
                  variant: TvButtonVariant.secondary,
                  focusNode: _back,
                  onSelect: args.onBack,
                  onNavigateLeft: args.retryFocusNode.requestFocus,
                  onNavigateRight: () {},
                  onNavigateUp: () {},
                  onNavigateDown: () {},
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
