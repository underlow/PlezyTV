import 'package:plezy/utils/media_server_http_client.dart';
import 'package:plezy/media/ids.dart';
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
