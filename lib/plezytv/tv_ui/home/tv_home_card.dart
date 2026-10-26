import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../focus/dpad_navigator.dart';
import '../../../focus/transport_keys.dart';
import '../../../media/media_hub.dart';
import '../../../media/media_item.dart';
import '../../../media/media_kind.dart';
import '../../../providers/watch_state_store.dart';
import '../../../screens/hub_detail_screen.dart';
import '../../../services/music/music_playback_service.dart';
import '../../../utils/media_navigation_helper.dart';
import '../../../utils/provider_extensions.dart';
import '../../../widgets/media_context_menu.dart';
import '../components/tv_cards.dart';
import 'tv_home_playback.dart';

/// Play/Pause activates [playback]; Menu opens [menu]. Shared by every card
/// that offers Home's actions (Home rows, search rows and grids). A current
/// music track leaves transport to Plezy, including a paused or parked session.
KeyEventResult tvHomeCardKeys(
  TvHomePlayback playback,
  MediaItem item,
  KeyEvent event,
  VoidCallback menu, {
  required bool Function() musicActive,
}) {
  final transport = classifyTransportKey(event.logicalKey);
  if (transport == TransportCommand.play || transport == TransportCommand.toggle) {
    if (musicActive()) return KeyEventResult.ignored;
    if (event is KeyDownEvent) unawaited(playback.activate(item));
    return KeyEventResult.handled;
  }
  if (event.logicalKey.isContextMenuKey) {
    if (event is KeyDownEvent) menu();
    return KeyEventResult.handled;
  }
  return KeyEventResult.ignored;
}

/// One Home hub card: fresh watch state, context menu, transport keys and
/// OK opening the item, as on Home (S6, reused by S11 idle rows).
class TvHomeHubCard extends StatelessWidget {
  const TvHomeHubCard({
    super.key,
    required this.item,
    required this.focusNode,
    required this.playback,
    this.wide = false,
    this.playDirectly = false,
    this.isInContinueWatching = false,
    this.onRefresh,
    this.onRemoveFromContinueWatching,
  });

  final MediaItem item;
  final FocusNode focusNode;
  final TvHomePlayback playback;
  final bool wide, playDirectly, isInContinueWatching;
  final void Function(MediaItem item)? onRefresh;
  final VoidCallback? onRemoveFromContinueWatching;

  @override
  Widget build(BuildContext context) {
    final item = context.withFreshWatchState(this.item);
    final client = context.getMediaClientForItemOrNull(item);
    void select() => unawaited(navigateToMediaItem(context, item, onRefresh: onRefresh, playDirectly: playDirectly));
    return MediaContextMenu(
      item: item,
      onRefresh: onRefresh,
      onRemoveFromContinueWatching: onRemoveFromContinueWatching,
      isInContinueWatching: isInContinueWatching,
      child: Builder(
        builder: (menuContext) {
          void menu() => menuContext.findAncestorStateOfType<MediaContextMenuState>()?.showContextMenu(menuContext);
          return Focus(
            canRequestFocus: false,
            onKeyEvent: (_, event) => tvHomeCardKeys(
              playback,
              item,
              event,
              menu,
              musicActive: () => context.read<MusicPlaybackService?>()?.currentTrack != null,
            ),
            child: {MediaKind.artist, MediaKind.album, MediaKind.track}.contains(item.kind)
                ? TvMusicCard(item: item, client: client, focusNode: focusNode, onSelect: select, onLongPress: menu)
                : wide
                ? TvEpisode(item: item, client: client, focusNode: focusNode, onSelect: select, onLongPress: menu)
                : TvPoster(item: item, client: client, focusNode: focusNode, onSelect: select, onLongPress: menu),
          );
        },
      ),
    );
  }
}

/// Opens a hub's "All" screen, as Home does.
Future<void> openTvHubDetail(
  BuildContext context,
  MediaHub hub, {
  Future<List<MediaItem>> Function()? loadItems,
  bool continuing = false,
  VoidCallback? onRemoveFromContinueWatching,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => HubDetailScreen(
      hub: hub,
      loadItems: loadItems,
      isInContinueWatching: continuing || hub.isContinueWatchingHub,
      usesContinueWatchingAction: continuing || hub.usesContinueWatchingAction,
      onRemoveFromContinueWatching: onRemoveFromContinueWatching,
    ),
  ),
);
