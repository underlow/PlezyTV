import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:plezy/main.dart' show rootNavigatorKey;
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_library.dart';
import 'package:plezy/media/media_filter.dart';
import 'package:plezy/media/library_query.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_side_menu.dart';
import 'package:plezy/media/library_filter_result.dart';
import 'package:plezy/navigation/navigation_tabs.dart';
import 'package:plezy/navigation/profile_navigation_scope.dart';
import 'package:plezy/plezytv/screen_links/screen_link_router.dart';
import 'package:plezy/plezytv/tv_ui/library/tv_library_screen.dart';
import 'package:plezy/plezytv/tv_ui/library/tv_libraries_switch.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_button.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_right_panel.dart';
import 'package:plezy/plezytv/tv_ui/tv_strings.dart';
import 'package:plezy/plezytv/tv_ui/shell/tv_section_shell.dart';
import 'package:plezy/providers/libraries_provider.dart';
import 'package:plezy/providers/hidden_libraries_provider.dart';
import 'package:plezy/providers/multi_server_provider.dart';
import 'package:plezy/providers/offline_mode_provider.dart';
import 'package:plezy/screens/libraries/libraries_screen.dart';
import 'package:plezy/services/multi_server_manager.dart';
import 'package:plezy/services/data_aggregation_service.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/services/storage_service.dart';
import 'package:plezy/i18n/strings.g.dart';
import '../../../test_helpers/prefs.dart';
import 'fake_media_server_client.dart';

const video = MediaLibrary(
  id: '1',
  backend: MediaBackend.jellyfin,
  title: 'Movies',
  kind: MediaKind.movie,
  serverId: 'server',
);
const music = MediaLibrary(
  id: '2',
  backend: MediaBackend.jellyfin,
  title: 'Music',
  kind: MediaKind.artist,
  serverId: 'server',
);
const shows = MediaLibrary(
  id: '3',
  backend: MediaBackend.jellyfin,
  title: 'Shows',
  kind: MediaKind.show,
  serverId: 'server',
);

void main() {
  setUp(resetSharedPreferencesForTest);
  late FakeMediaServerClient client;
  late LibrariesProvider libraries;
  late HiddenLibrariesProvider hidden;
  late StorageService storage;
  late GlobalKey<TvSectionShellState> shell;
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> mount(
    WidgetTester tester, {
    List<MediaLibrary> rows = const [video, music, shows],
    String? saved,
    bool allHidden = false,
  }) async {
    client = FakeMediaServerClient()..libraries = rows;
    final manager = MultiServerManager()..debugRegisterClientForTesting(client);
    final aggregation = DataAggregationService(manager);
    final servers = MultiServerProvider(manager, aggregation);
    storage = await StorageService.getInstance();
    if (saved != null) await storage.saveSelectedLibraryKey(saved);
    libraries = LibrariesProvider()..initialize(aggregation);
    await libraries.syncToOnlineServers({'server'});
    hidden = HiddenLibrariesProvider();
    await hidden.ensureInitialized();
    if (allHidden) {
      for (final row in rows) {
        await hidden.hideLibrary(row.globalKey);
      }
    }
    final offline = OfflineModeProvider(manager);
    final settings = await SettingsService.getInstance();
    await settings.write(SettingsService.startupSection, NavigationTabId.libraries);
    shell = GlobalKey<TvSectionShellState>();
    TvSectionShell.sessionControllerFactoryForTesting = (_, _) => null;
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(() async {
      ScreenLinkRouter.instance.queue.dispose();
      await tester.pumpWidget(const SizedBox());
      profileNavigationRegistry.detachNavigator(rootNavigatorKey);
      libraries.dispose();
      hidden.dispose();
      offline.dispose();
      servers.dispose();
      manager.dispose();
      TvSectionShell.sessionControllerFactoryForTesting = null;
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<LibrariesProvider>.value(value: libraries),
          ChangeNotifierProvider<HiddenLibrariesProvider>.value(value: hidden),
          ChangeNotifierProvider<MultiServerProvider>.value(value: servers),
          ChangeNotifierProvider<OfflineModeProvider>.value(value: offline),
        ],
        child: MaterialApp(
          navigatorKey: rootNavigatorKey,
          home: TvSectionShell(key: shell, isOfflineMode: false, initialPromptHandled: true),
        ),
      ),
    );
    profileNavigationRegistry.attachNavigator(rootNavigatorKey);
    await settle(tester);
    expect(find.byType(TvLibrariesSwitch), findsOneWidget);
  }

  TvLibraryScreen screen(WidgetTester tester) => tester.widget(find.byType(TvLibraryScreen));

  testWidgets('real library section selects saved/explicit/hidden, recreates video → music → video', (tester) async {
    await mount(tester, saved: shows.globalKey);
    expect(screen(tester).controller.library, shows);
    expect(shell.currentState!.currentSection.libraryGlobalKey, shows.globalKey);
    ScreenLinkRouter.instance.claim('plezytv://screen/libraries');
    await settle(tester);
    expect(screen(tester).controller.library, shows);
    final menu = tester.widget<TvSideMenu>(find.byType(TvSideMenu));
    expect(menu.items[menu.currentIndex!].label, shows.title);
    final first = screen(tester).controller;
    tester
        .widget<TvSideMenu>(find.byType(TvSideMenu))
        .items
        .firstWhere((item) => item.label == music.title)
        .onSelect!();
    await settle(tester);
    expect(find.byType(LibrariesScreen), findsOneWidget);
    expect(find.byType(TvLibraryScreen), findsNothing);
    tester
        .widget<TvSideMenu>(find.byType(TvSideMenu))
        .items
        .firstWhere((item) => item.label == shows.title)
        .onSelect!();
    await settle(tester);
    expect(screen(tester).controller, isNot(same(first)));
    await hidden.hideLibrary(video.globalKey);
    ScreenLinkRouter.instance.claim('plezytv://screen/library?id=1&server=server');
    await settle(tester);
    expect(screen(tester).controller.library, video);
    expect(storage.getSelectedLibraryKey(), video.globalKey);
    expect(shell.currentState!.currentSection.libraryGlobalKey, video.globalKey);
    await hidden.hideLibrary(shows.globalKey);
    shell.currentState!.selectLibrary('server:999');
    await settle(tester);
    expect(find.byType(LibrariesScreen), findsOneWidget); // only visible music
    ScreenLinkRouter.instance.claim('plezytv://screen/library?id=999&server=server');
    await settle(tester);
    expect(shell.currentState!.currentSection.libraryGlobalKey, music.globalKey);
  });

  testWidgets('first visible default; hiding stays; removed selection resolves next visible', (tester) async {
    await mount(tester);
    expect(screen(tester).controller.library, video);
    await hidden.hideLibrary(video.globalKey);
    await settle(tester);
    expect(screen(tester).controller.library, video);
    client.libraries = [shows];
    await libraries.refresh();
    await settle(tester);
    expect(screen(tester).controller.library, shows);
    expect(shell.currentState!.currentSection.libraryGlobalKey, shows.globalKey);
    expect(storage.getSelectedLibraryKey(), shows.globalKey);
  });

  testWidgets('empty and all-hidden section, management button focused and usable', (tester) async {
    await mount(tester, allHidden: true);
    expect(find.text(t.libraries.allLibrariesHidden), findsOneWidget);
    final button = tester.widget<TvButton>(find.byType(TvButton));
    expect(button.focusNode!.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await settle(tester);
    expect(find.byType(TvRightPanel), findsOneWidget);
    expect(find.text(t.libraries.manageLibraries), findsWidgets);
    expect(find.byKey(ValueKey('hidden:${video.globalKey}')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    expect(find.byType(TvRightPanel), findsNothing);
    expect(button.focusNode!.hasFocus, isTrue);
  });

  testWidgets('real library header opens sort, Filters and More panels and restores anchors', (tester) async {
    await mount(tester);
    for (final label in ['Library sort', 'Library filters', 'Library more']) {
      final button = tester
          .widgetList<TvButton>(find.byType(TvButton))
          .firstWhere((button) => button.focusNode?.debugLabel == label);
      button.focusNode!.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await settle(tester);
      expect(find.byType(TvRightPanel), findsOneWidget);
      final title = switch (label) {
        'Library sort' => t.libraries.sortBy,
        'Library filters' => t.libraries.filters,
        _ => TvStrings.moreLibraries,
      };
      expect(find.text(title), findsWidgets);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(tester);
      expect(find.byType(TvRightPanel), findsNothing);
      expect(button.focusNode!.hasFocus, isTrue);
    }
  });

  testWidgets('no libraries reports empty state', (tester) async {
    await mount(tester, rows: []);
    expect(find.text(t.libraries.noLibrariesFound), findsOneWidget);
  });

  testWidgets('filtered links reject unknown library/kind/field/value; valid route never persists edits', (
    tester,
  ) async {
    await mount(tester);
    final before = screen(tester).controller;
    client.filters = LibraryFilterResult(
      filters: [MediaFilter(filter: 'genre', filterType: 'tag', key: 'genres', title: 'Genre', type: 'filter')],
      cachedValues: {
        'genre': [MediaFilterValue(key: '7', title: 'Drama')],
      },
    );
    for (final path in [
      'id=99&field=genre&value=7',
      'id=2&field=genre&value=7',
      'id=1&field=bad&value=7',
      'id=1&field=genre&value=bad',
    ]) {
      ScreenLinkRouter.instance.claim('plezytv://screen/library-filter?$path&server=server');
      await settle(tester);
      expect(screen(tester).controller, same(before));
    }
    await storage.saveLibraryTab(video.globalKey, 'recommended');
    await storage.saveLibraryGrouping(video.globalKey, 'movies');
    await storage.saveLibrarySort(video.globalKey, 'titleSort', descending: true);
    final savedFilter = LibraryFilter(field: 'genre', values: ['8']);
    await storage.saveLibraryFilters([savedFilter], sectionId: video.globalKey);
    final selected = shell.currentState!.currentSection;
    ScreenLinkRouter.instance.claim('plezytv://screen/library-filter?id=1&field=genre&value=7&server=server');
    await settle(tester);
    final filtered = tester.widgetList<TvLibraryScreen>(find.byType(TvLibraryScreen)).last.controller;
    expect(filtered.preferences.tab, 'browse');
    expect(filtered.preferences.grouping, 'movies');
    expect(filtered.preferences.sortKey, 'titleSort');
    expect(filtered.preferences.descending, isTrue);
    expect(filtered.preferences.filters.single.values, ['7']);
    await filtered.select(sort: filtered.sorts.last, descending: true);
    await filtered.resetFilters();
    await filtered.select(tab: 'collections');
    expect(storage.getLibraryTab(video.globalKey), 'recommended');
    expect(storage.getLibraryGrouping(video.globalKey), 'movies');
    expect(storage.getLibrarySort(video.globalKey), {'key': 'titleSort', 'descending': true});
    expect(storage.getLibraryFilters(sectionId: video.globalKey), [savedFilter]);
    expect(shell.currentState!.currentSection, selected);
    rootNavigatorKey.currentState!.pop();
    await settle(tester);
    expect(screen(tester).controller, same(before));
  });
  testWidgets('filtered links normalize Plex query, path and encoded value keys', (tester) async {
    const plex = MediaLibrary(
      id: '1',
      backend: MediaBackend.plex,
      title: 'Movies',
      kind: MediaKind.movie,
      serverId: 'server',
    );
    await mount(tester, rows: [plex]);
    for (final example in [
      ('genre', '/library/sections/1/all?genre=239', '239'),
      ('genre', '/library/sections/1/genre/239', '239'),
      ('contentRating', '16%2B', '16+'),
      ('contentRating', '/library/sections/1/all?contentRating=16%2B', '16+'),
    ]) {
      client.filters = LibraryFilterResult(
        filters: [MediaFilter(filter: example.$1, filterType: 'tag', key: '/values', title: 'Value', type: 'filter')],
        cachedValues: {
          example.$1: [MediaFilterValue(key: example.$2, title: 'Value')],
        },
      );
      final uri = Uri(
        scheme: 'plezytv',
        host: 'screen',
        path: '/library-filter',
        queryParameters: {'id': '1', 'server': 'server', 'field': example.$1, 'value': example.$3},
      );
      ScreenLinkRouter.instance.claim('$uri');
      await settle(tester);
      final screens = tester.widgetList<TvLibraryScreen>(find.byType(TvLibraryScreen)).toList();
      expect(screens.length, 1); // covered underlying route is offstage
      final c = screens.last.controller;
      expect(c.preferences.filters.single.values, [example.$3]);
      expect(client.queries.last.filters.single.values, [example.$3]);
      rootNavigatorKey.currentState!.pop();
      await settle(tester);
    }
  });
}
