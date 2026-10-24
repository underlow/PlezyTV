import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../media/episode_collection.dart';
import '../../../media/media_backend.dart';
import '../../../media/media_hub.dart';
import '../../../media/media_item.dart';
import '../../../media/media_kind.dart';
import '../../../media/media_rating.dart';
import '../../../media/media_server_client.dart';
import '../../../providers/catalog_sources_provider.dart';
import '../../../services/catalog/community_ratings.dart';
import '../../../services/catalog/library_watchlist_candidates.dart';
import '../../../services/plex_client.dart';
import '../../../utils/plex_season_display.dart';
import '../../../utils/watch_state_notifier.dart';
import '../../../widgets/media_rating_badge.dart';
import 'tv_show_logic.dart';

/// Screen-owned orchestration. The client/provider remain owned by the session.
class TvShowController extends ChangeNotifier {
  TvShowController({
    required this.client,
    required MediaItem metadata,
    this.catalogSources,
    this.libraryPrefs,
    Stream<WatchStateEvent>? watchEvents,
    this.pageSize = 50,
  }) : show = metadata {
    _watchSubscription = (watchEvents ?? WatchStateNotifier().stream).listen(applyWatchEvent);
  }
  final MediaServerClient client;
  final CatalogSourcesProvider? catalogSources;
  final Future<Map<String, dynamic>> Function(String libraryId)? libraryPrefs;
  final int pageSize;
  MediaItem show;
  MediaItem? onDeckEpisode;
  List<MediaItem> seasons = [];
  List<MediaItem> extras = [];
  List<MediaHub> relatedHubs = [];
  List<MediaRatingSource> communityRatings = [];
  List<WatchlistCandidate> watchlistCandidates = [];
  final Map<String, List<MediaItem>> _episodes = {};
  final Map<String, int?> _totals = {};
  final Set<String> _complete = {};
  final Set<String> _paging = {};
  final Map<String, Object> pageErrors = {};
  bool flattened = false;
  bool loading = false;
  bool watchStateChanged = false;
  Object? error;
  int _generation = 0;
  bool _disposed = false;
  final List<WatchStateEvent> _pendingWatchEvents = [];
  StreamSubscription<WatchStateEvent>? _watchSubscription;
  StreamSubscription<List<MediaRatingSource>>? _ratingsSubscription;

  List<MediaRatingSource> get ratings => withCommunityRatings(mediaRatingsFor(show), communityRatings);
  MediaItem? get trailer => tvShowPrimaryTrailer(show, extras);
  List<MediaItem> episodesFor(String key) => List.unmodifiable(_episodes[key] ?? const <MediaItem>[]);
  bool isComplete(String key) => _complete.contains(key);
  bool isLoadingEpisodes(String key) => _paging.contains(key);
  int? episodeTotal(String key) => _totals[key];
  String get flattenedKey => show.id;
  bool _current(int generation) => !_disposed && generation == _generation;

  TvShowPrimaryAction? get primaryAction {
    final regularSeasons = seasons.where((s) => !isSpecialSeasonNumber(s.index)).toList();
    final keys = flattened ? [flattenedKey] : regularSeasons.map((s) => s.id).toList();
    final episodes = [for (final key in keys) ...episodesFor(key)];
    final defaultSeason = defaultPlaybackSeason(seasons);
    final defaultEpisodes = episodesFor(flattened ? flattenedKey : defaultSeason?.id ?? '');
    final first = flattened
        ? defaultEpisodes.where((e) => !isSpecialSeasonNumber(e.parentIndex)).firstOrNull ?? defaultEpisodes.firstOrNull
        : defaultEpisodes.firstOrNull;
    return tvShowPrimaryAction(
      onDeck: onDeckEpisode,
      episodes: episodes,
      complete: keys.every(isComplete),
      firstEpisode: first,
    );
  }

  Future<void> load() => refresh();

  /// Reload every already loaded page, preserving the cache until replacement.
  Future<void> refresh() async {
    final generation = ++_generation;
    final previousLengths = {
      for (final key in _paging) key: 0,
      for (final e in _episodes.entries) e.key: e.value.length,
    };
    _paging.clear();
    pageErrors.clear();
    _pendingWatchEvents.clear();
    loading = true;
    error = null;
    notifyListeners();
    await _ratingsSubscription?.cancel();
    try {
      if (!_current(generation)) return;
      final result = await client.fetchItemWithOnDeck(show.id);
      if (!_current(generation)) return;
      if (result.item == null) throw StateError('Show not found');
      show = _applyPending(result.item!);
      onDeckEpisode = result.onDeckEpisode == null ? null : _applyPending(result.onDeckEpisode!);
      notifyListeners();
      final sources = catalogSources;
      if (sources != null) {
        _ratingsSubscription = sources.communityRatingsForLibraryItem(show, client: client).listen((value) {
          if (!_current(generation)) return;
          communityRatings = value;
          notifyListeners();
        }, onError: (Object _) {});
      }
      // Same dependency order as Plezy: metadata first, then independent rows.
      final values = await Future.wait<Object>([
        client.fetchChildren(show.id),
        _prefs().catchError((_) => <String, dynamic>{}),
        client.fetchExtras(show.id),
        client.fetchRelatedHubs(show.id),
        sources?.watchlistCandidatesFor(show, client: client) ?? Future.value(<WatchlistCandidate>[]),
      ]);
      if (!_current(generation)) return;
      seasons = (values[0] as List<MediaItem>)
          .where((s) => s.kind == MediaKind.season)
          .map(
            (season) => _applyPending(
              season.copyWith(
                serverId: show.serverId,
                serverName: show.serverName,
                parentId: show.id,
                libraryId: season.libraryId ?? show.libraryId,
                libraryTitle: season.libraryTitle ?? show.libraryTitle,
              ),
            ),
          )
          .toList();
      flattened = client.backend == MediaBackend.plex
          ? shouldShowPlexEpisodesDirectly(
              show: show,
              seasons: seasons,
              libraryPrefs: values[1] as Map<String, dynamic>,
            )
          : seasons.length <= 1;
      extras = values[2] as List<MediaItem>;
      relatedHubs = values[3] as List<MediaHub>;
      watchlistCandidates = values[4] as List<WatchlistCandidate>;
      _episodes.clear();
      _complete.clear();
      _totals.clear();
      final keys = flattened ? [flattenedKey] : seasons.map((s) => s.id).toList();
      final defaultKey = flattened ? flattenedKey : defaultPlaybackSeason(seasons)?.id;
      for (final key in keys) {
        if (key != defaultKey && !previousLengths.containsKey(key)) continue;
        do {
          await _loadPage(key, generation);
          if (!_current(generation)) return;
        } while (!isComplete(key) && episodesFor(key).length < (previousLengths[key] ?? pageSize));
      }
      // Resolve the first regular unwatched target without mistaking unloaded
      // episodes (or unwatched specials) for a completely watched show.
      if (onDeckEpisode == null) {
        for (final key in keys) {
          if (!flattened && isSpecialSeasonNumber(seasons.firstWhere((s) => s.id == key).index)) continue;
          while (_current(generation)) {
            if (firstUnwatchedEpisode(episodesFor(key).where((e) => !isSpecialSeasonNumber(e.parentIndex)).toList()) !=
                null) {
              break;
            }
            if (isComplete(key)) break;
            await _loadPage(key, generation);
          }
          if (!_current(generation)) return;
          if (firstUnwatchedEpisode(episodesFor(key).where((e) => !isSpecialSeasonNumber(e.parentIndex)).toList()) !=
              null) {
            break;
          }
        }
      }
    } catch (failure) {
      if (_current(generation)) error = failure;
    } finally {
      if (_current(generation)) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<Map<String, dynamic>> _prefs() async {
    final id = show.libraryId;
    if (client.backend != MediaBackend.plex || id == null) return {};
    if (libraryPrefs != null) return libraryPrefs!(id);
    if (client is PlexClient) return (client as PlexClient).getLibrarySectionPrefs(id);
    return {};
  }

  Future<void> loadMoreEpisodes(String key) async {
    if (_disposed || loading || _paging.contains(key) || isComplete(key)) return;
    final generation = _generation;
    try {
      await _loadPage(key, generation);
    } catch (failure) {
      if (_current(generation)) pageErrors[key] = failure;
    }
    if (_current(generation)) notifyListeners();
  }

  Future<void> _loadPage(String key, int generation) async {
    if (!_current(generation)) return;
    _paging.add(key);
    pageErrors.remove(key);
    notifyListeners();
    try {
      final start = _episodes[key]?.length ?? 0;
      final season = seasons.where((s) => s.id == key).firstOrNull;
      final page = flattened
          ? await client.fetchPlayableDescendantsPage(show.id, start: start, size: pageSize)
          : await fetchSeasonEpisodePage(client, show: show, season: season!, start: start, size: pageSize);
      if (!_current(generation)) return;
      _episodes[key] = [
        ...?_episodes[key],
        ...page.items.map(
          (episode) => _applyPending(
            flattened
                ? episode.copyWith(
                    serverId: show.serverId,
                    serverName: show.serverName,
                    grandparentId: show.id,
                    grandparentTitle: show.title,
                    libraryId: episode.libraryId ?? show.libraryId,
                    libraryTitle: episode.libraryTitle ?? show.libraryTitle,
                  )
                : episode,
          ),
        ),
      ];
      _totals[key] = page.totalCount;
      if (page.items.isEmpty || start + page.items.length >= page.totalCount) {
        _complete.add(key);
      }
    } finally {
      if (_current(generation)) {
        _paging.remove(key);
        notifyListeners();
      }
    }
  }

  /// Accepts the same server-qualified hierarchical watch events as Plezy.
  void applyWatchEvent(WatchStateEvent event) {
    if (_disposed ||
        event.serverId.toString() != show.serverId ||
        (event.itemId != show.id && !event.parentChain.contains(show.id))) {
      return;
    }
    watchStateChanged = true;
    _pendingWatchEvents.add(event);
    MediaItem patch(MediaItem item) => _patch(item, event);

    show = patch(show);
    seasons = seasons.map(patch).toList();
    for (final key in _episodes.keys.toList()) {
      _episodes[key] = _episodes[key]!.map(patch).toList();
    }
    seasons = [
      for (final season in seasons)
        if (!flattened && isComplete(season.id))
          season.copyWith(viewedLeafCount: episodesFor(season.id).where((e) => e.isWatched).length)
        else
          season,
    ];
    if (flattened && isComplete(flattenedKey)) {
      show = show.copyWith(viewedLeafCount: episodesFor(flattenedKey).where((e) => e.isWatched).length);
    } else if (seasons.isNotEmpty && seasons.every((s) => s.viewedLeafCount != null)) {
      show = show.copyWith(viewedLeafCount: seasons.fold<int>(0, (sum, s) => sum + s.viewedLeafCount!));
    }
    if (onDeckEpisode != null) {
      onDeckEpisode = patch(onDeckEpisode!);
      if (onDeckEpisode!.isWatched && !onDeckEpisode!.hasActiveProgress) onDeckEpisode = null;
    }
    notifyListeners();
  }

  MediaItem _applyPending(MediaItem item) {
    for (final event in _pendingWatchEvents) {
      item = _patch(item, event);
    }
    return item;
  }

  MediaItem _patch(MediaItem item, WatchStateEvent event) {
    if (item.id != event.itemId && item.parentId != event.itemId && item.grandparentId != event.itemId) return item;
    var updated = event.isNowWatched == null ? item : item.withWatchedFlag(event.isNowWatched!);
    if (event.viewOffset != null && item.id == event.itemId) {
      updated = updated.copyWith(viewOffsetMs: event.viewOffset);
    } else if (event.isNowWatched != null) {
      updated = updated.copyWith(viewOffsetMs: 0);
    }
    return updated;
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    unawaited(_watchSubscription?.cancel());
    unawaited(_ratingsSubscription?.cancel());
    super.dispose();
  }
}
