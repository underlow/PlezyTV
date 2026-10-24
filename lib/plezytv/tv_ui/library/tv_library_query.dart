import '../../../media/library_query.dart';
import '../../../media/media_kind.dart';
import '../../../media/media_library.dart';
import '../../../media/media_server_client.dart';
import '../../../media/media_sort.dart';
import '../../../services/library_query_translator.dart';
import '../../../services/plex_constants.dart';
import '../../../i18n/strings.g.dart';

// Copied glue: lib/screens/libraries/tabs/library_browse_tab.dart,
// _getGroupingTypeId, _browseTypeParam, _buildQuery, _sortOptionsLibraryType,
// _getGroupingLabel, _isTitleSortDescending. Keep aligned on upstream merges.
String? tvGroupingType(String grouping) => const {
  'movies': '1',
  'shows': '2',
  'seasons': '3',
  'episodes': '4',
  'artists': '8',
  'albums': '9',
  'tracks': '10',
}[grouping];

String tvSortLibraryType(MediaLibrary library, String grouping) => switch (grouping) {
  'albums' => MediaKind.album.id,
  'tracks' => MediaKind.track.id,
  _ => library.kind.id,
};

// lib/screens/libraries/libraries_screen.dart, build/canSelectedLibraryGroupByFolders.
bool tvCanGroupByFolders(MediaLibrary library, MediaServerClient client) =>
    !library.isShared && library.serverId != null && client.capabilities.folderGrouping;

bool tvTitleSortDescending(MediaSort? sort, bool descending) {
  final key = sort?.key.toLowerCase() ?? '';
  return descending && (key == 'title' || key == 'name' || key == 'sortname' || key.startsWith('titlesort'));
}

// lib/screens/libraries/sort_bottom_sheet.dart, _handleSortSelect.
bool tvDefaultSortDescending(MediaSort sort) => sort.isDefaultDescending;

String tvGroupingLabel(String grouping) => switch (grouping) {
  'movies' => t.libraries.groupings.movies,
  'shows' => t.libraries.groupings.shows,
  'seasons' => t.libraries.groupings.seasons,
  'episodes' => t.libraries.groupings.episodes,
  'artists' => t.libraries.groupings.artists,
  'albums' => t.libraries.groupings.albums,
  'tracks' => t.libraries.groupings.tracks,
  'folders' => t.libraries.groupings.folders,
  _ => t.libraries.groupings.all,
};

LibraryQuery tvLibraryQuery({
  required MediaLibrary library,
  required String grouping,
  required List<LibraryFilter> filters,
  MediaSort? sort,
  bool descending = false,
  String? alphaPrefix,
  int offset = 0,
  int limit = 60,
}) {
  final type = grouping == 'all' && library.isShared ? PlexMetadataType.videoCsv : tvGroupingType(grouping);
  final query = libraryQueryFromSelection(
    clauses: filters,
    libraryKind: type == null ? library.kind : null,
    typeParam: type,
    sortParam: sort?.getSortKey(descending: descending),
    alphaPrefix: alphaPrefix,
    offset: offset,
    limit: limit,
  );
  return (query.kind == null || query.kind == MediaKind.folder) &&
          query.includeKinds.isEmpty &&
          grouping == 'all' &&
          library.defaultBrowseKinds.isNotEmpty
      ? query.copyWith(includeKinds: library.defaultBrowseKinds)
      : query;
}

/// Same video-only shared grouping rule as Plezy.
bool isTvVideoLibrary(MediaLibrary library) =>
    library.kind == MediaKind.movie || library.kind == MediaKind.show || library.isShared;
