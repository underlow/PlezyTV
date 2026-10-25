import '../../utils/formatters.dart';

/// Fork-owned English templates for TV components and screens.
abstract final class TvStrings {
  static const noConnection = 'No connection to server';
  static const noConnectionHelp = 'Check that your server is on and your TV is connected to the same network.';
  static const retry = 'Retry';
  static const homeEmpty = 'Nothing here yet';
  static const refresh = 'Refresh';
  static const libraryReorderHint = 'Left: move up · Right: move down';
  static const ascending = 'Ascending';
  static const descending = 'Descending';
  static const exclude = 'Exclude';
  static const folderEmpty = 'Folder is empty';
  static const defaultSort = 'Default';
  static const refreshLibrary = 'Refresh library';
  static const libraryNoMatches = 'Nothing matches the filters';
  static String libraryEmpty(String name) => 'Nothing in “$name” yet';
  static const connecting = 'Connecting…';
  static const connectionSettings = 'Connection settings';
  static const connectionFailed = 'Could not connect to the server';
  static const all = 'All';
  static const continueWatching = 'Continue Watching';
  static const moreLibraries = 'More';
  static const moreActions = 'More';
  static const showDownloads = 'Show downloads';
  static const onServer = 'On server';
  static String seasons(int count) => '$count ${count == 1 ? 'season' : 'seasons'}';
  static String episodes(int count) => '$count ${count == 1 ? 'episode' : 'episodes'}';
  static String spoilerEpisode({required int season, required int episode, required String title}) =>
      'S$season, E$episode: $title';
  static const watch = 'Watch';
  static const rewatch = 'Rewatch';
  static String continueLeft(int remainingMs) => remainingMs > 0 ? 'Continue · ${left(remainingMs)}' : 'Continue';
  static String director(String names) => 'Director: $names';
  static const studio = 'Studio';
  static const audio = 'Audio';
  static const subtitles = 'Subtitles';
  static const file = 'File';
  static const movieUnavailable = 'This movie is no longer available';
  static String left(int milliseconds) => '${formatDurationTextual(milliseconds)} left';
  static String unwatched(int count) => '$count unwatched';
  static const playerUpNextInQueue = 'Up next in queue';
  static const playerPanel = 'Panel';
  static const playerMore = 'More';
  static const playerMoreDescription = 'Other playback settings';
  static const playerDirectPlay = 'No transcoding';
  static String playerTranscoding(int? kbps) {
    if (kbps == null) return 'Transcoding';
    final mbps = kbps / 1000;
    return 'Transcoding · ${mbps == mbps.roundToDouble() ? mbps.toStringAsFixed(0) : mbps.toStringAsFixed(1)} Mbps';
  }

  static const playerSyncStep = '←/→ · 50 ms step';
  static String playerQueueNow(int remainingMs) => remainingMs > 0 ? 'Now · ${left(remainingMs)}' : 'Now';
  static String playerQueueMore({required int count}) => '$count more';
  static String playerQueueMoreEpisodes({required int? season, required int count}) {
    final more = '$count more ${count == 1 ? 'episode' : 'episodes'}';
    return season == null ? more : 'Season $season · $more';
  }

  static String episode({required int season, required int episode, required String title}) =>
      '${formatSeasonEpisodeLabel(season, episode)} · $title';
}
