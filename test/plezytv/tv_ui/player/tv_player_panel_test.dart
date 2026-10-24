import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:plezy/plezytv/tv_ui/player/tv_player_bar.dart';
import 'package:plezy/plezytv/tv_ui/player/tv_player_panel.dart';
import 'package:plezy/plezytv/tv_ui/player/tv_player_session.dart';
import 'package:plezy/plezytv/tv_ui/tv_focusable.dart';
import 'package:plezy/plezytv/tv_ui/tv_ui.dart';
import 'package:plezy/widgets/video_controls/desktop_video_controls.dart';
import 'package:plezy/widgets/video_controls/player_chrome_controller.dart';

import '../../../test_helpers/tv_player_stand.dart';

/// S9 T2: the TV player panel — layout, showing, navigation, focus, seeking.
/// Expectations follow requirements R2–R8, R11a, R20, R22 and A1–A27.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final stand = TvPlayerStand();

  setUp(() async {
    await stand.setUp();
    TvUi.enabledForTesting = () => true;
  });

  tearDown(() async {
    TvUi.resetForTesting();
    await stand.tearDown();
  });

  String? focused() => FocusManager.instance.primaryFocus?.debugLabel;
  String label(TvPlayerPanelElement element) => 'TvPlayer.${element.name}';
  TvPlayerSession session() => TvPlayerSession.of(stand.player);

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }

  Future<void> hide(WidgetTester tester) async {
    stand.chrome.hide();
    await tester.pumpAndSettle();
  }

  TvFocusable button(WidgetTester tester, String semantics) =>
      tester.widget<TvFocusable>(find.byWidgetPredicate((w) => w is TvFocusable && w.semanticLabel == semantics));

  group('layout (R4)', () {
    testWidgets('episode with queue: header, ⏮ play ⏭, ends at, icons, queue hint; chapter ticks', (tester) async {
      stand.setQueue([TvPlayerStand.episode(), TvPlayerStand.episode(id: 'episode-2', index: 2)]);
      await stand.pumpControls(
        tester,
        stand.controls(
          metadata: TvPlayerStand.episode(),
          withNext: true,
          withPrevious: true,
          chapters: tvStandChapters(),
        ),
      );

      expect(find.byType(TvPlayerPanel), findsOneWidget);
      expect(find.byType(DesktopVideoControls), findsNothing);
      expect(find.text('Episode 1'), findsOneWidget);
      expect(find.textContaining('S1 E1'), findsOneWidget);
      expect(find.textContaining('Ends at'), findsOneWidget);
      expect(find.text('Up next in queue'), findsOneWidget);
      expect(find.text('5:00'), findsOneWidget, reason: 'elapsed');
      expect(find.text('−40:00'), findsOneWidget, reason: 'remaining with a minus');
      for (final semantics in ['Previous episode', 'Play', 'Pause', 'Next episode', 'Subtitles', 'Audio', 'Settings']) {
        final found = find.byWidgetPredicate((w) => w is TvFocusable && w.semanticLabel == semantics);
        if (semantics == 'Play') continue; // playing → pause icon
        expect(found, findsOneWidget, reason: semantics);
      }
      final bar = tester.widget<TvPlayerProgressBar>(find.byType(TvPlayerProgressBar));
      expect(bar.chapters, hasLength(3), reason: 'Plezy shows chapter markers on the timeline by default');
      await stand.unmount(tester);
    });

    testWidgets('movie without queue: no ⏮/⏭, no queue hint (A6, A7)', (tester) async {
      await stand.pumpControls(tester, stand.controls(withNext: true, withPrevious: true));
      expect(find.byWidgetPredicate((w) => w is TvFocusable && w.semanticLabel == 'Previous episode'), findsNothing);
      expect(find.byWidgetPredicate((w) => w is TvFocusable && w.semanticLabel == 'Next episode'), findsNothing);
      expect(find.text('Up next in queue'), findsNothing);
      await stand.unmount(tester);
    });
  });

  group('showing and hiding (R5)', () {
    testWidgets('A1: OK on a hidden panel shows it with focus on the bar', (tester) async {
      await stand.pumpControls(tester, stand.controls(metadata: TvPlayerStand.episode()));
      await hide(tester);
      expect(find.byType(TvPlayerPanel), findsNothing);

      await press(tester, LogicalKeyboardKey.select);
      expect(stand.chrome.controlsVisible, isTrue);
      expect(find.byType(TvPlayerPanel), findsOneWidget);
      expect(focused(), label(TvPlayerPanelElement.bar));
      await stand.unmount(tester);
    });

    testWidgets('A2: hides after 5 s while playing; stays while paused; fades by opacity only', (tester) async {
      await stand.pumpControls(tester, stand.controls());
      stand.player.setPlaying(true);
      await tester.pump();
      stand.chrome.restartAutoHideForCurrentPlaybackState();

      await tester.pump(const Duration(milliseconds: 4900));
      expect(stand.chrome.controlsVisible, isTrue);
      final before = tester.getRect(find.byType(TvPlayerPanel));
      await tester.pump(const Duration(milliseconds: 200));
      expect(stand.chrome.controlsVisible, isFalse);
      await tester.pump(const Duration(milliseconds: 100));
      // Mid-fade: same place and size, only the opacity animates.
      expect(find.byType(TvPlayerPanel), findsOneWidget);
      expect(tester.getRect(find.byType(TvPlayerPanel)), before);
      final fade = tester.widget<AnimatedOpacity>(
        find.ancestor(of: find.byType(TvPlayerPanel), matching: find.byType(AnimatedOpacity)).first,
      );
      expect(fade.opacity, 0);
      expect(fade.duration, const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(find.byType(TvPlayerPanel), findsNothing);

      stand.chrome.show();
      await tester.pumpAndSettle();
      stand.player.setPlaying(false);
      await tester.pump();
      await tester.pump(const Duration(seconds: 10));
      expect(stand.chrome.controlsVisible, isTrue, reason: 'paused: the panel stays');
      await stand.unmount(tester);
    });

    testWidgets('R11a: a prompt appearing hides the panel even while held; the prompt keeps focus', (tester) async {
      await stand.pumpControls(tester, stand.controls(metadata: TvPlayerStand.episode()));
      expect(focused(), label(TvPlayerPanelElement.bar));
      stand.chrome.hold(PlayerChromeHold.promptInteraction);

      await tester.pumpWidget(stand.host(stand.controls(metadata: TvPlayerStand.episode(), playNextPromptOpen: true)));
      stand.playNextFocusNode.requestFocus();
      await tester.pumpAndSettle();

      expect(stand.chrome.controlsVisible, isFalse);
      expect(stand.chrome.contentStripVisible, isFalse);
      expect(stand.playNextFocusNode.hasPrimaryFocus, isTrue);
      stand.chrome.release(PlayerChromeHold.promptInteraction);
      await stand.unmount(tester);
    });

    testWidgets('R11a: "still watching" (playbackPromptOpen) hides the panel and keeps focus on Continue', (tester) async {
      await stand.pumpControls(tester, stand.controls());
      expect(focused(), label(TvPlayerPanelElement.bar));
      // As _showStillWatchingDialog: Continue is focused in a post-frame
      // callback registered before the rebuild; no node goes in the args.
      final continueNode = stand.playNextFocusNode;
      WidgetsBinding.instance.addPostFrameCallback((_) => continueNode.requestFocus());
      await tester.pumpWidget(stand.host(stand.controls(playbackPromptOpen: true)));
      await tester.pumpAndSettle();
      expect(stand.chrome.controlsVisible, isFalse);
      expect(continueNode.hasPrimaryFocus, isTrue, reason: 'focus stays on the prompt');
      await stand.unmount(tester);
    });

    testWidgets('R11a: play next focused post-frame keeps focus after the yield', (tester) async {
      await stand.pumpControls(tester, stand.controls(metadata: TvPlayerStand.episode()));
      WidgetsBinding.instance.addPostFrameCallback((_) => stand.playNextFocusNode.requestFocus());
      await tester.pumpWidget(stand.host(stand.controls(metadata: TvPlayerStand.episode(), playNextPromptOpen: true)));
      await tester.pumpAndSettle();
      expect(stand.chrome.controlsVisible, isFalse);
      expect(stand.playNextFocusNode.hasPrimaryFocus, isTrue);
      await stand.unmount(tester);
    });

    testWidgets('R11a: the panel shown while a prompt is open yields to it', (tester) async {
      await stand.pumpControls(tester, stand.controls(metadata: TvPlayerStand.episode()));
      WidgetsBinding.instance.addPostFrameCallback((_) => stand.playNextFocusNode.requestFocus());
      await tester.pumpWidget(stand.host(stand.controls(metadata: TvPlayerStand.episode(), playNextPromptOpen: true)));
      await tester.pumpAndSettle();
      expect(stand.chrome.controlsVisible, isFalse);

      // As _listenToCompleted at EOF: show and cancel auto-hide.
      stand.chrome.show();
      stand.chrome.cancelAutoHide();
      await tester.pumpAndSettle();
      expect(stand.chrome.controlsVisible, isFalse);
      expect(stand.playNextFocusNode.hasPrimaryFocus, isTrue);
      await stand.unmount(tester);
    });

    testWidgets('R11a: show and a prompt in the same frame yield and drop the pause flag', (tester) async {
      await stand.pumpControls(tester, stand.controls());
      await hide(tester);
      session().focusPlayOnNextShow = true;
      final continueNode = stand.playNextFocusNode;
      WidgetsBinding.instance.addPostFrameCallback((_) => continueNode.requestFocus());
      stand.chrome.show();
      await tester.pumpWidget(stand.host(stand.controls(playbackPromptOpen: true)));
      await tester.pumpAndSettle();
      expect(stand.chrome.controlsVisible, isFalse);
      expect(session().focusPlayOnNextShow, isFalse);
      expect(continueNode.hasPrimaryFocus, isTrue);
      await stand.unmount(tester);
    });
  });

  group('navigation (R6)', () {
    testWidgets('bar ↑ icons, ←/→ between icons, ← from the first icon to play, ↓ back to the bar', (tester) async {
      await stand.pumpControls(tester, stand.controls());
      expect(focused(), label(TvPlayerPanelElement.bar));
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(focused(), label(TvPlayerPanelElement.subtitles));
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(focused(), label(TvPlayerPanelElement.audio));
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(focused(), label(TvPlayerPanelElement.settings));
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(focused(), label(TvPlayerPanelElement.settings));
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focused(), label(TvPlayerPanelElement.bar));
      await press(tester, LogicalKeyboardKey.arrowUp);
      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(focused(), label(TvPlayerPanelElement.play));
      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(focused(), label(TvPlayerPanelElement.play), reason: 'movie: nothing left of play');
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(focused(), label(TvPlayerPanelElement.bar));
      expect(stand.chrome.controlsVisible, isTrue);
      await stand.unmount(tester);
    });

    testWidgets('A7: OK on ⏭ plays the next episode as Plezy does', (tester) async {
      await stand.pumpControls(
        tester,
        stand.controls(metadata: TvPlayerStand.episode(), withNext: true, withPrevious: true),
      );
      await press(tester, LogicalKeyboardKey.arrowUp);
      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(focused(), label(TvPlayerPanelElement.play));
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(focused(), label(TvPlayerPanelElement.next));
      await press(tester, LogicalKeyboardKey.select);
      expect(stand.nextCalls, 1);
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(focused(), label(TvPlayerPanelElement.bar), reason: '→ from the last button goes to the bar');
      await stand.unmount(tester);
    });

    testWidgets('A22: ⏮ is active and runs Plezy previous (restart or previous item)', (tester) async {
      stand.player.setPosition(const Duration(seconds: 10));
      await stand.pumpControls(tester, stand.controls(metadata: TvPlayerStand.episode(), withPrevious: true));
      expect(button(tester, 'Previous episode').disabled, isFalse);
      expect(button(tester, 'Next episode').disabled, isTrue, reason: 'no next episode');
      await press(tester, LogicalKeyboardKey.arrowUp);
      await press(tester, LogicalKeyboardKey.arrowLeft);
      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(focused(), label(TvPlayerPanelElement.previous));
      await press(tester, LogicalKeyboardKey.select);
      expect(stand.previousCalls, 1);
      await stand.unmount(tester);
    });

    testWidgets('OK on the bar toggles playback', (tester) async {
      await stand.pumpControls(tester, stand.controls());
      expect(stand.player.state.playing, isTrue);
      await press(tester, LogicalKeyboardKey.select);
      expect(stand.player.state.playing, isFalse);
      await stand.unmount(tester);
    });

    testWidgets('Play/Pause on the remote is Plezy\'s: toggles playback, focus stays', (tester) async {
      await stand.pumpControls(tester, stand.controls());
      await press(tester, LogicalKeyboardKey.mediaPlayPause);
      expect(stand.player.state.playing, isFalse);
      expect(focused(), label(TvPlayerPanelElement.bar));
      await stand.unmount(tester);
    });

    testWidgets('A26/A17: a guest without control — Play/Pause does nothing, ⏮/⏭ inactive, no seek', (tester) async {
      await stand.pumpControls(
        tester,
        stand.controls(metadata: TvPlayerStand.episode(), canControl: false, withNext: true, withPrevious: true),
      );
      await press(tester, LogicalKeyboardKey.mediaPlayPause);
      expect(stand.player.state.playing, isTrue);
      expect(button(tester, 'Previous episode').disabled, isTrue);
      expect(button(tester, 'Next episode').disabled, isTrue);
      expect(tester.widget<TvPlayerProgressBar>(find.byType(TvPlayerProgressBar)).inactive, isTrue);

      expect(focused(), label(TvPlayerPanelElement.bar));
      await press(tester, LogicalKeyboardKey.arrowRight);
      await tester.pump(const Duration(seconds: 2));
      expect(stand.player.seeks, isEmpty);
      await press(tester, LogicalKeyboardKey.select);
      expect(stand.player.state.playing, isTrue, reason: 'OK on the bar is play/pause, denied too');

      await press(tester, LogicalKeyboardKey.arrowUp);
      await press(tester, LogicalKeyboardKey.arrowLeft);
      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(focused(), label(TvPlayerPanelElement.previous), reason: 'inactive buttons stay reachable');
      await press(tester, LogicalKeyboardKey.select);
      expect(stand.previousCalls, 0);
      await stand.unmount(tester);
    });
  });

  group('focus memory (R7)', () {
    testWidgets('A21: back on the last element within 30 s; on the bar after 40 s', (tester) async {
      var now = DateTime(2026, 10, 24, 20);
      await withClock(Clock(() => now), () async {
        await stand.pumpControls(tester, stand.controls());
        await press(tester, LogicalKeyboardKey.arrowUp);
        await press(tester, LogicalKeyboardKey.arrowRight);
        expect(focused(), label(TvPlayerPanelElement.audio));
        await hide(tester);

        now = now.add(const Duration(seconds: 10));
        await press(tester, LogicalKeyboardKey.select);
        expect(focused(), label(TvPlayerPanelElement.audio));

        await hide(tester);
        now = now.add(const Duration(seconds: 40));
        await press(tester, LogicalKeyboardKey.select);
        expect(focused(), label(TvPlayerPanelElement.bar));
        await stand.unmount(tester);
      });
    });

    testWidgets('a remembered element that became inactive gives way to the bar', (tester) async {
      await stand.pumpControls(tester, stand.controls(metadata: TvPlayerStand.episode(), withNext: true));
      await press(tester, LogicalKeyboardKey.arrowUp);
      await press(tester, LogicalKeyboardKey.arrowLeft);
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(focused(), label(TvPlayerPanelElement.next));
      await hide(tester);

      await tester.pumpWidget(stand.host(stand.controls(metadata: TvPlayerStand.episode())));
      await press(tester, LogicalKeyboardKey.select);
      expect(focused(), label(TvPlayerPanelElement.bar));
      await stand.unmount(tester);
    });

    testWidgets('A27: the play flag puts focus on play once and is consumed', (tester) async {
      await stand.pumpControls(tester, stand.controls());
      await press(tester, LogicalKeyboardKey.arrowUp);
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(focused(), label(TvPlayerPanelElement.audio));
      await hide(tester);

      // What H7 does on a remote pause with the panel hidden (flow 5).
      session().focusPlayOnNextShow = true;
      stand.chrome.show();
      await tester.pumpAndSettle();
      expect(focused(), label(TvPlayerPanelElement.play));
      expect(session().focusPlayOnNextShow, isFalse, reason: 'consumed on showing');

      await press(tester, LogicalKeyboardKey.arrowUp);
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(focused(), label(TvPlayerPanelElement.audio));
      await hide(tester);
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(focused(), label(TvPlayerPanelElement.audio), reason: 'no stale flag on a later showing');
      await stand.unmount(tester);
    });
  });

  group('seeking on the bar (R8)', () {
    Future<Duration> heldRight(WidgetTester tester, {int repeats = 3}) async {
      final panel = tester.widget<TvPlayerPanel>(find.byType(TvPlayerPanel));
      final step = Duration(seconds: panel.args.plezy.seekTimeSmall);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump(const Duration(milliseconds: 50));
      for (var i = 0; i < repeats; i++) {
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump(const Duration(milliseconds: 50));
      }
      return step + step * 1.5 * repeats;
    }

    testWidgets('A3: holding → shows the frame and time; one seek on release to the accumulated target', (
      tester,
    ) async {
      await stand.pumpControls(tester, stand.controls(withThumbnails: true));
      final start = stand.player.state.position;
      final travelled = await heldRight(tester);

      expect(stand.player.seeks, isEmpty, reason: 'no seek while held');
      expect(find.byKey(const ValueKey('tv-player-seek-frame')), findsOneWidget);
      expect(find.byType(TvPlayerSeekPreview), findsOneWidget);

      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(stand.player.seeks, [start + travelled]);
      await tester.pump(const Duration(seconds: 3));
      expect(stand.player.seeks, hasLength(1), reason: 'exactly one seek');
      await stand.unmount(tester);
    });

    testWidgets('A4: without thumbnails only the time shows', (tester) async {
      await stand.pumpControls(tester, stand.controls());
      final start = stand.player.state.position;
      final travelled = await heldRight(tester);
      expect(find.byType(TvPlayerSeekPreview), findsOneWidget);
      expect(find.byKey(const ValueKey('tv-player-seek-frame')), findsNothing);
      final preview = tester.widget<TvPlayerSeekPreview>(find.byType(TvPlayerSeekPreview));
      expect(preview.target, start + travelled);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(stand.player.seeks, [start + travelled]);
      await stand.unmount(tester);
    });

    testWidgets('A18: offline playback shows only the time even with thumbnails', (tester) async {
      await stand.pumpControls(tester, stand.controls(withThumbnails: true, isOfflinePlayback: true));
      await heldRight(tester);
      expect(find.byType(TvPlayerSeekPreview), findsOneWidget);
      expect(find.byKey(const ValueKey('tv-player-seek-frame')), findsNothing);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      await stand.unmount(tester);
    });

    testWidgets('⏩ on the remote without chapters is Plezy\'s step; the hidden panel stays hidden', (tester) async {
      await stand.pumpControls(tester, stand.controls());
      await hide(tester);
      final start = stand.player.state.position;
      final panel = find.byType(TvPlayerPanel);
      await tester.sendKeyEvent(LogicalKeyboardKey.mediaFastForward);
      await tester.pump(const Duration(seconds: 2));
      expect(stand.chrome.controlsVisible, isFalse);
      expect(panel, findsNothing);
      expect(stand.player.seeks, hasLength(1));
      expect(stand.player.seeks.single, greaterThan(start));
      await stand.unmount(tester);
    });

    testWidgets('A15 (part): buffering makes the bar inactive', (tester) async {
      await stand.pumpControls(tester, stand.controls());
      expect(tester.widget<TvPlayerProgressBar>(find.byType(TvPlayerProgressBar)).inactive, isFalse);
      stand.player.setBuffering(true);
      await tester.pump();
      await tester.pump();
      expect(tester.widget<TvPlayerProgressBar>(find.byType(TvPlayerProgressBar)).inactive, isTrue);
      stand.player.setBuffering(false);
      await tester.pump();
      await stand.unmount(tester);
    });

    testWidgets('a burst pending when the item changes is dropped, not committed', (tester) async {
      await stand.pumpControls(tester, stand.controls(metadata: TvPlayerStand.episode()));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      await tester.pumpWidget(stand.host(stand.controls(metadata: TvPlayerStand.episode(id: 'e2', index: 2))));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump(const Duration(seconds: 2));
      expect(stand.player.seeks, isEmpty);
      await stand.unmount(tester);
    });
  });

  group('Back (R22)', () {
    testWidgets('Back hides the visible panel; its release does not leave the player', (tester) async {
      await stand.pumpControls(tester, stand.controls());
      await tester.sendKeyDownEvent(LogicalKeyboardKey.gameButtonB);
      await tester.pump();
      expect(stand.chrome.controlsVisible, isTrue, reason: 'acts on release');
      await tester.sendKeyUpEvent(LogicalKeyboardKey.gameButtonB);
      await tester.pumpAndSettle();
      expect(stand.chrome.controlsVisible, isFalse);
      expect(stand.exitCalls, 0);
      await stand.unmount(tester);
    });

    testWidgets('Back on the icons moves to the bar; Back again hides the panel', (tester) async {
      await stand.pumpControls(tester, stand.controls());
      await press(tester, LogicalKeyboardKey.arrowUp);
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(focused(), label(TvPlayerPanelElement.audio));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.gameButtonB);
      await tester.pump();
      expect(focused(), label(TvPlayerPanelElement.audio), reason: 'acts on release');
      await tester.sendKeyUpEvent(LogicalKeyboardKey.gameButtonB);
      await tester.pumpAndSettle();
      expect(focused(), label(TvPlayerPanelElement.bar));
      expect(stand.chrome.controlsVisible, isTrue);
      expect(stand.exitCalls, 0);

      await press(tester, LogicalKeyboardKey.gameButtonB);
      expect(stand.chrome.controlsVisible, isFalse);
      expect(stand.exitCalls, 0);
      await stand.unmount(tester);
    });

    testWidgets('A19: Back with the panel hidden leaves the player', (tester) async {
      await stand.pumpControls(tester, stand.controls());
      await hide(tester);
      await press(tester, LogicalKeyboardKey.gameButtonB);
      expect(stand.exitCalls, 1);
      await stand.unmount(tester);
    });
  });
}
