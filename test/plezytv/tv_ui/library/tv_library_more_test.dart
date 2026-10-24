import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import '../../../test_helpers/prefs.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/media/media_library.dart';
import 'package:plezy/providers/libraries_provider.dart';
import 'package:plezy/providers/hidden_libraries_provider.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_button.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_right_panel.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_settings_item.dart';
import 'package:plezy/plezytv/tv_ui/library/tv_library_more.dart';
import 'package:plezy/plezytv/tv_ui/library/tv_library_screen.dart';
import 'package:plezy/plezytv/tv_ui/library/tv_library_controller.dart';
import 'package:plezy/plezytv/tv_ui/library/tv_library_preferences.dart';
import '../tv_theme_test_helper.dart';
import 'fake_media_server_client.dart';
import 'tv_library_screen_test.dart' show library, settle, press;

class FakeLibraries extends LibrariesProvider {
  List<MediaLibrary> rows = [
    library,
    const MediaLibrary(id: '2', backend: MediaBackend.jellyfin, title: 'Other', serverId: 'server'),
  ];
  @override
  List<MediaLibrary> get libraries => rows;
  @override
  Future<void> updateLibraryOrder(
    List<MediaLibrary> orderedLibraries, {
    String? profileId,
    void Function()? checkCurrent,
  }) async {
    rows = orderedLibraries;
    notifyListeners();
  }
}

void main() {
  setUp(resetSharedPreferencesForTest);
  Future<void> activate(WidgetTester tester, String id) async {
    final row = find.byKey(ValueKey(id));
    await tester.ensureVisible(row);
    tester.widget<TvSettingsItem>(row).onSelect!();
    await settle(tester);
  }

  Future<FocusNode> mount(
    WidgetTester tester,
    FakeMediaServerClient client, {
    FakeLibraries? libraries,
    HiddenLibrariesProvider? hidden,
    bool allowed = true,
  }) async {
    final anchor = FocusNode(debugLabel: 'More anchor');
    addTearDown(anchor.dispose);
    await pumpTvWidget(
      tester,
      MultiProvider(
        providers: [
          Provider<String>.value(value: 'fixture'),
          if (libraries != null) ChangeNotifierProvider<LibrariesProvider>.value(value: libraries),
          if (hidden != null) ChangeNotifierProvider<HiddenLibrariesProvider>.value(value: hidden),
        ],
        child: Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: [
                TvButton(
                  label: 'More',
                  focusNode: anchor,
                  onSelect: () => showTvLibraryMore(
                    context,
                    anchor,
                    MediaLibrary(id: '1', backend: client.backend, title: 'Movies', serverId: 'server'),
                    client,
                    canAdminister: allowed,
                  ),
                ),
                if (libraries != null && hidden != null)
                  Consumer2<LibrariesProvider, HiddenLibrariesProvider>(
                    builder: (_, libs, visibility, _) => Text(
                      'menu:${libs.libraries.where((l) => !visibility.hiddenLibraryKeys.contains(l.globalKey)).map((l) => l.id).join(',')}',
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    tester.widget<TvButton>(find.byType(TvButton)).onSelect!();
    await settle(tester);
    return anchor;
  }

  for (final action in ['scan', 'analyze', 'refresh', 'trash']) {
    testWidgets('A18 Plex $action confirms, closes, restores focus and calls exact client', (tester) async {
      final client = FakePlexLibraryClient();
      final anchor = await mount(tester, client);
      await activate(tester, action);
      expect(client.calls, isEmpty);
      await activate(tester, 'cancel');
      expect(client.calls, isEmpty);
      await activate(tester, action);
      await activate(tester, 'confirm');
      expect(client.calls, ['$action:1']);
      expect(find.byType(TvRightPanel), findsNothing);
      expect(anchor.hasFocus, isTrue);
      await tester.pump(const Duration(seconds: 3));
      await settle(tester);
      final message = switch (action) {
        'scan' => t.messages.libraryScanStarted(title: 'Movies'),
        'analyze' => t.libraries.analysisStarted(title: 'Movies'),
        'refresh' => t.messages.metadataRefreshStarted(title: 'Movies'),
        _ => t.libraries.trashEmptied(title: 'Movies'),
      };
      expect(find.textContaining(message), findsOneWidget);
    });
  }
  testWidgets('other servers offer only refresh; failure uses Plezy message', (tester) async {
    final client = FakeMediaServerClient()..actionError = StateError('offline');
    await mount(tester, client);
    expect(find.byKey(const ValueKey('scan')), findsNothing);
    expect(find.byKey(const ValueKey('analyze')), findsNothing);
    expect(find.byKey(const ValueKey('trash')), findsNothing);
    await activate(tester, 'refresh');
    await activate(tester, 'confirm');
    await tester.pump(const Duration(seconds: 3));
    await settle(tester);
    expect(client.calls, ['refresh:1']);
    expect(find.textContaining('offline'), findsOneWidget);
  });
  testWidgets('screen More default opens management and hiding keeps current controller', (tester) async {
    final libraries = FakeLibraries();
    final hidden = HiddenLibrariesProvider();
    await hidden.ensureInitialized();
    final controller = TvLibraryController(
      library: library,
      client: FakeMediaServerClient(),
      store: TvMemoryLibraryPreferences(),
    );
    addTearDown(libraries.dispose);
    addTearDown(hidden.dispose);
    addTearDown(controller.dispose);
    await pumpTvWidget(
      tester,
      MultiProvider(
        providers: [
          ChangeNotifierProvider<LibrariesProvider>.value(value: libraries),
          ChangeNotifierProvider<HiddenLibrariesProvider>.value(value: hidden),
        ],
        child: TvLibraryScreen(controller: controller),
      ),
    );
    await settle(tester);
    final button = find.byWidgetPredicate((w) => w is TvButton && w.label == 'More');
    tester.widget<TvButton>(button).onSelect!();
    await settle(tester);
    await activate(tester, 'manage');
    await activate(tester, 'order:${library.globalKey}');
    await press(tester, LogicalKeyboardKey.escape);
    await press(tester, LogicalKeyboardKey.escape);
    expect(tester.widget<TvLibraryScreen>(find.byType(TvLibraryScreen)).controller, same(controller));
    expect(controller.library, same(library));
    expect(tester.widget<TvButton>(button).focusNode!.hasFocus, isTrue);
  });
  testWidgets('non-admin has management only', (tester) async {
    await mount(tester, FakePlexLibraryClient(), allowed: false);
    expect(find.byKey(const ValueKey('scan')), findsNothing);
    expect(find.byKey(const ValueKey('refresh')), findsNothing);
    expect(find.byKey(const ValueKey('manage')), findsOneWidget);
  });
  testWidgets('A19 providers immediately update menu; current library stays hidden and reorder persists', (
    tester,
  ) async {
    final libraries = FakeLibraries();
    final hidden = HiddenLibrariesProvider();
    await hidden.ensureInitialized();
    addTearDown(libraries.dispose);
    addTearDown(hidden.dispose);
    final anchor = await mount(tester, FakeMediaServerClient(), libraries: libraries, hidden: hidden);
    await activate(tester, 'manage');
    await activate(tester, 'order:${library.globalKey}');
    expect(hidden.hiddenLibraryKeys, contains(library.globalKey));
    expect(find.text('menu:2'), findsOneWidget);
    expect(find.byType(TvRightPanel), findsOneWidget);
    final row = tester.widget<TvSettingsItem>(find.byKey(ValueKey('order:${library.globalKey}')));
    row.onMoveDown!();
    await settle(tester);
    expect(libraries.libraries.map((l) => l.id), ['2', '1']);
    await activate(tester, 'order:${library.globalKey}');
    expect(find.text('menu:2,1'), findsOneWidget);
    await press(tester, LogicalKeyboardKey.escape);
    await press(tester, LogicalKeyboardKey.escape);
    expect(anchor.hasFocus, isTrue);
  });
}
