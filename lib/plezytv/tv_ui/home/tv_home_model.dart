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
  final TvHomeState? _retryState;

  const TvHomeModel._({
    required this.rows,
    required this.onDeckState,
    required this.hubsState,
    required this.errorMessage,
    required this.isLoadInFlight,
    this._retryState,
  });

  TvHomeState get state {
    if (rows.isNotEmpty) return TvHomeState.content;
    if (_retryState != null) return _retryState;
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
  TvHomeState? _terminalState;
  String? _terminalError;

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
            // Plezy TV renders no Continue Watching counter in its hub header.
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
    // Preserve the retry/refresh button while the provider clears its error
    // and switches to loading on the next microtask. Existing rows always win.
    final partsLoading = provider.isLoading || provider.areHubsLoading;
    final retryState = provider.isLoadInFlight && partsLoading && _rows.isEmpty ? _terminalState : null;
    final model = TvHomeModel._(
      rows: _rows,
      onDeckState: provider.isLoading ? TvHomePartState.loading : TvHomePartState.ready,
      hubsState: provider.areHubsLoading ? TvHomePartState.loading : TvHomePartState.ready,
      errorMessage: retryState == TvHomeState.error ? _terminalError : provider.errorMessage,
      // The coordinator is still busy during the last notification and does
      // not notify when its drain ends. Part readiness settles the UI instead.
      isLoadInFlight: provider.isLoadInFlight && partsLoading,
      retryState: retryState,
    );
    if (model.state == TvHomeState.content) {
      _terminalState = null;
      _terminalError = null;
    } else if (!partsLoading && (model.state == TvHomeState.error || model.state == TvHomeState.empty)) {
      _terminalState = model.state;
      _terminalError = model.errorMessage;
    }
    return model;
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
