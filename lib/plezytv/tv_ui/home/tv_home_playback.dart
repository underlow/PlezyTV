import 'package:flutter/material.dart';

import '../../../media/episode_collection.dart';
import '../../../media/media_item.dart';
import '../../../media/media_kind.dart';
import '../../../media/media_server_client.dart';
import '../../../utils/media_navigation_helper.dart';
import '../../../utils/dialogs.dart';
import '../../../utils/app_logger.dart';
import '../../../utils/provider_extensions.dart';
import '../../../utils/video_player_navigation.dart';

/// Play/Pause intent, independent of the settings used for card activation.
/// Navigation callbacks complete when the destination route returns.
class TvHomePlayback {
  TvHomePlayback({
    required this.clientForItem,
    required this.play,
    required this.openDetails,
    bool Function()? isCurrent,
    this.beginLookup,
    this.endLookup,
  }) : isCurrent = isCurrent ?? (() => true);

  /// Keep one adapter per Home state. [isCurrent] also fences tab changes
  /// inside the shell, which do not change the enclosing navigator route.
  factory TvHomePlayback.forContext(BuildContext context, {bool Function()? isCurrent}) {
    final sourceRoute = ModalRoute.of(context);
    final loading = ScopedLoadingDialogController();
    ModalRoute<dynamic>? loadingRoute;
    var cancelled = false;
    var dismissing = false;
    bool current() =>
        context.mounted &&
        !cancelled &&
        (isCurrent?.call() ?? true) &&
        (loading.isVisible ? loadingRoute?.isCurrent == true : sourceRoute?.isCurrent == true);
    return TvHomePlayback(
      clientForItem: context.getMediaClientForItemOrNull,
      isCurrent: current,
      beginLookup: () async {
        cancelled = false;
        dismissing = false;
        loading.show(
          context,
          onDisposed: () {
            if (!dismissing) cancelled = true;
          },
          builder: (dialogContext) {
            loadingRoute = ModalRoute.of(dialogContext);
            return const Center(child: CircularProgressIndicator());
          },
        );
        await loading.ready;
      },
      endLookup: () async {
        dismissing = true;
        final route = loadingRoute;
        if (route != null && route.isActive && !route.isCurrent) {
          route.navigator?.removeRoute(route);
        }
        await loading.dismiss();
        cancelled = false;
      },
      play: (item) async {
        if (current()) {
          // The predicate is retained by VideoPlayerScreen after the push.
          // Covering Home with the committed player must not cancel that player.
          await navigateToVideoPlayer(
            context,
            metadata: item,
            isLaunchCurrent: () =>
                context.mounted &&
                !cancelled &&
                (isCurrent?.call() ?? true) &&
                sourceRoute?.isActive == true &&
                (sourceRoute!.isCurrent || VideoPlayerRoute.hasActivePlayer(Navigator.of(context))),
          );
        }
      },
      openDetails: (item) async {
        if (current()) await navigateToMediaItem(context, item);
      },
    );
  }

  final bool Function() isCurrent;
  final Future<void> Function()? beginLookup;
  final Future<void> Function()? endLookup;
  bool _inFlight = false;

  final MediaServerClient? Function(MediaItem item) clientForItem;
  final Future<void> Function(MediaItem item) play;
  final Future<void> Function(MediaItem item) openDetails;

  Future<void> activate(MediaItem item) async {
    if (_inFlight || !isCurrent()) return;
    _inFlight = true;
    try {
      await _activate(item);
    } finally {
      _inFlight = false;
    }
  }

  Future<void> _activate(MediaItem item) async {
    if (item.kind == MediaKind.movie || item.kind == MediaKind.episode) {
      // Preserve the offset; the player also resolves fresh session watch state.
      await play(item);
      return;
    }
    MediaItem? episode;
    if (item.kind == MediaKind.show || item.kind == MediaKind.season) {
      await beginLookup?.call();
      try {
        final client = clientForItem(item);
        if (client != null) {
          if (item.kind == MediaKind.show) {
            episode = (await client.fetchItemWithOnDeck(item.id)).onDeckEpisode;
            if (episode == null) {
              final season = defaultPlaybackSeason(await client.fetchChildren(item.id));
              if (season != null) {
                episode = await fetchFirstEpisodeForSeason(client, season.id, seriesId: item.id);
              }
            }
          } else {
            episode = await fetchFirstEpisodeForSeason(client, item.id, seriesId: item.grandparentId ?? item.parentId);
          }
        }
      } catch (error) {
        appLogger.d('Home playback episode lookup failed', error: error);
      }
      // Check before dismissing: a newer route above the spinner cancels launch.
      final launchCurrent = isCurrent();
      await endLookup?.call();
      if (!launchCurrent || !isCurrent()) return;
    }
    if (episode?.kind == MediaKind.episode) {
      await play(episode!.copyWith(serverId: item.serverId, serverName: item.serverName ?? episode.serverName));
    } else {
      await openDetails(item);
    }
  }
}
