import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:plezy/media/media_item.dart';
import 'package:plezy/plezytv/tv_ui/player/tv_player_hooks.dart';
import 'package:plezy/plezytv/tv_ui/player/tv_player_panel.dart';
import 'package:plezy/plezytv/tv_ui/player/tv_player_session.dart';
import 'package:plezy/plezytv/tv_ui/tv_ui.dart';
import 'package:plezy/screens/video_player/widgets/player_prompt_overlays.dart';
import 'package:plezy/widgets/video_controls/desktop_video_controls.dart';
import 'package:plezy/widgets/video_controls/player_chrome_controller.dart';
import 'package:plezy/widgets/video_controls/widgets/skip_marker_button.dart';

import '../../../test_helpers/media_items.dart';
import '../../../test_helpers/tv_player_stand.dart';

class _Marker extends StatelessWidget {
  const _Marker(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Text(label);
}

/// Every hook switched on, each answering with a labelled stand-in, and the
/// arguments H1 received.
TvPlayerBuilders _allOn(List<TvPlayerPanelArgs> panelArgs) => TvPlayerBuilders(
  panel: (context, args) {
    panelArgs.add(args);
    return const _Marker('tv panel');
  },
  skipButton: (context, plezy) => const _Marker('tv skip'),
  panelOwnsRemote: ({required controlsVisible}) => controlsVisible,
  upNextCard: (context, plezy) => const _Marker('tv up next'),
  buffering: (context, plezy) => const _Marker('tv buffering'),
  playbackError: (args) => const _Marker('tv error'),
  pauseIndicator: (player, chrome) => const _Marker('tv pause'),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final stand = TvPlayerStand();
  final panelArgs = <TvPlayerPanelArgs>[];

  tearDown(() {
    TvUi.resetForTesting();
    panelArgs.clear();
  });

  group('H1 panel lookup (R1, A20)', () {
    tearDown(stand.tearDown);

    testWidgets('TV + movie with the panel switched on: our panel, not Plezy desktop controls', (tester) async {
      await stand.setUp();
      TvUi.enabledForTesting = () => true;
      TvUi.playerBuildersForTesting = _allOn(panelArgs);
      final movie = testMediaItem(id: 'movie-1');
      await stand.pumpControls(
        tester,
        stand.controls(
          metadata: movie,
          canControl: false,
          canNavigateMediaItems: false,
          isOfflinePlayback: true,
          playNextPromptOpen: true,
          playbackPromptOpen: true,
        ),
      );

      expect(find.text('tv panel'), findsOneWidget);
      expect(find.byType(DesktopVideoControls), findsNothing);
      final args = panelArgs.last;
      expect(args.plezy.player, same(stand.player));
      expect(args.plezy.metadata.id, 'movie-1');
      expect(args.plezy.chromeController, same(stand.chrome));
      expect(args.canControl, isFalse);
      expect(args.canNavigateMediaItems, isFalse);
      expect(args.isOfflinePlayback, isTrue);
      expect(args.playbackPromptOpen, isTrue);
      expect(args.playNextFocusNode, same(stand.playNextFocusNode));
      expect(args.skipMarkerFocusNode.debugLabel, 'SkipMarkerButton');
      expect(TvPlayerSession.of(stand.player).itemKey, movie.globalKey);
      await stand.unmount(tester);
    });

    testWidgets('TV + episode with the panel switched on: our panel', (tester) async {
      await stand.setUp();
      TvUi.enabledForTesting = () => true;
      TvUi.playerBuildersForTesting = _allOn(panelArgs);
      await stand.pumpControls(tester, stand.controls(metadata: TvPlayerStand.episode()));
      expect(find.text('tv panel'), findsOneWidget);
      expect(find.byType(DesktopVideoControls), findsNothing);
      await stand.unmount(tester);
    });

    testWidgets('not TV: Plezy controls even with the panel switched on', (tester) async {
      await stand.setUp();
      TvUi.enabledForTesting = () => false;
      TvUi.playerBuildersForTesting = _allOn(panelArgs);
      await stand.pumpControls(tester, stand.controls());
      expect(find.byType(DesktopVideoControls), findsOneWidget);
      expect(find.text('tv panel'), findsNothing);
      expect(panelArgs, isEmpty);
      await stand.unmount(tester);
    });

    testWidgets('Live TV on TV: Plezy controls even with the panel switched on', (tester) async {
      await stand.setUp();
      TvUi.enabledForTesting = () => true;
      TvUi.playerBuildersForTesting = _allOn(panelArgs);
      await stand.pumpControls(tester, stand.controls(isLive: true));
      expect(find.byType(DesktopVideoControls), findsOneWidget);
      expect(find.text('tv panel'), findsNothing);
      expect(panelArgs, isEmpty);
      await stand.unmount(tester);
    });

    testWidgets('production builders: TV gets our panel (T2)', (tester) async {
      await stand.setUp();
      TvUi.enabledForTesting = () => true;
      await stand.pumpControls(tester, stand.controls(chapters: tvStandChapters()));
      expect(find.byType(TvPlayerPanel), findsOneWidget);
      expect(find.byType(DesktopVideoControls), findsNothing);
      await stand.unmount(tester);
    });
  });

  group('H2 skip button lookup', () {
    tearDown(stand.tearDown);

    testWidgets('TV + movie: our skip button; Live TV and not TV: Plezy', (tester) async {
      for (final (tv, live, ours) in [(true, false, true), (true, true, false), (false, false, false)]) {
        await stand.setUp();
        TvUi.enabledForTesting = () => tv;
        // The panel stays Plezy's so the skip button is reachable.
        TvUi.playerBuildersForTesting = TvPlayerBuilders(skipButton: (context, plezy) => const _Marker('tv skip'));
        await stand.pumpControls(tester, stand.controls(isLive: live, markers: tvStandMarkers()));
        final hasSkip = find.byType(SkipMarkerButton).evaluate().isNotEmpty;
        if (ours) {
          expect(find.text('tv skip'), findsOneWidget, reason: 'tv=$tv live=$live');
        } else {
          expect(find.text('tv skip'), findsNothing, reason: 'tv=$tv live=$live');
        }
        expect(hasSkip, isTrue, reason: 'precondition: the marker shows a skip button');
        await stand.unmount(tester);
        await stand.tearDown();
      }
      await stand.setUp();
    });
  });

  group('direct lookups H3–H7', () {
    for (final (tv, live) in [(true, false), (true, true), (false, false)]) {
      final ours = tv && !live;
      test('H3, H6, H7 on tv=$tv live=$live', () {
        TvUi.enabledForTesting = () => tv;
        TvUi.playerBuildersForTesting = _allOn(panelArgs);
        expect(TvUi.playerPanelOwnsRemote(isLive: live, controlsVisible: true), ours);
        expect(TvUi.playerPanelOwnsRemote(isLive: live, controlsVisible: false), isFalse);
        final error = TvUi.playerPlaybackError(
          TvPlaybackErrorArgs(message: 'm', onRetry: () {}, retryFocusNode: FocusNode(), onBack: () {}),
          isLive: live,
        );
        expect(error != null, ours);
        final chrome = PlayerChromeController();
        addTearDown(chrome.dispose);
        expect(
          TvUi.playerPauseIndicator(player: TvStandPlayer(), chromeController: chrome, isLive: live) != null,
          ours,
        );
        expect(TvUi.playerPauseIndicator(player: null, chromeController: chrome, isLive: live), isNull);
      });
    }

    test('production builders: every lookup keeps Plezy on TV', () {
      TvUi.enabledForTesting = () => true;
      final chrome = PlayerChromeController();
      addTearDown(chrome.dispose);
      expect(TvUi.playerPanelOwnsRemote(isLive: false, controlsVisible: true), isFalse);
      expect(
        TvUi.playerPlaybackError(
          TvPlaybackErrorArgs(message: 'm', onRetry: () {}, retryFocusNode: FocusNode(), onBack: () {}),
          isLive: false,
        ),
        isNull,
      );
      expect(TvUi.playerPauseIndicator(player: TvStandPlayer(), chromeController: chrome, isLive: false), isNull);
    });

    group('H4, H5 overlays', () {
      tearDown(stand.tearDown);
      for (final (tv, live) in [(true, false), (false, false), (true, true)]) {
        testWidgets('tv=$tv live=$live', (tester) async {
          await stand.setUp(tv: tv);
          TvUi.enabledForTesting = () => tv;
          TvUi.playerBuildersForTesting = _allOn(panelArgs);
          final cancel = FocusNode();
          final confirm = FocusNode();
          final countdown = ValueNotifier<int>(10);
          final buffering = ValueNotifier<bool>(true);
          final firstFrame = ValueNotifier<bool>(true);
          final exiting = ValueNotifier<bool>(false);
          addTearDown(() {
            cancel.dispose();
            confirm.dispose();
            for (final n in [countdown, buffering, firstFrame, exiting]) {
              n.dispose();
            }
          });
          await tester.pumpWidget(
            stand.host(
              Stack(
                children: [
                  VideoPlayerBufferingOverlay(
                    isBuffering: buffering,
                    hasFirstFrame: firstFrame,
                    isExiting: exiting,
                    isLive: live,
                  ),
                  VideoPlayerPlayNextOverlay(
                    visible: true,
                    nextEpisode: TvPlayerStand.episode(id: 'next', index: 2),
                    autoPlayCountdown: countdown,
                    cancelFocusNode: cancel,
                    confirmFocusNode: confirm,
                    chromeController: stand.chrome,
                    onCancel: () {},
                    onPlayNext: () {},
                    isLive: live,
                  ),
                ],
              ),
            ),
          );
          await tester.pump();
          final ours = tv && !live;
          expect(find.text('tv buffering'), ours ? findsOneWidget : findsNothing);
          expect(find.text('tv up next'), ours ? findsOneWidget : findsNothing);
          expect(find.text('10'), ours ? findsNothing : findsWidgets, reason: 'Plezy countdown off TV and in Live TV');
          await stand.unmount(tester);
        });
      }
    });
  });

  group('TvPlayerSession', () {
    test('one session per player, distinct across players', () {
      final a = TvStandPlayer();
      final b = TvStandPlayer();
      expect(TvPlayerSession.of(a), same(TvPlayerSession.of(a)));
      expect(TvPlayerSession.of(a), isNot(same(TvPlayerSession.of(b))));
    });

    test('a different ratingKey drops focus memory but not the play flag; the same one keeps both', () {
      final session = TvPlayerSession.of(TvStandPlayer());
      MediaItem item(String id) => testMediaItem(id: id);
      session.bindItem(item('1').globalKey);
      final at = DateTime(2026, 10, 24, 12);
      session.rememberFocus('subtitles', at);
      session.focusPlayOnNextShow = true;

      session.bindItem(item('1').globalKey);
      expect(session.lastFocusedId, 'subtitles');
      expect(session.hiddenAt, at);
      expect(session.focusPlayOnNextShow, isTrue);

      session.bindItem(item('2').globalKey);
      expect(session.itemKey, item('2').globalKey);
      expect(session.lastFocusedId, isNull);
      expect(session.hiddenAt, isNull);
      expect(session.focusPlayOnNextShow, isTrue, reason: 'H7 may set it for the new item before the panel binds');
    });

    test('pause with the panel hidden after an in-place episode change keeps focus-play (flow 5)', () {
      final session = TvPlayerSession.of(TvStandPlayer());
      session.bindItem(TvPlayerStand.episode(id: 'ep1').globalKey);
      // Play-next swaps to ep2 on the same player while the panel is hidden;
      // the pause layer then asks for play focus before the panel rebuilds.
      session.focusPlayOnNextShow = true;
      session.bindItem(TvPlayerStand.episode(id: 'ep2', index: 2).globalKey);
      expect(session.focusPlayOnNextShow, isTrue);
    });
  });
}
