import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:plezy/focus/dpad_navigator.dart';
import 'package:plezy/focus/key_event_utils.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/play_queue.dart';
import 'package:plezy/models/plex/play_queue_response.dart';
import 'package:plezy/plezytv/tv_ui/player/tv_player_hooks.dart';
import 'package:plezy/plezytv/tv_ui/player/tv_player_session.dart';
import 'package:plezy/plezytv/tv_ui/postplay/tv_postplay_exit.dart';
import 'package:plezy/plezytv/tv_ui/tv_ui.dart';
import 'package:plezy/providers/playback_state_provider.dart';
import 'package:plezy/services/sleep_timer_service.dart';
import 'package:plezy/utils/platform_detector.dart';
import 'package:plezy/widgets/overlay_sheet.dart';
import 'package:plezy/widgets/video_controls/player_chrome_controller.dart';

import '../../../test_helpers/media_items.dart';
import '../../../test_helpers/tv_player_stand.dart';

final _movie = testMediaItem(id: 'movie-1', title: 'Movie');
final _episode = testMediaItem(
  id: 'ep-1',
  kind: MediaKind.episode,
  title: 'Episode',
  grandparentId: 'show-1',
  parentId: 'season-1',
);
final _otherEpisode = testMediaItem(
  id: 'ep-2',
  kind: MediaKind.episode,
  title: 'Other',
  grandparentId: 'show-1',
  parentId: 'season-1',
);

TvPostPlayFacts _facts({
  bool tv = true,
  bool isLive = false,
  bool isOffline = false,
  bool watchTogether = false,
  MediaKind kind = MediaKind.movie,
  bool latched = true,
  bool promptOpen = false,
  bool loadingNext = false,
  bool sleepTimerEnded = false,
  QueueNavigationStatus nextStatus = QueueNavigationStatus.unavailable,
  bool normalLaunch = true,
}) => TvPostPlayFacts(
  tv: tv,
  isLive: isLive,
  isOffline: isOffline,
  watchTogether: watchTogether,
  kind: kind,
  latched: latched,
  promptOpen: promptOpen,
  loadingNext: loadingNext,
  sleepTimerEnded: sleepTimerEnded,
  nextStatus: nextStatus,
  normalLaunch: normalLaunch,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('R1 predicate', () {
    test('allowed: a movie at its end, an episode at its end with or without a next one', () {
      expect(tvPostPlayAllowed(_facts()), isTrue);
      expect(tvPostPlayAllowed(_facts(kind: MediaKind.episode, nextStatus: QueueNavigationStatus.boundary)), isTrue);
      expect(tvPostPlayAllowed(_facts(kind: MediaKind.episode, nextStatus: QueueNavigationStatus.found)), isTrue);
    });

    test('a downloaded file played online is not offline (A39)', () {
      // `isOffline` is Plezy's offline library mode only; a local source in
      // an online session is a normal online end.
      expect(tvPostPlayAllowed(_facts(isOffline: false)), isTrue);
    });

    final exclusions = <String, TvPostPlayFacts>{
      'end by the sleep timer (A23)': _facts(sleepTimerEnded: true),
      'play-next or still-watching prompt open (A22)': _facts(promptOpen: true),
      'next item loading': _facts(loadingNext: true),
      'latch not set: seeked back from the end (A15)': _facts(latched: false),
      'offline library mode (A27)': _facts(isOffline: true),
      'Watch Together (A27)': _facts(watchTogether: true),
      'playlist / collection / shuffle (A25)': _facts(normalLaunch: false),
      'trailer or clip (A26)': _facts(kind: MediaKind.clip),
      'neighbours failed to load (A24)': _facts(kind: MediaKind.episode, nextStatus: QueueNavigationStatus.failed),
      'Live TV (A27)': _facts(isLive: true),
      'not TV (A27)': _facts(tv: false),
    };
    for (final entry in exclusions.entries) {
      test('excluded: ${entry.key}', () => expect(tvPostPlayAllowed(entry.value), isFalse));
    }
  });

  group('normal launch', () {
    late PlaybackStateProvider queue;
    setUp(() => queue = PlaybackStateProvider());
    tearDown(() => queue.dispose());

    test('no queue: normal for a movie and an episode', () {
      expect(tvNormalLaunch(_movie, null), isTrue);
      expect(tvNormalLaunch(_movie, queue), isTrue);
      expect(tvNormalLaunch(_episode, queue), isTrue);
    });

    test('sequential series queue (Plex /playQueues or the local series queue): normal', () {
      queue.setPlaybackFromLocalQueue(LocalPlayQueue(items: [_episode, _otherEpisode]), contextKey: 'show-1');
      expect(queue.isPlaylistActive && queue.isQueueActive, isTrue, reason: 'the flags alone cannot tell');
      expect(tvNormalLaunch(_episode, queue), isTrue);

      queue.clearShuffle();
      unawaited(
        queue.setPlaybackFromPlayQueue(
          PlayQueueResponse(playQueueID: 7, playQueueShuffled: false, playQueueTotalCount: 2, items: [_episode]),
          'show-1',
        ),
      );
      expect(tvNormalLaunch(_episode, queue), isTrue);
    });

    test('a season as the queue context: normal', () {
      queue.setPlaybackFromLocalQueue(LocalPlayQueue(items: [_episode]), contextKey: 'season-1');
      expect(tvNormalLaunch(_episode, queue), isTrue);
    });

    test('shuffled series (Plex or Jellyfin): not normal', () {
      queue.setPlaybackFromLocalQueue(LocalPlayQueue(items: [_episode], shuffled: true), contextKey: 'show-1');
      expect(tvNormalLaunch(_episode, queue), isFalse);
      queue.clearShuffle();
      unawaited(
        queue.setPlaybackFromPlayQueue(
          PlayQueueResponse(playQueueID: 7, playQueueShuffled: true, playQueueTotalCount: 1, items: [_episode]),
          'show-1',
        ),
      );
      expect(tvNormalLaunch(_episode, queue), isFalse);
    });

    test('playlist, collection or folder queue: not normal, for movies and episodes', () {
      for (final key in ['playlist-9', 'collection-3', '/library/sections/1/folder?parent=5']) {
        queue.setPlaybackFromLocalQueue(LocalPlayQueue(items: [_movie, _episode]), contextKey: key);
        expect(tvNormalLaunch(_movie, queue), isFalse, reason: key);
        expect(tvNormalLaunch(_episode, queue), isFalse, reason: key);
      }
    });

    test('another series\' queue: not normal', () {
      queue.setPlaybackFromLocalQueue(LocalPlayQueue(items: [_episode]), contextKey: 'show-2');
      expect(tvNormalLaunch(_episode, queue), isFalse);
    });
  });

  group('C3 sleep-timer flag', () {
    late TvStandPlayer player;
    setUp(() {
      player = TvStandPlayer();
      SleepTimerService().cancelTimer();
    });
    tearDown(() async {
      SleepTimerService().cancelTimer();
      await player.close();
    });

    bool ended(MediaItem item) => TvPlayerSession.of(player).sleepTimerEndedItemKey == item.globalKey;

    // Mirrors Plezy's `_onVideoCompleted` on an episode with a next one: the
    // H8 line runs with the latch as it was before Plezy's branch; Plezy then
    // latches (sleepTimer, presentNext) and the sleep timer disarms itself.
    void eof(MediaItem item, {required bool latched}) {
      TvUi.playerVideoCompleted(player, latched: latched, item: item, isLive: false);
      SleepTimerService().notifyVideoCompleted();
    }

    test('sleepTimer → flag; a repeated EOF while latched keeps it; presentNext → cleared (A23, A35)', () {
      TvUi.enabledForTesting = () => true;
      addTearDown(TvUi.resetForTesting);
      SleepTimerService().armEndOfVideo();
      eof(_episode, latched: false); // branch sleepTimer
      expect(ended(_episode), isTrue);
      eof(_episode, latched: true); // a duplicate EOF, Plezy: "latched"
      expect(ended(_episode), isTrue);
      // Seeked back (latch re-armed), watched to the end without the timer.
      eof(_episode, latched: false); // branch presentNext
      expect(ended(_episode), isFalse);
    });

    test('a new item never matches the flag', () {
      TvUi.enabledForTesting = () => true;
      addTearDown(TvUi.resetForTesting);
      SleepTimerService().armEndOfVideo();
      eof(_episode, latched: false);
      expect(ended(_episode), isTrue);
      expect(ended(_otherEpisode), isFalse);
    });

    test('not TV or Live TV: nothing recorded', () {
      TvUi.enabledForTesting = () => false;
      addTearDown(TvUi.resetForTesting);
      SleepTimerService().armEndOfVideo();
      TvUi.playerVideoCompleted(player, latched: false, item: _episode, isLive: false);
      expect(TvPlayerSession.of(player).sleepTimerEndedItemKey, isNull);
      TvUi.enabledForTesting = () => true;
      TvUi.playerVideoCompleted(player, latched: false, item: _episode, isLive: true);
      expect(TvPlayerSession.of(player).sleepTimerEndedItemKey, isNull);
    });
  });

  group('C2 exitToPostPlay', () {
    testWidgets('accepted by this call: post-play over the player, the player removed, Browse never on top', (
      tester,
    ) async {
      final stand = await _NavStand.pump(tester);
      stand.exitTo();
      await tester.pump();
      await tester.pump();
      expect(stand.exitCalls, 1);
      expect(find.text('Post-play Movie'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(stand.playerRoute.isActive, isFalse, reason: 'removed by removeRoute');
      expect(find.text('Post-play Movie'), findsOneWidget);
      expect(stand.tops, [
        'post-play',
        'post-play',
      ], reason: 'pushed over the player, then the player removed under it');
      await expectLater(stand.removedArg!, completes, reason: 'playerRemoved completes after the removal');
    });

    testWidgets('exit declined (a prompt dismissed, A22): no route', (tester) async {
      final stand = await _NavStand.pump(tester, accept: false);
      stand.exitTo();
      await tester.pump();
      await tester.pump();
      expect(stand.exitCalls, 1);
      expect(find.textContaining('Post-play'), findsNothing);
      expect(stand.playerRoute.isCurrent, isTrue);
    });

    testWidgets('an exit already accepted before the call: no route, exit not called again', (tester) async {
      final stand = await _NavStand.pump(tester);
      stand.pending = true;
      stand.exitTo();
      await tester.pump();
      await tester.pump();
      expect(stand.exitCalls, 0);
      expect(find.textContaining('Post-play'), findsNothing);
    });

    testWidgets('two calls in a row (H8 and H9): one screen', (tester) async {
      final stand = await _NavStand.pump(tester);
      stand.exitTo();
      stand.exitTo();
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(stand.exitCalls, 1);
      expect(find.text('Post-play Movie'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(stand.navigator.currentState!.canPop(), isTrue);
      stand.navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.text('Browse'), findsOneWidget, reason: 'only one post-play route was pushed');
    });

    testWidgets('a failed exit still counts as removed for the screen', (tester) async {
      final stand = await _NavStand.pump(tester, failExit: true);
      stand.exitTo();
      await tester.pump();
      await tester.pump();
      expect(find.text('Post-play Movie'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      await expectLater(stand.removedArg!, throwsA(isA<StateError>()));
    });
  });

  group('C4 early Back handler', () {
    final stand = TvPlayerStand();
    setUp(() async {
      await stand.setUp();
      TvUi.enabledForTesting = () => true;
    });
    tearDown(() async {
      TvUi.resetForTesting();
      TvDetectionService.debugSetAppleTVOverride(null);
      await stand.tearDown();
    });

    testWidgets('own press, Android: handled on down and up, action on the up; Plezy never sees it', (tester) async {
      final layer = await _pumpLayer(tester, stand);
      expect(await _down(tester), isTrue);
      expect(layer.exits, 0);
      expect(await _up(tester), isTrue);
      expect(layer.exits, 1);
      expect(stand.exitCalls, 0, reason: "Plezy's Back chain did not run");
    });

    testWidgets('own press, Apple TV: action on the down, the up consumed', (tester) async {
      TvDetectionService.debugSetAppleTVOverride(true);
      final layer = await _pumpLayer(tester, stand);
      expect(await _down(tester, key: LogicalKeyboardKey.escape), isTrue);
      expect(layer.exits, 1);
      expect(await _up(tester, key: LogicalKeyboardKey.escape), isTrue);
      expect(layer.exits, 1);
    });

    testWidgets('the action marks the press handled against the system pop duplicate', (tester) async {
      await _pumpLayer(tester, stand);
      await _down(tester);
      BackKeyCoordinator.clear();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.goBack, physicalKey: PhysicalKeyboardKey.escape);
      expect(BackKeyCoordinator.consumeIfHandled(), isTrue);
    });

    testWidgets('panel visible: ignored for the pair, Plezy hides the panel (A11)', (tester) async {
      final layer = await _pumpLayer(tester, stand);
      stand.chrome.show();
      await tester.pump();
      await _down(tester);
      await _up(tester);
      expect(layer.exits, 0);
      expect(stand.chrome.controlsVisible, isFalse, reason: "Plezy's chain hid the panel");
      expect(stand.exitCalls, 0);
    });

    testWidgets('right panel open, sheet open, skip button visible, queue open: ignored (A12, A31)', (tester) async {
      final layer = await _pumpLayer(tester, stand);
      final session = TvPlayerSession.of(stand.player);

      session.sidePanelOpen.value = true;
      expect(await _press(tester, layer), isFalse);
      session.sidePanelOpen.value = false;

      final owner = Object();
      session.markSkipButton(owner, mounted: true);
      expect(await _press(tester, layer), isFalse);
      session.markSkipButton(owner, mounted: false);

      stand.chrome.setContentStripVisible(true);
      expect(await _press(tester, layer), isFalse);
      stand.chrome.setContentStripVisible(false);

      final sheet = OverlaySheetController.of(layer.context);
      unawaited(sheet.show<void>(builder: (_) => const SizedBox(height: 10)));
      await tester.pump();
      expect(await _press(tester, layer), isFalse);
      expect(layer.exits, 0);
      sheet.pop();
      await tester.pumpAndSettle();
      stand.chrome.cancelAutoHide();
    });

    testWidgets('R1 false: ignored, Plezy exits as before (A15)', (tester) async {
      final layer = await _pumpLayer(tester, stand, latched: false);
      expect(await _press(tester, layer), isFalse);
      expect(layer.exits, 0);
      expect(stand.exitCalls, 1);
    });

    testWidgets('state changes between down and up: the down decides', (tester) async {
      final layer = await _pumpLayer(tester, stand);
      await _down(tester);
      layer.latched = false;
      expect(await _up(tester), isTrue);
      expect(layer.exits, 1, reason: 'our press stays ours');

      layer.latched = false;
      await _down(tester);
      layer.latched = true;
      await _up(tester);
      expect(layer.exits, 1, reason: 'a press not ours stays not ours');
    });

    testWidgets('a key-up without our key-down, and a suppressed key-up: ignored', (tester) async {
      final layer = await _pumpLayer(tester, stand);
      // Key-down taken elsewhere (simulated: the layer was not mounted then).
      layer.latched = false;
      await _down(tester);
      layer.latched = true;
      await _up(tester);
      expect(layer.exits, 0);

      await _down(tester);
      BackKeyUpSuppressor.suppressBackUntilKeyUp();
      expect(await _up(tester), isTrue, reason: "Plezy's handler swallows the suppressed up");
      expect(layer.exits, 0, reason: 'a suppressed release never acts');
    });

    testWidgets('Home is never taken (A28)', (tester) async {
      final layer = await _pumpLayer(tester, stand);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.home);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.home);
      expect(layer.exits, 0);
    });

    testWidgets('the handler goes with the layer', (tester) async {
      final layer = await _pumpLayer(tester, stand);
      final session = TvPlayerSession.of(stand.player);
      expect(session.endBinding, isNotNull);
      layer.mounted = false;
      await tester.pump();
      expect(session.endBinding, isNull);
      expect(await _press(tester, layer), isFalse);
      expect(layer.exits, 0);
    });

    testWidgets('H8 exit: true and the exit taken when R1 holds, false otherwise', (tester) async {
      final layer = await _pumpLayer(tester, stand);
      expect(TvUi.playerExitAtEnd(stand.player, isLive: false), isTrue);
      expect(layer.exits, 1);
      expect(TvUi.playerExitAtEnd(stand.player, isLive: true), isFalse);
      layer.latched = false;
      expect(TvUi.playerExitAtEnd(stand.player, isLive: false), isFalse);
      expect(layer.exits, 1);
    });
  });

  group('H9 lookup', () {
    test('null off TV, for Live TV and without a player', () {
      final chrome = PlayerChromeController();
      addTearDown(chrome.dispose);
      final probe = _probe(() => true, () {});
      TvUi.enabledForTesting = () => false;
      addTearDown(TvUi.resetForTesting);
      final player = TvStandPlayer();
      expect(TvUi.playerPostPlayExit(player: player, chromeController: chrome, probe: probe, isLive: false), isNull);
      TvUi.enabledForTesting = () => true;
      expect(TvUi.playerPostPlayExit(player: player, chromeController: chrome, probe: probe, isLive: true), isNull);
      expect(TvUi.playerPostPlayExit(player: null, chromeController: chrome, probe: probe, isLive: false), isNull);
      expect(
        TvUi.playerPostPlayExit(player: player, chromeController: chrome, probe: probe, isLive: false),
        isA<TvPostPlayExitLayer>(),
      );
    });
  });
}

TvPlayerEndProbe _probe(bool Function() latched, void Function() onExit) => TvPlayerEndProbe(
  watched: () => _movie,
  next: () => null,
  latched: latched,
  promptOpen: () => false,
  loadingNext: () => false,
  nextStatus: () => QueueNavigationStatus.unavailable,
  watchTogether: () => false,
  isOffline: false,
  exitPending: () => false,
  exit: () async => onExit(),
);

/// The layer under test in the S9 stand, with Plezy's Back chain below it.
class _LayerHandle {
  int exits = 0;
  bool latched = true;
  late BuildContext context;
  late StateSetter _setState;
  bool _mounted = true;
  set mounted(bool value) => _setState(() => _mounted = value);
}

Future<_LayerHandle> _pumpLayer(WidgetTester tester, TvPlayerStand stand, {bool latched = true}) async {
  final handle = _LayerHandle()..latched = latched;
  stand.chrome.hide(ignoreHolds: true);
  stand.chrome.markControlsHidden();
  final probe = _probe(() => handle.latched, () {});
  await tester.pumpWidget(
    stand.host(
      const SizedBox.expand(),
      layer: StatefulBuilder(
        builder: (context, setState) {
          handle._setState = setState;
          handle.context = context;
          if (!handle._mounted) return const SizedBox.shrink();
          return TvPostPlayExitLayer(
            player: stand.player,
            chromeController: stand.chrome,
            probe: probe,
            tv: () => true,
            exitToPostPlay: ({required context, required watched, next, required exitPending, required exit}) =>
                handle.exits++,
          );
        },
      ),
    ),
  );
  await tester.pump();
  return handle;
}

Future<bool> _down(WidgetTester tester, {LogicalKeyboardKey key = LogicalKeyboardKey.goBack}) async {
  final result = await tester.sendKeyDownEvent(key, physicalKey: PhysicalKeyboardKey.escape);
  await tester.pump();
  return result;
}

Future<bool> _up(WidgetTester tester, {LogicalKeyboardKey key = LogicalKeyboardKey.goBack}) async {
  final result = await tester.sendKeyUpEvent(key, physicalKey: PhysicalKeyboardKey.escape);
  await tester.pump();
  return result;
}

/// A full press; true when the layer took it and acted.
Future<bool> _press(WidgetTester tester, _LayerHandle layer) async {
  final before = layer.exits;
  await _down(tester);
  await _up(tester);
  return layer.exits > before;
}

/// A navigator with Browse at the root and a stand-in player route; the
/// fake exit mirrors Plezy's `_exitPlayerRoute` (accepted synchronously,
/// player removed by identity after the 1 s budget).
class _NavStand {
  _NavStand(
    this.navigator,
    this.playerContext,
    this.playerRoute,
    this.tops, {
    required this.accept,
    this.failExit = false,
  });

  final GlobalKey<NavigatorState> navigator;
  final BuildContext playerContext;
  final Route<void> playerRoute;
  final List<String> tops;
  final bool accept;
  final bool failExit;
  bool pending = false;
  int exitCalls = 0;
  Future<void>? removedArg;

  static Future<_NavStand> pump(WidgetTester tester, {bool accept = true, bool failExit = false}) async {
    final navigator = GlobalKey<NavigatorState>();
    final tops = <String>[];
    late BuildContext playerContext;
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        navigatorObservers: [_Tops(tops)],
        home: const Scaffold(body: Text('Browse')),
      ),
    );
    final route = MaterialPageRoute<void>(
      settings: const RouteSettings(name: 'player'),
      builder: (context) {
        playerContext = context;
        return const Scaffold(body: Text('Player'));
      },
    );
    unawaited(navigator.currentState!.push(route));
    await tester.pumpAndSettle();
    tops.clear();
    TvUi.postPlayRouteForTesting = null;
    return _NavStand(navigator, playerContext, route, tops, accept: accept, failExit: failExit);
  }

  Future<void> _exit() {
    exitCalls++;
    if (!accept) return Future<void>.value();
    pending = true;
    final nav = navigator.currentState!;
    return Future<void>.delayed(const Duration(seconds: 1), () {
      if (playerRoute.isActive) {
        if (playerRoute.isCurrent) {
          nav.pop();
        } else {
          nav.removeRoute(playerRoute);
        }
      }
      if (failExit) throw StateError('exit failed');
    });
  }

  void exitTo() => tvExitToPostPlay(
    context: playerContext,
    watched: _movie,
    exitPending: () => pending,
    exit: _exit,
    route: (args) {
      removedArg = args.playerRemoved;
      return MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'post-play'),
        builder: (_) => Scaffold(body: Text('Post-play ${args.watched.title}')),
      );
    },
  );
}

/// Records the name of the top route after every navigator change.
class _Tops extends NavigatorObserver {
  _Tops(this.tops);
  final List<String> tops;
  final List<Route<dynamic>> _stack = [];

  void _record() {
    final top = _stack.isEmpty ? null : _stack.last;
    tops.add(top == null ? 'none' : (top.isFirst ? 'browse' : top.settings.name ?? 'other'));
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.add(route);
    _record();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.remove(route);
    _record();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.remove(route);
    _record();
  }
}
