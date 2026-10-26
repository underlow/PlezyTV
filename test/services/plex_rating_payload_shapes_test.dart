// Live-payload regression: the exact `/library/metadata/{id}` and
// `/library/sections/{id}/all` shapes a real Plex Media Server returned
// (PMS 1.x, `tv.plex.agents.series`), captured verbatim. Plex sends the
// multi-source `Rating[]` array only on the metadata endpoint — probing
// `includeRatings`, `includeElements=Rating`, and `includeFields=Rating`
// against the listing endpoint all came back without it, while
// `includeGuids=1` demonstrably does add `Guid[]`. That asymmetry is why the
// raw listings carry fewer scores; the TV home hero fetches full metadata.
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/ids.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/services/plex_mappers.dart';

const _serverId = 'plex-machine-1';

PlexMediaItem _mediaItemFromJson(Map<String, dynamic> json, {ServerId? serverId}) {
  return PlexMappers.mediaItem(PlexMetadataDto.fromJsonWithImages(json).copyWith(serverId: serverId));
}

void main() {
  test('attributed array excludes conflicting scalar scores', () {
    final ratings = plexRatingSources(
      rating: 6.8,
      audienceRating: 9.4,
      audienceRatingImage: 'imdb://image.rating',
      ratingSources: [
        (image: 'imdb://image.rating', type: 'audience', value: 6.9),
        (image: 'rottentomatoes://image.rating', type: 'critic', value: 9.4),
        (image: 'rottentomatoes://image.rating', type: 'audience', value: 8.4),
        (image: 'tmdb://image.rating', type: 'audience', value: 6.9),
      ],
    )!;
    expect(ratings.map((r) => r.source), ['imdb', 'rottenTomatoesCritic', 'rottenTomatoesAudience', 'tmdb']);
    expect(ratings.map((r) => r.value), [6.9, 9.4, 8.4, 6.9]);
  });

  group('live Plex payloads', () {
    test('detail response surfaces IMDb alongside Rotten Tomatoes and TMDB', () {
      final item = _mediaItemFromJson({
        'ratingKey': '2254',
        'type': 'show',
        'title': '【OSHI NO KO】',
        'audienceRating': 8.3,
        'audienceRatingImage': 'themoviedb://image.rating',
        'Rating': [
          {'image': 'imdb://image.rating', 'value': 8.3, 'type': 'audience'},
          {'image': 'rottentomatoes://image.rating.upright', 'value': 9.6, 'type': 'audience'},
          {'image': 'themoviedb://image.rating', 'value': 8.3, 'type': 'audience'},
        ],
      }, serverId: ServerId(_serverId));

      // The attributed array supplies the scores in server order.
      expect(item.ratings?.map((rating) => rating.source).toList(), ['imdb', 'rottenTomatoesAudience', 'tmdb']);
      expect(item.ratings?.map((rating) => rating.value).toList(), [8.3, 9.6, 8.3]);
    });

    test('listing response carries only the scalar the server chose', () {
      final item = _mediaItemFromJson({
        'ratingKey': '2254',
        'type': 'show',
        'title': '【OSHI NO KO】',
        'audienceRating': 8.3,
        'audienceRatingImage': 'themoviedb://image.rating',
      }, serverId: ServerId(_serverId));

      expect(item.ratings?.single.source, 'tmdb');
      expect(item.ratings?.single.value, 8.3);
    });
  });
}
