import '../../utils/formatters.dart';

/// Whole English templates; screen-specific wording belongs to later stages.
abstract final class TvStrings {
  static const showDownloads = 'Show downloads';
  static const onServer = 'On server';
  static String left(int milliseconds) => '${formatDurationTextual(milliseconds)} left';
  static String unwatched(int count) => '$count unwatched';
  static String episode({required int season, required int episode, required String title}) =>
      '${formatSeasonEpisodeLabel(season, episode)} · $title';
}
