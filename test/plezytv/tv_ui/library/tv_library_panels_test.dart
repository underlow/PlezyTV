import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/services/jellyfin_client.dart';
import '../../../test_helpers/backend_client_fixtures.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/library_filter_result.dart';
import 'package:plezy/focus/focusable_text_field.dart';
import 'package:plezy/media/library_query.dart';
import 'package:plezy/media/media_filter.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_library.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_button.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_right_panel.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_settings_item.dart';
import 'package:plezy/plezytv/tv_ui/library/tv_library_controller.dart';
import 'package:plezy/plezytv/tv_ui/library/tv_library_panels.dart';
import 'package:plezy/plezytv/tv_ui/library/tv_library_preferences.dart';
import 'package:plezy/plezytv/tv_ui/library/tv_library_screen.dart';
import 'package:plezy/plezytv/tv_ui/tv_strings.dart';
import '../tv_theme_test_helper.dart';
import 'fake_media_server_client.dart';
import 'tv_library_screen_test.dart' show library, movie, settle, press, focus;

void main() {
  Future<TvLibraryController> mount(
    WidgetTester tester,
    FakeMediaServerClient client, {
    TvLibraryPreferences? saved,
    MediaLibrary lib = library,
    Future<void> Function(BuildContext, MediaItem)? open,
  }) async {
    final c = TvLibraryController(
      library: lib,
      client: client,
      store: TvMemoryLibraryPreferences(seed: saved),
    );
    addTearDown(c.dispose);
    await pumpTvWidget(tester, TvLibraryScreen(controller: c, openItem: open));
    await settle(tester);
    return c;
  }

  Future<void> activate(WidgetTester tester, String key) async {
    final found = find.byKey(ValueKey(key));
    await tester.ensureVisible(found);
    tester.widget<TvSettingsItem>(found).onSelect!();
    await settle(tester);
  }

  Future<void> button(WidgetTester tester, String label) async {
    final found = find.byWidgetPredicate((w) => w is TvButton && w.label.startsWith(label));
    tester.widget<TvButton>(found).onSelect!();
    await settle(tester);
  }

  testWidgets('A16: sort default direction, panel refresh, Back anchor and Down first item', (tester) async {
    final client = FakeMediaServerClient()..items = [movie(0), movie(1)];
    final c = await mount(tester, client);
    await button(tester, TvStrings.defaultSort);
    await activate(tester, 'sort:addedAt');
    expect(c.preferences.descending, isTrue);
    expect(client.queries.last.sort?.field, 'addedAt');
    expect(find.byType(TvRightPanel), findsOneWidget);
    await c.refresh();
    await settle(tester);
    expect(find.byType(TvRightPanel), findsOneWidget);
    await press(tester, LogicalKeyboardKey.escape);
    expect(focus, 'Library sort');
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(focus, 'TV grid 0');
  });
  testWidgets('A7 A22: multi-select updates field count and server count; clear empty results', (tester) async {
    final client = FakeMediaServerClient()..items = [movie(0), movie(1)];
    client.filters = LibraryFilterResult(
      filters: [MediaFilter(filter: 'genre', filterType: 'tag', key: '/genre', title: 'Genre', type: 'filter')],
      cachedValues: {
        'genre': [MediaFilterValue(key: 'drama', title: 'Drama')],
      },
    );
    client.onPage = (q) async =>
        LibraryPage(items: q.filters.isEmpty ? client.items : [], totalCount: q.filters.isEmpty ? 2 : 0);
    final c = await mount(tester, client);
    await button(tester, 'Filters');
    await activate(tester, 'genre');
    await activate(tester, 'drama');
    expect(c.preferences.filters.single.values, ['drama']);
    expect(find.text('Filters · 1'), findsOneWidget);
    expect(find.textContaining(' · 0'), findsOneWidget);
    await press(tester, LogicalKeyboardKey.escape);
    await press(tester, LogicalKeyboardKey.escape);
    expect(focus, 'Library filters');
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(find.text(TvStrings.libraryNoMatches), findsOneWidget);
    expect(focus, 'Library state action');
    await press(tester, LogicalKeyboardKey.enter);
    expect(c.preferences.filters, isEmpty);
  });
  testWidgets('Jellyfin Filters disabled until discovery completes', (tester) async {
    final pending = Completer<LibraryFilterResult>();
    final client = FakeMediaServerClient()
      ..items = [movie(0)]
      ..onFilters = () => pending.future;
    await mount(tester, client);
    TvButton filters() => tester.widget<TvButton>(find.byWidgetPredicate((w) => w is TvButton && w.label == 'Filters'));
    expect(filters().disabled, isTrue);
    pending.complete(LibraryFilterResult.empty);
    await settle(tester);
    expect(filters().disabled, isFalse);
  });
  testWidgets('A17: folders preserve row after item, refresh and Back; empty and retry', (tester) async {
    final folder = movie(10).copyWith(kind: MediaKind.folder, title: 'Folder');
    var fail = false;
    final client = FakeMediaServerClient()
      ..onFolder = (f) async {
        if (fail) throw StateError('offline');
        return f == null ? [folder, movie(2)] : [movie(3)];
      };
    var opened = 0;
    final c = await mount(
      tester,
      client,
      saved: TvLibraryPreferences(grouping: 'folders'),
      open: (_, item) async {
        opened++;
      },
    );
    expect(focus, 'Folder row 0');
    await press(tester, LogicalKeyboardKey.enter);
    expect(c.folders.length, 2);
    await press(tester, LogicalKeyboardKey.enter);
    expect(opened, 1);
    expect(focus, 'Folder row 0');
    await c.refresh();
    await settle(tester);
    expect(c.folders.length, 2);
    expect(focus, 'Folder row 0');
    await button(tester, TvStrings.defaultSort);
    final level = c.folders.last;
    await c.refresh();
    await settle(tester);
    expect(c.folders.last, same(level));
    expect(find.byType(TvRightPanel), findsOneWidget);
    await press(tester, LogicalKeyboardKey.escape);
    expect(focus, 'Library sort');
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(focus, 'Folder row 0');
    await press(tester, LogicalKeyboardKey.escape);
    expect(c.folders.length, 1);
    expect(find.text('Folder'), findsOneWidget);
    await press(tester, LogicalKeyboardKey.enter);
    client.onFolder = (_) async => [];
    await c.refresh();
    await settle(tester);
    expect(find.text(TvStrings.folderEmpty), findsOneWidget);
    await press(tester, LogicalKeyboardKey.escape);
    expect(c.folders.length, 1);
    fail = true;
    client.onFolder = (_) async {
      if (fail) throw StateError('offline');
      return [folder];
    };
    await c.refresh();
    await settle(tester);
    expect(find.text(TvStrings.retry), findsOneWidget);
    fail = false;
    tester.widget<TvSettingsItem>(find.widgetWithText(TvSettingsItem, TvStrings.retry)).onSelect!();
    await settle(tester);
    expect(find.text('Folder'), findsOneWidget);
  });
  testWidgets('native text, numeric units and two bounds, date windows and boolean tri-state', (tester) async {
    MediaFilter filter(String name, String type, {MediaFilterUnit unit = MediaFilterUnit.none}) =>
        MediaFilter(filter: name, filterType: type, key: '', title: name, type: 'filter', unit: unit);
    final client = FakeMediaServerClient()..items = [movie(0)];
    client.filters = LibraryFilterResult(
      filters: [
        filter('title', 'string'),
        filter('duration', 'integer', unit: MediaFilterUnit.duration),
        filter('addedAt', 'date'),
        filter('unwatched', 'boolean'),
      ],
      cachedValues: {},
    );
    final c = await mount(tester, client);
    await button(tester, 'Filters');
    await activate(tester, 'title');
    expect(
      tester.widget<FocusableTextField>(find.byType(FocusableTextField)).tvTextInputPresentation,
      TvTextInputPresentation.platform,
    );
    await tester.enterText(find.byType(TextField), 'Alien');
    await settle(tester);
    expect(c.preferences.filters.single.values, ['Alien']);
    final owner = FocusManager.instance.primaryFocus;
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    expect(FocusManager.instance.primaryFocus, owner);
    expect(find.byType(TvRightPanel), findsOneWidget);
    await press(tester, LogicalKeyboardKey.escape);
    await activate(tester, 'duration');
    await tester.enterText(find.byType(TextField).at(0), '90');
    await settle(tester);
    await tester.enterText(find.byType(TextField).at(1), '120');
    await settle(tester);
    expect(c.preferences.filters.where((x) => x.field == 'duration').map((x) => x.values.single), [
      '5400000',
      '7200000',
    ]);
    await press(tester, LogicalKeyboardKey.escape);
    await activate(tester, 'addedAt');
    await activate(tester, 'LibraryFilterOperator.atLeast:-30d');
    expect(c.preferences.filters.last.values, ['-30d']);
    await press(tester, LogicalKeyboardKey.escape);
    await activate(tester, 'unwatched');
    await activate(tester, '0');
    expect(c.preferences.filters.last.op, LibraryFilterOperator.isNot);
    expect(c.preferences.filters.last.values, ['1']);
    await activate(tester, 'clear');
    expect(c.preferences.filters.any((x) => x.field == 'unwatched'), isFalse);
  });
  testWidgets('grouping page switches grid to folders and reset restores defaults', (tester) async {
    final client = FakeMediaServerClient()..items = [movie(0)];
    final c = await mount(tester, client);
    await button(tester, TvStrings.defaultSort);
    await activate(tester, 'grouping');
    await activate(tester, 'group:folders');
    expect(c.grouping, 'folders');
    expect(find.byType(TvRightPanel), findsOneWidget);
    await press(tester, LogicalKeyboardKey.escape);
    await activate(tester, 'reset');
    expect(c.grouping, 'movies');
    expect(c.selectedSort, isNull);
    await press(tester, LogicalKeyboardKey.escape);
    expect(focus, 'Library sort');
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(focus, 'TV grid 0');
  });
  testWidgets('3000 real Actor values stay lazy while traversing, toggling and returning', (tester) async {
    final values = Completer<List<MediaFilterValue>>();
    final client = FakePlexLibraryClient()
      ..items = [movie(0)]
      ..filters = LibraryFilterResult(
        filters: [MediaFilter(filter: 'actor', filterType: 'tag', key: '/actors', title: 'Actor', type: 'filter')],
        cachedValues: {},
      )
      ..onValues = (key) async {
        expect(key, '/actors');
        return values.future;
      };
    final c = await mount(
      tester,
      client,
      lib: const MediaLibrary(
        id: '1',
        backend: MediaBackend.plex,
        title: 'Movies',
        kind: MediaKind.movie,
        serverId: 'server',
      ),
    );
    await button(tester, 'Filters');
    await activate(tester, 'actor');
    final loadingClear = FocusManager.instance.primaryFocus;
    expect(loadingClear?.context?.findAncestorWidgetOfExactType<TvLibraryFilterEditor>(), isNotNull);
    values.complete(
      List.generate(3000, (i) => MediaFilterValue(key: '/library/sections/1/all?actor=$i', title: 'Actor $i')),
    );
    await settle(tester);
    expect(FocusManager.instance.primaryFocus, same(loadingClear));
    int mountedRows() => find
        .descendant(of: find.byType(TvLibraryFilterEditor), matching: find.byType(TvSettingsItem))
        .evaluate()
        .length;
    expect(mountedRows(), lessThan(30));
    expect(find.text('Actor 2999'), findsNothing);
    final clear = tester.widget<TvSettingsItem>(
      find.descendant(of: find.byType(TvLibraryFilterEditor), matching: find.byKey(const ValueKey('clear'))),
    );
    clear.focusNode!.requestFocus();
    await settle(tester);
    await press(tester, LogicalKeyboardKey.arrowDown); // exclusion
    await press(tester, LogicalKeyboardKey.arrowDown); // actor 0
    for (var i = 0; i < 60; i++) {
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(mountedRows(), lessThan(30));
    }
    final row = find.byKey(const ValueKey('/library/sections/1/all?actor=60'));
    final node = tester.widget<TvSettingsItem>(row).focusNode;
    expect(node!.hasFocus, isTrue);
    final scroll = tester.state<ScrollableState>(
      find.descendant(of: find.byType(TvLibraryFilterEditor), matching: find.byType(Scrollable)),
    );
    final offset = scroll.position.pixels;
    await press(tester, LogicalKeyboardKey.enter);
    expect(c.preferences.filters.single.values, ['60']);
    expect(tester.widget<TvSettingsItem>(row).selected, isTrue);
    expect(FocusManager.instance.primaryFocus, same(node));
    expect(scroll.position.pixels, offset);
    expect(mountedRows(), lessThan(30));
    await press(tester, LogicalKeyboardKey.enter);
    expect(c.preferences.filters, isEmpty);
    for (final key in [LogicalKeyboardKey.arrowLeft, LogicalKeyboardKey.arrowRight]) {
      await press(tester, key);
      expect(
        FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<TvLibraryFilterEditor>(),
        isNotNull,
      );
    }
    await press(tester, LogicalKeyboardKey.escape);
    expect(find.byKey(const ValueKey('actor')), findsOneWidget);
    await press(tester, LogicalKeyboardKey.escape);
    expect(focus, 'Library filters');
  });

  testWidgets('real Jellyfin favorite schema offers Any/Yes; unwatched retains No', (tester) async {
    final backend = JellyfinClient.forTesting(
      connection: testJellyfinConnection(),
      httpClient: MockClient((_) async => http.Response('{}', 200)),
    );
    addTearDown(backend.close);
    final schema = await backend.fetchLibraryFiltersWithValues('1', libraryKind: MediaKind.movie);
    final client = FakeMediaServerClient()
      ..items = [movie(0)]
      ..filters = schema;
    final c = await mount(tester, client);
    await button(tester, 'Filters');
    await activate(tester, 'favorite');
    expect(find.text(t.libraries.advancedFilters.no), findsNothing);
    await activate(tester, '1');
    expect(c.preferences.filters.single.op, LibraryFilterOperator.is_);
    expect(c.preferences.filters.single.field, 'favorite');
    await activate(tester, 'clear');
    expect(c.preferences.filters, isEmpty);
    await press(tester, LogicalKeyboardKey.escape);
    await activate(tester, 'unwatched');
    await activate(tester, '0');
    expect(c.preferences.filters.single.op, LibraryFilterOperator.isNot);
  });
}
