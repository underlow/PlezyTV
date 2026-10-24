import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/play_queue.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_cards.dart';
import 'package:plezy/plezytv/tv_ui/player/tv_player_panel.dart';
import 'package:plezy/plezytv/tv_ui/player/tv_player_queue_row.dart';
import 'package:plezy/plezytv/tv_ui/tv_focusable.dart';
import 'package:plezy/plezytv/tv_ui/tv_strings.dart';
import 'package:plezy/plezytv/tv_ui/tv_ui.dart';
import 'package:plezy/services/settings_service.dart';

import '../../../test_helpers/media_items.dart';
import '../../../test_helpers/tv_player_stand.dart';

/// S9 T3: the queue row. Expectations follow R2, R3, R9, R10, R22 and A5, A6,
/// A17, A18; Plezy's hide spoilers.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final stand = TvPlayerStand();

  setUp(() async {
    await stand.setUp();
    TvUi.enabledForTesting = () => true;
    stand.observeQueueSelections();
  });

  tearDown(() async {
    TvUi.resetForTesting();
    await stand.tearDown();
  });

  String? focused() => FocusManager.instance.primaryFocus?.debugLabel;
  String label(TvPlayerPanelElement element) => 'TvPlayer.${element.name}';

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }

  final episodes = [for (var i = 1; i <= 4; i++) TvPlayerStand.episode(id: 'episode-$i', index: i)];

  /// The focused queue card's label, or null when focus is not in the row.
  String? focusedCard(WidgetTester tester) {
    for (final card in tester.widgetList<TvFocusable>(
      find.descendant(of: find.byType(TvPlayerQueueRow), matching: find.byType(TvFocusable)),
    )) {
      if (card.focusNode?.hasPrimaryFocus ?? false) return card.semanticLabel;
    }
    return null;
  }

  Future<void> pumpEpisodeWithQueue(WidgetTester tester, {int current = 0, bool guest = false}) async {
    stand.setQueue(episodes, current: current);
    await stand.pumpControls(
      tester,
      stand.controls(
        metadata: episodes[current],
        withNext: true,
        withPrevious: true,
        canControl: !guest,
        canNavigateMediaItems: !guest,
      ),
    );
  }

  testWidgets('A5: ↓ from the bar opens the row on the next item; OK starts it through Plezy', (tester) async {
    await pumpEpisodeWithQueue(tester);
    expect(focused(), label(TvPlayerPanelElement.bar));

    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(find.byType(TvPlayerQueueRow), findsOneWidget);
    expect(stand.chrome.contentStripVisible, isTrue, reason: 'Plezy\'s Back chain must know the row is up');
    expect(find.text('Up next in queue'), findsOneWidget, reason: 'row title');
    expect(find.text('Season 1 · 3 more episodes'), findsOneWidget);
    expect(find.text('Panel'), findsOneWidget, reason: 'hint turns into ⌃ Panel');
    expect(focusedCard(tester), 'S1 E2 · Episode 2');

    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(focusedCard(tester), 'S1 E3 · Episode 3');
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(focusedCard(tester), 'S1 E2 · Episode 2');

    await press(tester, LogicalKeyboardKey.select);
    expect(stand.queueSelections.map((MediaItem item) => item.id), ['episode-2']);
    await stand.unmount(tester);
  });

  testWidgets('the row starts with the playing item, the rest follow; earlier items are left out', (tester) async {
    await pumpEpisodeWithQueue(tester, current: 1);
    await press(tester, LogicalKeyboardKey.arrowDown);
    final labels = tester
        .widgetList<TvFocusable>(find.descendant(of: find.byType(TvPlayerQueueRow), matching: find.byType(TvFocusable)))
        .map((card) => card.semanticLabel)
        .toList();
    expect(labels.first, 'S1 E2 · Episode 2');
    expect(labels, isNot(contains('S1 E1 · Episode 1')));
    expect(focusedCard(tester), 'S1 E3 · Episode 3');
    expect(find.textContaining('Now'), findsOneWidget, reason: 'the playing item is marked');
    await stand.unmount(tester);
  });

  testWidgets('↓ from play and ⏭ opens the row too', (tester) async {
    await pumpEpisodeWithQueue(tester);
    await press(tester, LogicalKeyboardKey.arrowUp); // bar → icons
    await press(tester, LogicalKeyboardKey.arrowLeft); // first icon → play
    expect(focused(), label(TvPlayerPanelElement.play));
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(focusedCard(tester), 'S1 E2 · Episode 2');
    await stand.unmount(tester);
  });

  testWidgets('R10: ↑ closes the row, focus on the bar', (tester) async {
    await pumpEpisodeWithQueue(tester);
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(find.byType(TvPlayerQueueRow), findsNothing);
    expect(stand.chrome.contentStripVisible, isFalse);
    expect(focused(), label(TvPlayerPanelElement.bar));
    expect(stand.chrome.controlsVisible, isTrue);
    expect(stand.queueSelections, isEmpty);
    await stand.unmount(tester);
  });

  testWidgets('Back in the row closes the row, not the panel; its release does not hide or exit', (tester) async {
    await pumpEpisodeWithQueue(tester);
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.arrowRight);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.gameButtonB);
    await tester.pump();
    expect(find.byType(TvPlayerQueueRow), findsOneWidget, reason: 'acts on release');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.gameButtonB);
    await tester.pumpAndSettle();
    expect(find.byType(TvPlayerQueueRow), findsNothing);
    expect(stand.chrome.contentStripVisible, isFalse);
    expect(stand.chrome.controlsVisible, isTrue, reason: 'one action per press');
    expect(focused(), label(TvPlayerPanelElement.bar));
    expect(stand.exitCalls, 0);

    await press(tester, LogicalKeyboardKey.gameButtonB);
    expect(stand.chrome.controlsVisible, isFalse, reason: 'the next Back hides the panel');
    expect(stand.exitCalls, 0);
    await stand.unmount(tester);
  });

  testWidgets('hiding the panel drops the row; it comes back closed with focus on the bar', (tester) async {
    await pumpEpisodeWithQueue(tester);
    await press(tester, LogicalKeyboardKey.arrowDown);
    stand.chrome.hide(ignoreHolds: true);
    await tester.pumpAndSettle();
    expect(stand.chrome.contentStripVisible, isFalse);

    await press(tester, LogicalKeyboardKey.select);
    expect(stand.chrome.controlsVisible, isTrue);
    expect(find.byType(TvPlayerQueueRow), findsNothing);
    expect(focused(), label(TvPlayerPanelElement.bar));
    await stand.unmount(tester);
  });

  testWidgets('Plezy dropping the strip closes the row; focus goes to the bar', (tester) async {
    await pumpEpisodeWithQueue(tester);
    await press(tester, LogicalKeyboardKey.arrowDown);
    stand.chrome.setContentStripVisible(false);
    await tester.pumpAndSettle();
    expect(find.byType(TvPlayerQueueRow), findsNothing);
    expect(focused(), label(TvPlayerPanelElement.bar));
    await stand.unmount(tester);
  });

  testWidgets('R11a: a prompt opening over the row closes it and the strip', (tester) async {
    await pumpEpisodeWithQueue(tester);
    await press(tester, LogicalKeyboardKey.arrowDown);
    stand.playNextFocusNode.requestFocus();
    await tester.pumpWidget(
      stand.host(stand.controls(metadata: episodes[0], withNext: true, withPrevious: true, playNextPromptOpen: true)),
    );
    await tester.pumpAndSettle();
    expect(stand.chrome.contentStripVisible, isFalse);
    expect(find.byType(TvPlayerQueueRow), findsNothing);
    expect(focused(), 'PlayNext');
    await stand.unmount(tester);
  });

  for (final offline in [false, true]) {
    testWidgets('A6${offline ? ', A18 (offline)' : ''}: no queue — ↓ does nothing and there is no hint', (
      tester,
    ) async {
      await stand.pumpControls(
        tester,
        offline ? stand.controls(metadata: episodes[0], isOfflinePlayback: true) : stand.controls(),
      );
      expect(find.text('Up next in queue'), findsNothing);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(find.byType(TvPlayerQueueRow), findsNothing);
      expect(stand.chrome.contentStripVisible, isFalse);
      expect(focused(), label(TvPlayerPanelElement.bar));
      await stand.unmount(tester);
    });
  }

  testWidgets('A18: offline with an active queue follows Plezy\'s queue rule — the row opens', (tester) async {
    stand.setQueue(episodes);
    await stand.pumpControls(tester, stand.controls(metadata: episodes[0], withNext: true, isOfflinePlayback: true));
    expect(find.text('Up next in queue'), findsOneWidget);
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(focusedCard(tester), 'S1 E2 · Episode 2');
    await stand.unmount(tester);
  });

  testWidgets('A17: a Watch Together guest without control gets no queue on ↓', (tester) async {
    await pumpEpisodeWithQueue(tester, guest: true);
    expect(find.text('Up next in queue'), findsNothing);
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(find.byType(TvPlayerQueueRow), findsNothing);
    expect(stand.chrome.contentStripVisible, isFalse);
    await stand.unmount(tester);
  });

  Iterable<ImageFiltered> blurs(WidgetTester tester) => tester.widgetList<ImageFiltered>(
    find.descendant(of: find.byType(TvPlayerQueueRow), matching: find.byType(ImageFiltered)),
  );

  testWidgets('hide spoilers blurs unwatched episodes in the row, and follows the setting', (tester) async {
    await SettingsService.instance.write(SettingsService.hideSpoilers, true);
    final items = [
      episodes[0],
      testMediaItem(id: 'watched', kind: MediaKind.episode, title: 'Watched', index: 2, parentIndex: 1, viewCount: 1),
      episodes[2],
    ];
    stand.setQueue(items);
    await stand.pumpControls(tester, stand.controls(metadata: items[0], withNext: true));
    await press(tester, LogicalKeyboardKey.arrowDown);
    // The playing item and the unwatched one; not the watched one.
    expect(blurs(tester), hasLength(2));
    await SettingsService.instance.write(SettingsService.hideSpoilers, false);
    await tester.pumpAndSettle();
    expect(blurs(tester), isEmpty);
    await stand.unmount(tester);
  });

  testWidgets('the playing card\'s bar and caption follow the live position while the row is open', (tester) async {
    // Stored offset (10 of 45 min) differs from the player's (5 min).
    final playing = testMediaItem(
      id: 'episode-1',
      kind: MediaKind.episode,
      title: 'Episode 1',
      index: 1,
      parentIndex: 1,
      durationMs: 45 * 60000,
      viewOffsetMs: 10 * 60000,
    );
    final items = [playing, ...episodes.skip(1)];
    stand.setQueue(items);
    await stand.pumpControls(tester, stand.controls(metadata: playing, withNext: true));
    await press(tester, LogicalKeyboardKey.arrowDown);
    TvMediaProgress bar() => tester.widget<TvMediaProgress>(
      find.descendant(of: find.byType(TvPlayerQueueRow), matching: find.byType(TvMediaProgress)).first,
    );
    expect(find.text('Now · ${TvStrings.left(40 * 60000)}'), findsOneWidget);
    expect(bar().fraction, closeTo(5 / 45, 1e-9));
    stand.player.setPosition(const Duration(minutes: 30)); // the stream delivers on the next frame
    await tester.pump();
    await tester.pump();
    expect(find.text('Now · ${TvStrings.left(15 * 60000)}'), findsOneWidget);
    expect(bar().fraction, closeTo(30 / 45, 1e-9));
    await stand.unmount(tester);
  });

  Future<void> openWith(WidgetTester tester, List<MediaItem> items, {int current = 0}) async {
    stand.setQueue(items, current: current);
    await stand.pumpControls(tester, stand.controls(metadata: items[current], withNext: true));
    await press(tester, LogicalKeyboardKey.arrowDown);
  }

  testWidgets('counter: episodes across seasons drop the season', (tester) async {
    await openWith(tester, [
      episodes[0],
      testMediaItem(id: 's2e1', kind: MediaKind.episode, title: 'Next season', index: 1, parentIndex: 2),
      episodes[1],
    ]);
    expect(find.text('2 more episodes'), findsOneWidget);
    expect(find.textContaining('Season'), findsNothing);
    await stand.unmount(tester);
  });

  testWidgets('counter: one more episode in one season', (tester) async {
    await openWith(tester, episodes.take(2).toList());
    expect(find.text('Season 1 · 1 more episode'), findsOneWidget);
    await stand.unmount(tester);
  });

  testWidgets('counter: items that are not all episodes get a neutral form', (tester) async {
    await openWith(tester, [episodes[0], testMediaItem(id: 'movie', title: 'A movie'), episodes[1]]);
    expect(find.text('2 more'), findsOneWidget);
    await stand.unmount(tester);
  });

  testWidgets('the playing item outside the loaded window: ↓ focuses the first card, all count', (tester) async {
    // A window that does not hold the playing item (currentIndex past it).
    stand.playbackState.setPlaybackFromLocalQueue(LocalPlayQueue(items: episodes, currentIndex: 99));
    await stand.pumpControls(tester, stand.controls(metadata: episodes[0], withNext: true));
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(focusedCard(tester), 'S1 E1 · Episode 1');
    expect(find.text('Season 1 · 4 more episodes'), findsOneWidget);
    expect(find.textContaining('Now'), findsNothing);
    await stand.unmount(tester);
  });

  testWidgets('an active queue with nothing loaded: no hint and ↓ does not open the row', (tester) async {
    stand.playbackState.setPlaybackFromLocalQueue(const LocalPlayQueue(items: [], currentIndex: 0));
    await stand.pumpControls(tester, stand.controls(metadata: episodes[0], withNext: true));
    expect(stand.playbackState.isQueueActive, isTrue);
    expect(find.text('Up next in queue'), findsNothing);
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(find.byType(TvPlayerQueueRow), findsNothing);
    expect(stand.chrome.contentStripVisible, isFalse);
    expect(focused(), label(TvPlayerPanelElement.bar));
    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(focused(), isNot(label(TvPlayerPanelElement.bar)));
    await stand.unmount(tester);
  });
}
