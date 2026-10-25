import '../../../media/media_hub.dart';
import '../../../media/media_item.dart';
import '../../../media/media_kind.dart';
import '../../../utils/formatters.dart';

/// Input of the post-play screen (S14 C1).
class TvPostPlayArgs {
  const TvPostPlayArgs({required this.watched, this.next, required this.playerRemoved});

  /// The item that just finished (`_currentMetadata`).
  final MediaItem watched;

  /// The episode Plezy would offer next (`_episode.next`), if any.
  final MediaItem? next;

  /// Completes when Plezy has removed the old player route; an error counts
  /// as removed.
  final Future<void> playerRemoved;
}

/// Layout of the screen (R3, R4, R5).
enum TvPostPlayVariant { episode, movie, showEnded }

TvPostPlayVariant tvPostPlayVariant(MediaItem watched, MediaItem? next) {
  if (next != null) return TvPostPlayVariant.episode;
  return watched.kind == MediaKind.episode ? TvPostPlayVariant.showEnded : TvPostPlayVariant.movie;
}

/// "Similar": the related hub whose identifier mentions `similar`, else the
/// first non-empty one; null when there is nothing to show.
MediaHub? tvPostPlaySimilarHub(List<MediaHub> hubs) {
  final candidates = hubs.where((h) => h.items.isNotEmpty).toList();
  for (final hub in candidates) {
    if ((hub.identifier ?? '').toLowerCase().contains('similar')) return hub;
  }
  return candidates.isEmpty ? null : candidates.first;
}

/// Episodes of [next]'s season that come after it (R3 row).
List<MediaItem> tvPostPlayEpisodesAfter(List<MediaItem> season, MediaItem next) {
  final at = season.indexWhere((e) => e.id == next.id);
  if (at >= 0) return season.sublist(at + 1);
  final index = next.index;
  if (index == null) return const [];
  return season.where((e) => (e.index ?? -1) > index).toList();
}

/// Plezy's 0–10 user rating as star half-units.
int tvPostPlayRatingUnits(double? userRating) =>
    userRating == null || userRating <= 0 ? 0 : userRating.round().clamp(0, 10);

/// The series an episode belongs to, built from the episode's own fields
/// until the server item arrives.
MediaItem tvPostPlayShowOf(MediaItem episode) => MediaItem(
  id: episode.grandparentId ?? '',
  backend: episode.backend,
  kind: MediaKind.show,
  title: episode.grandparentTitle,
  thumbPath: episode.grandparentThumbPath,
  serverId: episode.serverId,
  serverName: episode.serverName,
  libraryId: episode.libraryId,
  libraryTitle: episode.libraryTitle,
);

/// "S2 E1 · Title" (or just the title when numbers are missing).
String tvPostPlayEpisodeLabel(MediaItem episode) {
  final label = formatSeasonEpisodeLabel(episode.parentIndex, episode.index);
  final title = episode.title ?? '';
  if (label == null) return title;
  return title.isEmpty ? label : '$label · $title';
}

abstract final class TvPostPlayStrings {
  static const youWatched = 'You watched';
  static String youWatchedEpisode(MediaItem episode) => 'You watched ${tvPostPlayEpisodeLabel(episode)}';
  static const upNext = 'Up next';
  static String watchEpisode(MediaItem episode) {
    final label = formatSeasonEpisodeLabel(episode.parentIndex, episode.index);
    return label == null ? 'Watch' : 'Watch $label';
  }

  static const toShow = 'Go to show';
  static const backToMovie = 'Back to movie';
  static const watchAgain = 'Watch again';
  static const yourRating = 'Your rating';
  static const similar = 'Similar';
  static String markedWatched(int? durationMs) =>
      (durationMs ?? 0) > 0 ? 'Marked as watched · ${formatDurationTextual(durationMs!)}' : 'Marked as watched';
  static String season(int? number) => number == null ? 'Season' : 'Season $number';
  static String moreEpisodes(int count) => '$count more ${count == 1 ? 'episode' : 'episodes'}';
}
