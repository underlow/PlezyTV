import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/services/music/music_playback_service.dart';
import 'package:plezy/plezytv/tv_ui/home/tv_home_card.dart';
import 'package:plezy/plezytv/tv_ui/home/tv_home_playback.dart';
import '../../test_helpers/media_items.dart';

class _Music extends ChangeNotifier implements MusicPlaybackService {
  _Music(this.currentTrack);
  @override
  final MediaItem? currentTrack;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final kind in [MediaKind.track, MediaKind.movie, MediaKind.album]) {
    for (final session in ['absent', 'empty', 'paused-or-playing']) {
      testWidgets('C4 $kind session=$session: transport yields only with current track', (tester) async {
        final item = testMediaItem(id: 'target', kind: kind);
        final activated = <MediaItem>[];
        final playback = TvHomePlayback(clientForItem: (_) => null, play: (_) async {}, openDetails: (_) async {});
        // Override activation to observe the shared Home/search key contract directly.
        final recording = _Playback(activated);
        var menus = 0;
        late BuildContext context;
        Widget child = Builder(
          builder: (value) {
            context = value;
            return const SizedBox();
          },
        );
        if (session != 'absent') {
          child = ChangeNotifierProvider<MusicPlaybackService>.value(
            value: _Music(session == 'empty' ? null : item),
            child: child,
          );
        }
        await tester.pumpWidget(child);
        for (final key in [LogicalKeyboardKey.mediaPlay, LogicalKeyboardKey.mediaPlayPause]) {
          activated.clear();
          final result = tvHomeCardKeys(
            recording,
            item,
            KeyDownEvent(logicalKey: key, physicalKey: PhysicalKeyboardKey.mediaPlayPause, timeStamp: Duration.zero),
            () => menus++,
            musicActive: () => context.read<MusicPlaybackService?>()?.currentTrack != null,
          );
          expect(result, session == 'paused-or-playing' ? KeyEventResult.ignored : KeyEventResult.handled);
          expect(activated, session == 'paused-or-playing' ? isEmpty : [item]);
          tvHomeCardKeys(
            recording,
            item,
            KeyUpEvent(logicalKey: key, physicalKey: PhysicalKeyboardKey.mediaPlayPause, timeStamp: Duration.zero),
            () => menus++,
            musicActive: () => context.read<MusicPlaybackService?>()?.currentTrack != null,
          );
          expect(activated.length, session == 'paused-or-playing' ? 0 : 1);
        }
        expect(
          tvHomeCardKeys(
            playback,
            item,
            const KeyDownEvent(
              logicalKey: LogicalKeyboardKey.contextMenu,
              physicalKey: PhysicalKeyboardKey.contextMenu,
              timeStamp: Duration.zero,
            ),
            () => menus++,
            musicActive: () => true,
          ),
          KeyEventResult.handled,
        );
        expect(menus, 1);
      });
    }
  }
}

class _Playback extends TvHomePlayback {
  _Playback(this.activated) : super(clientForItem: (_) => null, play: (_) async {}, openDetails: (_) async {});
  final List<MediaItem> activated;
  @override
  Future<void> activate(MediaItem item) async {
    activated.add(item);
  }
}
