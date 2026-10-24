import '../../../media/library_query.dart';
import '../../../services/storage_service.dart';

/// Tab names deliberately match Plezy's LibraryTabType.name.
class TvLibraryPreferences {
  TvLibraryPreferences({
    this.tab = 'browse',
    this.grouping,
    this.sortKey,
    this.descending = false,
    List<LibraryFilter> filters = const [],
  }) : filters = List.unmodifiable(filters);
  final String tab;
  final String? grouping, sortKey;
  final bool descending;
  final List<LibraryFilter> filters;
}

abstract interface class TvLibraryPreferencesStore {
  Future<TvLibraryPreferences> load(String key);
  Future<void> save(String key, TvLibraryPreferences value);
}

class TvStorageLibraryPreferences implements TvLibraryPreferencesStore {
  TvStorageLibraryPreferences(this.storage);
  final StorageService storage;
  @override
  Future<TvLibraryPreferences> load(String key) async {
    final sort = storage.getLibrarySort(key);
    return TvLibraryPreferences(
      tab: storage.getLibraryTab(key) ?? 'browse',
      grouping: storage.getLibraryGrouping(key),
      sortKey: sort?['key'] as String?,
      descending: sort?['descending'] as bool? ?? false,
      filters: storage.getLibraryFilters(sectionId: key),
    );
  }

  @override
  Future<void> save(String key, TvLibraryPreferences value) async {
    await storage.saveLibraryTab(key, value.tab);
    if (value.grouping != null) await storage.saveLibraryGrouping(key, value.grouping!);
    if (value.sortKey case final sort?) {
      await storage.saveLibrarySort(key, sort, descending: value.descending);
    } else {
      await storage.clearLibrarySort(key);
    }
    await storage.saveLibraryFilters(value.filters, sectionId: key);
  }
}

/// Seed a filtered route with saved grouping/sort and its sole incoming clause.
/// No StorageService dependency: edits cannot escape the route.
class TvMemoryLibraryPreferences implements TvLibraryPreferencesStore {
  TvMemoryLibraryPreferences({TvLibraryPreferences? seed}) : _seed = seed ?? TvLibraryPreferences();
  factory TvMemoryLibraryPreferences.filtered(TvLibraryPreferences saved, LibraryFilter filter) =>
      TvMemoryLibraryPreferences(
        seed: TvLibraryPreferences(
          grouping: saved.grouping,
          sortKey: saved.sortKey,
          descending: saved.descending,
          filters: [filter],
        ),
      );
  final TvLibraryPreferences _seed;
  final _values = <String, TvLibraryPreferences>{};
  @override
  Future<TvLibraryPreferences> load(String key) async => _values[key] ?? _seed;
  @override
  Future<void> save(String key, TvLibraryPreferences value) async {
    _values[key] = value;
  }
}
