import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../media/library_filter_result.dart';
import '../../../media/library_first_character.dart';
import '../../../media/library_query.dart';
import '../../../media/media_item.dart';
import '../../../media/media_library.dart';
import '../../../media/media_server_client.dart';
import '../../../media/media_sort.dart';
import '../../../providers/libraries_provider.dart';
import '../../../screens/libraries/alpha_jump_helper.dart';
import '../../../screens/libraries/library_alpha_bar_strategy.dart';
import '../../../screens/libraries/library_browse_grouping.dart';
import '../../../services/library_query_translator.dart';
import '../../../services/plex_client.dart';
import '../../../utils/deletion_notifier.dart';
import '../../../utils/library_content_notifier.dart';
import '../../../utils/watch_state_notifier.dart';
import '../components/tv_paged_source.dart';
import 'tv_library_preferences.dart';
import 'tv_library_query.dart';

class TvFolderLevel {
  TvFolderLevel({this.folder});
  final MediaItem? folder;
  int focusedIndex = 0;
  List<MediaItem> items = const [];
  Object? error;
  bool loading = false;
  int _request = 0;
}

/// One library and one persistence mode for its entire lifetime.
/// Recreate on library/profile change; dispose invalidates every outstanding load.
class TvLibraryController extends ChangeNotifier {
  TvLibraryController({
    required this.library,
    required this.client,
    required this.store,
    LibraryAlphaBarStrategy? alphaStrategy,
    this.librariesProvider,
  }) {
    strategy =
        alphaStrategy ??
        LibraryAlphaBarStrategy.forBackend(
          library.backend,
          plexClientProvider: () => client as PlexClient,
          libraryKey: library.id,
          isShared: library.isShared,
        );
    source = TvPagedSource<MediaItem>(loadPage: _loadPage)..addListener(_sourceChanged);
    _subscriptions.add(WatchStateNotifier().stream.listen(_watch));
    _subscriptions.add(DeletionNotifier().stream.listen(_delete));
    _subscriptions.add(
      LibraryContentNotifier().stream.listen((event) {
        if (event.serverId == library.serverId &&
            event.hasChanges &&
            (event.targetsWholeServer || event.libraryIds.contains(library.id))) {
          unawaited(refresh());
        }
      }),
    );
    librariesProvider?.addListener(_providerChanged);
  }
  final MediaLibrary library;
  final MediaServerClient client;
  final TvLibraryPreferencesStore store;
  final LibrariesProvider? librariesProvider;
  late final LibraryAlphaBarStrategy strategy;
  late final TvPagedSource<MediaItem> source;
  final _subscriptions = <StreamSubscription<dynamic>>[];
  final _loaded = <int, MediaItem>{};
  final folders = <TvFolderLevel>[];
  TvLibraryPreferences preferences = TvLibraryPreferences();
  List<MediaSort> sorts = const [];
  MediaSort? selectedSort;
  LibraryFilterResult filterResult = LibraryFilterResult.empty;
  List<LibraryFirstCharacter> characters = const [];
  AlphaJumpHelper alphaHelper = AlphaJumpHelper(const []);
  String? alphaPrefix;
  Object? error, filterError;
  bool filtersLoading = false, loading = false, _disposed = false;
  bool _jumping = false, _refreshPending = false;
  int _generation = 0, _contentEpoch = 0;
  int focusedIndex = 0;
  Future<void> _writes = Future.value();
  int get generation => _generation;
  int? get totalCount => source.totalCount;
  bool get canGroupByFolders => tvCanGroupByFolders(library, client);
  String get grouping =>
      normalizeLibraryBrowseGrouping(library, preferences.grouping, canGroupByFolders: canGroupByFolders);
  List<String> get groupingOptions => libraryBrowseGroupingOptions(library, canGroupByFolders: canGroupByFolders);
  bool get showAlpha => strategy.shouldShow(
    totalItemCount: totalCount ?? 0,
    loadedCharacterCount: characters.length,
    sortKey: selectedSort?.key,
    isFolderGrouping: grouping == 'folders',
    mediaBrowserAlphaPrefix: alphaPrefix,
    isPhone: false,
  );
  bool _current(int epoch) => !_disposed && epoch == _generation;
  void _emit() {
    if (!_disposed) notifyListeners();
  }

  void _sourceChanged() => _emit();

  Future<void> initialize() async {
    final epoch = ++_generation;
    loading = true;
    error = null;
    _emit();
    try {
      final saved = await store.load(library.globalKey);
      if (!_current(epoch)) return;
      preferences = saved;
      await _loadOptions(epoch);
      if (!_current(epoch)) return;
      await _loadContent(epoch);
    } catch (e) {
      if (_current(epoch)) error = e;
    } finally {
      if (_current(epoch)) {
        loading = false;
        _emit();
      }
    }
  }

  Future<void> _loadOptions(int epoch) async {
    final sortTask = client.fetchSortOptions(library.id, libraryType: tvSortLibraryType(library, grouping));
    final filterTask = library.backend.usesMediaBrowserApi
        ? null
        : client.fetchLibraryFiltersWithValues(library.id, libraryKind: library.kind);
    await Future.wait([sortTask, ?filterTask]);
    if (!_current(epoch)) return;
    sorts = await sortTask;
    selectedSort = sorts.where((s) => s.key == preferences.sortKey).firstOrNull;
    if (filterTask != null) filterResult = await filterTask;
    filtersLoading = library.backend.usesMediaBrowserApi;
  }

  LibraryQuery query({int offset = 0, int limit = 60}) => tvLibraryQuery(
    library: library,
    grouping: grouping,
    filters: preferences.filters,
    sort: selectedSort,
    descending: preferences.descending,
    alphaPrefix: alphaPrefix,
    offset: offset,
    limit: limit,
  );

  Future<TvPage<MediaItem>> _loadPage(int offset, int limit) async {
    final epoch = _generation, pageEpoch = source.generation;
    final page = await client.fetchLibraryPagedContent(
      library.id,
      query: query(offset: offset, limit: limit),
      libraryKind: library.kind,
    );
    if (_current(epoch) && pageEpoch == source.generation) {
      _loaded.removeWhere((i, _) => i >= page.totalCount || (i >= offset && i < offset + limit));
      for (var i = 0; i < page.items.length; i++) {
        _loaded[offset + i] = page.items[i];
      }
    }
    return TvPage(page.items, page.totalCount);
  }

  Future<void> _loadContent(int epoch) async {
    final contentEpoch = librariesProvider?.libraryContentEpoch(library.globalKey) ?? 0;
    if (grouping == 'folders') {
      if (folders.isEmpty) folders.add(TvFolderLevel());
      await loadFolder(folders.last);
    } else {
      await Future.wait([source.requestIndex(0), _loadCharacters(epoch)]);
    }
    if (!_current(epoch)) return;
    if (library.backend.usesMediaBrowserApi) unawaited(_loadFilters(epoch));
    _contentEpoch = contentEpoch;
  }

  Future<void> _loadFilters(int epoch) async {
    filtersLoading = true;
    filterError = null;
    _emit();
    try {
      final result = await client.fetchLibraryFiltersWithValues(library.id, libraryKind: library.kind);
      if (_current(epoch)) filterResult = result;
    } catch (e) {
      if (_current(epoch)) filterError = e;
    } finally {
      if (_current(epoch)) {
        filtersLoading = false;
        _emit();
      }
    }
  }

  Future<void> _loadCharacters(int epoch) async {
    try {
      final result = await strategy.loadCharacters(
        filters: plexFilterQueryParameters(preferences.filters),
        typeId: int.tryParse(tvGroupingType(grouping) ?? ''),
        descending: tvTitleSortDescending(selectedSort, preferences.descending),
      );
      if (!_current(epoch)) return;
      characters = result.chars;
      alphaHelper = result.helper;
    } catch (_) {
      if (!_current(epoch)) return;
      characters = const [];
      alphaHelper = AlphaJumpHelper(const []);
    }
    _emit();
  }

  /// Every selection invalidates pages and asynchronous metadata, including tab changes.
  Future<void> select({
    String? tab,
    String? grouping,
    MediaSort? sort,
    bool clearSort = false,
    bool? descending,
    List<LibraryFilter>? filters,
    bool resetAll = false,
  }) async {
    final nextGrouping = resetAll
        ? defaultLibraryBrowseGrouping(library, canGroupByFolders: canGroupByFolders)
        : grouping ?? this.grouping;
    if (grouping != null || resetAll) {
      alphaPrefix = null;
      folders.clear();
    }
    final nextSort = resetAll || clearSort ? null : sort ?? selectedSort;
    preferences = TvLibraryPreferences(
      tab: tab ?? preferences.tab,
      grouping: nextGrouping,
      sortKey: nextSort?.key,
      descending: resetAll || clearSort
          ? false
          : descending ?? (sort != null ? tvDefaultSortDescending(sort) : preferences.descending),
      filters: resetAll ? const [] : filters ?? preferences.filters,
    );
    selectedSort = nextSort;
    final saved = preferences;
    // Serialize rapid panel edits so an older write cannot finish last.
    final write = _writes.then((_) => store.save(library.globalKey, saved));
    _writes = write.catchError((Object _) {});
    final reload = _reloadSelection();
    await Future.wait([write, reload]);
  }

  /// The filter panel's “Reset all” clears clauses and the transient letter,
  /// while retaining the user's grouping and sort.
  Future<void> resetFilters() async {
    alphaPrefix = null;
    await select(filters: const []);
  }

  Future<void> setAlphaPrefix(String? prefix) async {
    alphaPrefix = prefix;
    await _reloadSelection();
  }

  Future<void> _reloadSelection() async {
    final epoch = ++_generation;
    source.reset();
    _loaded.clear();
    focusedIndex = 0;
    characters = const [];
    alphaHelper = AlphaJumpHelper(const []);
    error = null;
    loading = true;
    _emit();
    try {
      await _loadOptions(epoch);
      if (_current(epoch)) await _loadContent(epoch);
    } catch (e) {
      if (_current(epoch)) error = e;
    } finally {
      if (_current(epoch)) {
        loading = false;
        _emit();
      }
    }
  }

  void setJumping(bool value) {
    _jumping = value;
    if (!value && _refreshPending) {
      _refreshPending = false;
      unawaited(refresh());
    }
  }

  void _providerChanged() {
    if ((librariesProvider?.libraryContentEpoch(library.globalKey) ?? 0) != _contentEpoch) unawaited(refresh());
  }

  Future<void> refresh() async {
    if (_disposed) return;
    if (_jumping) {
      _refreshPending = true;
      return;
    }
    final epoch = ++_generation;
    final contentEpoch = librariesProvider?.libraryContentEpoch(library.globalKey) ?? 0;
    if (grouping == 'folders') {
      if (folders.isEmpty) folders.add(TvFolderLevel());
      await loadFolder(folders.last);
    } else {
      final index = await source.refresh(anchorIndex: focusedIndex, idOf: (item) => item.globalKey);
      if (!_current(epoch)) return;
      focusedIndex = index;
      await _loadCharacters(epoch);
    }
    if (!_current(epoch)) return;
    if (source.errors.isEmpty && (folders.isEmpty || folders.last.error == null)) _contentEpoch = contentEpoch;
    if (filtersLoading) unawaited(_loadFilters(epoch));
    _emit();
  }

  Future<void> openFolder(MediaItem folder) async {
    final level = TvFolderLevel(folder: folder);
    folders.add(level);
    await loadFolder(level);
  }

  bool popFolder() {
    if (folders.length <= 1) return false;
    folders.removeLast()._request++;
    _emit();
    return true;
  }

  Future<void> loadFolder(TvFolderLevel level) async {
    final epoch = _generation, request = ++level._request;
    level.loading = true;
    level.error = null;
    _emit();
    try {
      final items = level.folder == null
          ? await client.fetchLibraryFolders(library.id)
          : await client.fetchFolderChildren(level.folder!, libraryId: library.id, libraryTitle: library.title);
      if (_current(epoch) && request == level._request && folders.contains(level)) level.items = items;
    } catch (e) {
      if (_current(epoch) && request == level._request && folders.contains(level)) level.error = e;
    } finally {
      if (_current(epoch) && request == level._request && folders.contains(level)) {
        level.loading = false;
        _emit();
      }
    }
  }

  // Same event policy as library_browse_tab.dart onWatchStateChanged/onDeletionEvent;
  // watch metadata refresh follows lib/mixins/item_updatable.dart updateItem.
  void _watch(WatchStateEvent event) {
    if (event.serverId != library.serverId ||
        event.changeType == WatchStateChangeType.progressUpdate ||
        event.changeType == WatchStateChangeType.removedFromContinueWatching) {
      return;
    }
    final affected = <String, MediaItem>{};
    for (final item in [..._loaded.values, for (final level in folders) ...level.items]) {
      if (event.affectsItem(item.id)) affected[item.globalKey] = item;
    }
    for (final item in affected.values) {
      unawaited(_updateItem(item));
    }
  }

  Future<void> _updateItem(MediaItem item) async {
    final epoch = _generation;
    try {
      final updated = await client.fetchItem(item.id);
      if (!_current(epoch) || updated == null) return;
      for (final entry in _loaded.entries.toList()) {
        if (entry.value.globalKey == item.globalKey) {
          _loaded[entry.key] = updated;
          source.update(entry.key, updated);
        }
      }
      for (final level in folders) {
        level.items = [for (final row in level.items) row.globalKey == item.globalKey ? updated : row];
      }
      _emit();
    } catch (_) {
      /* Next refresh reconciles metadata. */
    }
  }

  void _remove(int index) {
    source.removeAt(index);
    final old = Map.of(_loaded);
    _loaded.clear();
    for (final entry in old.entries) {
      if (entry.key != index) _loaded[entry.key > index ? entry.key - 1 : entry.key] = entry.value;
    }
    focusedIndex = focusedIndex.clamp(0, (totalCount ?? 0) > 0 ? totalCount! - 1 : 0);
    _emit();
  }

  void _delete(DeletionEvent event) {
    if (event.isDownloadOnly || event.serverId != library.serverId) return;
    for (final level in folders) {
      level.items = [
        for (final row in level.items)
          if (row.id != event.itemId)
            if (!event.parentChain.contains(row.id))
              row
            else if ((row.leafCount ?? 1) > event.leafCount)
              row.copyWith(leafCount: (row.leafCount ?? 1) - event.leafCount),
      ];
      level.focusedIndex = level.focusedIndex.clamp(0, level.items.isEmpty ? 0 : level.items.length - 1);
    }
    _emit();
    final match = _loaded.entries.where((e) => e.value.id == event.itemId).firstOrNull;
    if (match != null) {
      _remove(match.key);
      return;
    }
    for (final parent in event.parentChain) {
      final entry = _loaded.entries.where((e) => e.value.id == parent).firstOrNull;
      if (entry == null) continue;
      final count = (entry.value.leafCount ?? 1) - event.leafCount;
      if (count <= 0) {
        _remove(entry.key);
      } else {
        final item = entry.value.copyWith(leafCount: count);
        _loaded[entry.key] = item;
        source.update(entry.key, item);
      }
      return;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    librariesProvider?.removeListener(_providerChanged);
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    source.dispose();
    super.dispose();
  }
}
