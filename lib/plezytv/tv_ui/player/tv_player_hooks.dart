import 'package:flutter/widgets.dart';

import '../../../mpv/mpv.dart';
import '../../../screens/video_player/widgets/player_prompt_overlays.dart';
import '../../../widgets/video_controls/desktop_video_controls.dart';
import '../../../widgets/video_controls/player_chrome_controller.dart';
import '../../../widgets/video_controls/widgets/skip_marker_button.dart';

/// Everything H1 hands the TV panel: the [DesktopVideoControls] Plezy built
/// (all of its public inputs; never mounted, so its key stays unused — D7)
/// plus the `PlexVideoControls` state the desktop layout does not receive.
@immutable
class TvPlayerPanelArgs {
  const TvPlayerPanelArgs({
    required this.plezy,
    required this.canControl,
    required this.canNavigateMediaItems,
    required this.playbackPromptOpen,
    required this.playNextFocusNode,
    required this.isOfflinePlayback,
    required this.skipMarkerFocusNode,
  });

  final DesktopVideoControls plezy;
  final bool canControl;
  final bool canNavigateMediaItems;
  final bool playbackPromptOpen;
  final FocusNode? playNextFocusNode;
  final bool isOfflinePlayback;
  final FocusNode skipMarkerFocusNode;
}

/// What H6 hands the TV error screen: Plezy's text, actions and focus node.
@immutable
class TvPlaybackErrorArgs {
  const TvPlaybackErrorArgs({
    required this.message,
    required this.onRetry,
    required this.retryFocusNode,
    required this.onBack,
  });

  final String message;
  final VoidCallback onRetry;
  final FocusNode retryFocusNode;
  final VoidCallback onBack;
}

/// Builders behind the player lookups H1–H7. A null builder (or null result)
/// keeps Plezy's widget. Gating on TV and Live TV happens in `TvUi`.
@immutable
class TvPlayerBuilders {
  const TvPlayerBuilders({
    this.panel,
    this.skipButton,
    this.panelOwnsRemote,
    this.upNextCard,
    this.buffering,
    this.playbackError,
    this.pauseIndicator,
  });

  /// H1 — replaces `DesktopVideoControls`.
  final Widget? Function(BuildContext context, TvPlayerPanelArgs args)? panel;

  /// H2 — replaces the look of `SkipMarkerButton`.
  final Widget? Function(BuildContext context, SkipMarkerButton plezy)? skipButton;

  /// H3 — true keeps the skip button from taking focus.
  final bool Function({required bool controlsVisible})? panelOwnsRemote;

  /// H4 — the content inside Plezy's play-next shell.
  final Widget? Function(BuildContext context, VideoPlayerPlayNextOverlay plezy)? upNextCard;

  /// H5 — replaces the buffering spinner.
  final Widget? Function(BuildContext context, VideoPlayerBufferingOverlay plezy)? buffering;

  /// H6 — replaces `_buildPlaybackFailure`.
  final Widget? Function(TvPlaybackErrorArgs args)? playbackError;

  /// H7 — an extra layer in the player stack.
  final Widget? Function(Player player, PlayerChromeController chromeController)? pauseIndicator;
}
