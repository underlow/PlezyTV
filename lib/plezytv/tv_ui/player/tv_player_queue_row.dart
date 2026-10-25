import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../../media/ids.dart';
import '../../../media/media_item.dart';
import '../../../media/media_item_types.dart';
import '../../../mpv/mpv.dart';
import '../../../providers/playback_state_provider.dart';
import '../../../services/settings_service.dart';
import '../../../utils/provider_extensions.dart';
import '../../../widgets/settings_builder.dart';
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
  TvPlayerQueue _queue = const TvPlayerQueue._([], false);

  static String _key(MediaItem item) => item.globalKey;

  /// Focus on the first item after the playing one; on the playing one when it
  /// is the last; on the first card when the playing item is not shown.
  void focusNext() {
    final row = _row.currentState;
    final items = _queue.items;
    if (row == null || items.isEmpty) return;
    row.requestFocus(itemKey: _key(items[_queue.firstIsCurrent && items.length > 1 ? 1 : 0]));
  }

  @override
  Widget build(BuildContext context) {
    final queue = _queue = TvPlayerQueue.of(context.watch<PlaybackStateProvider>());
    final items = queue.items;
    return SettingValueBuilder<bool>(
      pref: SettingsService.hideSpoilers,
      builder: (context, hideSpoilers, _) => TvHorizontalRow(
        key: _row,
        title: TvStrings.playerUpNextInQueue,
        counter: _counter(queue.upcoming),
        contentLeft: TvTokens.space.safeX,
        itemCount: items.length,
        cardWidth: TvTokens.size.episode.w.toDouble(),
        cardHeight: TvPlayerQueueRow.cardHeight,
        itemKey: (index) => _key(items[index]),
        cardBuilder: (context, index, node) {
          final item = items[index];
          final blur = hideSpoilers && item.shouldHideSpoiler;
          Widget card({String? caption, double? progress}) => TvEpisode(
            item: item,
            client: context.tryGetMediaClientForServer(serverIdOrNull(item.serverId)),
            focusNode: node,
            caption: caption,
            progress: progress,
            blurThumbnail: blur,
            onSelect: () => widget.onSelected(item),
          );
          if (!(index == 0 && queue.firstIsCurrent)) return card();
          // The playing item follows the player, not the stored offset.
          final player = widget.player;
          return StreamBuilder<Duration>(
            stream: player.streams.position,
            initialData: player.state.position,
            builder: (context, snapshot) {
              final position = snapshot.data ?? player.state.position;
              final duration = player.state.duration;
              final ms = duration.inMilliseconds;
              return card(
                caption: TvStrings.playerQueueNow((duration - position).inMilliseconds),
                progress: ms > 0 ? (position.inMilliseconds / ms).clamp(0.0, 1.0) : null,
              );
            },
          );
        },
      ),
    );
  }

  /// "Season n · k more episodes" for one season's episodes, "k more
  /// episodes" across seasons, "k more" for mixed items.
  static String? _counter(List<MediaItem> upcoming) {
    if (upcoming.isEmpty) return null;
    final count = upcoming.length;
    if (!upcoming.every((item) => item.isEpisode)) return TvStrings.playerQueueMore(count: count);
    final seasons = upcoming.map((item) => item.parentIndex).toSet();
    final season = seasons.length == 1 ? seasons.single : null;
    return TvStrings.playerQueueMoreEpisodes(season: season, count: count);
  }
}

/// What the queue row shows from Plezy's play queue: the playing item and the
/// ones after it; the whole loaded window when the playing item is not in it.
@immutable
class TvPlayerQueue {
  const TvPlayerQueue._(this.items, this.firstIsCurrent);

  factory TvPlayerQueue.of(PlaybackStateProvider state) {
    final items = state.loadedItems;
    final currentId = state.currentPlayQueueItemID;
    final index = currentId == null ? -1 : items.indexWhere((item) => state.playQueueItemIdFor(item) == currentId);
    return index < 0 ? TvPlayerQueue._(items, false) : TvPlayerQueue._(items.sublist(index), true);
  }

  final List<MediaItem> items;

  /// Whether [items] starts with the playing item.
  final bool firstIsCurrent;

  /// The items after the playing one.
  List<MediaItem> get upcoming => firstIsCurrent ? items.sublist(1) : items;
}
