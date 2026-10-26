import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_server_client.dart';
import 'package:plezy/models/catalog/catalog_item.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_cards.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_paged_grid.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_skeletons.dart';
import 'package:plezy/plezytv/tv_ui/home/tv_home_playback.dart';
import 'package:plezy/plezytv/tv_ui/watchlist/tv_catalog_item_screen.dart';
import 'package:plezy/plezytv/tv_ui/watchlist/tv_watchlist_screen.dart';
import 'package:plezy/plezytv/tv_ui/watchlist/tv_watchlist_controller.dart';
import 'package:plezy/providers/multi_server_provider.dart';
import 'package:plezy/services/catalog/catalog_library_matcher.dart';
import 'package:plezy/services/catalog/catalog_source.dart';
import 'package:plezy/services/data_aggregation_service.dart';

import '../../../test_helpers/library_lookup.dart';
import '../../../test_helpers/media_items.dart';
import '../tv_theme_test_helper.dart';

class _Source implements CatalogSource {
  _Source(this.id, this.items);

  @override
  final CatalogSourceId id;
  List<CatalogItem> items;
  int listFetches = 0;
  Object? error;
  Completer<void>? gate;
  final WatchlistChangeNotifier changes = WatchlistChangeNotifier();

  @override
  String get displayName => id == CatalogSourceId.plex ? 'Plex' : 'Trakt';
  @override
  bool get supportsWatchlist => true;
  @override
  Listenable get watchlistChanges => changes;

  @override
  Future<CatalogPage> fetchRow(CatalogRowId row, {int page = 1, int limit = 25}) async {
    if (page == 1) listFetches++;
    if (gate case final gate?) await gate.future;
    if (error case final error?) throw error;
    final start = ((page - 1) * limit).clamp(0, items.length);
    final end = (start + limit).clamp(0, items.length);
    return CatalogPage(items: items.sublist(start, end), hasMore: end < items.length);
  }

  @override
  Future<void> ensureWatchlistLoaded() async {}

  @override
  bool? isOnWatchlist(MediaKind kind, CatalogItemIds ids) => null;

  @override
  Future<CatalogDetail> fetchDetail(CatalogItem item, {int castLimit = 20, int relatedLimit = 20}) async =>
      CatalogDetail(item: item);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Sources extends ChangeNotifier {
  _Sources(this.list);
  List<CatalogSource> list;
}

class _Call {
  _Call(this.item, this.refresh);
  final CatalogItem item;
  final bool refresh;
  final completer = Completer<LibraryLookupResult>();
}

final _notFound = libraryLookupResult(const [], succeeded: {'a'});

class _Matcher implements CatalogLibraryMatcher {
  /// Answers by title; unknown titles are not found. With [hold], calls wait.
  final Map<String, LibraryLookupResult> results = {};
  bool hold = false;
  final List<_Call> calls = [];

  @override
  Future<LibraryLookupResult> match(CatalogItem item, {bool refreshIncomplete = false}) {
    final call = _Call(item, refreshIncomplete);
    calls.add(call);
    if (!hold) call.completer.complete(results[item.title] ?? _notFound);
    return call.completer.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Servers extends ChangeNotifier implements MultiServerProvider {
  @override
  List<String> expectedServerIds = ['a'];
  @override
  List<String> onlineServerIds = ['a'];
  void set({required List<String> expected, required List<String> online}) {
    expectedServerIds = expected;
    onlineServerIds = online;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Client implements MediaServerClient {
  _Client(this.episode);
  final MediaItem? episode;
  @override
  Future<({MediaItem? item, MediaItem? onDeckEpisode})> fetchItemWithOnDeck(
    String id, {
    void Function(MediaItem item)? onItemReady,
  }) async => (item: null, onDeckEpisode: episode);
  @override
  Future<List<MediaItem>> fetchChildren(String id) async => const [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

CatalogItem _item(
  int n, {
  CatalogSourceId source = CatalogSourceId.plex,
  MediaKind kind = MediaKind.movie,
  String? title,
}) => CatalogItem(
  source: source,
  kind: kind,
  title: title ?? 'T$n',
  year: 2000 + n % 20,
  ids: CatalogItemIds(trakt: n),
);

List<CatalogItem> _items(int count, {CatalogSourceId source = CatalogSourceId.plex}) => [
  for (var i = 0; i < count; i++) _item(i, source: source),
];

LibraryLookupResult _found(String id, {Set<String> succeeded = const {'a'}, Set<String> unqueried = const {}}) =>
    libraryLookupResult(
      [testMediaItem(id: id, serverId: 'a')],
      succeeded: succeeded,
      unqueried: unqueried,
    );

void main() {
  late _Matcher matcher;
  late _Servers servers;
  late TvMemoryWatchlistPreferences prefs;
  late _Sources sources;
  late List<String> searches;
  late List<MediaItem> played, details, openedCopies;
  late List<TvCatalogItemArgs> cards;
  Future<void> Function(BuildContext, TvCatalogItemArgs)? cardHook;
  MediaServerClient? client;
  var clock = DateTime(2026, 10, 25, 12);

  setUp(() {
    matcher = _Matcher();
    servers = _Servers();
    prefs = TvMemoryWatchlistPreferences();
    searches = [];
    played = [];
    details = [];
    openedCopies = [];
    cards = [];
    cardHook = null;
    client = null;
    clock = DateTime(2026, 10, 25, 12);
  });

  tearDown(() => tvOpenCopyForTesting = null);

  Future<TvWatchlistScreenState> pumpScreen(WidgetTester tester, List<CatalogSource> list) async {
    sources = _Sources(list);
    await pumpTvWidget(
      tester,
      Scaffold(
        body: TvWatchlistScreen(
          onOpenSearch: () => searches.add('search'),
          matcher: matcher,
          multiServer: servers,
          sourcesListenable: sources,
          readSources: () => sources.list,
          preferences: prefs,
          now: () => clock,
          playbackFactory: (context, isCurrent) => TvHomePlayback(
            clientForItem: (_) => client,
            isCurrent: isCurrent,
            play: (item) async => played.add(item),
            openDetails: (item) async => details.add(item),
          ),
          openCatalogItem: (context, args) async {
            cards.add(args);
            await cardHook?.call(context, args);
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();
    return tester.state<TvWatchlistScreenState>(find.byType(TvWatchlistScreen));
  }

  TvPagedGridState<CatalogItem> grid(WidgetTester tester) =>
      tester.state<TvPagedGridState<CatalogItem>>(find.byType(TvPagedGrid<CatalogItem>));

  String? focusLabel() => FocusManager.instance.primaryFocus?.debugLabel;

  List<String> badged(WidgetTester tester) => [
    for (final poster in tester.widgetList<TvPoster>(find.byType(TvPoster)))
      if (poster.onServer) poster.item.title ?? "",
  ];

  Future<void> key(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pump();
    await tester.pump();
  }

  /// OK opens a card route that covers the grid; the item is removed while
  /// covered, then Back returns to the grid (the real removal path).
  Future<void> removeWhileCovered(WidgetTester tester) async {
    TvCatalogItemArgs? opened;
    cardHook = (context, args) {
      opened = args;
      return Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const Focus(autofocus: true, debugLabel: 'card', child: SizedBox()),
        ),
      );
    };
    await key(tester, LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(focusLabel(), 'card', reason: 'the card covers the grid');
    opened!.onRemoved(opened!.item);
    await tester.pumpAndSettle();
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();
  }

  testWidgets('A3: single source loads, counts, focuses the first card, no source button', (tester) async {
    await pumpScreen(tester, [_Source(CatalogSourceId.plex, _items(32))]);

    expect(find.text('Watchlist'), findsOneWidget);
    expect(find.text('Date added · 32'), findsOneWidget);
    expect(find.text('Plex'), findsNothing);
    expect(focusLabel(), 'TV grid 0');
    expect(grid(tester).focusedIndex, 0);
    expect(find.byType(TvPosterSkeleton), findsNothing);
  });

  testWidgets('skeleton: hidden for a fast answer, shown after 300 ms, header drawn at once', (tester) async {
    final source = _Source(CatalogSourceId.plex, _items(3))..gate = Completer();
    await pumpScreen(tester, [source]);
    expect(find.text('Watchlist'), findsOneWidget);
    expect(find.text('Date added'), findsOneWidget);
    expect(find.byType(TvPosterSkeleton), findsNothing);
    await tester.pump(const Duration(milliseconds: 310));
    expect(find.byType(TvPosterSkeleton), findsWidgets);
    source.gate!.complete();
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(find.byType(TvPosterSkeleton), findsNothing);
    expect(focusLabel(), 'TV grid 0');
  });

  testWidgets('a fast answer never shows the skeleton', (tester) async {
    final source = _Source(CatalogSourceId.plex, _items(3))..gate = Completer();
    await pumpScreen(tester, [source]);
    await tester.pump(const Duration(milliseconds: 200));
    source.gate!.complete();
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(TvPosterSkeleton), findsNothing);
  });

  testWidgets('A21: load error focuses Retry; retry loads the list', (tester) async {
    final source = _Source(CatalogSourceId.plex, _items(4))..error = Exception('offline');
    await pumpScreen(tester, [source]);
    await tester.pump();

    expect(find.text('Couldn’t load the watchlist'), findsOneWidget);
    expect(focusLabel(), 'Watchlist state action');
    expect(find.text('Date added'), findsNothing);

    source.error = null;
    await key(tester, LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump();
    expect(find.text('Date added · 4'), findsOneWidget);
    expect(find.byType(TvPoster), findsNWidgets(4));
  });

  testWidgets('A19: empty list with one source; Go to search is focused and opens search', (tester) async {
    await pumpScreen(tester, [_Source(CatalogSourceId.plex, [])]);
    await tester.pump();

    expect(find.text('Your watchlist is empty'), findsOneWidget);
    expect(find.text('Plex'), findsNothing);
    expect(find.textContaining('Date added'), findsNothing);
    expect(focusLabel(), 'Watchlist state action');
    await key(tester, LogicalKeyboardKey.enter);
    expect(searches, ['search']);
  });

  testWidgets('A20: empty remembered Trakt keeps the source button; Up reaches it; Plex loads', (tester) async {
    prefs = TvMemoryWatchlistPreferences(const TvWatchlistPreferences(source: 'trakt'));
    final plex = _Source(CatalogSourceId.plex, _items(5));
    final trakt = _Source(CatalogSourceId.trakt, []);
    await pumpScreen(tester, [plex, trakt]);
    await tester.pump();

    expect(find.text('Your watchlist is empty'), findsOneWidget);
    expect(find.text('Trakt'), findsOneWidget);
    expect(find.textContaining('Date added'), findsNothing);
    expect(focusLabel(), 'Watchlist state action');

    await key(tester, LogicalKeyboardKey.arrowUp);
    expect(focusLabel(), 'Watchlist source');

    await key(tester, LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('source:plex')), findsOneWidget);
    await key(tester, LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.text('Plex'), findsOneWidget);
    expect(find.text('Date added · 5'), findsOneWidget);
    expect(focusLabel(), 'TV grid 0');
    expect(prefs.value.source, 'plex');
  });

  testWidgets('A25: with nothing remembered Plex opens first', (tester) async {
    await pumpScreen(tester, [_Source(CatalogSourceId.trakt, _items(2)), _Source(CatalogSourceId.plex, _items(3))]);
    expect(find.text('Plex'), findsOneWidget);
    expect(find.text('Date added · 3'), findsOneWidget);
  });

  testWidgets('A18: an empty tab shows its text and keeps focus on the tabs', (tester) async {
    await pumpScreen(tester, [_Source(CatalogSourceId.plex, _items(3))]);
    await key(tester, LogicalKeyboardKey.arrowUp);
    await key(tester, LogicalKeyboardKey.arrowRight);
    await key(tester, LogicalKeyboardKey.arrowRight);
    await key(tester, LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();

    expect(find.text('No shows in your watchlist'), findsOneWidget);
    expect(find.text('Date added · 0'), findsOneWidget);
    bool onTabs() => FocusManager.instance.primaryFocus!.ancestors.any((n) => n.debugLabel == 'Watchlist tabs');
    expect(onTabs(), isTrue);
    expect(find.byType(TvPoster), findsNothing);
    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(onTabs(), isTrue);
  });

  testWidgets('A13: On server tab says checking, then adds found items without moving focus', (tester) async {
    matcher.hold = true;
    prefs = TvMemoryWatchlistPreferences(const TvWatchlistPreferences(tab: TvWatchlistTab.onServer));
    final state = await pumpScreen(tester, [_Source(CatalogSourceId.plex, _items(6))]);

    expect(find.text('Checking what’s on the server…'), findsOneWidget);
    final tabFocus = FocusManager.instance.primaryFocus;

    final call = matcher.calls.firstWhere((c) => c.item.title == 'T2');
    call.completer.complete(_found('copy-2'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(TvPoster), findsOneWidget);
    expect(badged(tester), ['T2']);
    expect(FocusManager.instance.primaryFocus, tabFocus);

    while (matcher.calls.any((c) => !c.completer.isCompleted)) {
      for (final c in matcher.calls.where((c) => !c.completer.isCompleted).toList()) {
        c.completer.complete(_notFound);
      }
      await tester.pump();
      await tester.pump();
    }
    expect(state.availability.checking, isFalse);
    expect(badged(tester), ['T2']);
  });

  testWidgets('On server tab with nothing found after checking says so', (tester) async {
    prefs = TvMemoryWatchlistPreferences(const TvWatchlistPreferences(tab: TvWatchlistTab.onServer));
    await pumpScreen(tester, [_Source(CatalogSourceId.plex, _items(2))]);
    await tester.pump();
    await tester.pump();
    expect(find.text('Nothing from your watchlist is on the server'), findsOneWidget);
  });

  testWidgets('A4: visible items are checked before the rest', (tester) async {
    matcher.hold = true;
    final state = await pumpScreen(tester, [_Source(CatalogSourceId.plex, _items(375))]);
    await grid(tester).jumpTo(300);
    await tester.pump();
    await tester.pump();

    // Drain the checks started before the scroll; later ones follow the view.
    for (var round = 0; round < 3; round++) {
      for (final c in matcher.calls.where((c) => !c.completer.isCompleted).toList()) {
        c.completer.complete(_notFound);
      }
      await tester.pump();
    }
    final recent = matcher.calls.reversed.take(3).map((c) => int.parse(c.item.title.substring(1)));
    final view = [for (final i in state.controller.view) int.parse(i.title.substring(1))];
    for (final n in recent) {
      expect((view.indexOf(n) - 300).abs(), lessThan(60), reason: 'T$n is far from the visible rows');
    }
  });

  testWidgets('A4 variant: after a sort change mid-scan the visible items are checked first', (tester) async {
    matcher.hold = true;
    final state = await pumpScreen(tester, [_Source(CatalogSourceId.plex, _items(375))]);
    // At the top the visible range stays the same while its items change.
    state.controller.setSort(TvWatchlistSort.year);
    await tester.pump();
    await tester.pump();
    for (var round = 0; round < 3; round++) {
      for (final c in matcher.calls.where((c) => !c.completer.isCompleted).toList()) {
        c.completer.complete(_notFound);
      }
      await tester.pump();
    }
    final recent = matcher.calls.reversed.take(3).map((c) => c.item.title);
    final view = [for (final i in state.controller.view) i.title];
    for (final title in recent) {
      expect(view.indexOf(title), lessThan(60), reason: '$title is far from the visible rows');
    }
  });

  testWidgets('A30: reconnect prime keeps the list, focus and scroll; no reload while loading', (tester) async {
    final source = _Source(CatalogSourceId.plex, _items(60));
    final gate = source.gate = Completer<void>();
    final state = await pumpScreen(tester, [source]);
    state.primeRefresh();
    await tester.pump();
    expect(source.listFetches, 1, reason: 'cold start prime during the first load');
    gate.complete();
    source.gate = null;
    await tester.pumpAndSettle();
    for (var i = 0; i < 4; i++) {
      await key(tester, LogicalKeyboardKey.arrowDown);
    }
    final index = grid(tester).focusedIndex;
    final title = state.controller.view[index].title;
    final top = tester.getTopLeft(find.text(title)).dy;

    state.primeRefresh();
    expect(state.controller.phase, TvWatchlistPhase.ready);
    await tester.pumpAndSettle();
    expect(source.listFetches, 2, reason: 'silent re-read');
    expect(find.byType(TvPosterSkeleton), findsNothing);
    expect(grid(tester).focusedIndex, index);
    expect(focusLabel(), 'TV grid $index');
    expect(tester.getTopLeft(find.text(title)).dy, top);
  });

  testWidgets('a background re-read with new metadata updates the posters', (tester) async {
    final source = _Source(CatalogSourceId.plex, _items(3));
    final state = await pumpScreen(tester, [source]);
    await tester.pumpAndSettle();
    source.items = [
      CatalogItem(
        source: CatalogSourceId.plex,
        kind: MediaKind.movie,
        title: 'T0',
        year: 1999,
        ids: const CatalogItemIds(trakt: 0),
      ),
      ...source.items.skip(1),
    ];
    state.refresh();
    await tester.pumpAndSettle();
    final poster = tester.widgetList<TvPoster>(find.byType(TvPoster)).firstWhere((p) => p.item.title == 'T0');
    expect(poster.item.year, 1999);
  });

  testWidgets('A5: found with one copy opens its card; Back returns to the same poster', (tester) async {
    matcher.results['T3'] = _found('copy-3');
    await pumpScreen(tester, [_Source(CatalogSourceId.plex, _items(8))]);
    await tester.pump();
    tvOpenCopyForTesting = (context, copy) async {
      openedCopies.add(copy);
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const Text('S8')));
    };
    await key(tester, LogicalKeyboardKey.arrowRight);
    await key(tester, LogicalKeyboardKey.arrowRight);
    await key(tester, LogicalKeyboardKey.arrowRight);
    final title = grid(tester).focusedIndex;
    expect(tester.state<TvWatchlistScreenState>(find.byType(TvWatchlistScreen)).controller.view[title].title, 'T3');

    await key(tester, LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(openedCopies.single.id, 'copy-3');
    expect(find.text('S8'), findsOneWidget);

    Navigator.of(tester.element(find.text('S8'))).pop();
    await tester.pumpAndSettle();
    expect(grid(tester).focusedIndex, 3);
    expect(focusLabel(), 'TV grid 3');
  });

  testWidgets('A6: several copies open the copy menu, the choice opens its card', (tester) async {
    matcher.results['T0'] = libraryLookupResult(
      [testMediaItem(id: 'uhd', serverId: 'a'), testMediaItem(id: 'hd', serverId: 'a')],
      succeeded: {'a'},
    );
    await pumpScreen(tester, [_Source(CatalogSourceId.plex, _items(2))]);
    await tester.pump();
    tvOpenCopyForTesting = (context, copy) async => openedCopies.add(copy);

    await key(tester, LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Choose a copy'), findsOneWidget);
    await key(tester, LogicalKeyboardKey.arrowDown);
    await key(tester, LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(openedCopies.single.id, 'hd');
  });

  testWidgets('A7/A24: not found and unchecked open the catalog card', (tester) async {
    matcher.results['T1'] = libraryLookupResult(const [], succeeded: {'a'}, failed: {'b'});
    await pumpScreen(tester, [_Source(CatalogSourceId.plex, _items(2, source: CatalogSourceId.plex))]);
    await tester.pump();
    expect(badged(tester), isEmpty);
    expect(find.textContaining('error', findRichText: true), findsNothing);

    await key(tester, LogicalKeyboardKey.enter);
    await key(tester, LogicalKeyboardKey.arrowRight);
    await key(tester, LogicalKeyboardKey.enter);
    expect([for (final c in cards) c.item.title], ['T0', 'T1']);
    expect(cards.first.source.id, CatalogSourceId.plex);
  });

  testWidgets('A7: the real catalog card route opens for a not-found item', (tester) async {
    final state = await pumpScreen(tester, [_Source(CatalogSourceId.plex, _items(1))]);
    await tester.pump();
    // Use the default route rather than the injected hook.
    await tester.pumpWidget(const SizedBox.shrink());
    expect(state.mounted, isFalse);
    sources = _Sources([_Source(CatalogSourceId.plex, _items(1))]);
    await pumpTvWidget(
      tester,
      Scaffold(
        body: TvWatchlistScreen(
          onOpenSearch: () {},
          matcher: matcher,
          multiServer: servers,
          sourcesListenable: sources,
          readSources: () => sources.list,
          preferences: prefs,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();
    await key(tester, LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(TvCatalogItemScreen), findsOneWidget);
    expect(find.text('Not on server'), findsOneWidget);
  });

  for (final (name, focusIndex, expected) in [
    ('A8/A34: removal on the catalog card', 2, 'T3'),
    ('A27: removal of the last item focuses the previous', 4, 'T3'),
  ]) {
    testWidgets('$name drops the item at once and focuses its neighbour', (tester) async {
      final source = _Source(CatalogSourceId.plex, _items(5));
      final state = await pumpScreen(tester, [source]);
      await tester.pump();
      for (var i = 0; i < focusIndex; i++) {
        await key(tester, LogicalKeyboardKey.arrowRight);
      }
      final fetches = source.listFetches;
      await removeWhileCovered(tester);

      expect([for (final i in state.controller.view) i.title], isNot(contains('T$focusIndex')));
      expect(find.byType(TvPoster), findsNWidgets(4));
      expect(state.controller.view[grid(tester).focusedIndex].title, expected);
      expect(focusLabel(), 'TV grid ${grid(tester).focusedIndex}');
      expect(find.byType(TvPosterSkeleton), findsNothing);
      expect(source.listFetches, fetches);
    });
  }

  testWidgets('A27: removal far down keeps the scroll position', (tester) async {
    final source = _Source(CatalogSourceId.plex, _items(60));
    final state = await pumpScreen(tester, [source]);
    await tester.pump();
    for (var i = 0; i < 4; i++) {
      await key(tester, LogicalKeyboardKey.arrowDown);
    }
    final index = grid(tester).focusedIndex;
    final title = state.controller.view[index].title;
    final before = tester.getTopLeft(find.text(title)).dy;
    await removeWhileCovered(tester);

    final next = state.controller.view[grid(tester).focusedIndex].title;
    expect(grid(tester).focusedIndex, index);
    expect(tester.getTopLeft(find.text(next)).dy, before);
  });

  testWidgets('A28: returning without changes does not reload', (tester) async {
    final source = _Source(CatalogSourceId.plex, _items(4));
    await pumpScreen(tester, [source]);
    await tester.pump();
    await key(tester, LogicalKeyboardKey.arrowRight);
    final fetches = source.listFetches;
    await key(tester, LogicalKeyboardKey.enter);
    await tester.pump();
    expect(source.listFetches, fetches);
    expect(focusLabel(), 'TV grid 1');
  });

  testWidgets('A12: onTabShown rechecks old not-found results', (tester) async {
    final state = await pumpScreen(tester, [_Source(CatalogSourceId.plex, _items(2))]);
    await tester.pump();
    final before = matcher.calls.length;
    state.onTabHidden();
    state.onTabShown();
    await tester.pump();
    expect(matcher.calls.length, before, reason: 'fresh not-found results are reused');

    clock = clock.add(const Duration(minutes: 11));
    state.onTabHidden();
    state.onTabShown();
    await tester.pump();
    await tester.pump();
    expect(matcher.calls.length, before + 2);
  });

  testWidgets('A22: Play/Pause plays a found movie; nothing on other items', (tester) async {
    matcher.results['T0'] = _found('copy-0');
    await pumpScreen(tester, [_Source(CatalogSourceId.plex, _items(2))]);
    await tester.pump();

    await key(tester, LogicalKeyboardKey.mediaPlayPause);
    expect([for (final p in played) p.id], ['copy-0']);
    await key(tester, LogicalKeyboardKey.arrowRight);
    await key(tester, LogicalKeyboardKey.mediaPlayPause);
    expect(played, hasLength(1));
    expect(details, isEmpty);
  });

  testWidgets('A23: Play/Pause on a found show plays the next episode, else opens the show', (tester) async {
    final show = testMediaItem(id: 'show-1', kind: MediaKind.show, serverId: 'a');
    matcher.results['S'] = libraryLookupResult([show], succeeded: {'a'});
    await pumpScreen(tester, [
      _Source(CatalogSourceId.plex, [_item(0, kind: MediaKind.show, title: 'S')]),
    ]);
    await tester.pump();

    client = _Client(testMediaItem(id: 'ep-5', kind: MediaKind.episode));
    await key(tester, LogicalKeyboardKey.mediaPlayPause);
    await tester.pumpAndSettle();
    expect([for (final p in played) p.id], ['ep-5']);

    client = _Client(null);
    await key(tester, LogicalKeyboardKey.mediaPlayPause);
    await tester.pumpAndSettle();
    expect([for (final d in details) d.id], ['show-1']);
  });

  testWidgets('Play/Pause after the section is hidden does not start the player', (tester) async {
    matcher.results['T0'] = _found('copy-0');
    final state = await pumpScreen(tester, [_Source(CatalogSourceId.plex, _items(1))]);
    await tester.pump();
    state.onTabHidden();
    await key(tester, LogicalKeyboardKey.mediaPlayPause);
    expect(played, isEmpty);
  });

  testWidgets('A11/A32: a server coming online adds the badge; OK and Play/Pause work on partial found', (
    tester,
  ) async {
    servers.set(expected: ['a', 'b'], online: ['a']);
    matcher.results['T1'] = libraryLookupResult(const [], succeeded: {'a'}, unqueried: {'b'});
    matcher.results['T0'] = _found('copy-a', unqueried: {'b'});
    await pumpScreen(tester, [_Source(CatalogSourceId.plex, _items(2))]);
    await tester.pump();
    expect(badged(tester), ['T0']);

    tvOpenCopyForTesting = (context, copy) async => openedCopies.add(copy);
    await key(tester, LogicalKeyboardKey.enter);
    expect([for (final c in openedCopies) c.id], ['copy-a']);
    await key(tester, LogicalKeyboardKey.mediaPlayPause);
    expect([for (final p in played) p.id], ['copy-a']);

    matcher.results['T1'] = libraryLookupResult(
      [testMediaItem(id: 'copy-b', serverId: 'b')],
      succeeded: {'a', 'b'},
    );
    servers.set(expected: ['a', 'b'], online: ['a', 'b']);
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(badged(tester), containsAll(['T0', 'T1']));
  });

  testWidgets('focused found item carries the On server caption prefix', (tester) async {
    matcher.results['T0'] = _found('copy-0');
    await pumpScreen(tester, [_Source(CatalogSourceId.plex, _items(2))]);
    await tester.pump();
    final posters = tester.widgetList<TvPoster>(find.byType(TvPoster)).toList();
    expect(posters[0].caption, 'On server · 2000');
    expect(posters[1].caption, '2001');
  });
}
