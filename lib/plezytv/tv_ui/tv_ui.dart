import 'package:flutter/material.dart';

import '../../utils/platform_detector.dart';
import 'tv_shell.dart';
import '../../media/media_item.dart';
import '../../media/media_kind.dart';
import '../../utils/layout_constants.dart';
import 'movie/tv_movie_screen.dart';
import 'show/tv_show_screen.dart';
import '../../mpv/mpv.dart';
import '../../screens/video_player/widgets/player_prompt_overlays.dart';
import '../../widgets/video_controls/player_chrome_controller.dart';
import '../../widgets/video_controls/video_controls.dart';
import '../../widgets/video_controls/widgets/skip_marker_button.dart';
import 'player/tv_player_hooks.dart';
import 'player/tv_player_overlays.dart';
import 'player/tv_player_panel.dart';
import 'player/tv_player_session.dart';
import 'postplay/tv_postplay_exit.dart';
import 'postplay/tv_postplay_logic.dart';
import 'postplay/tv_postplay_screen.dart';

/// Typed replacement lookups for upstream screen factories.
abstract final class TvUi {
  static bool Function() _enabled = PlatformDetector.isTV;

  static bool get enabled => _enabled();

  @visibleForTesting
  static set enabledForTesting(bool Function() value) => _enabled = value;

  @visibleForTesting
  static void resetForTesting() {
    _enabled = PlatformDetector.isTV;
    profileHomeBuilderForTesting = null;
    postPlayRouteForTesting = null;
    _player = _productionPlayer;
  }

  /// Player builders in production (S9 H1–H7).
  static final _productionPlayer = TvPlayerBuilders(
    panel: (context, args) => TvPlayerPanel(args: args),
    skipButton: TvSkipButton.build,
    panelOwnsRemote: ({required controlsVisible}) => controlsVisible,
    upNextCard: (context, plezy) => TvUpNextCard(plezy: plezy),
    buffering: (context, plezy) => TvBufferingDots(plezy: plezy),
    playbackError: (args) => TvPlaybackError(args: args),
    pauseIndicator: (player, chromeController, {required promptOpen, required canControl}) => TvPauseIndicator(
      player: player,
      chromeController: chromeController,
      promptOpen: promptOpen,
      canControl: canControl,
    ),
  );
  static TvPlayerBuilders _player = _productionPlayer;

  /// The production player builders, for tests that replace one of them.
  @visibleForTesting
  static TvPlayerBuilders get productionPlayerBuilders => _productionPlayer;

  /// Replaces the player builders; gating on TV and Live TV still applies.
  @visibleForTesting
  static set playerBuildersForTesting(TvPlayerBuilders value) => _player = value;

  /// Intercepts the selected replacement, including null (upstream fallback),
  /// so navigator tests can avoid mounting the full upstream home.
  @visibleForTesting
  static Widget? Function(Widget? replacement)? profileHomeBuilderForTesting;

  static PageRoute<bool>? showDetailRoute({
    required MediaItem metadata,
    bool isOffline = false,
    bool? enabled,
    int? initialSeasonIndex,
    String? initialSeasonId,
    String? initialEpisodeId,
  }) {
    if (!(enabled ?? TvUi.enabled) || isOffline) return null;
    final Widget Function() page;
    switch (metadata.kind) {
      case MediaKind.show:
        page = () => TvShowScreen(
          metadata: metadata,
          initialSeasonIndex: initialSeasonIndex,
          initialSeasonId: initialSeasonId,
          initialEpisodeId: initialEpisodeId,
        );
      case MediaKind.movie:
        page = () => TvMovieScreen(metadata: metadata);
      default:
        return null;
    }
    return PageRouteBuilder<bool>(
      opaque: true,
      pageBuilder: (_, _, _) => page(),
      transitionsBuilder: (_, animation, _, child) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic),
        child: child,
      ),
      transitionDuration: AppDurations.animMedium,
      reverseTransitionDuration: AppDurations.animMedium,
    );
  }

  /// S14 C1 — the opaque post-play route laid over the finishing player.
  static PageRoute<void> postPlayRoute(TvPostPlayArgs args) =>
      TvPostPlayRoute(builder: (_) => TvPostPlayScreen(args: args));

  /// Replaces [postPlayRoute] in [exitToPostPlay], for player tests.
  @visibleForTesting
  static PageRoute<void> Function(TvPostPlayArgs args)? postPlayRouteForTesting;

  /// S14 C2 — accepts Plezy's [exit] and, only when this call made the exit
  /// accepted ([exitPending] turned true), lays the post-play screen over the
  /// player; Plezy then removes only the player route. Nothing happens when
  /// an exit was already accepted or [exit] declined (a prompt dismissed).
  static void exitToPostPlay({
    required BuildContext context,
    required MediaItem watched,
    MediaItem? next,
    required bool Function() exitPending,
    required Future<void> Function() exit,
  }) => tvExitToPostPlay(
    context: context,
    watched: watched,
    next: next,
    exitPending: exitPending,
    exit: exit,
    route: postPlayRouteForTesting ?? postPlayRoute,
  );

  /// Pass a captured [enabled] value when the choice belongs to a session.
  static Widget? profileHome(
    BuildContext context, {
    bool? enabled,
    required bool isOfflineMode,
    required bool initialPromptHandled,
  }) {
    final replacement = (enabled ?? TvUi.enabled)
        ? TvShell(isOfflineMode: isOfflineMode, initialPromptHandled: initialPromptHandled)
        : null;
    final builder = profileHomeBuilderForTesting;
    return builder == null ? replacement : builder(replacement);
  }

  // Player (S9). Every lookup is synchronous; null/false keeps Plezy. Active
  // only on TV and never for Live TV (R1).

  static bool _playerActive({required bool isLive}) => TvUi.enabled && !isLive;

  /// Live TV as seen from inside the controls (the skip button sits under
  /// [PlexVideoControls]); screen-level overlays pass `isLive` explicitly.
  static bool _isLiveContext(BuildContext context) =>
      context.findAncestorWidgetOfExactType<PlexVideoControls>()?.isLive ?? false;

  /// H1 — the panel in place of `DesktopVideoControls`.
  static Widget? playerPanel(BuildContext context, TvPlayerPanelArgs args, {required bool isLive}) {
    if (!_playerActive(isLive: isLive)) return null;
    final builder = _player.panel;
    if (builder == null) return null;
    TvPlayerSession.of(args.plezy.player).bindItem(args.plezy.metadata.globalKey);
    return builder(context, args);
  }

  /// H2 — the skip button's look.
  static Widget? playerSkipButton(BuildContext context, SkipMarkerButton plezy) {
    final builder = _player.skipButton;
    if (builder == null || !_playerActive(isLive: _isLiveContext(context))) return null;
    return builder(context, plezy);
  }

  /// H3 — true when the panel owns the remote and a marker must not take focus.
  static bool playerPanelOwnsRemote({required bool isLive, required bool controlsVisible}) {
    final builder = _player.panelOwnsRemote;
    if (builder == null || !_playerActive(isLive: isLive)) return false;
    return builder(controlsVisible: controlsVisible);
  }

  /// H4 — the content of the play-next card inside Plezy's shell.
  static Widget? playerUpNextCard(BuildContext context, VideoPlayerPlayNextOverlay plezy, {required bool isLive}) {
    final builder = _player.upNextCard;
    if (builder == null || !_playerActive(isLive: isLive)) return null;
    return builder(context, plezy);
  }

  /// H5 — the buffering indicator.
  static Widget? playerBuffering(BuildContext context, VideoPlayerBufferingOverlay plezy, {required bool isLive}) {
    final builder = _player.buffering;
    if (builder == null || !_playerActive(isLive: isLive)) return null;
    return builder(context, plezy);
  }

  /// H6 — the playback error screen.
  static Widget? playerPlaybackError(TvPlaybackErrorArgs args, {required bool isLive}) {
    final builder = _player.playbackError;
    if (builder == null || !_playerActive(isLive: isLive)) return null;
    return builder(args);
  }

  /// H7 — the pause layer in the player stack.
  static Widget? playerPauseIndicator({
    required Player? player,
    required PlayerChromeController chromeController,
    required bool promptOpen,
    required bool Function() canControl,
    required bool isLive,
  }) {
    final builder = _player.pauseIndicator;
    if (player == null || builder == null || !_playerActive(isLive: isLive)) return null;
    return builder(player, chromeController, promptOpen: promptOpen, canControl: canControl);
  }

  // Post-play (S14). H8 and H9 keep Plezy's exit unless R1 holds on TV.

  /// H9 — the post-play exit layer beside H7: binds the end state for H8 and
  /// takes the last Back step for the post-play screen (C4).
  static Widget? playerPostPlayExit({
    required Player? player,
    required PlayerChromeController chromeController,
    required TvPlayerEndProbe probe,
    required bool isLive,
  }) {
    if (player == null || !_playerActive(isLive: isLive)) return null;
    return TvPostPlayExitLayer(
      player: player,
      chromeController: chromeController,
      probe: probe,
      exitToPostPlay: exitToPostPlay,
      tv: () => TvUi.enabled,
    );
  }

  /// H8, start of an accepted EOF — records an end by the sleep timer (C3).
  static void playerVideoCompleted(
    Player? player, {
    required bool latched,
    required MediaItem item,
    required bool isLive,
  }) {
    if (player == null || !_playerActive(isLive: isLive)) return;
    tvPostPlayVideoCompleted(player, latched: latched, item: item);
  }

  /// H8, Plezy's `exit` branch: true when the post-play path took the exit
  /// (R1 case a); false keeps Plezy's `_handleBackButton`.
  static bool playerExitAtEnd(Player? player, {required bool isLive}) {
    if (player == null || !_playerActive(isLive: isLive)) return false;
    final binding = TvPlayerSession.of(player).endBinding;
    if (binding == null || !binding.allowed) return false;
    binding.exit();
    return true;
  }
}
