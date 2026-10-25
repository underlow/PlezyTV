import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:plezy/database/app_database.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/focus/input_mode_tracker.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/plezytv/tv_ui/player/tv_player_session.dart';
import 'package:plezy/plezytv/tv_ui/tv_ui.dart';
import 'package:plezy/providers/playback_state_provider.dart';
import 'package:plezy/screens/video_player_screen.dart';
import 'package:plezy/services/episode_navigation_service.dart';
import 'package:plezy/services/playback_coordinator.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/services/sleep_timer_service.dart';
import 'package:plezy/utils/video_player_navigation.dart';
import 'package:plezy/watch_together/providers/watch_together_provider.dart';
import 'package:provider/provider.dart';

import '../../../test_helpers/media_items.dart';
import '../../../test_helpers/prefs.dart';
import '../../../test_helpers/pump.dart';
import '../../../test_helpers/theme.dart';
import '../../../test_helpers/watch_together_fakes.dart';

/// S14 T3 on a real [VideoPlayerScreen]: H8 (Plezy's `exit` branch at EOF)
/// and H9 (Back at the last step) open the post-play screen over the player,
/// and Plezy's exit then removes only the player (A1, R2).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    LocaleSettings.setLocaleSync(AppLocale.en);
    await initializeDateFormatting('en');
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
    TvUi.enabledForTesting = () => true;
    TvUi.postPlayRouteForTesting = (args) => MaterialPageRoute<void>(
      builder: (_) =>
          Scaffold(body: Text('Post-play ${args.watched.title}${args.next == null ? '' : ' → ${args.next!.title}'}')),
    );
  });

  tearDown(TvUi.resetForTesting);

  testWidgets('EOF of a movie: post-play over the player, then the player is removed; Browse never on top (A1)', (
    tester,
  ) async {
    final stand = await _pushStartedPlayer(tester);
    final tops = stand.tops;

    // A movie has no neighbours: Plezy's EOF takes the exit branch.
    stand.state.debugCommitAdjacentEpisodesForTesting(const AdjacentEpisodes.unavailable());
    stand.state.debugCompleteVideoForTesting();
    await tester.pump();
    await tester.pump();

    expect(find.text('Post-play Movie'), findsOneWidget);
    expect(stand.key.currentState, isNotNull, reason: 'the old player stays under the screen for the budget');

    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 400));
    expect(stand.key.currentState, isNull, reason: 'Plezy removed the player route');
    expect(find.text('Post-play Movie'), findsOneWidget);
    expect(tops, ['post-play', 'post-play'], reason: 'the previous screen never became the top route');

    // Back from the post-play screen goes where the player came from (R2).
    stand.navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('Browse'), findsOneWidget);
  });

  testWidgets('episode with a next one: Back closes the card, the next Back opens post-play (H9, A10)', (tester) async {
    final stand = await _pushStartedPlayer(tester, metadata: _episode);
    stand.state.debugCommitAdjacentEpisodesForTesting(
      AdjacentEpisodes(
        next: _next,
        nextStatus: QueueNavigationStatus.found,
        previousStatus: QueueNavigationStatus.boundary,
      ),
    );
    stand.state.debugCompleteVideoForTesting();
    await pumpUntil(tester, () => stand.state.debugPlayNextPromptVisibleForTesting);
    await tester.pump();

    // 1st Back: Plezy closes the card; the latch stays set at the end.
    await _back(tester);
    expect(stand.state.debugPlayNextPromptVisibleForTesting, isFalse);
    expect(find.textContaining('Post-play'), findsNothing);
    _hideChrome(stand);
    await tester.pump(const Duration(seconds: 1));

    // 2nd Back, Android: nothing on the key-down, post-play on the key-up.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.goBack, physicalKey: PhysicalKeyboardKey.escape);
    await tester.pump();
    expect(find.textContaining('Post-play'), findsNothing);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.goBack, physicalKey: PhysicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump();
    expect(find.text('Post-play Episode → Next'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 400));
    expect(stand.key.currentState, isNull, reason: 'Plezy removed the player route');
    expect(stand.tops, ['post-play', 'post-play']);
  });

  testWidgets('episode with a next one and auto-play: Plezy plays on, no post-play (A8)', (tester) async {
    final stand = await _pushStartedPlayer(tester, metadata: _episode);
    stand.state.debugCommitAdjacentEpisodesForTesting(
      AdjacentEpisodes(
        next: _next,
        nextStatus: QueueNavigationStatus.found,
        previousStatus: QueueNavigationStatus.boundary,
      ),
    );
    stand.state.debugCompleteVideoForTesting();
    await pumpUntil(tester, () => stand.state.debugPlayNextPromptVisibleForTesting);
    expect(stand.state.debugAutoPlayCountdownForTesting, greaterThan(0), reason: 'auto-play is on by default');
    // The countdown runs out and Plezy starts the next episode in place.
    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(seconds: 2));
    expect(find.textContaining('Post-play'), findsNothing);
    expect(stand.tops, isNot(contains('post-play')));
  });

  testWidgets('end by the end-of-video sleep timer: Back is Plezy\'s exit, no post-play (C3, A23)', (tester) async {
    final stand = await _pushStartedPlayer(tester, metadata: _episode);
    stand.state.debugCommitAdjacentEpisodesForTesting(
      AdjacentEpisodes(
        next: _next,
        nextStatus: QueueNavigationStatus.found,
        previousStatus: QueueNavigationStatus.boundary,
      ),
    );
    SleepTimerService().armEndOfVideo();
    addTearDown(SleepTimerService().cancelTimer);
    stand.state.debugCompleteVideoForTesting();
    await tester.pump();
    expect(TvPlayerSession.of(stand.state.player!).sleepTimerEndedItemKey, _episode.globalKey);
    _hideChrome(stand);
    await tester.pump(const Duration(seconds: 1));

    await _back(tester);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.textContaining('Post-play'), findsNothing);
    expect(find.text('Browse'), findsOneWidget);
  });

  testWidgets('not TV: the EOF exit is Plezy\'s, back to Browse', (tester) async {
    TvUi.enabledForTesting = () => false;
    final stand = await _pushStartedPlayer(tester);
    stand.state.debugCommitAdjacentEpisodesForTesting(const AdjacentEpisodes.unavailable());
    stand.state.debugCompleteVideoForTesting();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.textContaining('Post-play'), findsNothing);
    expect(find.text('Browse'), findsOneWidget);
  });
}

class _EndPlayer extends FakeSyncPlayer {
  _EndPlayer() : super(position: const Duration(minutes: 45), hasRenderedFrame: true);

  @override
  Future<void> updateFrame() async {}

  @override
  Future<void> abandonAudioFocus() async {}
}

class _Stand {
  _Stand(this.key, this.navigator, this.tops);
  final GlobalKey<VideoPlayerScreenState> key;
  final GlobalKey<NavigatorState> navigator;
  final List<String> tops;
  VideoPlayerScreenState get state => key.currentState!;
}

/// Records which route was on top after every navigator change.
class _TopObserver extends NavigatorObserver {
  _TopObserver(this.tops);
  final List<String> tops;
  final List<Route<dynamic>> _stack = [];

  void _record() {
    final top = _stack.isEmpty ? null : _stack.last;
    tops.add(
      top == null
          ? 'none'
          : top.isFirst
          ? 'browse'
          : top is VideoPlayerRoute
          ? 'player'
          : 'post-play',
    );
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

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final at = oldRoute == null ? -1 : _stack.indexOf(oldRoute);
    if (at >= 0 && newRoute != null) _stack[at] = newRoute;
    _record();
  }
}

/// A movie player route over a `Browse` root, startup held (as in
/// `player_route_exit_test.dart`) and then marked started with a fake player,
/// so the player's stack — with the H7/H9 layers — is built.
Future<_Stand> _pushStartedPlayer(WidgetTester tester, {MediaItem? metadata}) async {
  final key = GlobalKey<VideoPlayerScreenState>();
  final navigator = GlobalKey<NavigatorState>();
  final tops = <String>[];
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final player = _EndPlayer();
  final initializationHold = Completer<void>();
  Future<void> holdInitialization() => initializationHold.future;
  PlaybackCoordinator.instance.registerMusicSession(stopAndDispose: holdInitialization);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    PlaybackCoordinator.instance.unregisterMusicSession(holdInitialization);
    if (!initializationHold.isCompleted) initializationHold.complete();
    await tester.pump();
  });
  final database = AppDatabase.forTesting(NativeDatabase.memory());
  final watchTogether = WatchTogetherProvider();
  addTearDown(() async {
    watchTogether.dispose();
    await database.close();
  });
  await tester.pumpWidget(
    InputModeTracker(
      child: MultiProvider(
        providers: [
          Provider<AppDatabase>.value(value: database),
          ChangeNotifierProvider(create: (_) => PlaybackStateProvider()),
          ChangeNotifierProvider<WatchTogetherProvider>.value(value: watchTogether),
        ],
        child: MaterialApp(
          theme: ThemeData(platform: TargetPlatform.android, extensions: const [testMonoTokens]),
          navigatorKey: navigator,
          navigatorObservers: [_TopObserver(tops)],
          home: const Scaffold(body: Text('Browse')),
        ),
      ),
    ),
  );
  unawaited(
    VideoPlayerRoute(
      builder: (_) => VideoPlayerScreen(
        key: key,
        metadata: metadata ?? testMediaItem(title: 'Movie'),
        isOffline: false,
      ),
    ).push(navigator.currentState!),
  );
  await tester.pump();
  key.currentState!.player = player;
  await key.currentState!.debugMarkPlaybackStartedForTesting();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  expect(tops.last, 'player');
  tops.clear();
  return _Stand(key, navigator, tops);
}

final _episode = testMediaItem(
  id: 'ep-1',
  kind: MediaKind.episode,
  title: 'Episode',
  grandparentId: 'show-1',
  parentId: 'season-1',
  parentIndex: 1,
  index: 1,
);
final _next = testMediaItem(
  id: 'ep-2',
  kind: MediaKind.episode,
  title: 'Next',
  grandparentId: 'show-1',
  parentId: 'season-1',
  parentIndex: 1,
  index: 2,
);

/// The panel hidden and its fade-out finished (Plezy's controls report the
/// fade end through `markControlsHidden`; the stand's chrome never faded in).
void _hideChrome(_Stand stand) {
  stand.state.chromeController
    ..hide(ignoreHolds: true)
    ..markControlsHidden();
}

Future<void> _back(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.goBack, physicalKey: PhysicalKeyboardKey.escape);
  await tester.pump();
  await tester.sendKeyUpEvent(LogicalKeyboardKey.goBack, physicalKey: PhysicalKeyboardKey.escape);
  await tester.pump();
}
