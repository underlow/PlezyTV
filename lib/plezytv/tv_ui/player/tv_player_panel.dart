import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../focus/dpad_navigator.dart';
import '../../../i18n/strings.g.dart';
import '../../../media/media_kind.dart';
import '../../../media/stepped_seek.dart';
import '../../../utils/formatters.dart';
import '../../../utils/platform_detector.dart';
import '../../../widgets/app_icon.dart';
import '../../../widgets/video_controls/desktop_video_controls.dart';
import '../../../widgets/video_controls/player_chrome_controller.dart';
import '../../../widgets/video_controls/video_controls.dart' show PlayerNavigationKey, classifyPlayerNavigationKey, handlePlayerNavigationKeyAction;
import '../../../widgets/video_controls/widgets/finish_time_builder.dart';
import '../../../widgets/video_controls/widgets/play_pause_stream_builder.dart';
import '../components/tv_button.dart';
import '../tv_focusable.dart';
import '../tv_strings.dart';
import '../tv_theme.dart';
import '../tv_tokens.dart';
import 'tv_player_bar.dart';
import 'tv_player_hooks.dart';
import 'tv_player_session.dart';

/// Focusable elements of the panel; [name] is the id kept in
/// [TvPlayerSession] focus memory.
enum TvPlayerPanelElement { bar, previous, play, next, subtitles, audio, settings }

/// The TV player panel (S9) in place of Plezy's `DesktopVideoControls` (H1).
///
/// Plezy's `PlexVideoControls` stays the owner of keys while the panel is
/// hidden, of the fade, auto-hide and the outer Back chain; this widget draws
/// the panel, moves focus inside it and seeks from the bar (R4–R8, D8). Keys it
/// does not use (Play/Pause, ⏪/⏩, Back) go on to Plezy.
class TvPlayerPanel extends StatefulWidget {
  const TvPlayerPanel({super.key, required this.args});

  final TvPlayerPanelArgs args;

  @override
  State<TvPlayerPanel> createState() => TvPlayerPanelState();
}

@visibleForTesting
class TvPlayerPanelState extends State<TvPlayerPanel> {
  static const _keyRepeatThumbnailTimeout = Duration(milliseconds: 400);

  DesktopVideoControls get _plezy => widget.args.plezy;
  PlayerChromeController? get _chrome => _plezy.chromeController;
  TvPlayerSession get _session => TvPlayerSession.of(_plezy.player);

  late final Map<TvPlayerPanelElement, FocusNode> _nodes = {
    for (final element in TvPlayerPanelElement.values) element: FocusNode(debugLabel: 'TvPlayer.${element.name}'),
  };
  FocusNode _node(TvPlayerPanelElement element) => _nodes[element]!;

  TvPlayerPanelElement? _focused;
  bool _barFocused = false;
  bool _wasVisible = false;
  bool _buffering = false;
  StreamSubscription<bool>? _bufferingSubscription;

  // Held-key seeking on the bar, copied from DesktopVideoControlsState (D8).
  LogicalKeyboardKey? _seekDirection;
  int _seekRepeatCount = 0;
  bool _showKeyRepeatThumbnail = false;
  Timer? _keyRepeatThumbnailTimer;
  late final DebouncedSeekAccumulator _timelineSeek;

  bool get _isEpisode => _plezy.metadata.kind == MediaKind.episode;
  bool get _canControl => widget.args.canControl;
  bool get _promptOpen => widget.args.playNextFocusNode != null || widget.args.playbackPromptOpen;
  bool get _previousEnabled => _canControl && _plezy.onPrevious != null;
  bool get _nextEnabled => _canControl && _plezy.onNext != null;

  /// Whether the queue hint shows and ↓ will open the queue (T3).
  bool get _hasQueue => _plezy.showQueueTab && _plezy.onQueueItemSelected != null;

  List<TvPlayerPanelElement> get _row => [
    if (_isEpisode) TvPlayerPanelElement.previous,
    TvPlayerPanelElement.play,
    if (_isEpisode) TvPlayerPanelElement.next,
  ];

  static const _icons = [TvPlayerPanelElement.subtitles, TvPlayerPanelElement.audio, TvPlayerPanelElement.settings];

  @override
  void initState() {
    super.initState();
    _timelineSeek = DebouncedSeekAccumulator(
      currentPosition: () => _plezy.player.state.position,
      duration: () => _plezy.player.state.duration,
      seek: (target) => _plezy.onSeekEnd(target),
      playheadJumps: _plezy.player.streams.playheadJump,
      onChanged: () {
        if (mounted) setState(() {});
      },
    );
    _buffering = _plezy.player.state.buffering;
    _listenBuffering();
    _chrome?.addListener(_onChromeChanged);
    FocusManager.instance.addListener(_onPrimaryFocusChanged);
    _session.iconsFocusNode = _node(TvPlayerPanelElement.subtitles);
    _wasVisible = _chrome?.controlsVisible ?? true;
    // A prompt already open is a state, not only a transition (R11a): the
    // post-frame step yields to it instead of placing focus.
    if (_wasVisible) _schedulePlaceFocus();
  }

  @override
  void didUpdateWidget(TvPlayerPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget.args.plezy;
    if (!identical(old.player, _plezy.player)) {
      _timelineSeek.attachPlayheadJumps(_plezy.player.streams.playheadJump);
      _bufferingSubscription?.cancel();
      _listenBuffering();
      _session.iconsFocusNode = _node(TvPlayerPanelElement.subtitles);
    }
    if (old.chromeController != _chrome) {
      old.chromeController?.removeListener(_onChromeChanged);
      _chrome?.addListener(_onChromeChanged);
    }
    if (old.metadata.globalKey != _plezy.metadata.globalKey) {
      // A pending burst is an offset into the outgoing item (D7: replaces
      // Plezy's abandonPendingSeek through the key).
      _timelineSeek.cancel();
      _resetSeekState();
    }
    final wasPromptOpen = oldWidget.args.playNextFocusNode != null || oldWidget.args.playbackPromptOpen;
    if (_promptOpen != wasPromptOpen) {
      // Not during build: closing the strip notifies Plezy, which rebuilds.
      // On close the panel follows controlsVisible again.
      if (_promptOpen) {
        _focused = null;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _promptOpen) _yieldToPrompt();
        });
      } else if (_chrome?.controlsVisible ?? true) {
        _schedulePlaceFocus();
      }
    }
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_onPrimaryFocusChanged);
    _chrome?.removeListener(_onChromeChanged);
    _bufferingSubscription?.cancel();
    _keyRepeatThumbnailTimer?.cancel();
    _timelineSeek.dispose();
    final session = _session;
    if (identical(session.iconsFocusNode, _node(TvPlayerPanelElement.subtitles))) session.iconsFocusNode = null;
    for (final node in _nodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _listenBuffering() {
    _bufferingSubscription = _plezy.player.streams.buffering.listen((buffering) {
      if (mounted && buffering != _buffering) setState(() => _buffering = buffering);
    });
  }

  void _onChromeChanged() {
    final chrome = _chrome;
    if (!mounted || chrome == null) return;
    final visible = chrome.controlsVisible;
    if (visible == _wasVisible) return;
    _wasVisible = visible;
    if (visible) {
      _schedulePlaceFocus();
    } else {
      // Plezy has already moved focus to the player surface, so this records
      // the element tracked while it had focus.
      _session.rememberFocus(_focused?.name, clock.now());
      _focused = null;
    }
  }

  /// R11a: while a prompt (play next, still watching) is open the panel closes
  /// the side panel and the strip, drops the pause flag and stays invisible and
  /// inert (see [build]). It neither hides the chrome nor moves focus: the
  /// prompt's focused button holds the chrome up and Plezy places focus there,
  /// so hiding or refocusing would loop.
  void _yieldToPrompt() {
    // A pause flag must not send a later showing to play (R7).
    _session.focusPlayOnNextShow = false;
    final chrome = _chrome;
    if (chrome != null && chrome.contentStripVisible) chrome.setContentStripVisible(false);
  }

  /// Plezy parks the remote on its player surface (an ancestor of the panel)
  /// and, with the chrome up, hands it on through `_desktopControlsKey`, which
  /// the panel does not answer (D7). Take it from there whenever the panel is
  /// up; focus elsewhere (a prompt, a sheet) is left alone.
  void _onPrimaryFocusChanged() {
    if (!mounted || _promptOpen || !(_chrome?.controlsVisible ?? true) || _placeFocusScheduled) return;
    final primary = FocusManager.instance.primaryFocus;
    if (primary == null || !_node(TvPlayerPanelElement.bar).ancestors.contains(primary)) return;
    _schedulePlaceFocus();
  }

  bool _placeFocusScheduled = false;

  void _schedulePlaceFocus() {
    _placeFocusScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _placeFocusScheduled = false;
      if (!mounted || !(_chrome?.controlsVisible ?? true)) return;
      if (_promptOpen) return _yieldToPrompt();
      // Within one showing, a reclaimed remote returns to where it was.
      _node(_focused ?? _initialFocus()).requestFocus();
    });
  }

  /// R7: play after a remote pause (the flag is consumed here, so it never
  /// applies to a later showing), else the remembered element within 30 s if
  /// it is still there and active, else the bar.
  TvPlayerPanelElement _initialFocus() {
    final session = _session;
    if (session.focusPlayOnNextShow) {
      session.focusPlayOnNextShow = false;
      return TvPlayerPanelElement.play;
    }
    final id = session.lastFocusedId;
    final hiddenAt = session.hiddenAt;
    if (id == null || hiddenAt == null) return TvPlayerPanelElement.bar;
    if (clock.now().difference(hiddenAt) > Duration(milliseconds: TvTokens.player.focusResetAfter)) {
      return TvPlayerPanelElement.bar;
    }
    for (final element in TvPlayerPanelElement.values) {
      if (element.name == id && _isAvailable(element)) return element;
    }
    return TvPlayerPanelElement.bar;
  }

  bool _isAvailable(TvPlayerPanelElement element) => switch (element) {
    TvPlayerPanelElement.previous => _isEpisode && _previousEnabled,
    TvPlayerPanelElement.next => _isEpisode && _nextEnabled,
    TvPlayerPanelElement.play => _canControl,
    _ => true,
  };

  void _activity() => _plezy.onFocusActivity?.call();

  void _go(TvPlayerPanelElement element) {
    _node(element).requestFocus();
    _activity();
  }

  void _onElementFocus(TvPlayerPanelElement element, bool focused) {
    if (focused) {
      _focused = element;
      _activity();
    }
  }

  // ---- Keys ----

  /// Catches arrows and Select that no element used, so they neither reach
  /// Plezy's shortcuts (Enter there skips a marker) nor move focus out.
  /// Play/Pause, ⏪/⏩ and Back pass on to Plezy (R2, R6, R22).
  KeyEventResult _onPanelKey(FocusNode _, KeyEvent event) {
    final key = event.logicalKey;
    final back = _onIconsBack(event);
    if (back != null) return back;
    if (key.isSelectKey || key.isDpadDirection) {
      if (event.isActionable) _activity();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Latched for the whole press: the release lands on the bar.
  bool _iconsOwnBackPress = false;

  /// Back on the icons row moves to the bar (docs/design/player.md); a Back
  /// elsewhere goes on to Plezy. Down is consumed, the move happens on release
  /// (design §4), so the release neither hides the panel nor exits.
  KeyEventResult? _onIconsBack(KeyEvent event) {
    final navigationKey = classifyPlayerNavigationKey(event, isAppleTV: PlatformDetector.isAppleTV());
    if (navigationKey == PlayerNavigationKey.none || navigationKey == PlayerNavigationKey.home) return null;
    if (event is KeyDownEvent) {
      _iconsOwnBackPress = _icons.any((element) => _node(element).hasPrimaryFocus);
      // Restart auto-hide so the release still lands here, not on Plezy's
      // Back chain (which would exit with the chrome hidden).
      if (_iconsOwnBackPress) _activity();
    }
    if (!_iconsOwnBackPress) return null;
    if (event is KeyUpEvent) _iconsOwnBackPress = false;
    return handlePlayerNavigationKeyAction(event, navigationKey, () => _go(TvPlayerPanelElement.bar));
  }

  void _rowStep(TvPlayerPanelElement from, int delta) {
    final row = _row;
    final index = row.indexOf(from) + delta;
    if (index < 0) return _activity();
    _go(index >= row.length ? TvPlayerPanelElement.bar : row[index]);
  }

  void _iconStep(TvPlayerPanelElement from, int delta) {
    final index = _icons.indexOf(from) + delta;
    if (index < 0) return _go(TvPlayerPanelElement.play);
    if (index >= _icons.length) return _activity();
    _go(_icons[index]);
  }

  void _onDown() {
    // ↓ opens the queue (T3); nothing yet.
    _activity();
  }

  void _previous() {
    _timelineSeek.cancel();
    _plezy.onPrevious?.call();
  }

  void _next() {
    _timelineSeek.cancel();
    _plezy.onNext?.call();
  }

  void _resetSeekState() {
    _seekDirection = null;
    _seekRepeatCount = 0;
    _keyRepeatThumbnailTimer?.cancel();
    _keyRepeatThumbnailTimer = null;
    if (_showKeyRepeatThumbnail && mounted) setState(() => _showKeyRepeatThumbnail = false);
  }

  void _triggerKeyRepeatThumbnail() {
    if (!_showKeyRepeatThumbnail) setState(() => _showKeyRepeatThumbnail = true);
    _keyRepeatThumbnailTimer?.cancel();
    _keyRepeatThumbnailTimer = Timer(_keyRepeatThumbnailTimeout, () {
      if (mounted) setState(() => _showKeyRepeatThumbnail = false);
    });
  }

  void _onBarFocusChange(bool focused) {
    setState(() => _barFocused = focused);
    _onElementFocus(TvPlayerPanelElement.bar, focused);
    if (!focused) {
      _timelineSeek.flush();
      _resetSeekState();
    }
  }

  /// ←/→ on the bar as in `DesktopVideoControlsState._handleTimelineKeyEvent`:
  /// steps grow with key repeats, one seek when the key is released or the
  /// burst pauses (R8).
  KeyEventResult _onBarKey(FocusNode _, KeyEvent event) {
    final key = event.logicalKey;
    final horizontal = key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowRight;
    if (event is KeyUpEvent) {
      if (horizontal) {
        _timelineSeek.flush();
        _resetSeekState();
        return KeyEventResult.handled;
      }
      return key.isSelectKey ? KeyEventResult.handled : KeyEventResult.ignored;
    }
    if (!event.isActionable) return KeyEventResult.ignored;

    if (key.isSelectKey) {
      if (event is KeyDownEvent) _plezy.onPlayPause();
      _activity();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowDown) {
      _timelineSeek.flush();
      _resetSeekState();
      key == LogicalKeyboardKey.arrowUp ? _go(_icons.first) : _onDown();
      return KeyEventResult.handled;
    }
    if (!horizontal) return KeyEventResult.ignored;
    if (!_canControl) return KeyEventResult.handled;

    if (_seekDirection != key) {
      _seekDirection = key;
      _seekRepeatCount = 0;
    }
    if (event is KeyRepeatEvent) {
      _seekRepeatCount++;
      _triggerKeyRepeatThumbnail();
    }
    final duration = _plezy.player.state.duration;
    if (duration.inMilliseconds <= 0) return KeyEventResult.handled;
    final multiplier = event is KeyRepeatEvent ? steppedSeekMultiplier(_seekRepeatCount) : 1.0;
    final stepMs = (_plezy.seekTimeSmall * 1000 * multiplier).clamp(500, 120000).toInt();
    final step = Duration(milliseconds: stepMs);
    _timelineSeek.seekBy(key == LogicalKeyboardKey.arrowRight ? step : -step);
    _activity();
    return KeyEventResult.handled;
  }

  // ---- Layout ----

  @override
  Widget build(BuildContext context) {
    // R11a: invisible and inert while a prompt is open, whatever controlsVisible.
    final promptOpen = _promptOpen;
    return ExcludeFocus(
      excluding: promptOpen,
      child: Visibility(
        visible: !promptOpen,
        maintainState: true,
        child: _panel(),
      ),
    );
  }

  Widget _panel() {
    return TvTheme(
      child: Builder(
        builder: (context) => Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: _onPanelKey,
          child: FocusTraversalGroup(
            child: Stack(
              fit: StackFit.expand,
              children: [_bottomShade(context), _header(context), ..._bottom(context)],
            ),
          ),
        ),
      ),
    );
  }

  Widget _bottomShade(BuildContext context) {
    final px = TvTheme.of(context).px;
    final shade = TvTokens.player.shadeBottom;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      height: px(shade.h),
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: shade.stops),
          ),
        ),
      ),
    );
  }

  String _subtitle() {
    final item = _plezy.metadata;
    final durationMs = (item.durationMs ?? 0) > 0 ? item.durationMs! : _plezy.player.state.duration.inMilliseconds;
    final parts = <String>[
      if (_isEpisode) ...[
        ?formatSeasonEpisodeLabel(item.parentIndex, item.index),
        if (item.grandparentTitle?.isNotEmpty ?? false) item.grandparentTitle!,
      ] else if (item.year != null)
        '${item.year}',
      if (durationMs > 0) formatDurationTextual(durationMs),
    ];
    return parts.join(' · ');
  }

  Widget _header(BuildContext context) {
    final theme = TvTheme.of(context);
    final px = theme.px;
    final subtitle = _subtitle();
    return Positioned(
      left: px(TvTokens.space.safeX),
      right: px(TvTokens.space.safeX),
      top: px(TvTokens.space.safeY),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_plezy.metadata.title ?? '', style: theme.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    style: theme.body.copyWith(color: TvTokens.color.text.secondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          SizedBox(width: px(TvTokens.space.lg)),
          _TvPlayerClock(style: theme.title),
        ],
      ),
    );
  }

  List<Widget> _bottom(BuildContext context) {
    final theme = TvTheme.of(context);
    final px = theme.px;
    final controls = TvTokens.player.controls;
    final bar = TvTokens.player.bar;
    final button = TvTokens.size.iconButton;
    const elapsedW = 92;
    const gap = 24;
    const buttonGap = 16;
    final row = _row;
    final rowEnd = controls.playX + row.length * button.w + (row.length - 1) * buttonGap;
    final elapsedX = rowEnd + gap;
    final barX = elapsedX + elapsedW + gap;
    final barEnd = bar.x + bar.w;
    final timeStyle = theme.body.copyWith(
      color: TvTokens.color.text.primary,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return [
      Positioned(
        left: px(TvTokens.space.safeX),
        top: px(controls.iconsY),
        height: px(button.h),
        width: px(controls.iconsX.first - TvTokens.space.safeX - gap),
        child: Align(
          alignment: Alignment.centerLeft,
          child: FinishTimeBuilder(
            player: _plezy.player,
            builder: (context, finishTime) => finishTime == null
                ? const SizedBox.shrink()
                : Text(
                    t.videoControls.endsAt(
                      time: formatClockTime(finishTime, is24Hour: MediaQuery.alwaysUse24HourFormatOf(context)),
                    ),
                    style: theme.body,
                    maxLines: 1,
                  ),
          ),
        ),
      ),
      for (final (index, element) in _icons.indexed)
        Positioned(
          left: px(controls.iconsX[index]),
          top: px(controls.iconsY),
          child: TvIconButton(
            focusNode: _node(element),
            icon: switch (element) {
              TvPlayerPanelElement.subtitles => Symbols.subtitles_rounded,
              TvPlayerPanelElement.audio => Symbols.volume_up_rounded,
              _ => Symbols.settings_rounded,
            },
            caption: switch (element) {
              TvPlayerPanelElement.subtitles => t.videoControls.subtitlesLabel,
              TvPlayerPanelElement.audio => t.videoControls.audioLabel,
              _ => t.common.settings,
            },
            // The right panel opens in T4.
            onSelect: _activity,
            onFocusChange: (focused) => _onElementFocus(element, focused),
            onNavigateLeft: () => _iconStep(element, -1),
            onNavigateRight: () => _iconStep(element, 1),
            onNavigateUp: _activity,
            onNavigateDown: () => _go(TvPlayerPanelElement.bar),
          ),
        ),
      for (final (index, element) in row.indexed)
        Positioned(
          left: px(controls.playX + index * (button.w + buttonGap)),
          top: px(controls.rowY),
          child: _rowButton(element),
        ),
      StreamBuilder<Duration>(
        stream: _plezy.player.streams.position,
        initialData: _plezy.player.state.position,
        builder: (context, snapshot) {
          final position = snapshot.data ?? Duration.zero;
          return StreamBuilder<Duration>(
            stream: _plezy.player.streams.duration,
            initialData: _plezy.player.state.duration,
            builder: (context, durationSnapshot) =>
                _timeline(context, position, durationSnapshot.data ?? Duration.zero, barX, barEnd, elapsedX, timeStyle),
          );
        },
      ),
      if (_hasQueue)
        Positioned(
          left: 0,
          right: 0,
          top: px(controls.hintY),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AppIcon(Symbols.keyboard_arrow_down_rounded, size: px(24), color: Colors.white.withValues(alpha: 0.7)),
              SizedBox(width: px(8)),
              Text(
                TvStrings.playerUpNextInQueue,
                style: theme.caption.copyWith(color: Colors.white.withValues(alpha: 0.7)),
              ),
            ],
          ),
        ),
    ];
  }

  Widget _timeline(
    BuildContext context,
    Duration position,
    Duration duration,
    int barX,
    int barEnd,
    int elapsedX,
    TextStyle timeStyle,
  ) {
    final theme = TvTheme.of(context);
    final px = theme.px;
    final controls = TvTokens.player.controls;
    final rowH = TvTokens.size.iconButton.h;
    final pending = _timelineSeek.pendingPosition;
    final shown = pending == null ? position : _clamp(pending, duration);
    final chapters = _plezy.chaptersLoaded && _plezy.showChapterMarkersOnTimeline ? _plezy.chapters : const <Never>[];
    final showPreview = pending != null && _barFocused;
    final frameBuilder = widget.args.isOfflinePlayback ? null : _plezy.thumbnailDataBuilder;
    final frame = showPreview && _showKeyRepeatThumbnail ? frameBuilder?.call(shown) : null;
    final previewW =
        TvTokens.player.seekPreview.w + 2 * (TvTokens.size.focusRing.width + TvTokens.size.focusRing.offset);
    final fraction = duration.inMilliseconds <= 0 ? 0.0 : shown.inMilliseconds / duration.inMilliseconds;
    final thumbX = barX + (barEnd - barX) * fraction.clamp(0.0, 1.0);
    final previewLeft = (thumbX - previewW / 2).clamp(
      TvTokens.space.safeX.toDouble(),
      (1920 - TvTokens.space.safeX - previewW).toDouble(),
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          left: px(elapsedX),
          top: px(controls.rowY),
          height: px(rowH),
          child: Center(child: Text(formatDurationTimestamp(shown), style: timeStyle)),
        ),
        Positioned(
          left: px(barX),
          width: px(barEnd - barX),
          top: px(controls.rowY),
          height: px(rowH),
          child: Focus(
            focusNode: _node(TvPlayerPanelElement.bar),
            onKeyEvent: _onBarKey,
            onFocusChange: _onBarFocusChange,
            child: Semantics(
              slider: true,
              value: formatDurationTimestamp(shown),
              child: TvPlayerProgressBar(
                player: _plezy.player,
                position: position,
                duration: duration,
                pendingPosition: pending == null ? null : shown,
                focused: _barFocused,
                inactive: _buffering || !_canControl,
                chapters: chapters,
              ),
            ),
          ),
        ),
        Positioned(
          right: px(TvTokens.space.safeX),
          top: px(controls.rowY),
          height: px(rowH),
          child: Center(
            child: Text(
              '−${formatDurationTimestamp(duration - shown < Duration.zero ? Duration.zero : duration - shown)}',
              style: timeStyle,
            ),
          ),
        ),
        if (showPreview)
          Positioned(
            left: px(previewLeft),
            width: px(previewW),
            bottom: px(1080 - controls.iconsY + 10),
            child: IgnorePointer(
              child: TvPlayerSeekPreview(target: shown, current: position, frame: frame),
            ),
          ),
      ],
    );
  }

  static Duration _clamp(Duration value, Duration duration) {
    if (value.isNegative) return Duration.zero;
    if (duration > Duration.zero && value > duration) return duration;
    return value;
  }

  Widget _rowButton(TvPlayerPanelElement element) {
    void onLeft() => _rowStep(element, -1);
    void onRight() => _rowStep(element, 1);
    void onUp() => _go(_icons.first);
    void onFocus(bool focused) => _onElementFocus(element, focused);
    return switch (element) {
      TvPlayerPanelElement.previous => _TvPlayerButton(
        focusNode: _node(element),
        icon: Symbols.skip_previous_rounded,
        label: t.videoControls.previousButton,
        disabled: !_previousEnabled,
        onSelect: _previous,
        onFocusChange: onFocus,
        onLeft: onLeft,
        onRight: onRight,
        onUp: onUp,
        onDown: _onDown,
      ),
      TvPlayerPanelElement.next => _TvPlayerButton(
        focusNode: _node(element),
        icon: Symbols.skip_next_rounded,
        label: t.videoControls.nextButton,
        disabled: !_nextEnabled,
        onSelect: _next,
        onFocusChange: onFocus,
        onLeft: onLeft,
        onRight: onRight,
        onUp: onUp,
        onDown: _onDown,
      ),
      _ => PlayPauseStreamBuilder(
        player: _plezy.player,
        builder: (context, playing) => _TvPlayerButton(
          focusNode: _node(element),
          icon: playing ? Symbols.pause_rounded : Symbols.play_arrow_rounded,
          label: playing ? t.videoControls.pauseButton : t.videoControls.playButton,
          disabled: !_canControl,
          onSelect: _plezy.onPlayPause,
          onFocusChange: onFocus,
          onLeft: onLeft,
          onRight: onRight,
          onUp: onUp,
          onDown: _onDown,
        ),
      ),
    };
  }
}

/// Play/pause and ⏮/⏭ (design-system §6.3): 64 × 64, only the icon until
/// focused, then filled like an icon button. Inactive stays focusable so the
/// row keeps its shape (R2).
class _TvPlayerButton extends StatelessWidget {
  const _TvPlayerButton({
    required this.focusNode,
    required this.icon,
    required this.label,
    required this.disabled,
    required this.onSelect,
    required this.onFocusChange,
    required this.onLeft,
    required this.onRight,
    required this.onUp,
    required this.onDown,
  });

  final FocusNode focusNode;
  final IconData icon;
  final String label;
  final bool disabled;
  final VoidCallback onSelect;
  final ValueChanged<bool> onFocusChange;
  final VoidCallback onLeft, onRight, onUp, onDown;

  @override
  Widget build(BuildContext context) {
    final px = TvTheme.of(context).px;
    final size = TvTokens.size.iconButton;
    return TvFocusable(
      kind: TvFocusKind.fill,
      radius: TvTokens.radius.iconButton.toDouble(),
      focusedScale: TvTokens.focus.buttonScale,
      disabled: disabled,
      disabledFocus: TvDisabledFocus.focusable,
      focusNode: focusNode,
      onSelect: onSelect,
      semanticLabel: label,
      onFocusChange: onFocusChange,
      onNavigateLeft: onLeft,
      onNavigateRight: onRight,
      onNavigateUp: onUp,
      onNavigateDown: onDown,
      builder: (context, state) => Container(
        width: px(size.w),
        height: px(size.h),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(px(TvTokens.radius.iconButton)),
          color: state.pressed
              ? TvTokens.color.text.secondary
              : state.focused
              ? TvTokens.color.focus.fill
              : Colors.transparent,
        ),
        child: AppIcon(
          icon,
          fill: 1,
          size: px(36),
          color: state.disabled
              ? TvTokens.color.disabled.text
              : state.focused
              ? TvTokens.color.text.onFocus
              : TvTokens.color.text.primary,
        ),
      ),
    );
  }
}

/// The clock in the header, refreshed on the minute.
class _TvPlayerClock extends StatefulWidget {
  const _TvPlayerClock({required this.style});

  final TextStyle style;

  @override
  State<_TvPlayerClock> createState() => _TvPlayerClockState();
}

class _TvPlayerClockState extends State<_TvPlayerClock> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  void _schedule() {
    final now = clock.now();
    _timer = Timer(Duration(seconds: 60 - now.second), () {
      if (!mounted) return;
      setState(() {});
      _schedule();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Text(formatClockTime(clock.now(), is24Hour: MediaQuery.alwaysUse24HourFormatOf(context)), style: widget.style);
}
