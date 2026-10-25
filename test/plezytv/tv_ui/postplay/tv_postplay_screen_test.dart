import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/focus/input_mode_tracker.dart';
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
import 'package:plezy/plezytv/tv_ui/tv_tokens.dart';
import 'package:plezy/plezytv/tv_ui/tv_ui.dart';
import 'package:plezy/providers/multi_server_provider.dart';
import 'package:plezy/utils/formatters.dart';
import 'package:plezy/utils/media_server_http_client.dart';
import 'package:provider/provider.dart';

import '../movie/tv_movie_screen_test.dart' show Servers;
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

  /// Holds `fetchRelatedHubs` only.
  Completer<void>? hubsGate;

  /// Holds `rate` until completed.
  Completer<void>? rateGate;
  int rateCalls = 0;
  bool fail = false, failRate = false, failHubs = false;

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
    if (hubsGate != null) await hubsGate!.future;
    if (failHubs) throw StateError('hubs failed');
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
    rateCalls++;
    if (rateGate != null) await rateGate!.future;
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

/// One `navigateToVideoPlayer` call from the screen.
class Launch {
  Launch(this.item, {required this.replace, required this.resolve, this.position});
  final MediaItem item;
  final bool replace, resolve;
  final Duration? position;

  /// "Watch again": from the start, past Plezy's resume resolution.
  bool get fromStart => position == Duration.zero && !resolve;
}

/// Records card routes the screen pushed (`false`) or swapped in (`true`).
class _CardObserver extends NavigatorObserver {
  _CardObserver(this.details);
  final List<(MediaItem, bool)> details;

  void _record(Route<dynamic>? route, {required bool replaced}) {
    final item = route?.settings.arguments;
    if (route?.settings.name == 'card' && item is MediaItem) details.add((item, replaced));
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _record(route, replaced: false);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) => _record(newRoute, replaced: true);
}

/// Stand-in for `TvUi.showDetailRoute`: a card route carrying its item.
PageRoute<dynamic> cardRoute(MediaItem metadata, {List<String?>? seasons, String? initialSeasonId}) {
  seasons?.add(initialSeasonId);
  return MaterialPageRoute<void>(
    settings: RouteSettings(name: 'card', arguments: metadata),
    builder: (_) => Scaffold(body: Text('card ${metadata.id}')),
  );
}

class Harness {
  final launches = <Launch>[];
  final details = <(MediaItem, bool)>[];

  /// `initialSeasonId` of every card route asked for.
  final seasons = <String?>[];
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
    navigatorObservers: [_CardObserver(h.details)],
    Builder(
      builder: (context) => Center(
        child: TextButton(
          key: const ValueKey('home'),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => TvPostPlayScreen(
                args: args,
                controller: h.controller,
                launchPlayer:
                    (
                      _, {
                      required metadata,
                      required usePushReplacement,
                      required resolveWatchState,
                      initialPosition,
                    }) async => h.launches.add(
                      Launch(
                        metadata,
                        replace: usePushReplacement,
                        resolve: resolveWatchState,
                        position: initialPosition,
                      ),
                    ),
                detailRoute: ({required metadata, initialSeasonId}) =>
                    cardRoute(metadata, seasons: h.seasons, initialSeasonId: initialSeasonId),
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
      final play = h.launches.single;
      expect(play.item.id, 'e1-3');
      expect(
        (play.replace, play.resolve, play.position),
        (true, true, null),
        reason: 'in place of the screen, resumed',
      );
      await press(tester, LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<TvEpisode>()?.item.id, 'e1-4');
      await press(tester, LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(h.launches.last.item.id, 'e1-4');
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
      expect(h.seasons, ['s1'], reason: "on the watched episode's season");
      expect(find.byType(TvPostPlayScreen), findsNothing);
      expect(find.text('card show'), findsOneWidget);
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
      expect(h.seasons, [null]);
      expect(find.byType(TvPostPlayScreen, skipOffstage: false), findsOneWidget, reason: 'stays under the card');
    });

    testWidgets('unrated: focus on stars (A3); Down and Up always land on a button', (tester) async {
      final client = PostPlayClient()
        ..items['m'] = movie()
        ..hubs['m'] = [
          hub('sim', [movie(id: 's1')]),
        ];
      await pumpScreen(tester, client: client, watched: movie());
      expect(focusedLabel(), 'stars');
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedLabel(), 'Back to movie', reason: 'the buttons were never focused before');
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(focusedLabel(), 'Watch again');
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(focusedLabel(), 'stars');
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedLabel(), 'Watch again', reason: 'the button last focused');
      await press(tester, LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<TvPoster>(), isNotNull);
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(focusedLabel(), 'Watch again');
    });

    testWidgets('failed related hubs: ratings and stars stay, only Similar is empty', (tester) async {
      final client = PostPlayClient()
        ..items['m'] = movie().copyWith(rating: 8.1)
        ..failHubs = true;
      await pumpScreen(tester, client: client, watched: movie());
      expect(find.byType(TvRatingStars), findsOneWidget);
      expect(find.byType(TvRatings), findsOneWidget);
      expect(focusedLabel(), 'stars');
      expect(find.byType(TvHorizontalRow), findsNothing);
      expect(find.byType(TvRowSkeleton), findsNothing);
    });

    testWidgets('ratings do not wait for the rows; their placeholder is one line', (tester) async {
      final client = PostPlayClient()
        ..gate = Completer()
        ..hubsGate = Completer()
        ..items['m'] = movie().copyWith(rating: 8.1)
        ..hubs['m'] = [
          hub('sim', [movie(id: 's1')]),
        ];
      await pumpScreen(tester, client: client, watched: movie());
      final placeholder = find.byKey(const ValueKey('postplay-ratings-skeleton'));
      expect(placeholder, findsOneWidget);
      expect(tester.getSize(placeholder).height, lessThanOrEqualTo(TvTokens.type.body.lineHeight.toDouble()));
      final starsTop = tester.getTopLeft(find.byType(TvRatingStars)).dy;
      client.gate!.complete();
      await tester.pumpAndSettle();
      expect(placeholder, findsNothing);
      expect(find.byType(TvRatings), findsOneWidget);
      expect(find.byKey(const ValueKey('postplay-row-skeleton')), findsOneWidget, reason: 'hubs still loading');
      expect(
        (tester.getTopLeft(find.byType(TvRatingStars)).dy - starsTop).abs(),
        lessThanOrEqualTo(TvTokens.type.body.lineHeight.toDouble()),
        reason: 'the focused stars barely move when the ratings arrive',
      );
      client.hubsGate!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(TvHorizontalRow), findsOneWidget);
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
      final play = h.launches.single;
      expect(play.item.id, 'm');
      expect(play.fromStart, isTrue);
      expect(play.replace, isTrue);
    });
  });

  group('rating', () {
    testWidgets('change saves 600 ms after the last change (A3)', (tester) async {
      final client = PostPlayClient()..items['m'] = movie();
      await pumpScreen(tester, client: client, watched: movie());
      for (var i = 0; i < 3; i++) {
        if (i > 0) await tester.pump(const Duration(milliseconds: 400));
        await press(tester, LogicalKeyboardKey.arrowRight);
      }
      expect(tester.widget<TvRatingStars>(find.byType(TvRatingStars)).value, 3);
      expect(client.rated, isEmpty, reason: '800 ms after the first change, 0 after the last');
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

    testWidgets('Back with an unsaved value: saved before the screen closes (A40, R10)', (tester) async {
      final client = PostPlayClient()
        ..items['m'] = movie()
        ..rateGate = Completer();
      await pumpScreen(tester, client: client, watched: movie());
      await press(tester, LogicalKeyboardKey.arrowRight);
      await press(tester, LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(client.rateCalls, 1);
      expect(find.byType(TvPostPlayScreen), findsOneWidget, reason: 'the card below would reread the old rating');
      client.rateGate!.complete();
      await tester.pumpAndSettle();
      expect(client.rated, [2.0]);
      expect(find.byType(TvPostPlayScreen), findsNothing);
    });

    testWidgets('an autosave in flight is awaited before the card opens; no second save', (tester) async {
      final client = PostPlayClient()
        ..items['m'] = movie()
        ..rateGate = Completer();
      final h = await pumpScreen(tester, client: client, watched: movie());
      await press(tester, LogicalKeyboardKey.arrowRight);
      await tester.pump(const Duration(milliseconds: 700));
      expect(client.rateCalls, 1, reason: 'autosave sent');
      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.enter); // Back to movie
      await tester.pumpAndSettle();
      expect(h.details, isEmpty);
      client.rateGate!.complete();
      await tester.pumpAndSettle();
      expect(h.details.single.$1.id, 'm');
      expect(client.rated, [1.0]);
      expect(client.rateCalls, 1);
    });

    testWidgets('Back with an unsaved value the server refuses: the screen closes, no message (R6)', (tester) async {
      final client = PostPlayClient()
        ..items['m'] = movie()
        ..failRate = true;
      await pumpScreen(tester, client: client, watched: movie());
      await press(tester, LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      for (var i = 0; i < 5; i++) {
        await tester.pump();
        expect(find.text(t.errors.failedToRate), findsNothing);
      }
      await tester.pumpAndSettle();
      expect(client.rateCalls, 1);
      expect(find.byType(TvPostPlayScreen), findsNothing);
      expect(find.text(t.errors.failedToRate), findsNothing);
    });

    testWidgets('an autosave failing while the user leaves shows no message; retried silently (R6)', (tester) async {
      final client = PostPlayClient()
        ..items['m'] = movie()
        ..failRate = true
        ..rateGate = Completer();
      final h = await pumpScreen(tester, client: client, watched: movie());
      await press(tester, LogicalKeyboardKey.arrowRight);
      await tester.pump(const Duration(milliseconds: 700));
      expect(client.rateCalls, 1, reason: 'autosave sent, reports its errors');
      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.enter); // Back to movie
      await tester.pump();
      client.rateGate!.complete();
      for (var i = 0; i < 5; i++) {
        await tester.pump();
        expect(find.text(t.errors.failedToRate), findsNothing);
      }
      await tester.pumpAndSettle();
      expect(client.rateCalls, 2, reason: 'the failed value is sent once more on leaving');
      expect(h.details.single.$1.id, 'm');
      expect(find.text('card m'), findsOneWidget);
      expect(find.text(t.errors.failedToRate), findsNothing);
    });

    testWidgets('screen-owned controller: client from the provider; plain Back saves (A40)', (tester) async {
      final client = PostPlayClient()..items['m'] = movie();
      final servers = Servers(client);
      addTearDown(servers.dispose);
      await pumpTvWidget(tester, const SizedBox.shrink());
      await tester.pumpWidget(
        InputModeTracker(
          child: ChangeNotifierProvider<MultiServerProvider>.value(
            value: servers,
            child: MaterialApp(
              home: Builder(
                builder: (context) => TextButton(
                  child: const Text('home'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => TvPostPlayScreen(
                        args: TvPostPlayArgs(watched: movie(), playerRemoved: Future.value()),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('home'));
      await tester.pumpAndSettle();
      expect(focusedLabel(), 'stars', reason: 'loaded through the provider client');
      await press(tester, LogicalKeyboardKey.arrowRight);
      await press(tester, LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(TvPostPlayScreen), findsNothing);
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

    testWidgets('loading: focus on Go to show, then once to the stars when the series is unrated (A38)', (
      tester,
    ) async {
      final client = PostPlayClient()
        ..gate = Completer()
        ..items['show'] = showItem();
      final h = await pumpScreen(tester, client: client, watched: episode(3, 8));
      expect(focusedLabel(), 'Go to show');
      expect(find.byType(TvRatingStars), findsNothing);
      client.gate!.complete();
      await tester.pumpAndSettle();
      expect(focusedLabel(), 'stars');
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedLabel(), 'Go to show');
      h.controller.notifyListeners();
      await tester.pumpAndSettle();
      expect(focusedLabel(), 'Go to show', reason: 'moves only once');
    });

    for (final key in [LogicalKeyboardKey.arrowDown, LogicalKeyboardKey.arrowUp, LogicalKeyboardKey.enter]) {
      testWidgets('a key (${key.keyLabel}) pressed before the series loads keeps the focus put (A38)', (tester) async {
        final client = PostPlayClient()
          ..gate = Completer()
          ..items['show'] = showItem();
        // OK on "Go to show" waits for the old player, so the screen stays.
        await pumpScreen(tester, client: client, watched: episode(3, 8), playerRemoved: Completer<void>().future);
        await press(tester, key);
        expect(focusedLabel(), 'Go to show');
        client.gate!.complete();
        await tester.pumpAndSettle();
        expect(find.byType(TvRatingStars), findsOneWidget);
        expect(focusedLabel(), 'Go to show');
      });
    }

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
    testWidgets('actions wait for the removal, then each runs at most once', (tester) async {
      final removed = Completer<void>();
      final client = PostPlayClient()..items['m'] = movie(userRating: 4);
      final h = await pumpScreen(tester, client: client, watched: movie(userRating: 4), playerRemoved: removed.future);
      await press(tester, LogicalKeyboardKey.enter); // Back to movie
      await press(tester, LogicalKeyboardKey.enter); // again
      await press(tester, LogicalKeyboardKey.arrowRight);
      await press(tester, LogicalKeyboardKey.enter); // Watch again
      await tester.pumpAndSettle();
      expect(h.details, isEmpty);
      expect(h.launches, isEmpty);
      expect(find.byType(TvPostPlayScreen), findsOneWidget);
      removed.complete();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      // Which press wins is not specified; never a card and a launch both.
      expect(h.details.length + h.launches.length, 1, reason: 'exactly one action once the player is gone');
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
      expect(h.launches.single.item.id, 'e1-3');
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
      expect(h.launches.single.item.id, 'e1-3');
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

  testWidgets('nothing below is painted while it appears and the player is removed under it (R2, A1, A9)', (
    tester,
  ) async {
    await pumpTvWidget(tester, const Text('home'));
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    final player = MaterialPageRoute<void>(
      builder: (_) => const ColoredBox(color: Colors.black, child: Text('player')),
    );
    unawaited(nav.push(player));
    await tester.pumpAndSettle();
    // Plezy's exit may finish within a frame (case b): the player goes at once.
    unawaited(nav.push(TvUi.postPlayRoute(TvPostPlayArgs(watched: movie(), playerRemoved: Future.value()))));
    await tester.pump();
    nav.removeRoute(player);
    for (var frame = 0; frame < 30; frame++) {
      expect(find.text('home'), findsNothing, reason: 'frame $frame');
      expect(find.text('player'), findsNothing, reason: 'frame $frame');
      expect(find.byType(TvPostPlayScreen), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 16));
    }
  });
}
