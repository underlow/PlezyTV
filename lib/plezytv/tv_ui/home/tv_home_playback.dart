import 'package:flutter/widgets.dart';

import '../../../media/episode_collection.dart';
import '../../../media/media_item.dart';
import '../../../media/media_kind.dart';
import '../../../media/media_server_client.dart';
import '../../../utils/media_navigation_helper.dart';
import '../../../utils/provider_extensions.dart';
import '../../../utils/video_player_navigation.dart';

/// Play/Pause intent, independent of the settings used for card activation.
/// Navigation callbacks complete when the destination route returns.
class TvHomePlayback {
  const TvHomePlayback({required this.clientForItem, required this.play, required this.openDetails});

  factory TvHomePlayback.forContext(BuildContext context) => TvHomePlayback(
    clientForItem: context.getMediaClientForItemOrNull,
    play: (item) async {
      if (context.mounted) await navigateToVideoPlayer(context, metadata: item);
    },
    openDetails: (item) async {
      if (context.mounted) await navigateToMediaItem(context, item);
    },
  );

  final MediaServerClient? Function(MediaItem item) clientForItem;
  final Future<void> Function(MediaItem item) play;
  final Future<void> Function(MediaItem item) openDetails;

  Future<void> activate(MediaItem item) async {
    if (item.kind == MediaKind.movie || item.kind == MediaKind.episode) {
      // Preserve the offset; the player also resolves fresh session watch state.
      await play(item);
      return;
    }
    MediaItem? episode;
    if (item.kind == MediaKind.show || item.kind == MediaKind.season) {
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
            episode = await fetchFirstEpisodeForSeason(client, item.id, seriesId: item.parentId);
          }
        }
      } catch (_) {
        // A failed lookup has the same fallback as an empty show/season.
      }
    }
    if (episode?.kind == MediaKind.episode) {
      await play(episode!.copyWith(serverId: item.serverId, serverName: item.serverName ?? episode.serverName));
    } else {
      await openDetails(item);
    }
  }
}
