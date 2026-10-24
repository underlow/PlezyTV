import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:plezy/media/media_item.dart';
import 'package:plezy/plezytv/tv_ui/player/tv_player_panel.dart';
import 'package:plezy/plezytv/tv_ui/player/tv_player_queue_row.dart';
import 'package:plezy/plezytv/tv_ui/tv_focusable.dart';
import 'package:plezy/plezytv/tv_ui/tv_ui.dart';

import '../../../test_helpers/tv_player_stand.dart';

/// S9 T3: the queue row. Expectations follow R2, R3, R9, R10, R22 and A5, A6,
/// A17, A18.
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

  testWidgets('A6: a movie without a queue — ↓ does nothing and there is no hint', (tester) async {
    await stand.pumpControls(tester, stand.controls());
    expect(find.text('Up next in queue'), findsNothing);
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(find.byType(TvPlayerQueueRow), findsNothing);
    expect(stand.chrome.contentStripVisible, isFalse);
    expect(focused(), label(TvPlayerPanelElement.bar));
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

  testWidgets('A18: offline playback without a queue has no hint and ↓ does nothing', (tester) async {
    await stand.pumpControls(tester, stand.controls(metadata: episodes[0], isOfflinePlayback: true));
    expect(find.text('Up next in queue'), findsNothing);
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(find.byType(TvPlayerQueueRow), findsNothing);
    await stand.unmount(tester);
  });
}
