import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/media/ids.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_hub.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_part.dart';
import 'package:plezy/media/media_role.dart';
import 'package:plezy/media/media_stream.dart';
import 'package:plezy/media/media_version.dart';
import 'package:plezy/media/media_version_preference.dart';
import 'package:plezy/models/catalog/catalog_item.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_button.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_chip.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_horizontal_row.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_ratings.dart';
import 'package:plezy/plezytv/tv_ui/movie/tv_movie_controller.dart';
import 'package:plezy/plezytv/tv_ui/movie/tv_movie_screen.dart';
import 'package:plezy/plezytv/tv_ui/tv_focusable.dart';
import 'package:plezy/plezytv/tv_ui/tv_strings.dart';
import 'package:plezy/services/watch_actions.dart';
import 'package:plezy/utils/deletion_notifier.dart';
import 'package:plezy/utils/formatters.dart';
import 'package:plezy/utils/media_quality_labels.dart';
import 'package:plezy/utils/platform_detector.dart';
import 'package:plezy/widgets/media_context_menu.dart';
import '../show/fake_media_server_client.dart';
import '../show/tv_show_actions_test.dart' show Source;
import '../tv_theme_test_helper.dart';

MediaItem movieItem({String id = 'm', int? viewCount, int? offset, String? edition}) =>
    (edition == null
            ? MediaItem(
                id: id,
                backend: MediaBackend.jellyfin,
                kind: MediaKind.movie,
                title: 'Movie $id',
                serverId: 'server',
                durationMs: 9960000,
              )
            : MediaItem.plex(
                id: id,
                kind: MediaKind.movie,
                title: 'Movie $id',
                editionTitle: edition,
                serverId: 'server',
                durationMs: 9960000,
              ))
        .copyWith(viewCount: viewCount, viewOffsetMs: offset);

const _v1080 = MediaVersion(id: 'a', videoResolution: '1080', videoCodec: 'h264');
final _v2160 = MediaVersion(
  id: 'b',
  videoResolution: '2160',
  videoCodec: 'hevc',
  parts: [
    MediaPart(
      id: 'p',
      sizeBytes: 3 * 1024 * 1024 * 1024,
      streams: const [
        MediaStream(id: 'v', kind: MediaStreamKind.video),
        MediaStream(id: 'a1', kind: MediaStreamKind.audio, language: 'Russian'),
        MediaStream(id: 'a2', kind: MediaStreamKind.audio, language: 'English'),
      ],
    ),
  ],
);

FakeShowClient fixture({MediaItem? movie}) => FakeShowClient()..show = movie ?? movieItem();

class Mounted {
  Mounted(this.controller, this.client);
  final TvMovieController controller;
  final FakeShowClient client;
  final played = <int?>[];
  var versionPlays = 0;
  final marked = <bool>[];
}

Future<Mounted> mount(
  WidgetTester tester,
  FakeShowClient client, {
  MediaVersionPreference? preference,
  bool reduced = false,
  bool online = true,
  bool hideSpoilers = false,
  Future<void> Function()? onPlay,
}) async {
  final c = TvMovieController(
    client: client,
    metadata: client.show,
    versionPreference: (_) async => preference,
    watchEvents: const Stream.empty(),
  );
  addTearDown(c.dispose);
  final m = Mounted(c, client);
  await pumpTvWidget(
    tester,
    reduced: reduced,
    TvMovieScreen(
      metadata: client.show,
      controller: c,
      hideSpoilers: hideSpoilers,
      serverOnline: (_) => online,
      play: (_, movie, start) async {
        m.played.add(start);
        await onPlay?.call();
      },
      playVersion: (_, _) async => m.versionPlays++,
      markWatched: (movie, watched) async {
        m.marked.add(watched);
        client.show = client.show.withWatchedFlag(watched).copyWith(viewOffsetMs: 0);
        return WatchMarkOutcome.marked;
      },
    ),
  );
  await tester.pumpAndSettle();
  return m;
}

TvButton primary(WidgetTester tester) => tester.widget<TvButton>(find.byType(TvButton).first);
Iterable<TvIconButton> iconButtons(WidgetTester tester) => tester.widgetList<TvIconButton>(find.byType(TvIconButton));
bool hasIcon(WidgetTester tester, IconData icon) => iconButtons(tester).any((b) => b.icon == icon);
IconData? focusedIcon() =>
    FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<TvIconButton>()?.icon;

void main() {
  testWidgets('A1/A4 opens with focus on Watch; watched movie shows Rewatch from start', (tester) async {
    final m = await mount(tester, fixture());
    expect(primary(tester).label, 'Watch');
    expect(primary(tester).focusNode!.hasFocus, true);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(m.played, [null]);
  });

  testWidgets('A4 watched movie without progress shows Rewatch', (tester) async {
    final m = await mount(tester, fixture(movie: movieItem(viewCount: 1)));
    expect(primary(tester).label, 'Rewatch');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(m.played, [0]);
  });

  testWidgets('A3 progress shows Continue with time left and resumes from the offset', (tester) async {
    final m = await mount(tester, fixture(movie: movieItem(offset: 9960000 - 4800000)));
    expect(primary(tester).label, 'Continue · ${formatDurationTextual(4800000)} left');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(m.played, [9960000 - 4800000]);
  });

  testWidgets('A13 return from player refreshes primary button and watched state', (tester) async {
    late Mounted m;
    m = await mount(
      tester,
      fixture(movie: movieItem(offset: 600000)),
      onPlay: () async => m.client.show = m.client.show.withWatchedFlag(true).copyWith(viewOffsetMs: 0),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(primary(tester).label, 'Rewatch');
    expect(hasIcon(tester, Icons.remove_done), true);
  });

  testWidgets('A11 missing director, genres, ratings, edition and summary leave no parts', (tester) async {
    await mount(tester, fixture());
    for (final key in ['movie-genres', 'movie-edition', 'movie-summary', 'movie-chips', 'movie-tech-info']) {
      expect(find.byKey(ValueKey(key)), findsNothing, reason: key);
    }
    expect(find.byType(TvRatings), findsNothing);
    expect(find.text('Movie m'), findsOneWidget);
  });

  testWidgets('R2 header shows edition, meta, genres, director, ratings and summary', (tester) async {
    final movie = movieItem(edition: 'Part Two').copyWith(
      year: 2024,
      contentRating: 'ru/12+',
      genres: ['Drama', 'Action'],
      directors: ['Denis'],
      rating: 8.5,
      summary: 'Story',
    );
    await mount(tester, fixture(movie: movie));
    expect(find.text('PART TWO'), findsOneWidget);
    expect(find.text('2024 · ${formatDurationTextual(9960000)} · 12+'), findsOneWidget);
    expect(find.widgetWithText(TvChip, 'Drama'), findsOneWidget);
    expect(find.text('Director: Denis'), findsOneWidget);
    expect(find.byType(TvRatings), findsOneWidget);
    expect(find.text('Story'), findsOneWidget);
  });

  testWidgets('A19 spoiler rule follows Plezy shouldHideSpoiler (movies stay visible)', (tester) async {
    await mount(tester, fixture(movie: movieItem().copyWith(summary: 'Plot')), hideSpoilers: true);
    expect(find.text('Plot'), findsOneWidget);
  });

  testWidgets('A15/A12 chips and tech info describe the remembered second version', (tester) async {
    final movie = movieItem().copyWith(studio: 'Legendary', mediaVersions: [_v1080, _v2160]);
    await mount(
      tester,
      fixture(movie: movie),
      preference: const MediaVersionPreference(versionId: 'b', index: 1),
    );
    final chips = tester.widgetList<TvChip>(find.byType(TvChip)).map((c) => c.label).toList();
    expect(chips, buildMediaQualityLabels(movie, versionIndex: 1));
    expect(chips, isNot(buildMediaQualityLabels(movie)));
    expect(find.text('Legendary'), findsOneWidget);
    expect(find.text('Russian, English'), findsOneWidget);
    expect(find.textContaining('HEVC'), findsOneWidget);
    expect(find.text(TvStrings.subtitles), findsNothing);
  });

  testWidgets('A5 version segment only with several versions on an online server; selecting plays', (tester) async {
    final movie = movieItem().copyWith(mediaVersions: [_v1080, _v2160]);
    final m = await mount(tester, fixture(movie: movie));
    final segment = iconButtons(tester).firstWhere((b) => b.icon == Icons.video_library);
    segment.onSelect!();
    await tester.pumpAndSettle();
    expect(m.versionPlays, 1);
  });

  testWidgets('A5 no version segment for one version or an offline server', (tester) async {
    await mount(tester, fixture(movie: movieItem().copyWith(mediaVersions: [_v1080])));
    expect(hasIcon(tester, Icons.video_library), false);
    await mount(tester, fixture(movie: movieItem().copyWith(mediaVersions: [_v1080, _v2160])), online: false);
    expect(hasIcon(tester, Icons.video_library), false);
  });

  testWidgets('R4 trailer only when found; watchlist inactive while loading', (tester) async {
    final client = fixture();
    final m = await mount(tester, client);
    expect(hasIcon(tester, Icons.theaters), false);
    expect(hasIcon(tester, Icons.bookmark_add), false);
    final source = Source();
    addTearDown(source.watchlistChanges.dispose);
    client.extras = [
      client.show.copyWith(id: 'trailer', kind: MediaKind.clip, raw: {'ExtraType': 'Trailer'}),
    ];
    m.controller
      ..watchlistCandidates = [(source: source, ids: const CatalogItemIds(imdb: 'tt1'))]
      ..watchlistLoading = true;
    await m.controller.refresh();
    await tester.pumpAndSettle();
    expect(hasIcon(tester, Icons.theaters), true);
    expect(iconButtons(tester).firstWhere((b) => b.icon == Icons.bookmark_add).disabled, true);
    m.controller.watchlistLoading = false;
    await m.controller.refresh();
    await tester.pumpAndSettle();
    final list = iconButtons(tester).firstWhere((b) => b.icon == Icons.bookmark_add);
    expect(list.disabled, false);
    list.onSelect!();
    await tester.pumpAndSettle();
    expect(source.member, true);
    expect(hasIcon(tester, Icons.bookmark_added), true);
  });

  testWidgets('A20 no download button on Apple TV', (tester) async {
    await mount(tester, fixture());
    expect(hasIcon(tester, Icons.download), true);
    TvDetectionService.debugSetAppleTVOverride(true);
    addTearDown(() => TvDetectionService.debugSetAppleTVOverride(null));
    await mount(tester, fixture());
    expect(hasIcon(tester, Icons.download), false);
  });

  testWidgets('A7 More wraps Plezy MediaContextMenu for the movie', (tester) async {
    final m = await mount(tester, fixture());
    final more = find.ancestor(
      of: find.byWidgetPredicate((w) => w is TvIconButton && w.caption == TvStrings.moreActions),
      matching: find.byType(MediaContextMenu),
    );
    expect((tester.widget<MediaContextMenu>(more).item as MediaItem).id, m.controller.movie.id);
  });

  testWidgets('A9 movie without cast, extras and related has no lower rows', (tester) async {
    await mount(tester, fixture());
    expect(find.byType(TvHorizontalRow), findsNothing);
  });

  Future<Mounted> withRows(WidgetTester tester, {bool reduced = false}) {
    final client = fixture(
      movie: movieItem().copyWith(
        roles: [const MediaRole(id: 'actor', tag: 'Actor', role: 'Hero')],
        studio: 'Legendary Pictures',
        summary: 'Plot',
        genres: ['Drama'],
      ),
    );
    client.extras = [
      client.show.copyWith(id: 'trailer', kind: MediaKind.clip, raw: {'ExtraType': 'Trailer'}),
    ];
    client.relatedHubs = [
      MediaHub(
        id: 'similar',
        title: 'Similar',
        type: 'movie',
        items: [movieItem(id: 'other')],
      ),
    ];
    return mount(tester, client, reduced: reduced);
  }

  testWidgets('A8 Down from Trailer reaches cast, collapses header; Up returns to Trailer', (tester) async {
    final m = await withRows(tester);
    expect(find.byType(TvHorizontalRow), findsNWidgets(3));
    while (focusedIcon() != Icons.theaters) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
    }
    expect(find.byKey(const ValueKey('movie-compact-header')), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.pump();
    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable).first);
    final midway = scrollable.position.pixels;
    await tester.pumpAndSettle();
    final cast = tester.widgetList<TvFocusable>(find.byType(TvFocusable)).firstWhere((w) => w.semanticLabel == 'Actor');
    expect(cast.focusNode!.hasFocus, true);
    expect(scrollable.position.pixels, greaterThan(midway), reason: 'scroll is animated');
    expect(find.byKey(const ValueKey('movie-compact-header')), findsOneWidget);
    final box = cast.focusNode!.context!.findRenderObject()! as RenderBox;
    expect(box.localToGlobal(Offset(0, box.size.height)).dy, lessThanOrEqualTo(1080));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    final tech = tester.getRect(find.byKey(const ValueKey('movie-tech-info')));
    expect(tech.bottom, lessThanOrEqualTo(1080), reason: 'last row reveals the tech block');
    expect(find.text('Legendary Pictures'), findsOneWidget);
    String? row() =>
        FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<TvHorizontalRow>()?.title;
    expect(row(), 'Similar');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(row(), t.discover.extras);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(row(), t.discover.cast);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(focusedIcon(), Icons.theaters);
    expect(scrollable.position.pixels, 0);
    expect(find.byKey(const ValueKey('movie-compact-header')), findsNothing);
    expect(m.controller.movie.id, 'm');
  });

  testWidgets('R8 reduced devices jump without animation', (tester) async {
    await withRows(tester, reduced: true);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.pump();
    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable).first);
    final jumped = scrollable.position.pixels;
    expect(jumped, greaterThan(0));
    await tester.pumpAndSettle();
    expect(scrollable.position.pixels, jumped);
  });

  Future<Future<bool?> Function()> pushed(
    WidgetTester tester,
    Widget Function() screen, {
    String label = 'Open',
  }) async {
    bool? result;
    var done = false;
    await pumpTvWidget(
      tester,
      Builder(
        builder: (context) => TextButton(
          child: Text(label),
          onPressed: () async {
            result = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => screen()));
            done = true;
          },
        ),
      ),
    );
    return () async => done ? result : null;
  }

  TvMovieController controllerFor(FakeShowClient client, {Stream<DeletionEvent>? deletions}) {
    final c = TvMovieController(
      client: client,
      metadata: client.show,
      versionPreference: (_) async => null,
      watchEvents: const Stream.empty(),
      deletionEvents: deletions,
    );
    addTearDown(c.dispose);
    return c;
  }

  testWidgets('A6 Watched toggles state and buttons; Back pops with true', (tester) async {
    final client = fixture();
    final c = controllerFor(client);
    final result = await pushed(
      tester,
      () => TvMovieScreen(
        metadata: client.show,
        controller: c,
        markWatched: (movie, watched) async {
          client.show = client.show.withWatchedFlag(watched);
          return WatchMarkOutcome.marked;
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    iconButtons(tester).firstWhere((b) => b.icon == Icons.check).onSelect!();
    await tester.pumpAndSettle();
    expect(primary(tester).label, 'Rewatch');
    expect(hasIcon(tester, Icons.remove_done), true);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(TvMovieScreen), findsNothing);
    expect(await result(), true);
  });

  testWidgets('A18 stacked movie screens pop one at a time with their own results', (tester) async {
    final first = fixture();
    final second = fixture(movie: movieItem(id: 'second'));
    final c1 = controllerFor(first), c2 = controllerFor(second);
    await pushed(
      tester,
      () => TvMovieScreen(
        metadata: first.show,
        controller: c1,
        play: (context, _, _) async {
          final changed = await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) => TvMovieScreen(metadata: second.show, controller: c2),
            ),
          );
          if (changed == true) c1.watchStateChanged = true;
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Movie second'), findsOneWidget);
    c2.watchStateChanged = true;
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Movie m'), findsOneWidget);
    expect(c1.watchStateChanged, true);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(TvMovieScreen), findsNothing);
  });

  testWidgets('A10 deletion from server closes the screen; download-only deletion does not', (tester) async {
    final client = fixture();
    final deletions = StreamController<DeletionEvent>.broadcast();
    addTearDown(deletions.close);
    final c = controllerFor(client, deletions: deletions.stream);
    await pushed(tester, () => TvMovieScreen(metadata: client.show, controller: c));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    deletions.add(
      DeletionEvent(
        itemId: 'm',
        serverId: ServerId('server'),
        parentChain: [],
        mediaType: 'movie',
        isDownloadOnly: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TvMovieScreen), findsOneWidget);
    deletions.add(DeletionEvent(itemId: 'm', serverId: ServerId('server'), parentChain: [], mediaType: 'movie'));
    await tester.pumpAndSettle();
    expect(find.byType(TvMovieScreen), findsNothing);
    expect(tester.takeException(), null);
  });

  testWidgets('A17 missing movie closes a pushed screen', (tester) async {
    final client = fixture()..onFetch = () async => (item: null, onDeckEpisode: null);
    final c = controllerFor(client);
    await pushed(tester, () => TvMovieScreen(metadata: client.show, controller: c));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byType(TvMovieScreen), findsNothing);
  });

  testWidgets('A17 missing movie as the first route shows unavailable state', (tester) async {
    final client = fixture()..onFetch = () async => (item: null, onDeckEpisode: null);
    await mount(tester, client);
    expect(find.text(TvStrings.movieUnavailable), findsOneWidget);
    expect(find.byType(TvButton), findsNothing);
  });

  testWidgets('R9/R10 skeleton until metadata; failure keeps passed data', (tester) async {
    final pending = Completer<({MediaItem? item, MediaItem? onDeckEpisode})>();
    final client = fixture()..onFetch = () => pending.future;
    final c = TvMovieController(
      client: client,
      metadata: client.show,
      versionPreference: (_) async => null,
      watchEvents: const Stream.empty(),
    );
    addTearDown(c.dispose);
    await pumpTvWidget(tester, TvMovieScreen(metadata: client.show, controller: c));
    await tester.pump();
    expect(find.byKey(const ValueKey('movie-rows-skeleton')), findsOneWidget);
    expect(find.text('Movie m'), findsOneWidget);
    pending.completeError(StateError('offline'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('movie-rows-skeleton')), findsNothing);
    expect(find.text('Movie m'), findsOneWidget);
    expect(primary(tester).label, 'Watch');
    expect(t.discover.cast, isNotEmpty);
  });
}
