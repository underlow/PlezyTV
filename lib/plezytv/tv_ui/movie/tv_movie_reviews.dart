import '../../../services/plex_client.dart';
import '../../../utils/media_server_http_client.dart';

enum TvMovieReviewFreshness { fresh, rotten }

/// A critic's review, owned by one movie page.
class TvMovieReview {
  const TvMovieReview({required this.text, this.source, this.tag, this.freshness});

  final String? source;
  final String? tag;
  final String text;
  final TvMovieReviewFreshness? freshness;
}

typedef TvMovieReviewsLoader = Future<List<TvMovieReview>> Function(String id, AbortController abort);

/// Reads only the reviews on the first Plex metadata item, preserving order.
List<TvMovieReview> parseTvMovieReviews(Object? data) {
  if (data is! Map) return const [];
  final container = data['MediaContainer'];
  if (container is! Map) return const [];
  final metadata = container['Metadata'];
  if (metadata is! List || metadata.isEmpty || metadata.first is! Map) return const [];
  final reviews = (metadata.first as Map)['Review'];
  if (reviews is! List) return const [];
  String? field(Object? value) => value is String && value.trim().isNotEmpty ? value : null;
  return List.unmodifiable([
    for (final review in reviews)
      if (review is Map)
        if (field(review['text']) case final String text)
          if (field(review['source']) != null || field(review['tag']) != null)
            TvMovieReview(
              source: field(review['source']),
              tag: field(review['tag']),
              text: text,
              freshness: switch (field(review['image'])) {
                final String image when image.endsWith('review.fresh') => TvMovieReviewFreshness.fresh,
                final String image when image.endsWith('review.rotten') => TvMovieReviewFreshness.rotten,
                _ => null,
              },
            ),
  ]);
}

/// Each call owns its transport. Cancellation closes it immediately; completion
/// and the total request deadline also close it, including during body parsing.
Future<List<TvMovieReview>> loadTvMovieReviews(
  PlexClient client,
  String id,
  AbortController abort, {
  Duration timeout = const Duration(seconds: 10),
  MediaServerHttpClient Function(String baseUrl, Map<String, String> headers)? httpFactory,
}) async {
  MediaServerHttpClient? http;
  try {
    if (abort.isAborted || client.isOfflineMode) return const [];
    final config = client.config;
    final transport = http = httpFactory == null
        ? MediaServerHttpClient(baseUrl: config.baseUrl, defaultHeaders: config.headers)
        : httpFactory(config.baseUrl, config.headers);
    final request = transport.get(
      '/library/metadata/${Uri.encodeComponent(id)}',
      queryParameters: {'includeReviews': 1},
      timeout: timeout,
      abort: abort,
    );
    final response = await Future.any<MediaServerResponse?>([
      request,
      abort.trigger.then((_) => null),
    ]).timeout(timeout);
    if (abort.isAborted || response == null || response.statusCode < 200 || response.statusCode >= 300) return const [];
    return parseTvMovieReviews(response.data);
  } catch (_) {
    return const [];
  } finally {
    http?.close();
  }
}
