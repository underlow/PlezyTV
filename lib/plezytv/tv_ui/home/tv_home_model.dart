import '../../../media/media_hub.dart';
import '../../../media/media_item.dart';
import '../../../media/media_kind.dart';
import '../../../providers/discover_provider.dart';
import '../tv_strings.dart';

enum TvHomeState { loading, error, empty, content }

enum TvHomePartState { loading, ready }

enum TvHomeRowKind { continueWatching, hub }

/// Immutable row data; [hub] retains the source needed by Plezy's full list.
class TvHomeRow {
  final TvHomeRowKind kind;
  final String title;
  final List<MediaItem> items;
  final bool hasMore;
  final int? count;
  final MediaHub? hub;

  const TvHomeRow._({
    required this.kind,
    required this.title,
    required this.items,
    required this.hasMore,
    this.count,
    this.hub,
  });

  /// Uses Plezy's server-qualified identity for focus restoration.
  static String itemKey(MediaItem item) => item.globalKey;
}

class TvHomeModel {
  final List<TvHomeRow> rows;
  final TvHomePartState onDeckState;
  final TvHomePartState hubsState;
  final String? errorMessage;
  final bool isLoadInFlight;

  const TvHomeModel._({
    required this.rows,
    required this.onDeckState,
    required this.hubsState,
    required this.errorMessage,
    required this.isLoadInFlight,
  });

  TvHomeState get state {
    if (rows.isNotEmpty) return TvHomeState.content;
    if (onDeckState == TvHomePartState.loading || hubsState == TvHomePartState.loading) {
      return TvHomeState.loading;
    }
    if (errorMessage != null) return TvHomeState.error;
    return TvHomeState.empty;
  }
}

/// Keep one builder per screen. Call [build] on every provider notification:
/// rows are cached by list identity, but loading/error/retry flags stay live.
class TvHomeModelBuilder {
  List<MediaItem>? _onDeck;
  List<MediaHub>? _hubs;
  List<TvHomeRow> _continueRows = const [];
  List<TvHomeRow> _rows = const [];

  TvHomeModel build(DiscoverProvider provider) {
    if (!identical(_onDeck, provider.onDeck) || !identical(_hubs, provider.hubs)) {
      _onDeck = provider.onDeck;
      _hubs = provider.hubs;
      final onDeck = _videoItems(provider.onDeck);
      _continueRows = List.unmodifiable([
        if (onDeck.isNotEmpty)
          TvHomeRow._(
            kind: TvHomeRowKind.continueWatching,
            title: TvStrings.continueWatching,
            items: onDeck,
            hasMore: provider.hasMoreContinueWatching,
          ),
      ]);
      final rows = <TvHomeRow>[..._continueRows];
      for (final hub in provider.hubs) {
        if (hub.isContinueWatchingHub) continue;
        final items = _videoItems(hub.items);
        if (items.isEmpty) continue;
        rows.add(
          TvHomeRow._(
            kind: TvHomeRowKind.hub,
            title: hub.title,
            items: items,
            hasMore: hub.more,
            count: items.length == hub.items.length ? hub.size : null,
            hub: hub,
          ),
        );
      }
      _rows = rows.length == _continueRows.length ? _continueRows : List.unmodifiable(rows);
    }
    // Discover publishes onDeck first, even when the hub request finishes first.
    final hubsLoading = provider.isLoading || provider.areHubsLoading;
    return TvHomeModel._(
      rows: provider.isLoading ? _continueRows : _rows,
      onDeckState: provider.isLoading ? TvHomePartState.loading : TvHomePartState.ready,
      hubsState: hubsLoading ? TvHomePartState.loading : TvHomePartState.ready,
      errorMessage: provider.errorMessage,
      isLoadInFlight: provider.isLoadInFlight,
    );
  }

  static List<MediaItem> _videoItems(List<MediaItem> items) => List.unmodifiable(
    items.where(
      (item) => const {
        MediaKind.movie,
        MediaKind.show,
        MediaKind.season,
        MediaKind.episode,
        MediaKind.collection,
      }.contains(item.kind),
    ),
  );
}
