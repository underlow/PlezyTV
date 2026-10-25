import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:plezy/media/media_version.dart';
import 'package:plezy/mpv/mpv.dart';
import 'package:plezy/plezytv/tv_ui/player/tv_player_bar.dart';
import 'package:plezy/plezytv/tv_ui/player/tv_player_panel.dart';
import 'package:plezy/plezytv/tv_ui/player/tv_player_session.dart';
import 'package:plezy/plezytv/tv_ui/player/tv_player_side_panel.dart';
import 'package:plezy/plezytv/tv_ui/tv_ui.dart';
import 'package:plezy/widgets/video_controls/sheets/video_settings_sheet.dart';

import '../../../test_helpers/tv_player_stand.dart';

/// S9 T4: the right panel. Expectations follow R3, R6, R11–R16, R11a, R22 and
/// A8–A11, A18, A24.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final stand = TvPlayerStand();

  const english = SubtitleTrack(id: '1', language: 'eng');
  const german = SubtitleTrack(id: '2', language: 'ger');
  const audioEn = AudioTrack(id: '1', language: 'eng');
  const audioDe = AudioTrack(id: '2', language: 'ger');

  setUp(() async {
    await stand.setUp();
    TvUi.enabledForTesting = () => true;
    stand.player.tracks = const Tracks(audio: [audioEn, audioDe], subtitle: [english, german]);
    stand.player.selection = const TrackSelection(audio: audioEn, subtitle: english);
  });

  tearDown(() async {
    TvUi.resetForTesting();
    await stand.tearDown();
  });

  String? focused() => FocusManager.instance.primaryFocus?.debugLabel;
  String label(TvPlayerPanelElement element) => 'TvPlayer.${element.name}';
  String side(TvPlayerSidePage page, String id) => 'TvPlayerSide.${page.name}/$id';

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }

  /// bar → icons, then right to [icon], OK.
  Future<void> open(WidgetTester tester, TvPlayerPanelElement icon) async {
    await press(tester, LogicalKeyboardKey.arrowUp);
    for (var i = 0; i < icon.index - TvPlayerPanelElement.subtitles.index; i++) {
      await press(tester, LogicalKeyboardKey.arrowRight);
    }
    expect(focused(), label(icon));
    await press(tester, LogicalKeyboardKey.select);
    expect(find.byType(TvPlayerSidePanel), findsOneWidget);
  }

  Future<void> back(WidgetTester tester, {String? focusWhileDown}) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.gameButtonB);
    await tester.pump();
    if (focusWhileDown != null) expect(focused(), focusWhileDown, reason: 'acts on release');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.gameButtonB);
    await tester.pumpAndSettle();
  }

  testWidgets('A8: Subtitles opens on the selected track, OK switches through Plezy, Back closes to the icon', (
    tester,
  ) async {
    await stand.pumpControls(tester, stand.controls());
    await open(tester, TvPlayerPanelElement.subtitles);
    expect(focused(), side(TvPlayerSidePage.subtitles, 'track:1'));
    expect(TvPlayerSession.of(stand.player).sidePanelOpen.value, isTrue);
    expect(find.byType(TvPlayerProgressBar).hitTestable(), findsNothing, reason: 'R11: bottom panel hidden');
    expect(find.text('Stand movie'), findsOneWidget, reason: 'title stays');

    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.select);
    expect(stand.player.selection.subtitle, german);
    expect(stand.subtitleChanges, [german]);
    expect(find.byType(TvPlayerSidePanel), findsOneWidget, reason: 'the choice applies, the panel stays');

    await back(tester, focusWhileDown: side(TvPlayerSidePage.subtitles, 'track:2'));
    expect(find.byType(TvPlayerSidePanel), findsNothing, reason: 'R16: opened by the icon, Back closes at once');
    expect(focused(), label(TvPlayerPanelElement.subtitles));
    expect(TvPlayerSession.of(stand.player).sidePanelOpen.value, isFalse);
    expect(stand.chrome.controlsVisible, isTrue);
    expect(stand.exitCalls, 0);
    await stand.unmount(tester);
  });

  testWidgets('A9: → on audio sync changes the delay at once by Plezy\'s step', (tester) async {
    await stand.pumpControls(tester, stand.controls());
    await open(tester, TvPlayerPanelElement.audio);
    expect(focused(), side(TvPlayerSidePage.audio, 'track:1'));
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(focused(), side(TvPlayerSidePage.audio, 'sync'));
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(stand.player.properties, ['audio-delay=0.05']);
    await press(tester, LogicalKeyboardKey.arrowLeft);
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(stand.player.properties.last, 'audio-delay=-0.05');
    expect(find.byType(TvPlayerSidePanel), findsOneWidget, reason: '← on the regulator is not Back');
    await stand.unmount(tester);
  });

  testWidgets('A10: direct play — Quality reads "No transcoding"; R12 items with Plezy values', (tester) async {
    await stand.pumpControls(
      tester,
      stand.controls(
        availableVersions: const [
          MediaVersion(id: 'a', videoResolution: '1080'),
          MediaVersion(id: 'b', videoResolution: '720'),
        ],
        onCycleBoxFitMode: () {},
      ),
    );
    await open(tester, TvPlayerPanelElement.settings);
    expect(focused(), side(TvPlayerSidePage.settings, 'quality'));
    expect(find.text('No transcoding'), findsOneWidget);
    for (final title in ['Subtitles', 'Audio', 'Playback Speed', 'Aspect ratio', 'Sleep Timer', 'More']) {
      expect(find.text(title), findsOneWidget, reason: title);
    }
    await stand.unmount(tester);
  });

  testWidgets('A18: offline — no Quality and no subtitle search', (tester) async {
    await stand.pumpControls(
      tester,
      stand.controls(
        isOfflinePlayback: true,
        availableVersions: const [
          MediaVersion(id: 'a'),
          MediaVersion(id: 'b'),
        ],
        serverSupportsTranscoding: true,
      ),
    );
    await open(tester, TvPlayerPanelElement.settings);
    expect(find.text('No transcoding'), findsNothing);
    expect(focused(), side(TvPlayerSidePage.settings, 'subtitles'));
    await press(tester, LogicalKeyboardKey.select);
    expect(find.text('Search Subtitles'), findsNothing);
    await stand.unmount(tester);
  });

  testWidgets('a hidden item: no Aspect ratio when Plezy offers no box-fit switch', (tester) async {
    await stand.pumpControls(tester, stand.controls());
    await open(tester, TvPlayerPanelElement.settings);
    expect(find.text('Aspect ratio'), findsNothing);
    await stand.unmount(tester);
  });

  testWidgets('R16: submenu → Settings on the row it came from → close on the Settings icon; ← = Back', (tester) async {
    await stand.pumpControls(tester, stand.controls());
    await open(tester, TvPlayerPanelElement.settings);
    expect(focused(), side(TvPlayerSidePage.settings, 'subtitles'));
    await press(tester, LogicalKeyboardKey.select);
    expect(focused(), side(TvPlayerSidePage.subtitles, 'track:1'), reason: 'focus on the selected value');
    await back(tester, focusWhileDown: side(TvPlayerSidePage.subtitles, 'track:1'));
    expect(focused(), side(TvPlayerSidePage.settings, 'subtitles'));

    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.select);
    expect(focused(), side(TvPlayerSidePage.audio, 'track:1'));
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(focused(), side(TvPlayerSidePage.settings, 'audio'));

    await back(tester);
    expect(find.byType(TvPlayerSidePanel), findsNothing);
    expect(focused(), label(TvPlayerPanelElement.settings));
    expect(stand.exitCalls, 0);
    await stand.unmount(tester);
  });

  testWidgets('R11: auto-hide is off while the panel is open and back on after it closes', (tester) async {
    await stand.pumpControls(tester, stand.controls());
    await open(tester, TvPlayerPanelElement.audio);
    await tester.pump(const Duration(seconds: 12));
    expect(stand.chrome.controlsVisible, isTrue);
    await back(tester);
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(stand.chrome.controlsVisible, isFalse);
    await stand.unmount(tester);
  });

  testWidgets('R6: Play/Pause with the panel open toggles playback, focus stays, still no auto-hide', (tester) async {
    await stand.pumpControls(tester, stand.controls());
    await open(tester, TvPlayerPanelElement.subtitles);
    await press(tester, LogicalKeyboardKey.mediaPlayPause);
    expect(stand.player.state.playing, isFalse);
    expect(focused(), side(TvPlayerSidePage.subtitles, 'track:1'));
    await press(tester, LogicalKeyboardKey.mediaPlayPause);
    expect(stand.player.state.playing, isTrue);
    await tester.pump(const Duration(seconds: 12));
    expect(stand.chrome.controlsVisible, isTrue);
    expect(focused(), side(TvPlayerSidePage.subtitles, 'track:1'));
    await stand.unmount(tester);
  });

  testWidgets('A11: More opens Plezy\'s settings sheet; Back closes only the sheet, focus back on More', (
    tester,
  ) async {
    await stand.pumpControls(tester, stand.controls());
    await open(tester, TvPlayerPanelElement.settings);
    for (var i = 0; i < 5; i++) {
      if (focused() == side(TvPlayerSidePage.settings, 'more')) break;
      await press(tester, LogicalKeyboardKey.arrowDown);
    }
    expect(focused(), side(TvPlayerSidePage.settings, 'more'));
    await press(tester, LogicalKeyboardKey.select);
    expect(find.byType(VideoSettingsSheet), findsOneWidget);

    await back(tester);
    expect(find.byType(VideoSettingsSheet), findsNothing);
    expect(find.byType(TvPlayerSidePanel), findsOneWidget, reason: 'the release does not close the right panel');
    expect(focused(), side(TvPlayerSidePage.settings, 'more'));
    expect(stand.exitCalls, 0);
    await stand.unmount(tester);
  });

  testWidgets('A24: a prompt closes the right panel; focus is left to Plezy', (tester) async {
    await stand.pumpControls(tester, stand.controls(metadata: TvPlayerStand.episode()));
    await open(tester, TvPlayerPanelElement.subtitles);
    WidgetsBinding.instance.addPostFrameCallback((_) => stand.playNextFocusNode.requestFocus());
    await tester.pumpWidget(stand.host(stand.controls(metadata: TvPlayerStand.episode(), playNextPromptOpen: true)));
    await tester.pumpAndSettle();
    expect(find.byType(TvPlayerSidePanel), findsNothing);
    expect(TvPlayerSession.of(stand.player).sidePanelOpen.value, isFalse);
    expect(stand.chrome.contentStripVisible, isFalse);
    expect(focused(), 'PlayNext');
    await stand.unmount(tester);
  });
}
