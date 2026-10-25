import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/models/catalog/catalog_item.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_button.dart';
import 'package:plezy/plezytv/tv_ui/watchlist/tv_catalog_item_screen.dart';
import 'package:plezy/plezytv/tv_ui/watchlist/tv_watchlist_availability.dart';
import 'package:plezy/providers/multi_server_provider.dart';
import 'package:plezy/services/catalog/catalog_library_matcher.dart';
import 'package:plezy/services/catalog/catalog_source.dart';
import 'package:plezy/services/data_aggregation_service.dart';

import '../../../test_helpers/library_lookup.dart';
import '../../../test_helpers/media_items.dart';
import '../tv_theme_test_helper.dart';

class _Call {
  final CatalogItem item;
  final bool refresh;
  final Completer<LibraryLookupResult> completer = Completer();
  _Call(this.item, this.refresh);
}

class _FakeMatcher implements CatalogLibraryMatcher {
  final List<_Call> calls = [];

  @override
  Future<LibraryLookupResult> match(CatalogItem item, {bool refreshIncomplete = false}) {
    final call = _Call(item, refreshIncomplete);
    calls.add(call);
    return call.completer.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeServers extends ChangeNotifier implements MultiServerProvider {
  @override
  List<String> expectedServerIds = ['a', 'b'];
  @override
  List<String> onlineServerIds = ['a'];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSource implements CatalogSource {
  _FakeSource({this.membership = true, this.removeError, this.detail});

  /// The enriched form `fetchDetail` returns; the item itself when null.
  final CatalogItem? detail;

  /// Null models membership data that has not loaded yet.
  bool? membership;
  final Object? removeError;
  int removeCalls = 0;
  int addCalls = 0;

  @override
  CatalogSourceId get id => CatalogSourceId.trakt;

  @override
  Future<CatalogDetail> fetchDetail(CatalogItem item, {int castLimit = 20, int relatedLimit = 20}) async =>
      CatalogDetail(item: detail ?? item);

  @override
  bool? isOnWatchlist(MediaKind kind, CatalogItemIds ids) => membership;

  @override
  Future<void> removeFromWatchlist(MediaKind kind, CatalogItemIds ids) async {
    removeCalls++;
    final error = removeError;
    if (error != null) throw error;
  }

  @override
  Future<void> addToWatchlist(MediaKind kind, CatalogItemIds ids) async => addCalls++;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

CatalogItem _item({MediaKind kind = MediaKind.show, String? trailer}) => CatalogItem(
  source: CatalogSourceId.trakt,
  kind: kind,
  title: 'Some Show',
  year: 2020,
  overview: 'An overview.',
  trailerUrl: trailer,
  ids: const CatalogItemIds(trakt: 7),
);

final _notFound = libraryLookupResult(const [], succeeded: {'a', 'b'});
final _unchecked = libraryLookupResult(const [], succeeded: {'a'}, unqueried: {'b'});
LibraryLookupResult _found(List<MediaItem> copies) => libraryLookupResult(copies, succeeded: {'a', 'b'});

void main() {
  late _FakeMatcher matcher;
  late TvWatchlistAvailability availability;
  late List<CatalogItem> removed, restored;

  setUp(() {
    matcher = _FakeMatcher();
    availability = TvWatchlistAvailability(matcher, _FakeServers());
    removed = [];
    restored = [];
  });

  tearDown(() {
    availability.dispose();
    tvOpenCopyForTesting = null;
  });

  Future<void> pumpCard(WidgetTester tester, {required CatalogItem item, required _FakeSource source}) async {
    await pumpTvWidget(
      tester,
      TvCatalogItemScreen(
        args: TvCatalogItemArgs(
          item: item,
          source: source,
          availability: availability,
          onRemoved: removed.add,
          onRestored: restored.add,
        ),
      ),
    );
    await tester.pump();
  }

  TvButton button(WidgetTester tester, String key) => tester.widget<TvButton>(find.byKey(ValueKey(key)));
  bool focused(WidgetTester tester, String key) => button(tester, key).focusNode!.hasFocus;

  Future<void> answer(WidgetTester tester, LibraryLookupResult result) async {
    matcher.calls.last.completer.complete(result);
    await tester.pump();
    await tester.pump();
  }

  testWidgets('A7: not found shows a disabled Not on server and focuses Remove', (tester) async {
    await pumpCard(tester, item: _item(), source: _FakeSource());
    await answer(tester, _notFound);

    expect(button(tester, 'catalog-open').label, 'Not on server');
    expect(button(tester, 'catalog-open').disabled, isTrue);
    expect(focused(tester, 'catalog-watchlist'), isTrue);

    // The disabled Open is skipped by focus.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(focused(tester, 'catalog-watchlist'), isTrue);
  });

  testWidgets('A8: Remove reports removal and flips to Add', (tester) async {
    final item = _item();
    final source = _FakeSource();
    await pumpCard(tester, item: item, source: source);
    await answer(tester, _notFound);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(source.removeCalls, 1);
    expect(removed, [item]);
    expect(button(tester, 'catalog-watchlist').label, 'Add to Watchlist');

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(source.addCalls, 1);
    expect(restored, [item]);
    expect(button(tester, 'catalog-watchlist').label, 'Remove from Watchlist');
  });

  testWidgets('A34: Remove works before membership data has loaded', (tester) async {
    final item = _item();
    final source = _FakeSource(membership: null);
    await pumpCard(tester, item: item, source: source);
    await answer(tester, _notFound);

    expect(button(tester, 'catalog-watchlist').label, 'Remove from Watchlist');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(removed, [item]);
  });

  testWidgets('a failed removal shows the Plezy message and keeps the button', (tester) async {
    final source = _FakeSource(removeError: Exception('boom'));
    await pumpCard(tester, item: _item(), source: source);
    await answer(tester, _notFound);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump();

    expect(source.removeCalls, 1);
    expect(removed, isEmpty);
    expect(find.text('Couldn\'t update watchlist'), findsOneWidget);
    expect(button(tester, 'catalog-watchlist').label, 'Remove from Watchlist');
  });

  testWidgets('A9: a running check shows progress; the result does not move buttons or focus', (tester) async {
    await pumpCard(tester, item: _item(), source: _FakeSource());

    expect(find.byKey(const ValueKey('catalog-open-progress')), findsOneWidget);
    expect(button(tester, 'catalog-open').disabled, isTrue);
    expect(focused(tester, 'catalog-watchlist'), isTrue);
    final removeAt = tester.getTopLeft(find.byKey(const ValueKey('catalog-watchlist')));

    await answer(tester, _found([testMediaItem(id: 'c1', serverId: 'a')]));

    expect(find.byKey(const ValueKey('catalog-open-progress')), findsNothing);
    expect(button(tester, 'catalog-open').disabled, isFalse);
    expect(button(tester, 'catalog-open').label, 'Open');
    expect(focused(tester, 'catalog-watchlist'), isTrue);
    expect(tester.getTopLeft(find.byKey(const ValueKey('catalog-watchlist'))), removeAt);
  });

  testWidgets('R12: an older plain check does not end the enriched check in progress', (tester) async {
    final enriched = CatalogItem(
      source: CatalogSourceId.trakt,
      kind: MediaKind.show,
      title: 'Some Show',
      year: 2020,
      ids: const CatalogItemIds(trakt: 7, tmdb: 70),
    );
    await pumpCard(
      tester,
      item: _item(),
      source: _FakeSource(detail: enriched),
    );
    await tester.pump();
    expect(matcher.calls, hasLength(3), reason: 'plain check, then original + enriched forms');
    matcher.calls[0].completer.complete(_notFound);
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('catalog-open-progress')), findsOneWidget);
    expect(button(tester, 'catalog-open').label, isNot('Not on server'));

    matcher.calls[1].completer.complete(_notFound);
    matcher.calls[2].completer.complete(_found([testMediaItem(id: 'c1', serverId: 'a')]));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('catalog-open-progress')), findsNothing);
    expect(button(tester, 'catalog-open').label, 'Open');
  });

  testWidgets('reduced performance shows a static icon instead of a spinner', (tester) async {
    await pumpTvWidget(
      tester,
      TvCatalogItemScreen(
        args: TvCatalogItemArgs(
          item: _item(),
          source: _FakeSource(),
          availability: availability,
          onRemoved: removed.add,
          onRestored: restored.add,
        ),
      ),
      reduced: true,
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('catalog-open-progress')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await answer(tester, _notFound);
  });

  testWidgets('A10: unchecked is active; OK retries with refreshIncomplete and opens on a found copy', (tester) async {
    final opened = <MediaItem>[];
    tvOpenCopyForTesting = (_, copy) async => opened.add(copy);
    await pumpCard(tester, item: _item(), source: _FakeSource());
    await answer(tester, _unchecked);

    expect(button(tester, 'catalog-open').label, 'Couldn’t check');
    expect(button(tester, 'catalog-open').disabled, isFalse);
    // Focus stayed where it opened (Remove); the now-active Open is reachable.
    expect(focused(tester, 'catalog-watchlist'), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(focused(tester, 'catalog-open'), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(matcher.calls.last.refresh, isTrue);
    expect(find.byKey(const ValueKey('catalog-open-progress')), findsOneWidget);

    final copy = testMediaItem(id: 'c1', serverId: 'b');
    await answer(tester, _found([copy]));
    expect(button(tester, 'catalog-open').label, 'Open');
    expect(focused(tester, 'catalog-open'), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(opened, [copy]);
  });

  testWidgets('A6: two copies open a copy menu labelled like Plezy, then the chosen copy', (tester) async {
    final opened = <MediaItem>[];
    tvOpenCopyForTesting = (_, copy) async => opened.add(copy);
    final first = testMediaItem(id: 'c1', serverId: 'a', serverName: 'Home', libraryTitle: 'Movies');
    final second = testMediaItem(id: 'c2', serverId: 'b', serverName: 'Office', libraryTitle: 'Films');
    await pumpCard(
      tester,
      item: _item(kind: MediaKind.movie),
      source: _FakeSource(),
    );
    await answer(tester, _found([first, second]));

    // Initial focus went to Remove while checking; move to Open.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(focused(tester, 'catalog-open'), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.text('Movies'), findsOneWidget);
    expect(find.text('Films'), findsOneWidget);
    expect(find.text('Office'), findsOneWidget);
    expect(opened, isEmpty);

    Focus.of(tester.element(find.text('Films'))).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(opened, [second]);
  });

  testWidgets('Trailer is shown only when the item has a link', (tester) async {
    await pumpCard(tester, item: _item(), source: _FakeSource());
    expect(find.byKey(const ValueKey('catalog-trailer')), findsNothing);
    await answer(tester, _notFound);
  });

  testWidgets('Trailer button appears with a link', (tester) async {
    await pumpCard(
      tester,
      item: _item(trailer: 'https://example.com/t'),
      source: _FakeSource(),
    );
    expect(find.byKey(const ValueKey('catalog-trailer')), findsOneWidget);
    await answer(tester, _notFound);
  });
}
