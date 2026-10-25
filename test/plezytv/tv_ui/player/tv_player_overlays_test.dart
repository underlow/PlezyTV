import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:plezy/plezytv/tv_ui/player/tv_player_hooks.dart';
import 'package:plezy/plezytv/tv_ui/player/tv_player_overlays.dart';
import 'package:plezy/plezytv/tv_ui/player/tv_player_panel.dart';
import 'package:plezy/plezytv/tv_ui/player/tv_player_session.dart';
import 'package:plezy/plezytv/tv_ui/player/tv_player_side_panel.dart';
import 'package:plezy/plezytv/tv_ui/tv_ui.dart';
import 'package:plezy/screens/video_player/widgets/player_prompt_overlays.dart';
import 'package:plezy/widgets/video_controls/player_chrome_controller.dart';

import '../../../test_helpers/tv_player_stand.dart';

/// S9 T5: overlays — skip button (H2/H3), pause indicator and pause from the
/// remote (H7), play-next card (H4), buffering (H5), playback error (H6).
/// Expectations follow R5, R11a, R17–R21 and A12–A16, A23, A25, A27.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final stand = TvPlayerStand();

  tearDown(() async {
    TvUi.resetForTesting();
    await stand.tearDown();
  });

  /// Starts the stand on TV with production builders and the player at
  /// [position] (the intro marker covers 4–6 minutes).
  Future<void> setUpAt({Duration position = const Duration(minutes: 1)}) async {
    await stand.setUp(player: TvStandPlayer(position: position));
    TvUi.enabledForTesting = () => true;
  }

  String? focused() => FocusManager.instance.primaryFocus?.debugLabel;
  String label(TvPlayerPanelElement element) => 'TvPlayer.${element.name}';
  TvPlayerSession session() => TvPlayerSession.of(stand.player);
  final skip = find.byType(TvSkipButton);
  final skipText = find.text('Skip Intro');

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }

  Future<void> hide(WidgetTester tester) async {
    stand.chrome.hide();
    await tester.pumpAndSettle();
  }

  Future<void> enterIntro(WidgetTester tester) async {
    stand.player.setPosition(const Duration(minutes: 5));
    await tester.pumpAndSettle();
  }

  group('skip button (H2, H3, R17)', () {
    testWidgets('A12: a marker with the panel hidden — our button takes focus; OK skips as Plezy does', (tester) async {
      await setUpAt();
      await stand.pumpControls(tester, stand.controls(markers: tvStandMarkers()));
      await hide(tester);
      await enterIntro(tester);

      expect(skip, findsOneWidget);
      expect(skipText, findsOneWidget);
      expect(focused(), 'SkipMarkerButton');
      final rect = tester.getRect(skipText);
      expect(rect.right, greaterThan(1600), reason: 'bottom right');
      expect(rect.bottom, greaterThan(980));

      await press(tester, LogicalKeyboardKey.select);
      expect(stand.player.seeks.last, const Duration(minutes: 6), reason: 'to the marker end');
      await stand.unmount(tester);
    });

    testWidgets('with the panel up: no focus taken, sits above the icons, ↑ from the icons and ↓ back', (tester) async {
      await setUpAt();
      await stand.pumpControls(tester, stand.controls(markers: tvStandMarkers()));
      expect(focused(), label(TvPlayerPanelElement.bar));
      await enterIntro(tester);

      expect(skipText, findsOneWidget);
      expect(focused(), label(TvPlayerPanelElement.bar), reason: 'R11a/R17: the panel keeps the remote');
      final button = tester.getRect(find.descendant(of: skip, matching: find.byType(Container)).first);
      expect(button.bottom, lessThanOrEqualTo(840), reason: 'above the icons (y = 840)');
      expect(button.right, closeTo(1824, 4), reason: 'right-aligned with the icons (1760 + 64)');

      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(focused(), label(TvPlayerPanelElement.subtitles));
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(focused(), 'SkipMarkerButton');
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focused(), label(TvPlayerPanelElement.subtitles));
      await stand.unmount(tester);
    });

    testWidgets('Back on the button with the panel up hides the button; the release does not hide the panel', (
      tester,
    ) async {
      await setUpAt();
      await stand.pumpControls(tester, stand.controls(markers: tvStandMarkers()));
      await enterIntro(tester);
      await press(tester, LogicalKeyboardKey.arrowUp);
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(focused(), 'SkipMarkerButton');

      await tester.sendKeyDownEvent(LogicalKeyboardKey.gameButtonB);
      await tester.pump();
      expect(skipText, findsOneWidget, reason: 'acts on release');
      await tester.sendKeyUpEvent(LogicalKeyboardKey.gameButtonB);
      await tester.pumpAndSettle();
      expect(skipText, findsNothing);
      expect(stand.chrome.controlsVisible, isTrue);
      expect(stand.exitCalls, 0);
      expect(focused(), label(TvPlayerPanelElement.subtitles));

      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(focused(), label(TvPlayerPanelElement.subtitles), reason: 'nothing above the icons now');
      await stand.unmount(tester);
    });

    testWidgets('A25: a marker while the right panel is open — hidden, no focus; back on close', (tester) async {
      await setUpAt();
      await stand.pumpControls(tester, stand.controls(markers: tvStandMarkers()));
      await press(tester, LogicalKeyboardKey.arrowUp);
      await press(tester, LogicalKeyboardKey.select);
      expect(find.byType(TvPlayerSidePanel), findsOneWidget);
      final inSide = focused();

      await enterIntro(tester);
      expect(skipText, findsNothing);
      expect(focused(), inSide, reason: 'focus stays in the right panel');

      await press(tester, LogicalKeyboardKey.gameButtonB);
      expect(find.byType(TvPlayerSidePanel), findsNothing);
      expect(skipText, findsOneWidget, reason: 'the marker is still on');
      expect(focused(), label(TvPlayerPanelElement.subtitles));
      await stand.unmount(tester);
    });
  });

  group('pause (H7, R5, R18)', () {
    Widget layer() => TvUi.playerPauseIndicator(
      player: stand.player,
      chromeController: stand.chrome,
      promptOpen: false,
      isLive: false,
    )!;

    testWidgets('A27: Play/Pause with the panel hidden pauses and shows the panel with focus on play', (tester) async {
      await setUpAt();
      await stand.pumpControls(tester, stand.controls(), layer: layer());
      await press(tester, LogicalKeyboardKey.arrowUp);
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(focused(), label(TvPlayerPanelElement.audio));
      await hide(tester);

      await press(tester, LogicalKeyboardKey.mediaPlayPause);
      expect(stand.player.state.playing, isFalse);
      expect(stand.chrome.controlsVisible, isTrue);
      expect(find.byType(TvPlayerPanel), findsOneWidget);
      expect(focused(), label(TvPlayerPanelElement.play));
      expect(session().focusPlayOnNextShow, isFalse, reason: 'consumed');
      expect(find.text('Paused'), findsNothing, reason: 'not with the panel up');
      await stand.unmount(tester);
    });

    testWidgets('a pause while a prompt is open leaves the panel down and sets no flag', (tester) async {
      await setUpAt();
      await stand.pumpControls(
        tester,
        stand.controls(),
        layer: TvUi.playerPauseIndicator(
          player: stand.player,
          chromeController: stand.chrome,
          promptOpen: true,
          isLive: false,
        ),
      );
      await hide(tester);
      stand.player.setPlaying(false);
      await tester.pumpAndSettle();
      expect(stand.chrome.controlsVisible, isFalse);
      expect(session().focusPlayOnNextShow, isFalse);
      expect(find.text('Paused'), findsNothing);
      await stand.unmount(tester);
    });

    testWidgets('A13: Back on a paused panel — indicator; gone after 5 min and stays gone until playback resumes', (
      tester,
    ) async {
      await setUpAt();
      await stand.pumpControls(tester, stand.controls(), layer: layer());
      stand.player.setPlaying(false);
      await tester.pumpAndSettle();
      expect(stand.chrome.controlsVisible, isTrue);
      expect(find.text('Paused'), findsNothing, reason: 'panel visible');

      await press(tester, LogicalKeyboardKey.gameButtonB);
      expect(stand.chrome.controlsVisible, isFalse);
      expect(stand.exitCalls, 0);
      expect(find.text('Paused'), findsOneWidget);
      expect(find.text('1:00 / 45:00'), findsOneWidget);
      final rect = tester.getRect(find.text('Paused'));
      expect(rect.left, lessThan(300), reason: 'bottom left');
      expect(rect.top, greaterThan(900));

      await tester.pump(const Duration(minutes: 4));
      expect(find.text('Paused'), findsOneWidget);
      await tester.pump(const Duration(minutes: 1, seconds: 1));
      expect(find.text('Paused'), findsNothing, reason: '5 min from the pause start');

      stand.chrome.show();
      await tester.pumpAndSettle();
      await hide(tester);
      expect(find.text('Paused'), findsNothing, reason: 'does not return while still paused');

      stand.player.setPlaying(true);
      await tester.pumpAndSettle();
      expect(find.text('Paused'), findsNothing);
      stand.player.setPlaying(false);
      await tester.pumpAndSettle();
      expect(stand.chrome.controlsVisible, isFalse, reason: 'a pause not from the remote key leaves the panel down');
      expect(find.text('Paused'), findsOneWidget, reason: 'back after resuming and pausing again');
      await stand.unmount(tester);
    });

    testWidgets('A23: ⏩ with chapters goes to the next chapter; the panel does not open', (tester) async {
      await setUpAt(position: const Duration(minutes: 5));
      await stand.pumpControls(tester, stand.controls(chapters: tvStandChapters()), layer: layer());
      await hide(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.mediaFastForward);
      await tester.pump(const Duration(seconds: 2));
      expect(stand.player.seeks.last, const Duration(minutes: 10));
      expect(stand.chrome.controlsVisible, isFalse);
      expect(find.byType(TvPlayerPanel), findsNothing);
      await stand.unmount(tester);
    });
  });

  group('play-next card (H4, R19, A14)', () {
    late FocusNode cancel;
    late FocusNode confirm;
    late ValueNotifier<int> countdown;
    late int played;
    late int cancelled;

    Widget overlay() => Stack(
      children: [
        VideoPlayerPlayNextOverlay(
          visible: true,
          nextEpisode: TvPlayerStand.episode(id: 'episode-2', index: 2),
          autoPlayCountdown: countdown,
          cancelFocusNode: cancel,
          confirmFocusNode: confirm,
          chromeController: stand.chrome,
          onCancel: () => cancelled++,
          onPlayNext: () => played++,
        ),
      ],
    );

    Future<void> pumpCard(WidgetTester tester, int start) async {
      await setUpAt();
      cancel = FocusNode(debugLabel: 'cancel');
      confirm = FocusNode(debugLabel: 'confirm');
      countdown = ValueNotifier<int>(start);
      played = 0;
      cancelled = 0;
      addTearDown(() {
        cancel.dispose();
        confirm.dispose();
        countdown.dispose();
      });
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1920, 1080);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(stand.host(overlay()));
      // Plezy's screen focuses Watch when the prompt opens.
      confirm.requestFocus();
      await tester.pumpAndSettle();
    }

    testWidgets('countdown, title, Watch focused; OK plays next; → Cancel, OK cancels', (tester) async {
      await pumpCard(tester, 15);
      expect(find.byType(TvUpNextCard), findsOneWidget);
      expect(find.text('NEXT EPISODE IN 15 S'), findsOneWidget);
      expect(find.text('S1 E2 · Episode 2'), findsOneWidget);
      expect(stand.chrome.isHeld(PlayerChromeHold.promptInteraction), isTrue, reason: 'Plezy\'s shell holds');
      final card = tester.getRect(find.byType(TvUpNextCard));
      expect(card.width, 720);
      expect(card.right, greaterThan(1800), reason: 'in the corner, Plezy\'s position');

      countdown.value = 12;
      await tester.pumpAndSettle();
      expect(find.text('NEXT EPISODE IN 12 S'), findsOneWidget);
      final fill = tester.widgetList<FractionallySizedBox>(find.byType(FractionallySizedBox)).single;
      expect(fill.widthFactor, closeTo(12 / 15, 0.001));

      expect(focused(), 'confirm');
      await press(tester, LogicalKeyboardKey.select);
      expect(played, 1);
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(focused(), 'cancel');
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focused(), 'cancel', reason: 'focus stays on the card');
      await press(tester, LogicalKeyboardKey.select);
      expect(cancelled, 1);
      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(focused(), 'confirm');
    });

    testWidgets('without a countdown (auto-play off): only the buttons, no bar', (tester) async {
      await pumpCard(tester, 0);
      expect(find.text('NEXT EPISODE'), findsOneWidget);
      expect(find.byType(FractionallySizedBox), findsNothing);
      expect(find.text('Play'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });
  });

  testWidgets('A15: buffering — three dots in place of Plezy\'s spinner, shown when Plezy shows it', (tester) async {
    await setUpAt();
    final buffering = ValueNotifier<bool>(true);
    final hasFrame = ValueNotifier<bool>(true);
    final exiting = ValueNotifier<bool>(false);
    addTearDown(() {
      buffering.dispose();
      hasFrame.dispose();
      exiting.dispose();
    });
    await tester.pumpWidget(
      stand.host(
        Stack(
          children: [VideoPlayerBufferingOverlay(isBuffering: buffering, hasFirstFrame: hasFrame, isExiting: exiting)],
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(TvBufferingDots), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.bySemanticsLabel('Loading video'), findsOneWidget);
    final first = tester.widgetList<Opacity>(find.byType(Opacity)).map((o) => o.opacity).toList();
    await tester.pump(const Duration(milliseconds: 400));
    final later = tester.widgetList<Opacity>(find.byType(Opacity)).map((o) => o.opacity).toList();
    expect(first, hasLength(3));
    expect(later, isNot(equals(first)), reason: 'blinking by opacity');

    buffering.value = false;
    await tester.pump();
    expect(find.byType(Opacity), findsNothing);
    hasFrame.value = false;
    await tester.pump();
    expect(find.byType(Opacity), findsNWidgets(3), reason: 'initial load, as Plezy');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('A16: playback error — Plezy\'s text, Retry focused and runs Plezy\'s retry; Back', (tester) async {
    await setUpAt();
    final retryNode = FocusNode(debugLabel: 'retry');
    addTearDown(retryNode.dispose);
    var retries = 0;
    var backs = 0;
    await tester.pumpWidget(
      stand.host(
        TvUi.playerPlaybackError(
          TvPlaybackErrorArgs(
            message: 'The server did not respond.',
            onRetry: () => retries++,
            retryFocusNode: retryNode,
            onBack: () => backs++,
          ),
          isLive: false,
        )!,
      ),
    );
    // Plezy's screen focuses Retry explicitly.
    retryNode.requestFocus();
    await tester.pumpAndSettle();
    expect(find.byType(TvPlaybackError), findsOneWidget);
    expect(find.text('The server did not respond.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Back'), findsOneWidget);

    await press(tester, LogicalKeyboardKey.select);
    expect(retries, 1);
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(focused(), 'TvPlaybackError.back');
    await press(tester, LogicalKeyboardKey.select);
    expect(backs, 1);
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(focused(), 'retry');
  });
}
