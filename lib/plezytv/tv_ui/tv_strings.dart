import '../../utils/formatters.dart';

/// Fork-owned English templates for TV components and screens.
abstract final class TvStrings {
  static const noConnection = 'No connection to server';
  static const noConnectionHelp = 'Check that your server is on and your TV is connected to the same network.';
  static const retry = 'Retry';
  static const connecting = 'Connecting…';
  static const connectionSettings = 'Connection settings';
  static const connectionFailed = 'Could not connect to the server';
  static const all = 'All';
  static const moreLibraries = 'More';
  static const showDownloads = 'Show downloads';
  static const onServer = 'On server';
  static String left(int milliseconds) => '${formatDurationTextual(milliseconds)} left';
  static String unwatched(int count) => '$count unwatched';
  static String episode({required int season, required int episode, required String title}) =>
      '${formatSeasonEpisodeLabel(season, episode)} · $title';
}
