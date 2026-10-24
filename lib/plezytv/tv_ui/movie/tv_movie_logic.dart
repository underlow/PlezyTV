import '../../../media/media_item.dart';
import '../../../media/media_part.dart';
import '../../../media/media_stream.dart';
import '../../../media/media_version.dart';
import '../../../media/media_version_preference.dart';
import '../../../utils/codec_utils.dart';
import '../../../utils/formatters.dart';
import '../../../utils/resolution_label.dart';
import '../tv_strings.dart';

/// Primary button of the movie page (R3).
class TvMoviePrimaryAction {
  final String label;

  /// Start offset for playback; null lets Plezy pick (resume or start).
  final int? startPositionMs;
  final bool resume;
  final bool restart;
  const TvMoviePrimaryAction({required this.label, this.startPositionMs, this.resume = false, this.restart = false});
}

/// Watch / Continue · {t} left / Rewatch, by Plezy progress and watch state.
TvMoviePrimaryAction tvMoviePrimaryAction(MediaItem movie) {
  if (movie.hasActiveProgress) {
    return TvMoviePrimaryAction(
      label: TvStrings.continueLeft(movie.durationMs! - movie.viewOffsetMs!),
      startPositionMs: movie.viewOffsetMs,
      resume: true,
    );
  }
  if (movie.isWatched) return const TvMoviePrimaryAction(label: TvStrings.rewatch, startPositionMs: 0, restart: true);
  return const TvMoviePrimaryAction(label: TvStrings.watch);
}

/// Version that playback will use: the remembered Plezy choice, else the first.
int tvMovieVersionIndex(List<MediaVersion>? versions, MediaVersionPreference? preference) {
  if (versions == null || versions.isEmpty) return 0;
  return preference?.resolveIndex(versions) ?? 0;
}

/// "Director: A, B" when the item carries directors.
String? tvMovieDirector(MediaItem movie) {
  final names = movie.directors?.where((d) => d.trim().isNotEmpty).toList() ?? const <String>[];
  return names.isEmpty ? null : TvStrings.director(names.join(', '));
}

/// One labelled line of the technical block (R7).
typedef TvMovieInfoLine = ({String label, String value});

String? _streamName(MediaStream s) {
  for (final v in [s.language, s.languageCode, s.displayTitle, s.title]) {
    if (v != null && v.trim().isNotEmpty) return v.trim();
  }
  return null;
}

String? _streams(List<MediaStream> streams, MediaStreamKind kind) {
  final names = <String>[];
  for (final s in streams.where((s) => s.kind == kind)) {
    final name = _streamName(s);
    if (name != null && !names.contains(name)) names.add(name);
  }
  return names.isEmpty ? null : names.join(', ');
}

/// Studio / Audio / Subtitles / File lines for the version at [versionIndex];
/// missing fields are omitted, an empty list means the block is hidden.
List<TvMovieInfoLine> tvMovieTechInfo(MediaItem movie, {int versionIndex = 0}) {
  final versions = movie.mediaVersions ?? const <MediaVersion>[];
  final version = versions.isEmpty ? null : versions[versionIndex.clamp(0, versions.length - 1)];
  final streams = <MediaStream>[for (final part in version?.parts ?? const <MediaPart>[]) ...part.streams];
  final size = version?.parts.fold<int>(0, (sum, p) => sum + (p.sizeBytes ?? 0)) ?? 0;
  final resolution = version?.videoResolution?.isNotEmpty == true
      ? resolutionDisplayLabel(version!.videoResolution!)
      : version?.height != null
      ? '${version!.height}p'
      : null;
  final codec = version?.videoCodec?.isNotEmpty == true ? CodecUtils.formatVideoCodec(version!.videoCodec!) : null;
  final file = [?resolution, ?codec, if (size > 0) ByteFormatter.formatBytes(size)].join(' · ');
  final audio = _streams(streams, MediaStreamKind.audio);
  final subtitles = _streams(streams, MediaStreamKind.subtitle);
  return [
    if (movie.studio?.trim().isNotEmpty == true) (label: TvStrings.studio, value: movie.studio!.trim()),
    if (audio != null) (label: TvStrings.audio, value: audio),
    if (subtitles != null) (label: TvStrings.subtitles, value: subtitles),
    if (file.isNotEmpty) (label: TvStrings.file, value: file),
  ];
}
