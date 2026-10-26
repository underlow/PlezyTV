import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/plezytv/tv_ui/home/tv_home_card.dart';
import 'package:plezy/plezytv/tv_ui/home/tv_home_playback.dart';
import '../../test_helpers/media_items.dart';

void main() {
  testWidgets('C4 active music ignores transport key-up and preserves Menu', (tester) async {
    final item = testMediaItem(kind: MediaKind.track);
    final activated = <MediaItem>[];
    final playback = _Playback(activated);
    var menus = 0;
    for (final key in [LogicalKeyboardKey.mediaPlay, LogicalKeyboardKey.mediaPlayPause]) {
      expect(
        tvHomeCardKeys(
          playback,
          item,
          KeyUpEvent(logicalKey: key, physicalKey: PhysicalKeyboardKey.mediaPlayPause, timeStamp: Duration.zero),
          () => menus++,
          musicActive: () => true,
        ),
        KeyEventResult.ignored,
      );
    }
    expect(activated, isEmpty);
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
    expect(activated, isEmpty);
  });
}

class _Playback extends TvHomePlayback {
  _Playback(this.activated) : super(clientForItem: (_) => null, play: (_) async {}, openDetails: (_) async {});
  final List<MediaItem> activated;
  @override
  Future<void> activate(MediaItem item) async {
    activated.add(item);
  }
}
