import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/focus/key_event_utils.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/media/library_query.dart';
import 'package:plezy/media/media_hub.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/server_capabilities.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_button.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_cards.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_horizontal_row.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_rating_stars.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_ratings.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_skeletons.dart';
import 'package:plezy/plezytv/tv_ui/postplay/tv_postplay_controller.dart';
import 'package:plezy/plezytv/tv_ui/postplay/tv_postplay_logic.dart';
import 'package:plezy/plezytv/tv_ui/postplay/tv_postplay_screen.dart';
import 'package:plezy/plezytv/tv_ui/tv_ui.dart';
import 'package:plezy/utils/formatters.dart';
import 'package:plezy/utils/media_server_http_client.dart';

import '../show/fake_media_server_client.dart';
import '../tv_theme_test_helper.dart';

class PostPlayClient extends FakeShowClient {
  PostPlayClient({this.numeric = true});
  final bool numeric;
  final items = <String, MediaItem>{};
  final hubs = <String, List<MediaHub>>{};
  final rated = <double>[];
  final fetchedSeasons = <String>[];
  Completer<void>? gate;
  bool fail = false, failRate = false;

  @override
  ServerCapabilities get capabilities => numeric ? ServerCapabilities.plex : ServerCapabilities.jellyfin;

  Future<void> _wait() async {
    if (gate != null) await gate!.future;
    if (fail) throw StateError('offline');
  }

  @override
  Future<({MediaItem? item, MediaItem? onDeckEpisode})> fetchItemWithOnDeck(
    String id, {
    void Function(MediaItem)? onItemReady,
  }) async {
    await _wait();
    return (item: items[id], onDeckEpisode: null);
  }

  @override
  Future<List<MediaHub>> fetchRelatedHubs(String id, {int count = 10}) async {
    await _wait();
    return hubs[id] ?? [];
  }

  @override
  Future<LibraryPage<MediaItem>> fetchChildrenPage(
    String parentId, {
    int? start,
    int? size,
    AbortController? abort,
  }) async {
    fetchedSeasons.add(parentId);
    await _wait();
    final list = episodes[parentId] ?? [];
    return LibraryPage(items: list, totalCount: list.length);
  }

  @override
  Future<void> rate(MediaItem item, double rating) async {
    if (failRate) throw StateError('offline');
    rated.add(rating);
  }
}

MediaItem movie({String id = 'm', double? userRating, int? viewCount}) => MediaItem.plex(
  id: id,
  kind: MediaKind.movie,
  title: 'Movie $id',
  serverId: 'server',
  durationMs: 9960000,
  userRating: userRating,
  viewCount: viewCount,
);

MediaItem episode(int season, int index, {String show = 'show'}) => MediaItem.plex(
  id: 'e$season-$index',
  kind: MediaKind.episode,
  title: 'Episode $index',
  serverId: 'server',
  parentId: 's$season',
  parentIndex: season,
  index: index,
  grandparentId: show,
  grandparentTitle: 'The Show',
);

MediaItem showItem({double? userRating}) => MediaItem.plex(
  id: 'show',
  kind: MediaKind.show,
  title: 'The Show Loaded',
  serverId: 'server',
  userRating: userRating,
);

MediaHub hub(String id, List<MediaItem> items, {String? identifier}) =>
    MediaHub(id: id, title: id, type: 'movie', identifier: identifier, items: items);

class Harness {
  final launches = <(MediaItem, bool)>[];
  final details = <(MediaItem, bool)>[];
  late TvPostPlayController controller;
  bool disposed = false;
  void dispose() {
    if (disposed) return;
    disposed = true;
    controller.dispose();
  }
}

Future<Harness> pumpScreen(
  WidgetTester tester, {
  required PostPlayClient client,
  required MediaItem watched,
  MediaItem? next,
  Future<void>? playerRemoved,
  Duration autoSave = const Duration(milliseconds: 600),
}) async {
  final h = Harness();
  h.controller = TvPostPlayController(client: client, watched: watched, next: next, autoSaveDelay: autoSave);
  addTearDown(h.dispose);
  unawaited(h.controller.load());
  final args = TvPostPlayArgs(watched: watched, next: next, playerRemoved: playerRemoved ?? Future.value());
  await pumpTvWidget(
    tester,
    Builder(
      builder: (context) => Center(
        child: TextButton(
          key: const ValueKey('home'),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => TvPostPlayScreen(
                args: args,
                controller: h.controller,
                launchPlayer: (_, item, {required fromStart}) async => h.launches.add((item, fromStart)),
                openDetail: (_, item, {required replace}) async => h.details.add((item, replace)),
              ),
            ),
          ),
          child: const Text('home'),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey('home')));
  await tester.pumpAndSettle();
  return h;
}

bool focused(FocusNode? node) => node?.hasPrimaryFocus ?? false;
String? focusedLabel() {
  final ctx = FocusManager.instance.primaryFocus?.context;
  if (ctx == null) return null;
  if (ctx.findAncestorWidgetOfExactType<TvRatingStars>() != null) return 'stars';
  return ctx.findAncestorWidgetOfExactType<TvButton>()?.label;
}

Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pump();
}

void main() {
  group('logic', () {
    test('variant follows the input', () {
      expect(tvPostPlayVariant(episode(1, 1), episode(1, 2)), TvPostPlayVariant.episode);
      expect(tvPostPlayVariant(movie(), null), TvPostPlayVariant.movie);
      expect(tvPostPlayVariant(episode(1, 1), null), TvPostPlayVariant.showEnded);
    });

    test('similar hub prefers the similar identifier, else the first non-empty', () {
      final a = hub('a', [movie(id: '1')]);
      final s = hub('s', [movie(id: '2')], identifier: 'movie.similar');
      expect(tvPostPlaySimilarHub([hub('e', []), a, s]), same(s));
      expect(tvPostPlaySimilarHub([hub('e', []), a]), same(a));
      expect(tvPostPlaySimilarHub([hub('e', [])]), isNull);
    });
  });

  group('episode variant', () {
    testWidgets('shows watched/up next and the rest of next season; focus on Watch', (tester) async {
      final client = PostPlayClient()..episodes['s1'] = [for (var i = 1; i <= 6; i++) episode(1, i)];
      await pumpScreen(tester, client: client, watched: episode(1, 2), next: episode(1, 3));
      expect(find.text('YOU WATCHED S1 E2 · EPISODE 2'), findsOneWidget);
      expect(find.text('UP NEXT'), findsOneWidget);
      expect(find.text('S1 E3 · Episode 3'), findsOneWidget);
      expect(focusedLabel(), 'Watch S1 E3');
      final row = tester.widget<TvHorizontalRow>(find.byType(TvHorizontalRow));
      expect(row.title, 'Season 1');
      expect(row.counter, '3 more episodes');
      expect(row.itemCount, 3);
      expect(find.byType(TvRatingStars), findsNothing);
    });

    testWidgets('next is last of its season: no row', (tester) async {
      final client = PostPlayClient()..episodes['s1'] = [for (var i = 1; i <= 3; i++) episode(1, i)];
      await pumpScreen(tester, client: client, watched: episode(1, 2), next: episode(1, 3));
      expect(find.byType(TvHorizontalRow), findsNothing);
    });

    testWidgets('next from the following season: row from its season (A16)', (tester) async {
      final client = PostPlayClient()
        ..episodes['s1'] = [for (var i = 1; i <= 10; i++) episode(1, i)]
        ..episodes['s2'] = [for (var i = 1; i <= 4; i++) episode(2, i)];
      await pumpScreen(tester, client: client, watched: episode(1, 10), next: episode(2, 1));
      expect(client.fetchedSeasons, ['s2']);
      final row = tester.widget<TvHorizontalRow>(find.byType(TvHorizontalRow));
      expect(row.title, 'Season 2');
      expect(row.itemCount, 3);
    });

    testWidgets('Down, OK on a row episode launches it (A18); Play/Pause launches next (A13)', (tester) async {
      final client = PostPlayClient()..episodes['s1'] = [for (var i = 1; i <= 6; i++) episode(1, i)];
      final h = await pumpScreen(tester, client: client, watched: episode(1, 2), next: episode(1, 3));
      await press(tester, LogicalKeyboardKey.mediaPlayPause);
      await tester.pumpAndSettle();
      expect(h.launches.single.$1.id, 'e1-3');
      expect(h.launches.single.$2, isFalse);
      await press(tester, LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<TvEpisode>()?.item.id, 'e1-4');
      await press(tester, LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(h.launches.last.$1.id, 'e1-4');
    });

    testWidgets('Go to show opens the series in place of the screen', (tester) async {
      final client = PostPlayClient()..episodes['s1'] = [episode(1, 3)];
      final h = await pumpScreen(tester, client: client, watched: episode(1, 2), next: episode(1, 3));
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(focusedLabel(), 'Go to show');
      await press(tester, LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(h.details.single.$1.id, 'show');
      expect(h.details.single.$1.kind, MediaKind.show);
      expect(h.details.single.$2, isTrue);
    });
  });

  group('movie variant', () {
    testWidgets('watched mark only when the server marked it; similar row', (tester) async {
      final client = PostPlayClient()
        ..items['m'] = movie(viewCount: 1, userRating: 6)
        ..hubs['m'] = [
          hub('other', [movie(id: 'o')]),
          hub('sim', [movie(id: 's1'), movie(id: 's2')], identifier: 'movie.similar'),
        ];
      await pumpScreen(tester, client: client, watched: movie(userRating: 6));
      expect(find.byKey(const ValueKey('postplay-marked-watched')), findsOneWidget);
      expect(find.byKey(const ValueKey('postplay-watched-badge')), findsOneWidget);
      expect(find.text('Marked as watched · ${formatDurationTextual(9960000)}'), findsOneWidget);
      final row = tester.widget<TvHorizontalRow>(find.byType(TvHorizontalRow));
      expect(row.title, 'Similar');
      expect(row.itemCount, 2);
      expect(find.byType(TvRatings), findsOneWidget);
    });

    testWidgets('not marked and no hubs: no mark, no row', (tester) async {
      final client = PostPlayClient()..items['m'] = movie();
      await pumpScreen(tester, client: client, watched: movie());
      expect(find.byKey(const ValueKey('postplay-marked-watched')), findsNothing);
      expect(find.byKey(const ValueKey('postplay-watched-badge')), findsNothing);
      expect(find.byType(TvHorizontalRow), findsNothing);
    });

    testWidgets('OK on a similar poster opens its card over the screen', (tester) async {
      final client = PostPlayClient()
        ..items['m'] = movie(userRating: 6)
        ..hubs['m'] = [
          hub('sim', [movie(id: 's1')]),
        ];
      final h = await pumpScreen(tester, client: client, watched: movie(userRating: 6));
      await press(tester, LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<TvPoster>(), isNotNull);
      await press(tester, LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(h.details.single.$1.id, 's1');
      expect(h.details.single.$2, isFalse);
    });

    testWidgets('unrated: focus on stars (A3)', (tester) async {
      final client = PostPlayClient()..items['m'] = movie();
      await pumpScreen(tester, client: client, watched: movie());
      expect(focusedLabel(), 'stars');
    });

    testWidgets('rated: focus on Back to movie (A4) and it does not jump after load', (tester) async {
      final client = PostPlayClient()
        ..gate = Completer()
        ..items['m'] = movie();
      await pumpScreen(tester, client: client, watched: movie(userRating: 6));
      expect(focusedLabel(), 'Back to movie');
      client.gate!.complete();
      await tester.pumpAndSettle();
      expect(focusedLabel(), 'Back to movie');
    });

    testWidgets('no numeric rating: no block, focus on Back to movie (A7)', (tester) async {
      final client = PostPlayClient(numeric: false)..items['m'] = movie();
      await pumpScreen(tester, client: client, watched: movie());
      expect(find.byType(TvRatingStars), findsNothing);
      expect(find.text('Your rating'), findsNothing);
      expect(focusedLabel(), 'Back to movie');
    });

    testWidgets('Play/Pause does nothing (A37); Watch again restarts', (tester) async {
      final client = PostPlayClient()..items['m'] = movie(userRating: 4);
      final h = await pumpScreen(tester, client: client, watched: movie(userRating: 4));
      await press(tester, LogicalKeyboardKey.mediaPlayPause);
      await tester.pumpAndSettle();
      expect(h.launches, isEmpty);
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(focusedLabel(), 'Watch again');
      await press(tester, LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(h.launches.single.$1.id, 'm');
      expect(h.launches.single.$2, isTrue);
    });
  });

  group('rating', () {
    testWidgets('change saves after 600 ms (A3)', (tester) async {
      final client = PostPlayClient()..items['m'] = movie();
      await pumpScreen(tester, client: client, watched: movie());
      for (var i = 0; i < 3; i++) {
        await press(tester, LogicalKeyboardKey.arrowRight);
      }
      expect(tester.widget<TvRatingStars>(find.byType(TvRatingStars)).value, 3);
      await tester.pump(const Duration(milliseconds: 500));
      expect(client.rated, isEmpty);
      await tester.pump(const Duration(milliseconds: 150));
      expect(client.rated, [3.0]);
    });

    testWidgets('OK saves at once', (tester) async {
      final client = PostPlayClient()..items['m'] = movie();
      await pumpScreen(tester, client: client, watched: movie());
      await press(tester, LogicalKeyboardKey.arrowRight);
      await press(tester, LogicalKeyboardKey.enter);
      expect(client.rated, [1.0]);
      await tester.pump(const Duration(seconds: 1));
      expect(client.rated, [1.0]);
    });

    testWidgets('down to 0 clears the rating (A5)', (tester) async {
      final client = PostPlayClient()..items['m'] = movie(userRating: 2);
      await pumpScreen(tester, client: client, watched: movie(userRating: 2));
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(focusedLabel(), 'stars');
      await press(tester, LogicalKeyboardKey.arrowLeft);
      await press(tester, LogicalKeyboardKey.arrowLeft);
      await tester.pump(const Duration(milliseconds: 700));
      expect(client.rated, [-1.0]);
    });

    testWidgets('failed save: Plezy message, value stays (A6)', (tester) async {
      final client = PostPlayClient()
        ..items['m'] = movie()
        ..failRate = true;
      await pumpScreen(tester, client: client, watched: movie());
      await press(tester, LogicalKeyboardKey.arrowRight);
      await press(tester, LogicalKeyboardKey.enter);
      await tester.pump();
      expect(find.text(t.errors.failedToRate), findsOneWidget);
      expect(tester.widget<TvRatingStars>(find.byType(TvRatingStars)).value, 1);
    });

    testWidgets('leaving with an unsaved value saves it (A40)', (tester) async {
      final client = PostPlayClient()..items['m'] = movie();
      final h = await pumpScreen(tester, client: client, watched: movie());
      await press(tester, LogicalKeyboardKey.arrowRight);
      await press(tester, LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(TvPostPlayScreen), findsNothing);
      h.dispose();
      await tester.pump();
      expect(client.rated, [2.0]);
    });
  });

  group('series ended', () {
    testWidgets('movie-like layout with series data; focus on stars when unrated (A19, A38)', (tester) async {
      final client = PostPlayClient()
        ..items['show'] = showItem()
        ..hubs['show'] = [
          hub('sim', [showItem()]),
        ];
      final h = await pumpScreen(tester, client: client, watched: episode(3, 8));
      expect(tester.widget<Text>(find.byKey(const ValueKey('postplay-title'))).data, 'The Show Loaded');
      expect(find.text('Go to show'), findsOneWidget);
      expect(find.text('Back to movie'), findsNothing);
      expect(find.text('Watch again'), findsNothing);
      expect(find.byType(TvRatingStars), findsOneWidget);
      expect(focusedLabel(), 'stars');
      expect(tester.widget<TvHorizontalRow>(find.byType(TvHorizontalRow)).title, 'Similar');
      await press(tester, LogicalKeyboardKey.arrowRight);
      await press(tester, LogicalKeyboardKey.enter);
      expect(client.rated, [1.0]);
      expect(h.launches, isEmpty);
    });

    testWidgets('rated series: focus on Go to show; Play/Pause does nothing', (tester) async {
      final client = PostPlayClient()..items['show'] = showItem(userRating: 8);
      final h = await pumpScreen(tester, client: client, watched: episode(3, 8));
      expect(focusedLabel(), 'Go to show');
      await press(tester, LogicalKeyboardKey.mediaPlayPause);
      await tester.pumpAndSettle();
      expect(h.launches, isEmpty);
    });
  });

  group('waiting for the player to be removed (A14, A34)', () {
    testWidgets('actions wait, then run once', (tester) async {
      final removed = Completer<void>();
      final client = PostPlayClient()..items['m'] = movie(userRating: 4);
      final h = await pumpScreen(tester, client: client, watched: movie(userRating: 4), playerRemoved: removed.future);
      await press(tester, LogicalKeyboardKey.enter); // Back to movie
      await press(tester, LogicalKeyboardKey.arrowRight);
      await press(tester, LogicalKeyboardKey.enter); // Watch again
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(h.details, isEmpty);
      expect(h.launches, isEmpty);
      expect(find.byType(TvPostPlayScreen), findsOneWidget);
      removed.complete();
      await tester.pumpAndSettle();
      expect(h.details.length, 1);
      expect(h.launches, isEmpty);
      expect(find.byType(TvPostPlayScreen), findsOneWidget);
    });

    testWidgets('Back waits too, then pops', (tester) async {
      final removed = Completer<void>();
      final client = PostPlayClient()..items['m'] = movie(userRating: 4);
      await pumpScreen(tester, client: client, watched: movie(userRating: 4), playerRemoved: removed.future);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(TvPostPlayScreen), findsOneWidget);
      removed.complete();
      await tester.pumpAndSettle();
      expect(find.byType(TvPostPlayScreen), findsNothing);
    });

    testWidgets('an error completion counts as removed', (tester) async {
      final removed = Completer<void>();
      final client = PostPlayClient()..episodes['s1'] = [episode(1, 3), episode(1, 4)];
      final h = await pumpScreen(
        tester,
        client: client,
        watched: episode(1, 2),
        next: episode(1, 3),
        playerRemoved: removed.future,
      );
      await press(tester, LogicalKeyboardKey.enter);
      expect(h.launches, isEmpty);
      removed.completeError(StateError('exit failed'));
      await tester.pumpAndSettle();
      expect(h.launches.single.$1.id, 'e1-3');
    });
  });

  testWidgets('system pop left over from the opening press does not close the screen (A33)', (tester) async {
    final client = PostPlayClient()..items['m'] = movie(userRating: 4);
    await pumpScreen(tester, client: client, watched: movie(userRating: 4));
    BackKeyCoordinator.markHandled();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(TvPostPlayScreen), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(TvPostPlayScreen), findsNothing);
  });

  group('loading', () {
    testWidgets('skeletons while loading, buttons usable (A29)', (tester) async {
      final client = PostPlayClient()
        ..gate = Completer()
        ..episodes['s1'] = [episode(1, 3), episode(1, 4)];
      final h = await pumpScreen(tester, client: client, watched: episode(1, 2), next: episode(1, 3));
      expect(find.byType(TvRowSkeleton), findsOneWidget);
      await press(tester, LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(h.launches.single.$1.id, 'e1-3');
      client.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(TvRowSkeleton), findsNothing);
      expect(find.byType(TvHorizontalRow), findsOneWidget);
    });

    testWidgets('load failure hides rows and ratings; buttons work (A30)', (tester) async {
      final client = PostPlayClient()..fail = true;
      final h = await pumpScreen(tester, client: client, watched: movie(userRating: 4));
      expect(find.text('Movie m'), findsOneWidget);
      expect(find.byType(TvHorizontalRow), findsNothing);
      expect(find.byType(TvRowSkeleton), findsNothing);
      expect(find.byType(TvRatings), findsNothing);
      expect(find.byType(TvRatingStars), findsNothing);
      expect(focusedLabel(), 'Back to movie');
      await press(tester, LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(h.details.single.$1.id, 'm');
    });
  });

  test('postPlayRoute is an opaque page route', () {
    final route = TvUi.postPlayRoute(TvPostPlayArgs(watched: movie(), playerRemoved: Future.value()));
    expect(route.opaque, isTrue);
  });
}
