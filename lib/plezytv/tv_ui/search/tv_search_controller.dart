import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../i18n/strings.g.dart';
import '../../../media/media_item.dart';
import '../../../media/media_kind.dart';
import '../../../media/media_person.dart';
import '../../../services/data_aggregation_service.dart';
import '../../../utils/app_logger.dart';
import '../../../utils/media_server_http_client.dart';
import '../../../utils/search_relevance.dart';

/// Thrown by a [TvSearchFn] when no server is connected (as Plezy's
/// `_SearchUnavailableException`).
class TvSearchUnavailable implements Exception {
  const TvSearchUnavailable();
}

typedef TvSearchFn = Future<SearchAggregationResult> Function(String query, AbortController abort);

/// Re-reads [item] from its server, merged as `SearchScreen.updateItem` does;
/// null when it cannot be refreshed.
typedef TvFetchItemFn = Future<MediaItem?> Function(MediaItem item);

enum TvSearchState { idle, loading, results, empty, unavailable }

enum TvSearchKind { movies, shows, episodes, people }

enum TvSearchTab { all, movies, shows, episodes, people }

/// S11 search state (C1): debounce, stale-response guard, kinds, tabs.
class TvSearchController extends ChangeNotifier {
  TvSearchController({required this._search, required this._fetchItem});

  static const Duration debounce = Duration(milliseconds: 300);
  static const Duration skeletonDelay = Duration(milliseconds: 300);
  static const int rowLimit = 20;

  final TvSearchFn _search;
  final TvFetchItemFn _fetchItem;

  String _query = '';
  String _shownQuery = '';
  TvSearchState _state = TvSearchState.idle;
  bool _refining = false;
  bool _showSkeleton = false;
  String? _errorMessage;
  int _partialFailureRevision = 0;
  TvSearchTab _selectedTab = TvSearchTab.all;
  Map<TvSearchKind, List<Object>> _lists = _emptyLists();

  int _generation = 0;
  AbortController? _abort;
  Timer? _debounceTimer;
  Timer? _skeletonTimer;
  bool _disposed = false;

  static Map<TvSearchKind, List<Object>> _emptyLists() => {for (final k in TvSearchKind.values) k: const []};

  String get query => _query;
  String get shownQuery => _shownQuery;
  TvSearchState get state => _state;
  bool get refining => _refining;
  bool get showSkeleton => _showSkeleton;

  /// Plezy's text for `unavailable` (searchUnavailable or searchFailed).
  String? get errorMessage => _errorMessage;
  int get partialFailureRevision => _partialFailureRevision;
  TvSearchTab get selectedTab => _selectedTab;

  /// Ranked items of [kind]: `MediaItem` for media kinds, `MediaPerson` for people.
  List<Object> allOf(TvSearchKind kind) => _lists[kind]!;
  List<Object> rowOf(TvSearchKind kind) => allOf(kind).take(rowLimit).toList();
  int countOf(TvSearchKind kind) => allOf(kind).length;

  List<TvSearchTab> get tabs => _state == TvSearchState.results
      ? [
          TvSearchTab.all,
          for (final kind in TvSearchKind.values)
            if (allOf(kind).isNotEmpty) _tabOf(kind),
        ]
      : const [];

  static TvSearchTab _tabOf(TvSearchKind kind) => TvSearchTab.values.byName(kind.name);

  void selectTab(TvSearchTab tab) {
    if (tab == _selectedTab || !tabs.contains(tab)) return;
    _selectedTab = tab;
    notifyListeners();
  }

  void setQuery(String value) {
    if (value == _query) return;
    _query = value;
    _debounceTimer?.cancel();
    if (value.trim().isEmpty) {
      _reset();
      return;
    }
    _debounceTimer = Timer(debounce, searchNow);
    notifyListeners();
  }

  void clear() {
    _query = '';
    _debounceTimer?.cancel();
    _reset();
  }

  void _reset() {
    _invalidate();
    _state = TvSearchState.idle;
    _refining = false;
    _shownQuery = '';
    _errorMessage = null;
    _selectedTab = TvSearchTab.all;
    _lists = _emptyLists();
    notifyListeners();
  }

  void _invalidate() {
    _generation++;
    _abort?.abort();
    _abort = null;
    _skeletonTimer?.cancel();
    _showSkeleton = false;
  }

  void searchNow() {
    _debounceTimer?.cancel();
    final q = _query.trim();
    if (q.isEmpty || _disposed) return;
    _invalidate();
    final generation = _generation;
    final abort = AbortController();
    _abort = abort;
    if (_state == TvSearchState.results) {
      _refining = true;
    } else {
      _state = TvSearchState.loading;
      _skeletonTimer = Timer(skeletonDelay, () {
        if (generation != _generation || _state != TvSearchState.loading) return;
        _showSkeleton = true;
        notifyListeners();
      });
    }
    notifyListeners();
    unawaited(_run(q, abort, generation));
  }

  Future<void> _run(String q, AbortController abort, int generation) async {
    try {
      final result = await _search(q, abort);
      if (generation != _generation || _disposed) return;
      if (result.succeededServerIds.isEmpty &&
          (result.failedServerIds.isNotEmpty || result.cancelledServerIds.isNotEmpty)) {
        throw const TvSearchUnavailable();
      }
      _apply(q, result);
    } catch (e) {
      if (generation != _generation || _disposed) return;
      if (e is! TvSearchUnavailable) appLogger.w('TvSearch: search failed', error: e);
      _finish();
      _state = TvSearchState.unavailable;
      _errorMessage = e is TvSearchUnavailable ? t.errors.searchUnavailable : t.errors.searchFailed(error: e);
      _shownQuery = q;
      _lists = _emptyLists();
      _selectedTab = TvSearchTab.all;
      notifyListeners();
    }
  }

  void _finish() {
    _abort = null;
    _skeletonTimer?.cancel();
    _showSkeleton = false;
    _refining = false;
  }

  void _apply(String q, SearchAggregationResult result) {
    List<Object> media(MediaKind kind) => rankMediaSearchResults(
      [
        for (final item in result.candidates)
          if (item.kind == kind) item,
      ],
      q,
      limit: defaultMediaSearchLimit,
    );
    _finish();
    _lists = {
      TvSearchKind.movies: media(MediaKind.movie),
      TvSearchKind.shows: media(MediaKind.show),
      TvSearchKind.episodes: media(MediaKind.episode),
      TvSearchKind.people: rankPeopleSearchResults(
        List<MediaPerson>.of(result.people),
        q,
        limit: defaultMediaSearchLimit,
      ),
    };
    _shownQuery = q;
    _errorMessage = null;
    _state = _lists.values.any((l) => l.isNotEmpty) ? TvSearchState.results : TvSearchState.empty;
    if (!tabs.contains(_selectedTab)) _selectedTab = TvSearchTab.all;
    if (result.failedServerIds.isNotEmpty) _partialFailureRevision++;
    notifyListeners();
  }

  /// Re-reads [source] and replaces it in every list.
  Future<void> refreshItem(MediaItem source) async {
    final MediaItem? updated;
    try {
      updated = await _fetchItem(source);
    } catch (e) {
      appLogger.d('TvSearch: item refresh skipped for ${source.globalKey}', error: e);
      return;
    }
    if (updated == null || _disposed) return;
    bool matches(Object item) => item is MediaItem && item.globalKey == source.globalKey;
    if (!_lists.values.any((list) => list.any(matches))) return;
    _lists = {
      for (final entry in _lists.entries) entry.key: [for (final item in entry.value) matches(item) ? updated : item],
    };
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _debounceTimer?.cancel();
    _invalidate();
    super.dispose();
  }
}
