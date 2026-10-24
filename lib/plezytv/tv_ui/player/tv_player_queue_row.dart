import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../../media/ids.dart';
import '../../../media/media_item.dart';
import '../../../mpv/mpv.dart';
import '../../../providers/playback_state_provider.dart';
import '../../../utils/provider_extensions.dart';
import '../components/tv_cards.dart';
import '../components/tv_horizontal_row.dart';
import '../tv_strings.dart';
import '../tv_tokens.dart';

/// The queue row under the lifted player panel (R9, R10, `10-player-queue`):
/// the item playing and the ones after it from Plezy's play queue, as episode
/// cards. OK hands the item to [onSelected] (Plezy's `onQueueItemSelected`).
///
/// Keys other than ←/→ and OK go on to the panel, which closes the row.
class TvPlayerQueueRow extends StatefulWidget {
  const TvPlayerQueueRow({super.key, required this.player, required this.onSelected});

  final Player player;
  final ValueChanged<MediaItem> onSelected;

  /// Card size including captions, as other episode rows.
  static const cardHeight = 315.0;

  @override
  State<TvPlayerQueueRow> createState() => TvPlayerQueueRowState();
}

class TvPlayerQueueRowState extends State<TvPlayerQueueRow> {
  final _row = GlobalKey<TvHorizontalRowState>();
  List<MediaItem> _items = const [];

  static String _key(MediaItem item) => item.globalKey;

  /// Focus on the next item, or the playing one when it is the last.
  void focusNext() {
    final row = _row.currentState;
    if (row == null || _items.isEmpty) return;
    row.requestFocus(itemKey: _key(_items[_items.length > 1 ? 1 : 0]));
  }

  /// The playing item and the ones after it; the whole loaded window when the
  /// playing item is not in it.
  static List<MediaItem> _upcoming(PlaybackStateProvider state) {
    final items = state.loadedItems;
    final currentId = state.currentPlayQueueItemID;
    final index = currentId == null ? -1 : items.indexWhere((item) => state.playQueueItemIdFor(item) == currentId);
    return index < 0 ? items : items.sublist(index);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PlaybackStateProvider>();
    final items = _items = _upcoming(state);
    final currentId = state.currentPlayQueueItemID;
    final first = items.isEmpty ? null : items.first;
    final firstIsCurrent = first != null && currentId != null && state.playQueueItemIdFor(first) == currentId;
    final more = firstIsCurrent ? items.length - 1 : items.length;
    return TvHorizontalRow(
      key: _row,
      title: TvStrings.playerUpNextInQueue,
      counter: more > 0 ? TvStrings.playerQueueMore(season: first?.parentIndex, count: more) : null,
      contentLeft: TvTokens.space.safeX,
      itemCount: items.length,
      cardWidth: TvTokens.size.episode.w.toDouble(),
      cardHeight: TvPlayerQueueRow.cardHeight,
      itemKey: (index) => _key(items[index]),
      cardBuilder: (context, index, node) {
        final item = items[index];
        final current = index == 0 && firstIsCurrent;
        final playerState = widget.player.state;
        return TvEpisode(
          item: item,
          client: context.tryGetMediaClientForServer(serverIdOrNull(item.serverId)),
          focusNode: node,
          caption: current
              ? TvStrings.playerQueueNow((playerState.duration - playerState.position).inMilliseconds)
              : null,
          onSelect: () => widget.onSelected(item),
        );
      },
    );
  }
}
