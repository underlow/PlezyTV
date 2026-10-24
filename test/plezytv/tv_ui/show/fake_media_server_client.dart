import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_hub.dart';
import 'package:plezy/media/media_server_client.dart';
import 'package:plezy/media/library_query.dart';
import 'package:plezy/utils/media_server_http_client.dart';

class FakeShowClient implements MediaServerClient {
  @override
  MediaBackend backend = MediaBackend.jellyfin;
  late MediaItem show;
  MediaItem? onDeck;
  List<MediaItem> seasons = [];
  List<MediaItem> extras = [];
  Map<String, List<MediaItem>> episodes = {};
  final calls = <String>[];
  Future<({MediaItem? item, MediaItem? onDeckEpisode})> Function()? onFetch;
  @override
  Future<({MediaItem? item, MediaItem? onDeckEpisode})> fetchItemWithOnDeck(
    String id, {
    void Function(MediaItem)? onItemReady,
  }) async {
    calls.add('metadata');
    return onFetch == null ? (item: show, onDeckEpisode: onDeck) : onFetch!();
  }

  @override
  Future<List<MediaItem>> fetchChildren(String id) async {
    calls.add('seasons');
    return seasons;
  }

  @override
  Future<List<MediaItem>> fetchExtras(String id) async {
    calls.add('extras');
    return extras;
  }

  @override
  Future<List<MediaHub>> fetchRelatedHubs(String id, {int count = 10}) async {
    calls.add('related');
    return [];
  }

  Future<LibraryPage<MediaItem>> Function(String, int, int)? onPage;
  @override
  Future<LibraryPage<MediaItem>> fetchChildrenPage(
    String parentId, {
    int? start,
    int? size,
    AbortController? abort,
  }) async {
    calls.add('page:$parentId:$start');
    if (onPage != null) return onPage!(parentId, start ?? 0, size ?? 50);
    final items = episodes[parentId] ?? [];
    return LibraryPage(items: items.skip(start ?? 0).take(size ?? 50).toList(), totalCount: items.length);
  }

  @override
  Future<LibraryPage<MediaItem>> fetchPlayableDescendantsPage(
    String parentId, {
    int? start,
    int? size,
    AbortController? abort,
  }) => fetchChildrenPage(parentId, start: start, size: size);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
