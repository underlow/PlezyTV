import 'dart:async';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'package:plezy/database/app_database.dart';
import 'package:plezy/focus/input_mode_tracker.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_source_info.dart';
import 'package:plezy/media/play_queue.dart';
import 'package:plezy/mpv/mpv.dart';
import 'package:plezy/providers/playback_state_provider.dart';
import 'package:plezy/services/scrub_preview_source.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/services/video_volume_controller.dart';
import 'package:plezy/utils/platform_detector.dart';
import 'package:plezy/watch_together/providers/watch_together_provider.dart';
import 'package:plezy/widgets/video_controls/player_chrome_controller.dart';
import 'package:plezy/widgets/video_controls/video_controls.dart';
import 'package:plezy/widgets/video_controls/widgets/player_toast_indicator.dart';

import 'media_items.dart';
import 'player_streams.dart';
import 'prefs.dart';
import 'theme.dart';

/// A [Player] for TV player tests: drives `playing`, `buffering` and
/// `position`, and records every [seek]. [play], [pause] and [playOrPause]
/// update the playing state and stream.
class TvStandPlayer implements Player {
  TvStandPlayer({Duration position = const Duration(minutes: 5), this.duration = const Duration(minutes: 45)})
    // ignore: prefer_initializing_formals
    : _position = position;

  final Duration duration;
  Duration _position;
  bool _playing = true;
  bool _buffering = false;
  final _playingController = StreamController<bool>.broadcast();
  final _bufferingController = StreamController<bool>.broadcast();
  final _positionController = StreamController<Duration>.broadcast();

  /// Every position passed to [seek], in order.
  final List<Duration> seeks = [];
  int get seekCount => seeks.length;

  void setPlaying(bool playing) {
    _playing = playing;
    _playingController.add(playing);
  }

  void setBuffering(bool buffering) {
    _buffering = buffering;
    _bufferingController.add(buffering);
  }

  void setPosition(Duration position) {
    _position = position;
    _positionController.add(position);
  }

  Future<void> close() async {
    await _playingController.close();
    await _bufferingController.close();
    await _positionController.close();
  }

  @override
  String get playerType => 'mpv';

  @override
  PlayerState get state =>
      PlayerState(playing: _playing, buffering: _buffering, position: _position, duration: duration, seekable: true);

  @override
  PlayerStreams get streams => emptyPlayerStreams(
    playing: _playingController.stream,
    buffering: _bufferingController.stream,
    position: _positionController.stream,
  );

  @override
  Future<void> seek(Duration position) async {
    seeks.add(position);
    setPosition(position);
  }

  @override
  Future<void> play() async => setPlaying(true);

  @override
  Future<void> pause() async => setPlaying(false);

  @override
  Future<void> playOrPause() async => setPlaying(!_playing);

  @override
  Future<void> setVolume(double volume) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// One preview frame: a 1×1 transparent PNG.
final Uint8List tvStandFrameBytes = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, //
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
]);

/// Chapters at 0, 10 and 20 minutes.
List<MediaChapter> tvStandChapters() => [
  MediaChapter(id: 1, index: 0, startTimeOffset: 0, endTimeOffset: 600000, title: 'Opening'),
  MediaChapter(id: 2, index: 1, startTimeOffset: 600000, endTimeOffset: 1200000, title: 'Middle'),
  MediaChapter(id: 3, index: 2, startTimeOffset: 1200000, endTimeOffset: 2700000, title: 'End'),
];

/// An intro marker covering the default position (4–6 minutes).
List<MediaMarker> tvStandMarkers() => [
  MediaMarker(id: 1, type: 'intro', startTimeOffset: 240000, endTimeOffset: 360000),
];

/// Shared TV player stand (S9): a fake player, chrome controller, playback
/// state and the providers `PlexVideoControls` needs, on a forced Android TV.
///
/// Call [setUp] / [tearDown] from the test's own hooks, then [pumpControls]
/// with the case under test. Timers advance with `tester.pump(duration)`.
class TvPlayerStand {
  late TvStandPlayer player;
  late PlayerChromeController chrome;
  late PlayerToastController toast;
  late VideoVolumeController volume;
  late PlaybackStateProvider playbackState;
  late WatchTogetherProvider watchTogether;
  late AppDatabase database;
  late ValueNotifier<bool> hasFirstFrame;
  late FocusNode screenFocusNode;

  /// Focus node standing in for the play-next prompt's button.
  late FocusNode playNextFocusNode;

  int nextCalls = 0;
  int previousCalls = 0;

  /// Times the screen's Back chain left the player.
  int exitCalls = 0;

  /// The screen's Back chain (strip → hide chrome → exit), as on the route.
  late PlayerNavigationCoordinator navigation;

  Future<void> setUp({bool tv = true, TvStandPlayer? player}) async {
    LocaleSettings.setLocaleSync(AppLocale.en);
    await initializeDateFormatting('en');
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    final settings = await SettingsService.getInstance();

    TvDetectionService.debugSetAppleTVOverride(null);
    await TvDetectionService.getInstance(forceTv: tv);
    TvDetectionService.setForceTVSync(tv);
    PlatformDetector.debugSetIsDesktopOSOverride(false);

    database = AppDatabase.forTesting(NativeDatabase.memory());
    this.player = player ?? TvStandPlayer();
    chrome = PlayerChromeController();
    toast = PlayerToastController();
    volume = VideoVolumeController(player: this.player, settings: settings, initialVolume: 100);
    playbackState = PlaybackStateProvider();
    watchTogether = WatchTogetherProvider();
    hasFirstFrame = ValueNotifier<bool>(true);
    screenFocusNode = FocusNode(debugLabel: 'VideoPlayerScreen');
    playNextFocusNode = FocusNode(debugLabel: 'PlayNext');
    nextCalls = 0;
    previousCalls = 0;
    exitCalls = 0;
    navigation = PlayerNavigationCoordinator(
      chromeController: chrome,
      isPromptOpen: () => false,
      dismissPrompt: () {},
      isChromePresented: () => chrome.controlsPresented,
      exitFullscreenIfActive: () async => false,
      exitPlayer: () => exitCalls++,
      navigateHome: () {},
    );
  }

  Future<void> tearDown() async {
    TvDetectionService.setForceTVSync(false);
    PlatformDetector.debugSetIsDesktopOSOverride(null);
    hasFirstFrame.dispose();
    screenFocusNode.dispose();
    playNextFocusNode.dispose();
    volume.dispose();
    playbackState.dispose();
    watchTogether.dispose();
    chrome.dispose();
    toast.dispose();
    await player.close();
    await database.close();
  }

  /// An episode item; movies come from [testMediaItem] directly.
  static MediaItem episode({String id = 'episode-1', int index = 1}) =>
      testMediaItem(id: id, kind: MediaKind.episode, title: 'Episode $index', index: index, parentIndex: 1);

  /// Makes [items] the active queue, with [current] playing.
  void setQueue(List<MediaItem> items, {int current = 0}) =>
      playbackState.setPlaybackFromLocalQueue(LocalPlayQueue(items: items, currentIndex: current));

  /// Wraps [child] in the providers, input-mode tracker and app the
  /// controls expect, on a 1920 × 1080 surface. The screen node walks the
  /// Back chain like `VideoPlayerScreen`; [playNextFocusNode] sits on a
  /// stand-in prompt button.
  Widget host(Widget child) => InputModeTracker(
    child: MultiProvider(
      providers: [
        Provider<AppDatabase>.value(value: database),
        ChangeNotifierProvider<PlaybackStateProvider>.value(value: playbackState),
        ChangeNotifierProvider<WatchTogetherProvider>.value(value: watchTogether),
      ],
      child: MaterialApp(
        theme: ThemeData(platform: TargetPlatform.android, extensions: const [testMonoTokens]),
        home: Scaffold(
          body: SizedBox(
            width: 1920,
            height: 1080,
            child: Focus(
              focusNode: screenFocusNode,
              autofocus: true,
              onKeyEvent: (node, event) {
                final key = classifyPlayerNavigationKey(event, isAppleTV: false);
                if (key == PlayerNavigationKey.none) return KeyEventResult.ignored;
                return handlePlayerNavigationKeyAction(event, key, () => navigation.handle(key));
              },
              child: Stack(
                children: [
                  Positioned.fill(child: child),
                  Positioned(
                    left: 0,
                    top: 0,
                    width: 1,
                    height: 1,
                    child: Focus(focusNode: playNextFocusNode, child: const SizedBox.expand()),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  /// Builds the controls for one case without mounting them.
  PlexVideoControls controls({
    MediaItem? metadata,
    bool isLive = false,
    bool canControl = true,
    bool canNavigateMediaItems = true,
    bool isOfflinePlayback = false,
    bool withThumbnails = false,
    List<MediaChapter>? chapters,
    List<MediaMarker>? markers,
    bool withNext = false,
    bool withPrevious = false,
    bool playNextPromptOpen = false,
    bool playbackPromptOpen = false,
  }) => PlexVideoControls(
    player: player,
    volumeController: volume,
    metadata: metadata ?? testMediaItem(id: 'tv-stand-movie', title: 'Stand movie'),
    toastController: toast,
    chromeController: chrome,
    hasFirstFrame: hasFirstFrame,
    isLive: isLive,
    canControl: canControl,
    canNavigateMediaItems: canNavigateMediaItems,
    isOfflinePlayback: isOfflinePlayback,
    thumbnailDataBuilder: withThumbnails ? (_) => BytesScrubFrame(tvStandFrameBytes) : null,
    initialChapters: chapters ?? const [],
    initialMarkers: markers ?? const [],
    onNext: withNext ? () => nextCalls++ : null,
    onPrevious: withPrevious ? () => previousCalls++ : null,
    playNextFocusNode: playNextPromptOpen ? playNextFocusNode : null,
    playbackPromptOpen: playbackPromptOpen,
  );

  /// Mounts [controls] and settles with the panel up.
  Future<void> pumpControls(WidgetTester tester, PlexVideoControls controls) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1920, 1080);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(host(const SizedBox.expand()));
    await tester.pump();
    await tester.pumpWidget(host(controls));
    await tester.pumpAndSettle();
    // Markers and the timeline react to position updates, not the snapshot.
    player.setPosition(player.state.position);
    await tester.pumpAndSettle();
  }

  /// Unmounts the controls and lets the pending chrome timers run out, so a
  /// test ends without timers outliving the tree.
  Future<void> unmount(WidgetTester tester) async {
    chrome.cancelAutoHide();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 30));
  }
}
