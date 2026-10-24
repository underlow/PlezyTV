import 'package:plezy/services/plex_client.dart';
import 'package:plezy/utils/media_server_http_client.dart';
import 'package:plezy/media/ids.dart';
import 'package:plezy/media/library_first_character.dart';
import 'package:plezy/media/media_filter.dart';
import 'package:plezy/media/media_library.dart';
import 'package:plezy/media/media_hub.dart';
import 'package:plezy/media/media_playlist.dart';
import 'package:plezy/media/library_filter_result.dart';
import 'package:plezy/media/library_query.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_server_client.dart';
import 'package:plezy/media/media_sort.dart';
import 'package:plezy/media/server_capabilities.dart';

/// Shared library fixture for T3–T8. Unimplemented calls fail loudly.
class FakeMediaServerClient implements MediaServerClient {
  FakeMediaServerClient({this.backend = MediaBackend.jellyfin});
  @override
  final MediaBackend backend;
  @override
  ServerId get serverId => ServerId('server');
  @override
  ServerCapabilities get capabilities =>
      backend == MediaBackend.plex ? ServerCapabilities.plex : ServerCapabilities.jellyfin;
  @override
  void close() {}
  @override
  Future<void> markWatched(MediaItem item) async {
    calls.add('watched:${item.id}');
    items = [for (final row in items) row.id == item.id ? row.copyWith(viewCount: 1) : row];
  }

  List<MediaLibrary> libraries = [];
  @override
  Future<List<MediaLibrary>> fetchLibraries() async => libraries;

  List<MediaHub> hubs = [];
  List<MediaItem> collections = [];
  List<MediaPlaylist> playlists = [];

  @override
  Future<List<MediaHub>> fetchLibraryHubs(
    String libraryId, {
    required String libraryName,
    int limit = defaultHubPreviewLimit,
    bool includePlaybackHubs = true,
    MediaKind? libraryKind,
    HubFetchDiagnostics? diagnostics,
  }) async {
    calls.add('hubs:$libraryId');
    return hubs;
  }

  @override
  Future<LibraryPage<MediaItem>> fetchCollectionsPage(
    String libraryId, {
    int? start,
    int? size,
    AbortController? abort,
  }) async {
    calls.add('collections:$libraryId:$start:$size');
    return LibraryPage(
      items: collections.skip(start ?? 0).take(size ?? collections.length).toList(),
      totalCount: collections.length,
    );
  }

  @override
  Future<LibraryPage<MediaPlaylist>> fetchPlaylistsPage({
    String playlistType = 'video',
    bool? smart,
    int? start,
    int? size,
    AbortController? abort,
  }) async {
    calls.add('playlists:$playlistType:$start:$size');
    return LibraryPage(
      items: playlists.skip(start ?? 0).take(size ?? playlists.length).toList(),
      totalCount: playlists.length,
    );
  }

  Object? actionError;
  Future<void> libraryAction(String action, String id) async {
    calls.add('$action:$id');
    if (actionError != null) throw actionError!;
  }

  @override
  Future<void> refreshLibraryMetadata(String libraryId) => libraryAction('refresh', libraryId);

  final calls = <String>[];
  final queries = <LibraryQuery>[];
  List<MediaItem> items = [];
  List<MediaSort> sorts = const [
    MediaSort(key: 'titleSort', title: 'Title'),
    MediaSort(key: 'addedAt', title: 'Added', defaultDirection: 'desc'),
  ];
  LibraryFilterResult filters = LibraryFilterResult.empty;
  Future<List<MediaSort>> Function(String id, String? type)? onSorts;
  Future<LibraryFilterResult> Function()? onFilters;
  Future<LibraryPage<MediaItem>> Function(LibraryQuery query)? onPage;
  Future<List<MediaItem>> Function(MediaItem? folder)? onFolder;
  Future<MediaItem?> Function(String id)? onItem;
  @override
  Future<List<MediaSort>> fetchSortOptions(String libraryId, {String? libraryType}) async {
    calls.add('sorts:$libraryId:$libraryType');
    return onSorts == null ? sorts : onSorts!(libraryId, libraryType);
  }

  @override
  Future<LibraryFilterResult> fetchLibraryFiltersWithValues(String libraryId, {MediaKind? libraryKind}) async {
    calls.add('filters:$libraryId');
    return onFilters == null ? filters : onFilters!();
  }

  @override
  Future<LibraryPage<MediaItem>> fetchLibraryPagedContent(
    String libraryId, {
    required LibraryQuery query,
    MediaKind? libraryKind,
    AbortController? abort,
  }) async {
    calls.add('page:$libraryId:${query.offset}');
    queries.add(query);
    return onPage == null
        ? LibraryPage(items: items.skip(query.offset).take(query.limit).toList(), totalCount: items.length)
        : onPage!(query);
  }

  @override
  Future<List<MediaItem>> fetchLibraryFolders(String libraryId, {void Function(List<MediaItem>)? onPage}) async =>
      onFolder == null ? items : onFolder!(null);
  @override
  Future<List<MediaItem>> fetchFolderChildren(
    MediaItem folder, {
    String? libraryId,
    String? libraryTitle,
    void Function(List<MediaItem>)? onPage,
  }) async => onFolder == null ? items : onFolder!(folder);
  @override
  Future<MediaItem?> fetchItem(String id) async =>
      onItem == null ? items.where((i) => i.id == id).firstOrNull : onItem!(id);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakePlexLibraryClient extends FakeMediaServerClient implements PlexClient {
  FakePlexLibraryClient() : super(backend: MediaBackend.plex);
  Future<List<MediaFilterValue>> Function(String)? onValues;
  @override
  Future<List<MediaFilterValue>> getFilterValues(String filterKey) async => onValues!(filterKey);
  Future<List<LibraryFirstCharacter>> Function()? onCharacters;
  int characterCalls = 0;
  @override
  Future<List<LibraryFirstCharacter>> getFirstCharacters(
    String sectionId, {
    int? type,
    Map<String, dynamic>? filters,
  }) async {
    characterCalls++;
    return onCharacters == null ? [] : onCharacters!();
  }

  @override
  Future<void> scanLibrary(String sectionId) => libraryAction('scan', sectionId);
  @override
  Future<void> analyzeLibrary(String sectionId) => libraryAction('analyze', sectionId);
  @override
  Future<void> emptyLibraryTrash(String sectionId) => libraryAction('trash', sectionId);
}
