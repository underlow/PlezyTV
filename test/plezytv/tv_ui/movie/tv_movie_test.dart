import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_hub.dart';
import 'package:plezy/media/ids.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_part.dart';
import 'package:plezy/media/media_stream.dart';
import 'package:plezy/media/media_version.dart';
import 'package:plezy/media/media_version_preference.dart';
import 'package:plezy/plezytv/tv_ui/movie/tv_movie_controller.dart';
import 'package:plezy/plezytv/tv_ui/movie/tv_movie_logic.dart';
import 'package:plezy/media/media_rating.dart';
import 'package:plezy/media/media_server_client.dart';
import 'package:plezy/models/catalog/catalog_item.dart';
import 'package:plezy/providers/catalog_sources_provider.dart';
import 'package:plezy/services/catalog/library_watchlist_candidates.dart';
import 'package:plezy/services/jellyfin_mappers.dart';
import 'package:plezy/utils/deletion_notifier.dart';
import 'package:plezy/utils/formatters.dart';
import 'package:plezy/utils/watch_state_notifier.dart';
import '../show/fake_media_server_client.dart';
import '../show/tv_show_actions_test.dart' show Source;

class FakeSources extends ChangeNotifier implements CatalogSourcesProvider {
  final ratings = StreamController<List<MediaRatingSource>>.broadcast();
  final candidates = Completer<List<WatchlistCandidate>>();
  @override
  Stream<List<MediaRatingSource>> communityRatingsForLibraryItem(
    MediaItem item, {
    required MediaServerClient? client,
  }) => ratings.stream;
  @override
  Future<List<WatchlistCandidate>> watchlistCandidatesFor(MediaItem item, {required MediaServerClient? client}) =>
      candidates.future;
  @override
  void dispose() {
    unawaited(ratings.close());
    super.dispose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MediaItem movie({MediaBackend backend = MediaBackend.jellyfin, int? viewCount, int? offset}) => MediaItem(
  id: 'm',
  backend: backend,
  kind: MediaKind.movie,
  title: 'Movie',
  serverId: ServerId('server'),
  durationMs: 7200000,
).copyWith(viewCount: viewCount, viewOffsetMs: offset);

MediaStream stream(String id, MediaStreamKind kind, {String? language, String? displayTitle}) =>
    MediaStream(id: id, kind: kind, language: language, displayTitle: displayTitle);

void main() {
  group('primary action', () {
    test('progress shows Continue with Plezy remaining-time format and resumes', () {
      final action = tvMoviePrimaryAction(movie(offset: 7200000 - 4800000));
      expect(action.label, 'Continue · ${formatDurationTextual(4800000)} left');
      expect(action.startPositionMs, 2400000);
      expect(action.resume, true);
    });
    test('no progress is Watch; watched without progress is Rewatch from start', () {
      expect(tvMoviePrimaryAction(movie()).label, 'Watch');
      final rewatch = tvMoviePrimaryAction(movie(viewCount: 1));
      expect(rewatch.label, 'Rewatch');
      expect(rewatch.startPositionMs, 0);
      expect(tvMoviePrimaryAction(movie(viewCount: 1, offset: 600000)).label, startsWith('Continue · '));
    });
    test('player launch: Watch and Continue let Plezy resolve; Rewatch restarts from zero', () {
      expect(tvMoviePlayerLaunch(tvMoviePrimaryAction(movie())), (resolveWatchState: true, initialPosition: null));
      expect(tvMoviePlayerLaunch(tvMoviePrimaryAction(movie(offset: 600000))), (
        resolveWatchState: true,
        initialPosition: null,
      ));
      expect(tvMoviePlayerLaunch(tvMoviePrimaryAction(movie(viewCount: 1))), (
        resolveWatchState: false,
        initialPosition: Duration.zero,
      ));
    });
  });

  test('version index follows remembered choice, else first', () {
    const versions = [
      MediaVersion(id: 'a', videoResolution: '1080', videoCodec: 'h264'),
      MediaVersion(id: 'b', videoResolution: '4k', videoCodec: 'hevc'),
    ];
    expect(tvMovieVersionIndex(versions, null), 0);
    expect(tvMovieVersionIndex(versions, const MediaVersionPreference(versionId: 'b', index: 0)), 1);
    expect(tvMovieVersionIndex(versions, const MediaVersionPreference(index: 1)), 1);
    expect(tvMovieVersionIndex(versions, const MediaVersionPreference(index: 5)), 0);
    expect(tvMovieVersionIndex(const [], const MediaVersionPreference(index: 1)), 0);
  });

  group('tech info', () {
    test('Plex-like data describes the selected version', () {
      final item = movie(backend: MediaBackend.plex).copyWith(
        studio: 'Studio X',
        mediaVersions: [
          const MediaVersion(id: 'a', videoResolution: '1080', videoCodec: 'h264'),
          MediaVersion(
            id: 'b',
            videoResolution: '2160',
            videoCodec: 'hevc',
            parts: [
              MediaPart(
                id: 'p',
                sizeBytes: 3 * 1024 * 1024 * 1024,
                streams: [
                  stream('v', MediaStreamKind.video),
                  stream('a1', MediaStreamKind.audio, language: 'Russian'),
                  stream('a2', MediaStreamKind.audio, language: 'English'),
                  stream('a3', MediaStreamKind.audio, language: 'English'),
                  stream('s1', MediaStreamKind.subtitle, language: 'English'),
                ],
              ),
            ],
          ),
        ],
      );
      final lines = tvMovieTechInfo(item, versionIndex: 1);
      expect(lines.map((l) => l.label), ['Studio', 'Audio', 'Subtitles', 'File']);
      expect(lines[1].value, 'Russian, English');
      expect(lines[2].value, 'English');
      expect(lines[3].value, '4K · HEVC · ${ByteFormatter.formatBytes(3 * 1024 * 1024 * 1024)}');
      expect(tvMovieTechInfo(item).map((l) => l.label), ['Studio', 'File']);
    });
    test('A16 Jellyfin JSON through the mapper fills the block', () {
      final item = JellyfinMappers.mediaItem(
        {
          'Id': 'm',
          'Name': 'Movie',
          'Type': 'Movie',
          'Studios': [
            {'Name': 'Legendary'},
          ],
          'MediaSources': [
            {
              'Id': 'src',
              'Size': 3 * 1024 * 1024 * 1024,
              'MediaStreams': [
                {'Index': 0, 'Type': 'Video', 'Codec': 'hevc', 'Width': 3840, 'Height': 2160},
                {'Index': 1, 'Type': 'Audio', 'Codec': 'aac', 'Language': 'rus', 'DisplayTitle': 'Russian AAC'},
                {'Index': 2, 'Type': 'Audio', 'Codec': 'ac3', 'Language': 'eng', 'DisplayTitle': 'English AC3'},
              ],
            },
          ],
        },
        serverId: ServerId('server'),
        absolutizer: null,
      )!;
      final lines = {for (final l in tvMovieTechInfo(item)) l.label: l.value};
      expect(lines.keys, ['Studio', 'Audio', 'File']);
      expect(lines['Studio'], 'Legendary');
      expect(
        lines['Audio'],
        allOf(contains(RegExp('rus', caseSensitive: false)), contains(RegExp('eng', caseSensitive: false))),
      );
      expect(lines['File'], '4K · HEVC · ${ByteFormatter.formatBytes(3 * 1024 * 1024 * 1024)}');
      final bare = JellyfinMappers.mediaItem(
        {'Id': 'm', 'Name': 'Movie', 'Type': 'Movie'},
        serverId: ServerId('server'),
        absolutizer: null,
      )!;
      expect(tvMovieTechInfo(bare), isEmpty);
    });
    test('stream without language falls back to its display title; empty fields are hidden', () {
      final item = movie().copyWith(
        mediaVersions: [
          MediaVersion(
            id: 'src',
            height: 1080,
            parts: [
              MediaPart(
                id: 'p',
                streams: [stream('a', MediaStreamKind.audio, displayTitle: 'rus AAC')],
              ),
            ],
          ),
        ],
      );
      final lines = tvMovieTechInfo(item);
      expect(lines.map((l) => (l.label, l.value)), [('Audio', 'rus AAC'), ('File', '1080p')]);
      expect(tvMovieTechInfo(movie()), isEmpty);
    });
  });

  test('director line only when present', () {
    expect(tvMovieDirector(movie()), null);
    expect(tvMovieDirector(movie().copyWith(directors: ['A', 'B'])), 'Director: A, B');
  });

  group('controller', () {
    late FakeShowClient client;
    late StreamController<WatchStateEvent> watch;
    late StreamController<DeletionEvent> deletion;
    TvMovieController create({MediaVersionPreference? preference}) {
      final c = TvMovieController(
        client: client,
        metadata: movie(),
        versionPreference: (_) async => preference,
        watchEvents: watch.stream,
        deletionEvents: deletion.stream,
      );
      addTearDown(c.dispose);
      return c;
    }

    setUp(() {
      client = FakeShowClient()
        ..show = movie().copyWith(summary: 'full', studio: 'S')
        ..extras = [MediaItem(id: 'x', backend: MediaBackend.jellyfin, kind: MediaKind.clip)]
        ..relatedHubs = [MediaHub(id: 'h', title: 'Similar', type: 'movie', items: const [])];
      watch = StreamController<WatchStateEvent>.broadcast(sync: true);
      deletion = StreamController<DeletionEvent>.broadcast(sync: true);
      addTearDown(watch.close);
      addTearDown(deletion.close);
    });

    test('loads metadata, rows and version preference', () async {
      final c = create(preference: const MediaVersionPreference(index: 0));
      expect(c.metadataLoaded, false);
      await c.load();
      expect(c.metadataLoaded, true);
      expect(c.rowsLoaded, true);
      expect(c.loading, false);
      expect(c.movie.summary, 'full');
      expect(c.movie.serverId, 'server');
      expect(c.extras, hasLength(1));
      expect(c.relatedHubs, hasLength(1));
      expect(c.versionPreference, isNotNull);
      expect(c.error, null);
    });

    test('metadata failure keeps passed data', () async {
      client.onFetch = () async => throw Exception('offline');
      final c = create();
      await c.load();
      expect(c.error, isNotNull);
      expect(c.deleted, false);
      expect(c.loading, false);
      expect(c.movie.title, 'Movie');
      expect(c.movie.summary, null);
    });

    test('missing item marks the movie deleted', () async {
      client.onFetch = () async => (item: null, onDeckEpisode: null);
      final c = create();
      await c.load();
      expect(c.deleted, true);
      expect(c.loading, false);
    });

    test('server deletion closes, download-only deletion does not', () async {
      final c = create();
      await c.load();
      deletion.add(
        DeletionEvent(
          itemId: 'm',
          serverId: ServerId('server'),
          parentChain: const [],
          mediaType: 'movie',
          isDownloadOnly: true,
        ),
      );
      expect(c.deleted, false);
      deletion.add(
        DeletionEvent(itemId: 'other', serverId: ServerId('server'), parentChain: const [], mediaType: 'movie'),
      );
      expect(c.deleted, false);
      deletion.add(DeletionEvent(itemId: 'm', serverId: ServerId('server'), parentChain: const [], mediaType: 'movie'));
      expect(c.deleted, true);
    });

    test('watch event updates the movie and route result, also across a refresh', () async {
      final gate = Completer<void>();
      final c = create();
      await c.load();
      expect(c.primaryAction.label, 'Watch');
      expect(c.watchStateChanged, false);
      client.onFetch = () async {
        await gate.future;
        return (item: movie(), onDeckEpisode: null);
      };
      final pending = c.refresh();
      watch.add(
        WatchStateEvent(
          itemId: 'm',
          serverId: ServerId('server'),
          changeType: WatchStateChangeType.watched,
          parentChain: const [],
          isNowWatched: true,
        ),
      );
      expect(c.watchStateChanged, true);
      expect(c.primaryAction.label, 'Rewatch');
      gate.complete();
      await pending;
      expect(c.primaryAction.label, 'Rewatch', reason: 'stale server item must not undo the event');
      watch.add(
        WatchStateEvent(
          itemId: 'other',
          serverId: ServerId('server'),
          changeType: WatchStateChangeType.unwatched,
          parentChain: const [],
          isNowWatched: false,
        ),
      );
      expect(c.movie.isWatched, true);
    });

    test('watchlist candidates and community ratings load from catalog sources', () async {
      final sources = FakeSources();
      addTearDown(sources.dispose);
      final c = TvMovieController(
        client: client,
        metadata: movie(),
        catalogSources: sources,
        versionPreference: (_) async => null,
        watchEvents: watch.stream,
        deletionEvents: deletion.stream,
      );
      addTearDown(c.dispose);
      await c.load();
      expect(c.watchlistLoading, true);
      expect(c.watchlistCandidates, isEmpty);
      final source = Source();
      addTearDown(source.watchlistChanges.dispose);
      sources.candidates.complete([(source: source, ids: const CatalogItemIds(imdb: 'tt1'))]);
      await pumpEventQueue();
      expect(c.watchlistLoading, false);
      expect(c.watchlistCandidates.single.source, same(source));
      sources.ratings.add(const [MediaRatingSource(source: 'imdb', value: 7.9)]);
      await pumpEventQueue();
      expect(c.ratings.map((r) => (r.source, r.value)), contains(('imdb', 7.9)));
    });

    test('a newer refresh wins over an older slow response', () async {
      final slow = Completer<({MediaItem? item, MediaItem? onDeckEpisode})>();
      client.onFetch = () => slow.future;
      final c = create();
      final first = c.load();
      client.onFetch = () async => (item: movie().copyWith(summary: 'new'), onDeckEpisode: null);
      await c.refresh();
      slow.complete((item: movie().copyWith(summary: 'old'), onDeckEpisode: null));
      await first;
      expect(c.movie.summary, 'new');
      expect(c.loading, false);
    });

    test('remembered second version drives selected version and tech info', () async {
      client.show = movie().copyWith(
        mediaVersions: const [
          MediaVersion(id: 'a', videoResolution: '1080'),
          MediaVersion(id: 'b', videoResolution: '4k'),
        ],
      );
      final c = create(preference: const MediaVersionPreference(versionId: 'b', index: 0));
      await c.load();
      await pumpEventQueue();
      expect(c.versionIndex, 1);
      expect(c.selectedVersion!.id, 'b');
      expect(c.techInfo.single.value, '4K');
    });
  });
}
