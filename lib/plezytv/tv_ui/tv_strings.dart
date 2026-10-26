import '../../i18n/app_locale_utils.dart';
import 'package:intl/intl.dart';
import '../../i18n/strings.g.dart';
import '../../utils/formatters.dart';

/// Fork-owned English templates for TV components and screens.
abstract final class TvStrings {
  static String sortBy(String field) => 'Sort: $field';
  static String date(String value) {
    final parsed = DateTime.tryParse(value);
    return parsed == null ? value : DateFormat('d MMM y', LocaleSettings.currentLocale.intlLocaleName).format(parsed);
  }

  static const transferBackup = 'Backup';
  static const transferExport = 'Export settings';
  static const transferImport = 'Import settings';
  static const transferConfirm = 'Replace settings from plezytv-settings.json? This cannot be undone.';
  static const transferNoUser = 'Sign in before transferring settings.';
  static const transferFileMissing = 'Settings file not found: plezytv-settings.json';
  static const transferInvalidFile = 'Invalid or unsupported settings file.';
  static const transferStorageUnavailable = 'External app storage is unavailable.';
  static const transferFailed = 'Could not transfer settings. Check the settings file and storage.';
  static String transferExported(String path) => 'Settings exported to $path';
  static String transferImported(int count) => 'Imported $count settings';
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
  static const catalogOpen = 'Open';
  static const catalogNotOnServer = 'Not on server';
  static const catalogCouldNotCheck = 'Couldn’t check';
  static const catalogChooseCopy = 'Choose a copy';
  static const watchlist = 'Watchlist';
  static const watchlistSource = 'Source';
  static const watchlistTabAll = 'All';
  static const watchlistTabMovies = 'Movies';
  static const watchlistTabShows = 'Shows';
  static const watchlistTabOnServer = 'On server';
  static const watchlistSortAdded = 'Date added';
  static const watchlistSortTitle = 'Title';
  static const watchlistSortYear = 'Year';
  static const watchlistSortRating = 'Rating';
  static const watchlistGenres = 'Genres';
  static const watchlistDecades = 'Decades';
  static String watchlistDecade(int decade) => '${decade}s';
  static const watchlistNoMovies = 'No movies in your watchlist';
  static const watchlistNoShows = 'No shows in your watchlist';
  static const watchlistNothingOnServer = 'Nothing from your watchlist is on the server';
  static const watchlistChecking = 'Checking what’s on the server…';
  static const watchlistEmpty = 'Your watchlist is empty';
  static const watchlistEmptyHelp =
      'Add movies and shows with “Watchlist” on their card — they appear here even if they are not on the server yet.';
  static const watchlistGoToSearch = 'Go to search';
  static const watchlistLoadFailed = 'Couldn’t load the watchlist';
  static const watchlistLoadFailedHelp = 'Check your internet connection and try again.';
  static String watchlistOnServerCaption(String caption) => caption.isEmpty ? onServer : '$onServer · $caption';
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
  static const reviews = 'Reviews';
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

  static const playerPaused = 'Paused';
  static String playerNextEpisodeIn(int seconds) => 'Next episode in $seconds s';
  static String playerSyncStep(int stepMs) => '←/→ · $stepMs ms step';
  static String playerQueueNow(int remainingMs) => remainingMs > 0 ? 'Now · ${left(remainingMs)}' : 'Now';
  static String playerQueueMore({required int count}) => '$count more';
  static String playerQueueMoreEpisodes({required int? season, required int count}) {
    final more = '$count more ${count == 1 ? 'episode' : 'episodes'}';
    return season == null ? more : 'Season $season · $more';
  }

  static String episode({required int season, required int episode, required String title}) =>
      '${formatSeasonEpisodeLabel(season, episode)} · $title';
}
