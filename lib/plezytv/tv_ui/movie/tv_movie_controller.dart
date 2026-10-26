import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../media/media_hub.dart';
import '../../../media/media_item.dart';
import '../../../media/media_rating.dart';
import '../../../media/media_server_client.dart';
import '../../../media/media_version.dart';
import '../../../media/media_version_preference.dart';
import '../../../providers/catalog_sources_provider.dart';
import '../../../services/plex_client.dart';
import '../../../utils/media_server_http_client.dart';
import '../../../services/catalog/community_ratings.dart';
import '../../../services/catalog/library_watchlist_candidates.dart';
import '../../../utils/deletion_notifier.dart';
import '../../../utils/video_player_navigation.dart';
import '../../../utils/watch_state_notifier.dart';
import '../../../widgets/media_rating_badge.dart';
import '../show/tv_show_logic.dart';
import 'tv_movie_logic.dart';
import 'tv_movie_reviews.dart';

/// Screen-owned data for the TV movie page. The client/provider stay owned by
/// the session; the screen owns focus, scroll and actions.
class TvMovieController extends ChangeNotifier {
  TvMovieController({
    required this.client,
    required MediaItem metadata,
    this.catalogSources,
    this.reviewsLoader,
    Future<MediaVersionPreference?> Function(MediaItem movie)? versionPreference,
    Stream<WatchStateEvent>? watchEvents,
    Stream<DeletionEvent>? deletionEvents,
  }) : movie = metadata,
       _initial = metadata,
       _versionPreference = versionPreference ?? savedMediaVersionPreferenceFor {
    _watchSubscription = (watchEvents ?? WatchStateNotifier().stream).listen(applyWatchEvent);
    _deletionSubscription = (deletionEvents ?? DeletionNotifier().stream).listen(applyDeletionEvent);
  }

  final MediaServerClient client;
  final CatalogSourcesProvider? catalogSources;
  final Future<MediaVersionPreference?> Function(MediaItem movie) _versionPreference;
  final MediaItem _initial;
  final TvMovieReviewsLoader? reviewsLoader;
  final AbortController _reviewsAbort = AbortController();
  bool _reviewsStarted = false;
  List<TvMovieReview> _reviews = const [];

  List<TvMovieReview> get reviews => _reviews;

  /// Passed metadata until the full item arrives, then the server item.
  MediaItem movie;
  List<MediaItem> extras = [];
  List<MediaHub> relatedHubs = [];
  List<MediaRatingSource> communityRatings = [];
  List<WatchlistCandidate> watchlistCandidates = [];
  MediaVersionPreference? versionPreference;

  /// True while a refresh is in flight.
  bool loading = false;

  /// Full metadata has been received at least once (R10: skeletons until then).
  bool metadataLoaded = false;

  /// Extras/hubs settled for the current refresh (rows may show skeletons until then).
  bool rowsLoaded = false;

  /// Watchlist candidates are still loading; the watchlist button stays inactive.
  bool watchlistLoading = false;

  /// Route result: watch state changed while the page was open.
  bool watchStateChanged = false;

  /// Server reported the movie missing, or it was deleted from the server.
  bool deleted = false;

  /// Last metadata failure; [movie] keeps the passed data.
  Object? error;

  int _generation = 0;
  bool _disposed = false;
  final List<WatchStateEvent> _pendingWatchEvents = [];
  StreamSubscription<WatchStateEvent>? _watchSubscription;
  StreamSubscription<DeletionEvent>? _deletionSubscription;
  StreamSubscription<List<MediaRatingSource>>? _ratingsSubscription;

  List<MediaRatingSource> get ratings => withCommunityRatings(mediaRatingsFor(movie), communityRatings);
  MediaItem? get trailer => tvShowPrimaryTrailer(movie, extras);
  TvMoviePrimaryAction get primaryAction => tvMoviePrimaryAction(movie);
  List<MediaVersion> get versions => movie.mediaVersions ?? const [];
  int get versionIndex => tvMovieVersionIndex(versions, versionPreference);
  MediaVersion? get selectedVersion => versions.isEmpty ? null : versions[versionIndex];
  List<TvMovieInfoLine> get techInfo => tvMovieTechInfo(movie, versionIndex: versionIndex);
  String? get director => tvMovieDirector(movie);

  bool _current(int generation) => !_disposed && generation == _generation;

  Future<void> load() => refresh();

  /// Reloads metadata and rows; a newer call supersedes an older one.
  Future<void> refresh() async {
    if (_disposed || deleted) return;
    final generation = ++_generation;
    _pendingWatchEvents.clear();
    loading = true;
    rowsLoaded = false;
    error = null;
    notifyListeners();
    await _ratingsSubscription?.cancel();
    _ratingsSubscription = null;
    if (!_current(generation)) return;
    unawaited(_loadVersionPreference(generation));
    try {
      final result = await client.fetchItemWithOnDeck(
        movie.id,
        onItemReady: (item) {
          if (_current(generation)) _publish(item);
        },
      );
      if (!_current(generation)) return;
      final item = result.item;
      if (item == null) {
        deleted = true;
      } else {
        _publish(item);
      }
    } catch (failure) {
      if (_current(generation)) error = failure;
    }
    if (!_current(generation)) return;
    if (deleted) {
      loading = false;
      notifyListeners();
      return;
    }
    final sources = catalogSources;
    if (sources != null) {
      _ratingsSubscription = sources.communityRatingsForLibraryItem(movie, client: client).listen((value) {
        if (!_current(generation)) return;
        communityRatings = value;
        notifyListeners();
      }, onError: (Object _) {});
      watchlistLoading = true;
      unawaited(
        sources
            .watchlistCandidatesFor(movie, client: client)
            .then((value) {
              if (_current(generation)) watchlistCandidates = value;
            }, onError: (Object _) {})
            .whenComplete(() {
              if (!_current(generation)) return;
              watchlistLoading = false;
              notifyListeners();
            }),
      );
    }
    final values = await Future.wait<Object>([
      client.fetchExtras(movie.id).catchError((Object _) => <MediaItem>[]),
      client.fetchRelatedHubs(movie.id).catchError((Object _) => <MediaHub>[]),
    ]);
    if (!_current(generation)) return;
    extras = values[0] as List<MediaItem>;
    relatedHubs = values[1] as List<MediaHub>;
    rowsLoaded = true;
    loading = false;
    notifyListeners();
  }

  Future<void> _loadVersionPreference(int generation) async {
    final value = await _versionPreference(movie).catchError((Object _) => null);
    if (!_current(generation)) return;
    versionPreference = value;
    notifyListeners();
  }

  void _publish(MediaItem item) {
    var next = item.copyWith(
      serverId: _initial.serverId ?? item.serverId,
      serverName: _initial.serverName ?? item.serverName,
      libraryId: item.libraryId ?? _initial.libraryId,
      libraryTitle: item.libraryTitle ?? _initial.libraryTitle,
    );
    for (final event in _pendingWatchEvents) {
      next = _patch(next, event);
    }
    movie = next;
    metadataLoaded = true;
    notifyListeners();
    _startReviews();
  }

  void _startReviews() {
    if (_disposed || _reviewsStarted) return;
    _reviewsStarted = true;
    final plex = client;
    if (plex is! PlexClient || plex.isOfflineMode) return;
    unawaited(_loadReviews(reviewsLoader ?? (id, abort) => loadTvMovieReviews(plex, id, abort)));
  }

  Future<void> _loadReviews(TvMovieReviewsLoader loader) async {
    try {
      final value = await loader(movie.id, _reviewsAbort);
      if (_disposed || _reviewsAbort.isAborted || value.isEmpty) return;
      _reviews = List.unmodifiable(value);
      notifyListeners();
    } catch (_) {
      // Reviews are optional; failures leave the page unchanged.
    }
  }

  bool _matches(String serverId, String itemId) => itemId == movie.id && serverId == movie.serverId;

  /// Applies Plezy watch events for this movie (from this or other screens).
  void applyWatchEvent(WatchStateEvent event) {
    if (_disposed || !_matches(event.serverId.toString(), event.itemId)) return;
    watchStateChanged = true;
    _pendingWatchEvents.add(event);
    movie = _patch(movie, event);
    notifyListeners();
  }

  /// Server-side deletion closes the page; download-only deletion does not.
  void applyDeletionEvent(DeletionEvent event) {
    if (_disposed || deleted || event.isDownloadOnly || !_matches(event.serverId.toString(), event.itemId)) return;
    deleted = true;
    ++_generation;
    loading = false;
    notifyListeners();
  }

  MediaItem _patch(MediaItem item, WatchStateEvent event) {
    var updated = event.isNowWatched == null ? item : item.withWatchedFlag(event.isNowWatched!);
    if (event.viewOffset != null) {
      updated = updated.copyWith(viewOffsetMs: event.viewOffset);
    } else if (event.isNowWatched != null) {
      updated = updated.copyWith(viewOffsetMs: 0);
    }
    return updated;
  }

  @override
  void dispose() {
    _disposed = true;
    _reviewsAbort.abort();
    ++_generation;
    unawaited(_watchSubscription?.cancel());
    unawaited(_deletionSubscription?.cancel());
    unawaited(_ratingsSubscription?.cancel());
    super.dispose();
  }
}
