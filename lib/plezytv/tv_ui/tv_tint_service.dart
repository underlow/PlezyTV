import 'dart:io';
import 'dart:ui' as ui;

import 'package:cached_network_image_ce/cached_network_image.dart' show FileInfo;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../../media/media_item.dart';
import '../../media/media_server_client.dart';
import '../../services/image_cache_service.dart';
import 'tv_tokens.dart';

/// Local paths are supplied by the download/local-artwork owner, as with
/// OptimizedMediaImage. Offline sources never attempt a server request.
class TvArtworkSource {
  const TvArtworkSource({
    required this.item,
    this.client,
    this.offline = false,
    this.localPosterPath,
    this.localBackdropPath,
  });
  final MediaItem item;
  final MediaServerClient? client;
  final bool offline;
  final String? localPosterPath;
  final String? localBackdropPath;
  String get cacheKey => '${item.backend.name}:${item.serverId ?? client?.serverId}:${item.id}';
}

typedef TvArtworkFetch = Future<Uint8List?> Function(TvArtworkSource source, bool backdrop, int width);
typedef TvArtworkDecode = Future<ui.Image> Function(Uint8List bytes, int width);

Future<Uint8List?> fetchTvArtwork(TvArtworkSource source, bool backdrop, int width) async {
  final local = backdrop ? source.localBackdropPath : source.localPosterPath;
  if (local != null && await File(local).exists()) return File(local).readAsBytes();
  if (source.offline || source.client == null) return null;
  final path = backdrop ? source.item.artPath : source.item.thumbPath;
  if (path == null || path.isEmpty) return null;
  final url = source.client!.thumbnailUrl(
    path,
    width: width,
    height: backdrop ? (width * 720 / 1280).round() : width,
    cover: false,
  );
  if (url.isEmpty) return null;
  await for (final response in PlexImageCacheManager.instance.getFileStream(url)) {
    if (response is FileInfo) return response.file.readAsBytes();
  }
  return null;
}

Future<ui.Image> decodeTvArtwork(Uint8List bytes, int width) async {
  final codec = await ui.instantiateImageCodec(bytes, targetWidth: width, allowUpscaling: false);
  try {
    return (await codec.getNextFrame()).image;
  } finally {
    codec.dispose();
  }
}

/// Quantized histogram rather than a mean: neutral borders cannot wash out the
/// dominant artwork hue. Executed in a worker isolate by [TvTintService].
int? dominantTvTint(Uint8List rgba) {
  final bins = <int, (int, double, double, double)>{};
  for (var i = 0; i + 3 < rgba.length; i += 4) {
    if (rgba[i + 3] < 128) continue;
    final r = rgba[i], g = rgba[i + 1], b = rgba[i + 2];
    final max = [r, g, b].reduce((a, b) => a > b ? a : b);
    final min = [r, g, b].reduce((a, b) => a < b ? a : b);
    if (max < 30 || min > 225 || max - min < 24) continue;
    final key = (r >> 4) << 8 | (g >> 4) << 4 | b >> 4;
    final old = bins[key] ?? (0, 0.0, 0.0, 0.0);
    bins[key] = (old.$1 + 1, old.$2 + r, old.$3 + g, old.$4 + b);
  }
  if (bins.isEmpty) return null;
  final bin = bins.values.reduce((a, b) => a.$1 >= b.$1 ? a : b);
  final hsl = HSLColor.fromColor(
    Color.fromARGB(255, (bin.$2 / bin.$1).round(), (bin.$3 / bin.$1).round(), (bin.$4 / bin.$1).round()),
  );
  // Leave one channel step of headroom so 8-bit rounding also obeys the
  // HSL bounds when callers inspect the returned Color.
  return hsl
      .withSaturation(hsl.saturation.clamp(0, TvTokens.color.bg.tintSaturationMax - .01))
      .withLightness(
        hsl.lightness.clamp(
          TvTokens.color.bg.tintLightnessRange[0] + .002,
          TvTokens.color.bg.tintLightnessRange[1] - .002,
        ),
      )
      .toColor()
      .toARGB32();
}

class TvTintService {
  TvTintService({this.fetch = fetchTvArtwork, this.decode = decodeTvArtwork, this.capacity = 256})
    : assert(capacity > 0 && capacity <= 512);
  static final shared = TvTintService();
  final TvArtworkFetch fetch;
  final TvArtworkDecode decode;
  final int capacity;
  final Map<String, Color?> _cache = <String, Color?>{};
  final _pending = <String, Future<Color?>>{};

  Future<Color?> tintFor(TvArtworkSource source) {
    final key = source.cacheKey;
    if (_cache.containsKey(key)) {
      final value = _cache.remove(key);
      _cache[key] = value;
      return Future.value(value);
    }
    return _pending.putIfAbsent(
      key,
      () => _load(source).then((color) {
        _pending.remove(key);
        _cache[key] = color;
        while (_cache.length > capacity) {
          _cache.remove(_cache.keys.first);
        }
        return color;
      }),
    );
  }

  Future<Color?> _load(TvArtworkSource source) async {
    try {
      final bytes = await fetch(source, false, 64);
      if (bytes == null) return null;
      final image = await decode(bytes, 64);
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
        if (data == null) return null;
        final value = await compute(dominantTvTint, data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
        return value == null ? null : Color(value);
      } finally {
        image.dispose();
      }
    } catch (_) {
      return null;
    }
  }
}
