import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../media/media_kind.dart';
import '../../../models/catalog/catalog_item.dart';
import '../../../services/catalog/catalog_source.dart';
import '../../../utils/app_logger.dart';
import 'tv_watchlist_availability.dart';
import 'tv_watchlist_preferences.dart';

export 'tv_watchlist_preferences.dart';

enum TvWatchlistPhase { loading, ready, error }

/// How the grid should treat the latest [TvWatchlistController.view] change.
enum TvWatchlistChange {
  /// Source, tab, sort, filters or first load: focus the first card.
  reset,

  /// Availability, background reload, removal, restore: keep focus by key.
  keepFocus,
}

/// State of the TV «Список» section (S10, plan C3). Lives while the section
/// is mounted.
class TvWatchlistController extends ChangeNotifier {
  TvWatchlistController({
    required this.availability,
    required this.sourcesListenable,
    required this.readSources,
    required TvWatchlistPreferencesStore preferences,
  }) : _store = preferences {
    _sources = _ordered(readSources());
    sourcesListenable.addListener(_onSourcesChanged);
    availability.addListener(_onAvailability);
  }

  static const int maxItems = 1000;
  static const int pageSize = 100;
  static const Duration refetchDelay = Duration(seconds: 1);
  static const Duration membershipRetry = Duration(seconds: 30);

  final TvWatchlistAvailability availability;

  /// Fires when connected sources change (`CatalogSourcesProvider`).
  final Listenable sourcesListenable;

  /// Current watchlist-capable sources (`watchlistCapableSources`).
  final List<CatalogSource> Function() readSources;
  final TvWatchlistPreferencesStore _store;

  List<CatalogSource> _sources = const [];
  CatalogSource? _source;
  Listenable? _subscribed;
  TvWatchlistPreferences? _prefs;
  TvWatchlistPhase _phase = TvWatchlistPhase.loading;
  List<CatalogItem> _all = const [];
  List<CatalogItem> _view = const [];
  TvWatchlistTab _tab = TvWatchlistTab.all;
  TvWatchlistSort _sort = TvWatchlistSort.added;
  TvWatchlistFilters _filters = TvWatchlistFilters.none;
  List<String> _genreOptions = const [];
  List<int> _decadeOptions = const [];
  TvWatchlistChange _lastChange = TvWatchlistChange.reset;
  int _viewRevision = 0;

  int _generation = 0;
  List<CatalogItem>? _orderOf;
  Map<String, int> _order = const {};
  int _seenFoundRevision = 0;
  bool _seenChecking = false;

  /// Membership per item key as of the last list change or notification;
  /// only a true → false flip removes an item (R13).
  Map<String, bool?> _membership = const {};
  bool _snapshotLoaded = false;
  Timer? _refetchTimer;
  Timer? _membershipTimer;
  final Map<String, ({int index, CatalogItem item})> _removed = {};
  bool _disposed = false;

  List<CatalogSource> get sources => _sources;
  CatalogSource? get source => _source;
  TvWatchlistPhase get phase => _phase;
  List<CatalogItem> get all => _all;
  List<CatalogItem> get view => _view;
  TvWatchlistTab get tab => _tab;
  TvWatchlistSort get sort => _sort;
  TvWatchlistFilters get filters => _filters;
  List<String> get genreOptions => _genreOptions;
  List<int> get decadeOptions => _decadeOptions;
  bool get hasMultipleSources => _sources.length > 1;
  TvWatchlistChange get lastChange => _lastChange;

  /// Bumped on every [view] change; pair with [lastChange].
  int get viewRevision => _viewRevision;

  // ---------- Commands ----------

  Future<void> load() async {
    final prefs = _prefs ??= await _store.load();
    if (_disposed) return;
    _tab = prefs.tab;
    _sort = prefs.sort;
    _sources = _ordered(readSources());
    final remembered = _sources.where((s) => s.id.name == prefs.source).firstOrNull;
    await _open(remembered ?? _defaultSource(), keepFilters: true);
  }

  Future<void> retry() => _open(_source ?? _defaultSource(), keepFilters: true);

  Future<void> selectSource(CatalogSource source) async {
    final prefs = _prefs ?? const TvWatchlistPreferences();
    _savePrefs(prefs.copyWith(source: source.id.name, filters: {...prefs.filters}..remove(source.id.name)));
    await _open(source, keepFilters: false);
  }

  void setTab(TvWatchlistTab tab) {
    if (tab == _tab) return;
    _tab = tab;
    _savePrefs((_prefs ?? const TvWatchlistPreferences()).copyWith(tab: tab));
    _rebuild(TvWatchlistChange.reset);
  }

  void setSort(TvWatchlistSort sort) {
    if (sort == _sort) return;
    _sort = sort;
    _savePrefs((_prefs ?? const TvWatchlistPreferences()).copyWith(sort: sort));
    _rebuild(TvWatchlistChange.reset);
  }

  void setFilters(TvWatchlistFilters filters) {
    if (filters == _filters) return;
    _filters = filters;
    _persistFilters();
    _rebuild(TvWatchlistChange.reset);
  }

  /// Resume: re-read silently when ready, otherwise load again.
  Future<void> backgroundRefresh() async {
    if (_phase == TvWatchlistPhase.ready) return _refetch();
    if (_phase == TvWatchlistPhase.error) return retry();
  }

  /// Profile reset: forget everything and load the new profile's choice.
  Future<void> fullReset() {
    _prefs = null;
    _filters = TvWatchlistFilters.none;
    _removed.clear();
    availability.reset();
    return load();
  }

  /// The catalog card removed [item]; drop it without waiting for the network.
  void itemRemoved(CatalogItem item) {
    final key = TvWatchlistAvailability.keyOf(item);
    final index = _all.indexWhere((e) => TvWatchlistAvailability.keyOf(e) == key);
    if (index < 0) return;
    _removed[key] = (index: index, item: _all[index]);
    _setAll([..._all]..removeAt(index), TvWatchlistChange.keepFocus);
  }

  /// The catalog card put [item] back.
  void itemRestored(CatalogItem item) {
    final key = TvWatchlistAvailability.keyOf(item);
    final removed = _removed.remove(key);
    if (_all.any((e) => TvWatchlistAvailability.keyOf(e) == key)) return;
    final index = (removed?.index ?? 0).clamp(0, _all.length);
    _setAll([..._all]..insert(index, removed?.item ?? item), TvWatchlistChange.keepFocus);
  }

  // ---------- Loading ----------

  Future<void> _open(CatalogSource? source, {required bool keepFilters}) async {
    final generation = ++_generation;
    _refetchTimer?.cancel();
    _membershipTimer?.cancel();
    final changedSource = !identical(source, _source);
    _source = source;
    _subscribe(source);
    if (changedSource) _removed.clear();
    _filters = keepFilters ? (_prefs?.filters[source?.id.name] ?? TvWatchlistFilters.none) : TvWatchlistFilters.none;
    _phase = TvWatchlistPhase.loading;
    _all = const [];
    _rebuild(TvWatchlistChange.reset);
    if (source == null) return;
    try {
      final items = await _fetchAll(source);
      if (generation != _generation || _disposed) return;
      _phase = TvWatchlistPhase.ready;
      _snapshotLoaded = _probeSnapshot(source);
      _all = items;
      _recordMembership();
      availability.setItems(items);
      _dropStaleFilters();
      _rebuild(TvWatchlistChange.reset);
      _ensureMembership(source, generation);
    } catch (e) {
      if (generation != _generation || _disposed) return;
      appLogger.w('TV watchlist: load failed for ${source.id.name}', error: e);
      _phase = TvWatchlistPhase.error;
      _rebuild(TvWatchlistChange.reset);
    }
  }

  Future<List<CatalogItem>> _fetchAll(CatalogSource source) async {
    final items = <CatalogItem>[];
    final seen = <String>{};
    var page = 1;
    while (items.length < maxItems) {
      final result = await source.fetchRow(CatalogRowId.watchlist, page: page, limit: pageSize);
      for (final item in result.items) {
        if (seen.add(TvWatchlistAvailability.keyOf(item))) items.add(item);
      }
      if (!result.hasMore || result.items.isEmpty) break;
      page++;
    }
    return items.length > maxItems ? items.sublist(0, maxItems) : items;
  }

  Future<void> _refetch() async {
    final source = _source;
    if (source == null || _phase != TvWatchlistPhase.ready) return;
    final generation = _generation;
    try {
      final items = await _fetchAll(source);
      if (generation != _generation || _disposed) return;
      final keys = {for (final item in items) TvWatchlistAvailability.keyOf(item)};
      _removed.removeWhere((key, _) => !keys.contains(key));
      final visible = items.where((item) => !_removed.containsKey(TvWatchlistAvailability.keyOf(item))).toList();
      _setAll(visible, TvWatchlistChange.keepFocus);
    } catch (e) {
      appLogger.w('TV watchlist: background reload failed', error: e);
    }
  }

  void _ensureMembership(CatalogSource source, int generation) {
    Future<void> attempt() async {
      try {
        await source.ensureWatchlistLoaded();
      } catch (e) {
        appLogger.w('TV watchlist: membership load failed', error: e);
      }
      if (generation != _generation || _disposed) return;
      if (_probeSnapshot(source)) {
        _snapshotLoaded = true;
      } else {
        _membershipTimer?.cancel();
        _membershipTimer = Timer(membershipRetry, attempt);
      }
    }

    unawaited(attempt());
  }

  // ---------- Membership changes (R13) ----------

  static bool _probeSnapshot(CatalogSource source) =>
      source.isOnWatchlist(MediaKind.movie, const CatalogItemIds()) != null;

  void _subscribe(CatalogSource? source) {
    final listenable = source?.watchlistChanges;
    if (identical(listenable, _subscribed)) return;
    _subscribed?.removeListener(_onWatchlistChanged);
    _subscribed = listenable;
    listenable?.addListener(_onWatchlistChanged);
  }

  void _onWatchlistChanged() {
    final source = _source;
    if (source == null || _phase != TvWatchlistPhase.ready) return;
    final wasLoaded = _snapshotLoaded;
    _snapshotLoaded = _probeSnapshot(source);
    if (!_snapshotLoaded) return;
    final previous = _membership;
    _recordMembership();
    final now = _membership;
    // Membership data is loaded once per session, so `false` for an item
    // added on another device may be stale; only a flip is a removal.
    final gone = _all.where((item) {
      final key = TvWatchlistAvailability.keyOf(item);
      return previous[key] == true && now[key] == false;
    }).toList();
    if (gone.isNotEmpty) {
      final goneKeys = {for (final item in gone) TvWatchlistAvailability.keyOf(item)};
      _setAll(
        _all.where((item) => !goneKeys.contains(TvWatchlistAvailability.keyOf(item))).toList(),
        TvWatchlistChange.keepFocus,
      );
    }
    // A first snapshot that agrees with the list is not a change; any other
    // notification may be an addition the snapshot cannot enumerate.
    if (wasLoaded || gone.isNotEmpty) _scheduleRefetch();
  }

  void _recordMembership() {
    final source = _source;
    _membership = {
      for (final item in _all) TvWatchlistAvailability.keyOf(item): source?.isOnWatchlist(item.kind, item.ids),
    };
  }

  void _scheduleRefetch() {
    _refetchTimer?.cancel();
    _refetchTimer = Timer(refetchDelay, () => unawaited(_refetch()));
  }

  // ---------- Sources ----------

  static List<CatalogSource> _ordered(List<CatalogSource> sources) => [
    ...sources.where((s) => s.supportsWatchlist && s.id == CatalogSourceId.plex),
    ...sources.where((s) => s.supportsWatchlist && s.id != CatalogSourceId.plex),
  ];

  CatalogSource? _defaultSource() => _sources.firstOrNull;

  void _onSourcesChanged() {
    final previous = _source;
    _sources = _ordered(readSources());
    if (previous == null || _prefs == null) {
      // Prefs loaded and nothing open (e.g. a reset with no sources): open
      // the first source that appears instead of staying in loading.
      if (previous == null && _prefs != null && _sources.isNotEmpty) {
        unawaited(load());
      } else {
        notifyListeners();
      }
      return;
    }
    final same = _sources.where((s) => s.id == previous.id).firstOrNull;
    if (same == null) {
      // Disconnected: fall back without touching the remembered choice.
      if (_sources.isNotEmpty) {
        unawaited(_open(_defaultSource(), keepFilters: true));
      } else {
        notifyListeners();
      }
    } else if (!identical(same, previous)) {
      _source = same;
      _subscribe(same);
      _snapshotLoaded = _probeSnapshot(same);
      _recordMembership();
      _ensureMembership(same, _generation);
      notifyListeners();
    } else {
      notifyListeners();
    }
  }

  // ---------- View ----------

  /// Only a change in which items are found reshapes «Есть на сервере»;
  /// posters follow their own status ([TvWatchlistAvailability.watch]).
  void _onAvailability() {
    if (_disposed) return;
    final foundRevision = availability.foundRevision;
    final checking = availability.checking;
    final foundChanged = foundRevision != _seenFoundRevision;
    final checkingChanged = checking != _seenChecking;
    _seenFoundRevision = foundRevision;
    _seenChecking = checking;
    if (_tab != TvWatchlistTab.onServer) return;
    if (foundChanged) {
      _rebuild(TvWatchlistChange.keepFocus);
    } else if (checkingChanged) {
      notifyListeners();
    }
  }

  void _setAll(List<CatalogItem> items, TvWatchlistChange change) {
    _all = items;
    _recordMembership();
    availability.setItems(items);
    _recomputeOptions();
    _rebuild(change);
  }

  void _recomputeOptions() {
    final genres = <String>{};
    final decades = <int>{};
    for (final item in _all) {
      genres.addAll(item.genres ?? const []);
      if (item.year case final year?) decades.add(year ~/ 10 * 10);
    }
    _genreOptions = genres.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    _decadeOptions = decades.toList()..sort((a, b) => b.compareTo(a));
  }

  void _dropStaleFilters() {
    _recomputeOptions();
    final kept = TvWatchlistFilters(
      genres: _filters.genres.where(_genreOptions.contains).toSet(),
      decades: _filters.decades.where(_decadeOptions.contains).toSet(),
    );
    if (kept != _filters) {
      _filters = kept;
      _persistFilters();
    }
  }

  void _persistFilters() {
    final name = _source?.id.name;
    if (name == null) return;
    final prefs = _prefs ?? const TvWatchlistPreferences();
    _savePrefs(prefs.copyWith(filters: {...prefs.filters, name: _filters}));
  }

  void _savePrefs(TvWatchlistPreferences prefs) {
    _prefs = prefs;
    unawaited(_store.save(prefs));
  }

  void _rebuild(TvWatchlistChange change) {
    if (_disposed) return;
    _view = _sorted(_all.where(_matches).toList());
    _lastChange = change;
    _viewRevision++;
    notifyListeners();
  }

  bool _matches(CatalogItem item) {
    final tabOk = switch (_tab) {
      TvWatchlistTab.all => true,
      TvWatchlistTab.movies => item.kind == MediaKind.movie,
      TvWatchlistTab.shows => item.kind == MediaKind.show,
      TvWatchlistTab.onServer => availability.statusOf(item) is TvAvailabilityFound,
    };
    if (!tabOk) return false;
    if (_filters.genres.isNotEmpty && !(item.genres ?? const []).any(_filters.genres.contains)) return false;
    if (_filters.decades.isNotEmpty) {
      final year = item.year;
      if (year == null || !_filters.decades.contains(year ~/ 10 * 10)) return false;
    }
    return true;
  }

  List<CatalogItem> _sorted(List<CatalogItem> items) {
    // Index in source order breaks ties so every sort is stable.
    if (!identical(_orderOf, _all)) {
      _orderOf = _all;
      _order = {for (var i = 0; i < _all.length; i++) TvWatchlistAvailability.keyOf(_all[i]): i};
    }
    final order = _order;
    int byOrder(CatalogItem a, CatalogItem b) =>
        order[TvWatchlistAvailability.keyOf(a)]!.compareTo(order[TvWatchlistAvailability.keyOf(b)]!);
    int nullsLastDesc(Comparable<Object?>? a, Comparable<Object?>? b) {
      if (a == null) return b == null ? 0 : 1;
      if (b == null) return -1;
      return b.compareTo(a);
    }

    int Function(CatalogItem, CatalogItem) primary;
    switch (_sort) {
      case TvWatchlistSort.added:
        // Undated lists keep the source order (R5): no source is known to
        // list oldest first.
        primary = (a, b) => nullsLastDesc(a.addedAt, b.addedAt);
      case TvWatchlistSort.title:
        primary = (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase());
      case TvWatchlistSort.year:
        primary = (a, b) => nullsLastDesc(a.year, b.year);
      case TvWatchlistSort.rating:
        primary = (a, b) => nullsLastDesc(a.rating, b.rating);
    }
    return items..sort((a, b) {
      final c = primary(a, b);
      return c != 0 ? c : byOrder(a, b);
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _refetchTimer?.cancel();
    _membershipTimer?.cancel();
    _subscribed?.removeListener(_onWatchlistChanged);
    sourcesListenable.removeListener(_onSourcesChanged);
    availability.removeListener(_onAvailability);
    super.dispose();
  }
}
