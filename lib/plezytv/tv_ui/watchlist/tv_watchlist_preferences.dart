import 'dart:convert';

import '../../../services/storage_service.dart';

enum TvWatchlistTab { all, movies, shows, onServer }

enum TvWatchlistSort { added, title, year, rating }

/// Genre and decade filters; values are OR-ed inside a group, groups AND-ed.
class TvWatchlistFilters {
  const TvWatchlistFilters({this.genres = const {}, this.decades = const {}});
  static const TvWatchlistFilters none = TvWatchlistFilters();

  final Set<String> genres;

  /// Decade start years (1990, 2000, …).
  final Set<int> decades;

  bool get isEmpty => genres.isEmpty && decades.isEmpty;

  /// Number of selected values, for «Фильтры · {n}».
  int get count => genres.length + decades.length;

  Map<String, Object> toJson() => {'genres': genres.toList(), 'decades': decades.toList()};

  static TvWatchlistFilters fromJson(Object? json) {
    if (json is! Map) return none;
    final genres = json['genres'];
    final decades = json['decades'];
    return TvWatchlistFilters(
      genres: {if (genres is List) ...genres.whereType<String>()},
      decades: {if (decades is List) ...decades.whereType<int>()},
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TvWatchlistFilters &&
      other.genres.length == genres.length &&
      other.genres.containsAll(genres) &&
      other.decades.length == decades.length &&
      other.decades.containsAll(decades);

  @override
  int get hashCode => Object.hash(Object.hashAllUnordered(genres), Object.hashAllUnordered(decades));
}

/// Per-profile watchlist preferences (S10 R4, R6). Filters are kept per source
/// name so a fallback source never inherits another source's filters.
class TvWatchlistPreferences {
  const TvWatchlistPreferences({
    this.source,
    this.sort = TvWatchlistSort.added,
    this.tab = TvWatchlistTab.all,
    this.filters = const {},
  });

  /// `CatalogSourceId.name` of the explicitly chosen source.
  final String? source;
  final TvWatchlistSort sort;
  final TvWatchlistTab tab;
  final Map<String, TvWatchlistFilters> filters;

  TvWatchlistPreferences copyWith({
    String? source,
    TvWatchlistSort? sort,
    TvWatchlistTab? tab,
    Map<String, TvWatchlistFilters>? filters,
  }) => TvWatchlistPreferences(
    source: source ?? this.source,
    sort: sort ?? this.sort,
    tab: tab ?? this.tab,
    filters: filters ?? this.filters,
  );

  String encode() => jsonEncode({
    'source': ?source,
    'sort': sort.name,
    'tab': tab.name,
    'filters': {for (final e in filters.entries) e.key: e.value.toJson()},
  });

  static TvWatchlistPreferences decode(String? raw) {
    if (raw == null) return const TvWatchlistPreferences();
    try {
      final json = jsonDecode(raw);
      if (json is! Map) return const TvWatchlistPreferences();
      final filters = json['filters'];
      return TvWatchlistPreferences(
        source: json['source'] is String ? json['source'] as String : null,
        sort: TvWatchlistSort.values.asNameMap()[json['sort']] ?? TvWatchlistSort.added,
        tab: TvWatchlistTab.values.asNameMap()[json['tab']] ?? TvWatchlistTab.all,
        filters: {
          if (filters is Map)
            for (final e in filters.entries)
              if (e.key is String) e.key as String: TvWatchlistFilters.fromJson(e.value),
        },
      );
    } on FormatException {
      return const TvWatchlistPreferences();
    }
  }
}

abstract interface class TvWatchlistPreferencesStore {
  Future<TvWatchlistPreferences> load();
  Future<void> save(TvWatchlistPreferences value);
}

/// Stored under the active profile's scope, like the S16 library preferences.
class TvStorageWatchlistPreferences implements TvWatchlistPreferencesStore {
  TvStorageWatchlistPreferences(this.storage);
  final StorageService storage;

  String get _key {
    final scope = storage.activeUserScope();
    return '${scope == null ? '' : 'user_${scope}_'}plezytv_watchlist_prefs';
  }

  @override
  Future<TvWatchlistPreferences> load() async => TvWatchlistPreferences.decode(storage.prefs.getString(_key));

  @override
  Future<void> save(TvWatchlistPreferences value) => storage.prefs.setString(_key, value.encode());
}

class TvMemoryWatchlistPreferences implements TvWatchlistPreferencesStore {
  TvMemoryWatchlistPreferences([this.value = const TvWatchlistPreferences()]);
  TvWatchlistPreferences value;
  @override
  Future<TvWatchlistPreferences> load() async => value;
  @override
  Future<void> save(TvWatchlistPreferences value) async => this.value = value;
}
