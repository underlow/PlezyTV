import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../../focus/dpad_navigator.dart';
import '../../../focus/key_event_utils.dart';
import '../../../media/media_item.dart';
import '../../../media/media_kind.dart';
import '../../../providers/playback_state_provider.dart';
import '../../../services/sleep_timer_service.dart';
import '../../../utils/platform_detector.dart';
import '../../../widgets/overlay_sheet.dart';
import '../../../widgets/video_controls/player_chrome_controller.dart';
import '../../../widgets/video_controls/video_controls.dart' show PlayerNavigationKey, classifyPlayerNavigationKey;
import '../../../mpv/mpv.dart';
import '../player/tv_player_hooks.dart';
import '../player/tv_player_session.dart';
import 'tv_postplay_logic.dart';

// ---- R1: when the post-play screen may replace the player's exit ----

/// Everything the R1 decision reads, sampled at the moment of the event.
@immutable
class TvPostPlayFacts {
  const TvPostPlayFacts({
    required this.tv,
    required this.isLive,
    required this.isOffline,
    required this.watchTogether,
    required this.kind,
    required this.latched,
    required this.promptOpen,
    required this.loadingNext,
    required this.sleepTimerEnded,
    required this.nextStatus,
    required this.normalLaunch,
  });

  final bool tv;
  final bool isLive;

  /// Plezy's offline library mode (`widget.isOffline`); a downloaded file
  /// played online is not offline (A39).
  final bool isOffline;
  final bool watchTogether;
  final MediaKind kind;

  /// Plezy's completion latch: the item is at its end and nobody seeked back.
  final bool latched;

  /// The play-next or still-watching prompt is up.
  final bool promptOpen;
  final bool loadingNext;

  /// This item ended through the end-of-video sleep timer (C3).
  final bool sleepTimerEnded;

  /// Next-item adjacency; `failed` means the neighbours did not load.
  final QueueNavigationStatus nextStatus;

  /// Started the ordinary way (see [tvNormalLaunch]).
  final bool normalLaunch;
}

/// R1: the item is at its end and leaving the player may open the post-play
/// screen. Every exclusion keeps Plezy's own exit.
bool tvPostPlayAllowed(TvPostPlayFacts f) =>
    f.tv &&
    !f.isLive &&
    !f.isOffline &&
    !f.watchTogether &&
    (f.kind == MediaKind.movie || f.kind == MediaKind.episode) &&
    f.latched &&
    !f.promptOpen &&
    !f.loadingNext &&
    !f.sleepTimerEnded &&
    f.nextStatus != QueueNavigationStatus.failed &&
    f.normalLaunch;

/// "Normal launch" (plan §1): no active queue, or the sequential queue of the
/// item's own series (its show or season as the queue's context, not
/// shuffled). Playlists, collections, folders and shuffle are not. The
/// `isPlaylistActive`/`isQueueActive` flags alone are also true for an
/// ordinary series queue, so the context key decides.
bool tvNormalLaunch(MediaItem item, PlaybackStateProvider? queue) {
  if (queue == null || !(queue.isQueueActive || queue.isPlaylistActive)) return true;
  if (queue.isShuffleActive) return false;
  final context = queue.shuffleContextKey;
  if (context == null || item.kind != MediaKind.episode) return false;
  return context == item.grandparentId || context == item.parentId;
}

// ---- C3: end by the end-of-video sleep timer ----

/// H8, at the start of an accepted EOF (before Plezy picks its branch). A
/// fresh end (latch not yet set) records whether Plezy is about to take the
/// sleep-timer branch for [item]; any other fresh end clears the flag. A
/// repeated EOF while still latched changes nothing.
void tvPostPlayVideoCompleted(Player player, {required bool latched, required MediaItem item}) {
  if (latched) return;
  final session = TvPlayerSession.of(player);
  session.sleepTimerEndedItemKey = SleepTimerService().isEndOfVideoMode ? item.globalKey : null;
}

// ---- C2: the transition ----

/// Accepts Plezy's exit and lays the post-play route over the player (C2).
/// Does nothing when an exit was already accepted, or when [exit] does not
/// accept one (a prompt dismissed, the route not removable).
void tvExitToPostPlay({
  required BuildContext context,
  required MediaItem watched,
  MediaItem? next,
  required bool Function() exitPending,
  required Future<void> Function() exit,
  required PageRoute<void> Function(TvPostPlayArgs args) route,
}) {
  if (exitPending()) return;
  final navigator = Navigator.of(context);
  final removed = exit();
  if (!exitPending()) return;
  // The screen awaits it and treats an error as "removed".
  removed.ignore();
  unawaited(navigator.push(route(TvPostPlayArgs(watched: watched, next: next, playerRemoved: removed))));
}

// ---- H9: the player's last Back step ----

/// The R1 facts for the player behind [probe], read now.
TvPostPlayFacts tvPostPlayFactsOf(BuildContext context, Player player, TvPlayerEndProbe probe, {required bool tv}) {
  final watched = probe.watched();
  PlaybackStateProvider? queue;
  try {
    queue = Provider.of<PlaybackStateProvider>(context, listen: false);
  } catch (_) {
    queue = null;
  }
  return TvPostPlayFacts(
    tv: tv,
    isLive: false,
    isOffline: probe.isOffline,
    watchTogether: probe.watchTogether(),
    kind: watched.kind,
    latched: probe.latched(),
    promptOpen: probe.promptOpen(),
    loadingNext: probe.loadingNext(),
    sleepTimerEnded: TvPlayerSession.of(player).sleepTimerEndedItemKey == watched.globalKey,
    nextStatus: probe.nextStatus(),
    normalLaunch: tvNormalLaunch(watched, queue),
  );
}

/// Invisible layer in the player's stack (H9, next to H7). While mounted it
/// binds the player's end state to [TvPlayerSession] (for H8) and owns an
/// early key handler that takes Back for the post-play screen when Back has
/// reached the last step of the S9 order and R1 holds (C4).
class TvPostPlayExitLayer extends StatefulWidget {
  const TvPostPlayExitLayer({
    super.key,
    required this.player,
    required this.chromeController,
    required this.probe,
    required this.exitToPostPlay,
    required this.tv,
  });

  final Player player;
  final PlayerChromeController chromeController;
  final TvPlayerEndProbe probe;

  /// `TvUi.exitToPostPlay`, injected to keep this file free of the registry.
  final void Function({
    required BuildContext context,
    required MediaItem watched,
    MediaItem? next,
    required bool Function() exitPending,
    required Future<void> Function() exit,
  })
  exitToPostPlay;

  /// TV UI detection, read at the event.
  final bool Function() tv;

  @override
  State<TvPostPlayExitLayer> createState() => TvPostPlayExitLayerState();
}

class TvPostPlayExitLayerState extends State<TvPostPlayExitLayer> implements TvPlayerEndBinding {
  /// The current Back press is ours, decided on its key-down and kept until
  /// its key-up whatever changes meanwhile.
  bool _ownsPress = false;

  TvPlayerSession get _session => TvPlayerSession.of(widget.player);

  @override
  void initState() {
    super.initState();
    _session.endBinding = this;
    FocusManager.instance.addEarlyKeyEventHandler(_onKey);
  }

  @override
  void didUpdateWidget(TvPostPlayExitLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.player != widget.player) {
      final old = TvPlayerSession.of(oldWidget.player);
      if (identical(old.endBinding, this)) old.endBinding = null;
      _session.endBinding = this;
    }
  }

  @override
  void dispose() {
    FocusManager.instance.removeEarlyKeyEventHandler(_onKey);
    if (identical(_session.endBinding, this)) _session.endBinding = null;
    super.dispose();
  }

  @override
  bool get allowed =>
      mounted && tvPostPlayAllowed(tvPostPlayFactsOf(context, widget.player, widget.probe, tv: widget.tv()));

  @override
  void exit() {
    if (!mounted) return;
    final probe = widget.probe;
    widget.exitToPostPlay(
      context: context,
      watched: probe.watched(),
      next: probe.next(),
      exitPending: probe.exitPending,
      exit: probe.exit,
    );
  }

  /// C4: the press is ours only at the last step of the S9 Back order.
  bool _lastBackStep() {
    if (!mounted || !(ModalRoute.isCurrentOf(context) ?? false)) return false;
    final chrome = widget.chromeController;
    if (chrome.controlsVisible || chrome.controlsPresented || chrome.contentStripVisible) return false;
    if (_session.sidePanelOpen.value || _session.skipButtonVisible) return false;
    if (OverlaySheetController.maybeOf(context)?.isOpen ?? false) return false;
    return allowed;
  }

  KeyEventResult _onKey(KeyEvent event) {
    final appleTv = PlatformDetector.isAppleTV();
    if (classifyPlayerNavigationKey(event, isAppleTV: appleTv) != PlayerNavigationKey.back) {
      return KeyEventResult.ignored;
    }
    if (event is KeyDownEvent) {
      _ownsPress = _lastBackStep();
      if (!_ownsPress) return KeyEventResult.ignored;
      // A stale suppression meets a fresh press: clear it, as Plezy's
      // handleBackKeyAction would on this key-down.
      BackKeyUpSuppressor.consumeIfSuppressed(event);
      if (appleTv) _act();
      return KeyEventResult.handled;
    }
    if (!_ownsPress) return KeyEventResult.ignored;
    if (event is KeyRepeatEvent) return KeyEventResult.handled;
    // Key-up of our press.
    _ownsPress = false;
    if (appleTv) return KeyEventResult.handled;
    if (BackKeyUpSuppressor.consumeIfSuppressed(event)) {
      // Not ours to act on: re-arm so Plezy's own handler swallows it.
      BackKeyUpSuppressor.suppressBackUntilKeyUp();
      return KeyEventResult.ignored;
    }
    _act();
    return KeyEventResult.handled;
  }

  void _act() {
    BackKeyCoordinator.markHandled();
    exit();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
