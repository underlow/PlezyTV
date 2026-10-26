import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/models/plex/plex_config.dart';
import 'package:plezy/plezytv/tv_ui/movie/tv_movie_controller.dart';
import 'package:plezy/plezytv/tv_ui/movie/tv_movie_reviews.dart';
import 'package:plezy/services/plex_client.dart';
import 'package:plezy/utils/media_server_http_client.dart';

import '../show/fake_media_server_client.dart';
import 'tv_movie_test.dart' show movie;

class ReviewPlex extends FakeShowClient implements PlexClient {
  @override
  bool isOfflineMode = false;
  @override
  PlexConfig config = PlexConfig(
    baseUrl: 'http://old',
    clientIdentifier: 'test',
    product: 'test',
    version: '1',
    token: 'secret',
  );
}

Object payload(List<Object?> reviews) => {
  'MediaContainer': {
    'Metadata': [
      {'Review': reviews},
    ],
  },
};

const review = TvMovieReview(source: 'Paper', tag: 'Critic', text: 'Full text');

void main() {
  test('Plex Review fields, filters, freshness and server order', () {
    // Field names verified against Python PlexAPI's Review implementation:
    // https://python-plexapi.readthedocs.io/en/stable/_modules/plexapi/media.html#Review
    final parsed = parseTvMovieReviews(
      payload([
        {'source': 'Paper', 'tag': 'Critic', 'text': 'First', 'image': 'rottentomatoes://image.review.fresh'},
        {'source': 'Only paper', 'text': 'Second', 'image': 'rottentomatoes://image.review.rotten'},
        {'tag': 'Only critic', 'text': 'Third', 'image': 'other'},
        {'tag': 'No image', 'text': 'Fourth'},
        {'text': 'No author'},
        {'source': 'No text'},
        {'source': 'Blank', 'text': '  '},
        {'source': ' ', 'tag': '', 'text': 'Blank author'},
        null,
      ]),
    );
    expect(parsed.map((r) => r.text), ['First', 'Second', 'Third', 'Fourth']);
    expect((parsed.first.source, parsed.first.tag), ('Paper', 'Critic'));
    expect(parsed.map((r) => r.freshness), [TvMovieReviewFreshness.fresh, TvMovieReviewFreshness.rotten, null, null]);
    expect(parsed[1].tag, isNull);
    expect(parsed[2].source, isNull);
    expect(() => parsed.add(review), throwsUnsupportedError);
    for (final malformed in [
      null,
      {},
      {'MediaContainer': []},
      payload([]),
      payload([42]),
    ]) {
      expect(parseTvMovieReviews(malformed), isEmpty);
    }
  });

  TvMovieController controller(FakeShowClient client, TvMovieReviewsLoader loader) => TvMovieController(
    client: client..show = movie(),
    metadata: movie(),
    reviewsLoader: loader,
    versionPreference: (_) async => null,
    watchEvents: const Stream.empty(),
    deletionEvents: const Stream.empty(),
  );

  test('starts after first metadata; slow reviews never hold rows; refresh preserves reviews', () async {
    final client = ReviewPlex();
    final gate = Completer<List<TvMovieReview>>();
    var calls = 0;
    late TvMovieController c;
    c = controller(client, (id, abort) {
      expect(c.metadataLoaded, true);
      expect(id, 'm');
      calls++;
      return gate.future;
    });
    addTearDown(c.dispose);
    expect(c.reviews, isEmpty);
    await c.load();
    expect(c.rowsLoaded, true);
    expect(c.loading, false);
    expect(calls, 1);
    var published = false;
    c.addListener(() {
      if (c.reviews.isNotEmpty) published = true;
    });
    gate.complete([review]);
    await pumpEventQueue();
    expect(published, true);
    expect(c.reviews, [review]);
    expect(() => c.reviews.clear(), throwsUnsupportedError);
    await c.refresh();
    await c.refresh();
    expect(calls, 1);
    expect(c.reviews, [review]);
  });

  test('does not request reviews before metadata or after metadata failure', () async {
    final client = ReviewPlex();
    // Keep the full metadata request pending until the assertion below.
    final ready = Completer<void>();
    client.onFetch = () async {
      await ready.future;
      throw StateError('metadata failed');
    };
    var calls = 0;
    final c = controller(client, (_, _) async {
      calls++;
      return [review];
    });
    final loading = c.load();
    await pumpEventQueue();
    expect(calls, 0);
    ready.complete();
    await loading;
    expect(calls, 0);
    expect(c.reviews, isEmpty);
    c.dispose();
  });

  test('non-Plex and offline never call loader', () async {
    for (final client in [FakeShowClient(), ReviewPlex()..isOfflineMode = true]) {
      var calls = 0;
      final checked = controller(client, (_, _) async {
        calls++;
        return [review];
      });
      await checked.load();
      expect(calls, 0);
      expect(checked.reviews, isEmpty);
      checked.dispose();
    }
  });

  test('error and empty response leave other data intact and are not retried', () async {
    for (final fail in [false, true]) {
      var calls = 0;
      final c = controller(ReviewPlex(), (_, _) async {
        calls++;
        if (fail) throw StateError('network');
        return [];
      });
      await c.load();
      await c.refresh();
      expect(calls, 1);
      expect(c.reviews, isEmpty);
      expect(c.error, isNull);
      expect(c.metadataLoaded, true);
      expect(c.rowsLoaded, true);
      expect(c.loading, false);
      c.dispose();
    }
  });

  test('dispose aborts and ignores late response without notification', () async {
    final gate = Completer<List<TvMovieReview>>();
    late AbortController signal;
    final c = controller(ReviewPlex(), (_, abort) {
      signal = abort;
      return gate.future;
    });
    await c.load();
    var notifications = 0;
    c.addListener(() => notifications++);
    c.dispose();
    expect(signal.isAborted, true);
    await signal.trigger;
    gate.complete([review]);
    await pumpEventQueue();
    expect(c.reviews, isEmpty);
    expect(notifications, 0);
  });

  test('loader uses current config, minimal query, parses and closes transport', () async {
    final client = ReviewPlex();
    client.config = client.config.copyWith(baseUrl: 'http://new');
    final transport = TrackingHttp(
      MockClient((request) async {
        expect(request.url.host, 'new');
        expect(request.url.path, '/library/metadata/m');
        expect(request.url.queryParameters, {'includeReviews': '1'});
        expect(request.headers['X-Plex-Token'], 'secret');
        return http.Response(
          '{"MediaContainer":{"Metadata":[{"Review":[{"source":"Paper","text":"Text"}]}]}}',
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    final result = await loadTvMovieReviews(
      client,
      'm',
      AbortController(),
      httpFactory: (base, headers) {
        transport.baseUrl = base;
        transport.defaultHeaders = headers;
        return transport;
      },
    );
    expect(result.single.text, 'Text');
    expect(transport.closed, true);
  });

  test('loader failures, total timeout and cancellation return empty and close', () async {
    for (final mode in ['error', 'format', 'status', 'timeout', 'abort', 'preabort']) {
      final abort = AbortController();
      final transport = TrackingHttp(
        MockClient((_) async {
          if (mode == 'error') throw StateError('network');
          if (mode == 'timeout' || mode == 'abort') return Completer<http.Response>().future;
          return http.Response(
            mode == 'format' ? 'invalid json' : '{}',
            mode == 'status' ? 500 : 200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      if (mode == 'preabort') abort.abort();
      final pending = loadTvMovieReviews(
        ReviewPlex(),
        'm',
        abort,
        timeout: const Duration(milliseconds: 20),
        httpFactory: (base, headers) {
          transport.baseUrl = base;
          return transport;
        },
      );
      if (mode == 'abort') abort.abort();
      expect(await pending, isEmpty, reason: mode);
      expect(transport.closed, mode != 'preabort', reason: mode);
      if (mode == 'preabort') transport.close();
    }
  });
}

class TrackingHttp extends MediaServerHttpClient {
  TrackingHttp(http.Client client) : super(client: client);
  bool closed = false;
  @override
  void close() {
    closed = true;
    super.close();
  }
}
