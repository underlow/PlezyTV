import '../../../i18n/strings.g.dart';
import '../../../media/episode_collection.dart';
import '../../../media/media_item.dart';
import '../tv_strings.dart';
import '../../../utils/formatters.dart';

class TvShowPrimaryAction {
  final MediaItem episode;
  final bool restart;
  const TvShowPrimaryAction(this.episode, {this.restart = false});
  int? get startPositionMs => restart ? 0 : episode.viewOffsetMs;
  String get label {
    if (restart) return 'Rewatch';
    final number = 'S${episode.parentIndex ?? 1} E${episode.index ?? 1}';
    if ((episode.viewOffsetMs ?? 0) > 0) {
      final remaining = (episode.durationMs ?? 0) - episode.viewOffsetMs!;
      return 'Continue $number${remaining > 0 ? ' · ${TvStrings.left(remaining)}' : ''}';
    }
    return 'Watch $number';
  }
}

/// Call with all regular episodes, or with [complete] false while paging.
TvShowPrimaryAction? tvShowPrimaryAction({
  MediaItem? onDeck,
  required List<MediaItem> episodes,
  required bool complete,
  MediaItem? firstEpisode,
}) {
  if (onDeck != null) return TvShowPrimaryAction(onDeck);
  final regular = episodes.where((e) => !isSpecialSeasonNumber(e.parentIndex)).toList();
  final unwatched = firstUnwatchedEpisode(regular);
  if (unwatched != null) return TvShowPrimaryAction(unwatched);
  final first = firstEpisode ?? regular.firstOrNull;
  if (first == null) return null;
  return TvShowPrimaryAction(first, restart: complete);
}

int tvShowInitialTab(
  List<MediaItem> seasons, {
  bool flattened = false,
  String? seasonId,
  int? seasonIndex,
  String? episodeId,
}) {
  if (seasonId == null && seasonIndex == null && episodeId == null) return 0;
  if (flattened) return 1;
  return preferredSeasonIndex(seasons, initialSeasonId: seasonId, initialSeasonIndex: seasonIndex) + 1;
}

MediaItem? tvShowFocusEpisode(List<MediaItem> episodes, {String? initialEpisodeId, String? lastEpisodeId}) {
  final id = lastEpisodeId ?? initialEpisodeId;
  return episodes.where((e) => e.id == id).firstOrNull ?? firstUnwatchedEpisode(episodes) ?? episodes.firstOrNull;
}

String tvShowMetadata(MediaItem show, List<MediaItem> seasons) => [
  if (show.year != null) '${show.year}',
  if (seasons.isNotEmpty) TvStrings.seasons(seasons.length),
  if (show.leafCount != null) TvStrings.episodes(show.leafCount!),
  if (show.contentRating?.isNotEmpty == true) show.contentRating!,
  if (show.studio?.isNotEmpty == true) show.studio!,
  ...?show.genres?.where((genre) => genre.trim().isNotEmpty),
].join(' · ');

String? tvShowWatchedProgress(MediaItem episode) => episode.hasActiveProgress && episode.durationMs != null
    ? 'Watched ${formatDurationTextual(episode.viewOffsetMs ?? 0)} of ${formatDurationTextual(episode.durationMs!)}'
    : null;

MediaItem? tvShowPrimaryTrailer(MediaItem show, List<MediaItem> extras) {
  if (show case PlexMediaItem(:final trailerKey?)) {
    final primary = extras.where((e) => e.id == trailerKey.split('/').last).firstOrNull;
    if (primary != null) return primary;
  }
  return extras.where((extra) {
    if (extra case PlexMediaItem(:final subtype?)) return subtype.toLowerCase() == 'trailer';
    return '${extra.raw?['ExtraType']}'.toLowerCase() == 'trailer' ||
        '${extra.raw?['Type']}'.toLowerCase() == 'trailer';
  }).firstOrNull;
}

/// A server may repeat the series title for unnamed seasons.
String tvShowSeasonTitle(MediaItem season, MediaItem show) {
  final title = season.title?.trim() ?? '';
  return title.isEmpty || title == show.title?.trim() ? t.common.seasonNumber(number: season.index ?? 1) : title;
}
