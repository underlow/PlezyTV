import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/focus/input_mode_tracker.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/media/ids.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_server_client.dart';
import 'package:plezy/models/download_models.dart';
import 'package:plezy/plezytv/tv_ui/tv_ui.dart';
import 'package:plezy/providers/download_provider.dart';
import 'package:plezy/providers/multi_server_provider.dart';
import 'package:plezy/providers/offline_mode_provider.dart';
import 'package:plezy/profiles/active_profile_provider.dart';
import 'package:plezy/services/multi_server_manager.dart';
import 'package:provider/provider.dart';
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
import 'package:plezy/plezytv/tv_ui/movie/tv_movie_logic.dart';
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
import '../show/tv_show_actions_test.dart' show Downloads, Source;
import '../../../test_helpers/multi_server_fixtures.dart';
import '../../../test_helpers/profile_stack.dart';
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

class MovieDownloads extends Downloads {
  final deleted = <String>[];
  @override
  Future<void> deleteDownload(String globalKey) async => deleted.add(globalKey);
}

/// Serves several movies by id and records server-side watch marks.
class RouteClient extends FakeShowClient {
  final items = <String, MediaItem>{};
  final fetches = <String, int>{};
  @override
  ServerId get serverId => ServerId('server');
  @override
  Future<({MediaItem? item, MediaItem? onDeckEpisode})> fetchItemWithOnDeck(
    String id, {
    void Function(MediaItem)? onItemReady,
  }) async {
    fetches.update(id, (n) => n + 1, ifAbsent: () => 1);
    return (item: items[id], onDeckEpisode: null);
  }

  @override
  Future<List<MediaHub>> fetchRelatedHubs(String id, {int count = 10}) async => id == 'm'
      ? [
          MediaHub(id: 'similar', title: 'Similar', type: 'movie', items: [items['second']!]),
        ]
      : [];

  @override
  Future<void> markWatched(MediaItem item) async => items[item.id] = items[item.id]!.withWatchedFlag(true);
}

class FakeManager implements MultiServerManager {
  bool online = true;
  @override
  bool isClientOnline(ServerId serverId, {String? clientScopeId}) => online;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Servers extends ChangeNotifier implements MultiServerProvider {
  Servers(this.client);
  final MediaServerClient client;
  final manager = FakeManager();
  @override
  MultiServerManager get serverManager => manager;
  @override
  List<String> get onlineServerIds => ['server'];
  @override
  MediaServerClient? getClientForServer(ServerId serverId) => client;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

FakeShowClient fixture({MediaItem? movie}) => FakeShowClient()..show = movie ?? movieItem();

class Mounted {
  Mounted(this.controller, this.client);
  final TvMovieController controller;
  final FakeShowClient client;
  final played = <TvMoviePlayerLaunch>[];
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
  bool? playerResult,
  Size size = const Size(1920, 1080),
  Widget Function(Widget)? wrap,
}) async {
  final c = TvMovieController(
    client: client,
    metadata: client.show,
    versionPreference: (_) async => preference,
    watchEvents: const Stream.empty(),
  );
  addTearDown(c.dispose);
  final m = Mounted(c, client);
  final screen = TvMovieScreen(
    metadata: client.show,
    controller: c,
    hideSpoilers: hideSpoilers,
    serverOnline: wrap == null ? (_) => online : null,
    launchPlayer: (_, movie, launch) async {
      m.played.add(launch);
      await onPlay?.call();
      return playerResult;
    },
    playVersion: (_, _) async => m.versionPlays++,
    markWatched: (movie, watched) async {
      m.marked.add(watched);
      client.show = client.show.withWatchedFlag(watched).copyWith(viewOffsetMs: 0);
      return WatchMarkOutcome.marked;
    },
  );
  await pumpTvWidget(tester, reduced: reduced, size: size, wrap?.call(screen) ?? screen);
  await tester.pumpAndSettle();
  return m;
}

TvButton primary(WidgetTester tester) => tester.widget<TvButton>(find.byType(TvButton).first);
Iterable<TvIconButton> iconButtons(WidgetTester tester) => tester.widgetList<TvIconButton>(find.byType(TvIconButton));
bool hasIcon(WidgetTester tester, IconData icon) => iconButtons(tester).any((b) => b.icon == icon);
IconData? focusedIcon() =>
    FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<TvIconButton>()?.icon;

void main() {
  testWidgets('A1 opens with focus on Watch; OK lets Plezy resolve the start', (tester) async {
    final m = await mount(tester, fixture());
    expect(primary(tester).label, 'Watch');
    expect(primary(tester).focusNode!.hasFocus, true);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(m.played, [(resolveWatchState: true, initialPosition: null)]);
    expect(m.controller.watchStateChanged, false);
  });

  testWidgets('A13 player reporting a watch change sets the route result', (tester) async {
    final m = await mount(tester, fixture(), playerResult: true);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(m.controller.watchStateChanged, true);
  });

  testWidgets('A4 watched movie without progress shows Rewatch', (tester) async {
    final m = await mount(tester, fixture(movie: movieItem(viewCount: 1)));
    expect(primary(tester).label, 'Rewatch');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(m.played, [(resolveWatchState: false, initialPosition: Duration.zero)]);
  });

  testWidgets('A3 progress shows Continue with time left; Plezy resolves the resume point', (tester) async {
    final m = await mount(tester, fixture(movie: movieItem(offset: 9960000 - 4800000)));
    expect(primary(tester).label, 'Continue · ${formatDurationTextual(4800000)} left');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(m.played, [(resolveWatchState: true, initialPosition: null)]);
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

  testWidgets('A7 More opens Plezy MediaContextMenu for the movie', (tester) async {
    final client = fixture();
    final manager = MultiServerManager();
    final servers = testMultiServerProvider(manager);
    final offline = OfflineModeProvider(manager);
    final stack = await ProfileStack.create(withStorage: false);
    final downloads = MovieDownloads();
    addTearDown(() async {
      downloads.dispose();
      await stack.dispose();
      offline.dispose();
      servers.dispose();
      manager.dispose();
    });
    final m = await mount(
      tester,
      client,
      wrap: (child) => MultiProvider(
        providers: [
          ChangeNotifierProvider<MultiServerProvider>.value(value: servers),
          ChangeNotifierProvider<ActiveProfileProvider>.value(value: stack.active),
          ChangeNotifierProvider<OfflineModeProvider>.value(value: offline),
          ChangeNotifierProvider<DownloadProvider>.value(value: downloads),
        ],
        child: child,
      ),
    );
    final more = find.ancestor(
      of: find.byWidgetPredicate((w) => w is TvIconButton && w.caption == TvStrings.moreActions),
      matching: find.byType(MediaContextMenu),
    );
    expect((tester.widget<MediaContextMenu>(more).item as MediaItem).id, m.controller.movie.id);
    while (focusedIcon() != Icons.more_horiz) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
    }
    // Menu-only entry: the screen itself never shows Plezy's "Rate" action.
    expect(find.text(t.mediaMenu.rate), findsNothing, reason: 'menu is closed before OK');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text(t.mediaMenu.rate), findsOneWidget, reason: 'Plezy movie menu is open');
  });

  testWidgets('A5 version segment follows the MultiServerProvider reachability check', (tester) async {
    final client = fixture(movie: movieItem().copyWith(mediaVersions: [_v1080, _v2160]));
    final servers = Servers(client);
    addTearDown(servers.dispose);
    await mount(
      tester,
      client,
      wrap: (child) => ChangeNotifierProvider<MultiServerProvider>.value(value: servers, child: child),
    );
    expect(hasIcon(tester, Icons.video_library), true);
    servers.manager.online = false;
    await mount(
      tester,
      fixture(movie: movieItem().copyWith(mediaVersions: [_v1080, _v2160])),
      wrap: (child) => ChangeNotifierProvider<MultiServerProvider>.value(value: servers, child: child),
    );
    expect(hasIcon(tester, Icons.video_library), false);
  });

  testWidgets('F1 Download on a downloaded movie asks to delete, not to re-queue', (tester) async {
    final client = fixture();
    final downloads = MovieDownloads()
      ..progress = DownloadProgress(globalKey: client.show.globalKey, status: DownloadStatus.completed);
    addTearDown(downloads.dispose);
    await mount(
      tester,
      client,
      wrap: (child) => ChangeNotifierProvider<DownloadProvider>.value(value: downloads, child: child),
    );
    iconButtons(tester).firstWhere((b) => b.icon == Icons.download_done).onSelect!();
    await tester.pumpAndSettle();
    expect(find.text(t.downloads.deleteDownload), findsOneWidget);
    expect(find.text(t.downloads.deleteConfirm(title: client.show.displayTitle)), findsOneWidget);
    await tester.tap(find.text(t.common.delete));
    await tester.pumpAndSettle();
    expect(downloads.deleted, [client.show.globalKey]);
  });

  testWidgets('R8 without rows Down scrolls to the tech block and Up returns', (tester) async {
    final movie = movieItem(edition: 'Part Two').copyWith(
      year: 2024,
      studio: 'Legendary',
      summary: List.filled(80, 'Long plot').join(' '),
      genres: ['Drama'],
      directors: ['Denis'],
      rating: 8.5,
      mediaVersions: [
        MediaVersion(
          id: 'many',
          videoResolution: '2160',
          parts: [
            MediaPart(
              id: 'p',
              streams: [
                for (var i = 0; i < 60; i++)
                  MediaStream(id: 'a$i', kind: MediaStreamKind.audio, language: 'Language number $i'),
              ],
            ),
          ],
        ),
      ],
    );
    await mount(tester, fixture(movie: movie));
    final scrollable = tester.state<ScrollableState>(
      find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first,
    );
    expect(scrollable.position.maxScrollExtent, greaterThan(0));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(scrollable.position.pixels, scrollable.position.maxScrollExtent);
    expect(tester.getRect(find.byKey(const ValueKey('movie-tech-info'))).bottom, lessThanOrEqualTo(1080));
    expect(primary(tester).focusNode!.hasFocus, true);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(scrollable.position.pixels, 0);
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

  testWidgets('A1 R10 player removed under post-play: focus stays on top, card rereads on return', (tester) async {
    final client = fixture(movie: movieItem(offset: 600000));
    final c = controllerFor(client);
    final top = FocusNode();
    addTearDown(top.dispose);
    final result = await pushed(
      tester,
      () => TvMovieScreen(
        metadata: client.show,
        controller: c,
        launchPlayer: (context, movie, launch) async {
          // Post-play covers the card; the removed player returns null.
          unawaited(
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => Scaffold(body: Focus(focusNode: top, autofocus: true, child: const Text('post-play'))),
              ),
            ),
          );
          await tester.pump();
          client.show = client.show.withWatchedFlag(true).copyWith(viewOffsetMs: 0);
          return null;
        },
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(top.hasFocus, true);
    final calls = client.calls.where((call) => call == 'metadata').length;
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    expect(client.calls.where((call) => call == 'metadata').length, greaterThan(calls));
    expect(primary(tester).label, 'Rewatch');
    expect(primary(tester).focusNode!.hasFocus, true);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(await result(), true);
  });

  testWidgets('A18 related movie opens through the real route; its watch change refreshes the first', (tester) async {
    TvUi.enabledForTesting = () => true;
    addTearDown(TvUi.resetForTesting);
    final client = RouteClient()
      ..items['m'] = movieItem()
      ..items['second'] = movieItem(id: 'second');
    final servers = Servers(client);
    addTearDown(servers.dispose);
    final pushedRoutes = <Route<dynamic>>[];
    await pumpTvWidget(tester, const SizedBox.shrink());
    // Provider above the navigator so every pushed route resolves the client.
    await tester.pumpWidget(
      InputModeTracker(
        child: ChangeNotifierProvider<MultiServerProvider>.value(
          value: servers,
          child: MaterialApp(
            navigatorObservers: [_Observer(pushedRoutes)],
            home: Builder(
              builder: (context) => TextButton(
                child: const Text('Open'),
                onPressed: () => Navigator.of(context).push(TvUi.showDetailRoute(metadata: client.items['m']!)!),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(client.fetches['m'], 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Movie second'), findsOneWidget);
    final secondRoute = pushedRoutes.last;
    expect(tester.widget<TvMovieScreen>(find.byType(TvMovieScreen)).metadata.id, 'second');
    while (focusedIcon() != Icons.check) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(client.items['second']!.isWatched, true);
    expect(hasIcon(tester, Icons.remove_done), true);
    final secondResult = secondRoute.popped;
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Movie m'), findsOneWidget);
    expect(await secondResult, true);
    expect(client.fetches['m'], 2, reason: 'first screen refreshed on a true result');
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

  testWidgets('A17 missing movie as the first route shows unavailable state; Back goes to the system', (tester) async {
    final client = fixture()..onFetch = () async => (item: null, onDeckEpisode: null);
    await mount(tester, client);
    expect(find.text(TvStrings.movieUnavailable), findsOneWidget);
    expect(find.byType(TvButton), findsNothing);
    final route = ModalRoute.of(tester.element(find.text(TvStrings.movieUnavailable)))!;
    expect(route.popDisposition, RoutePopDisposition.bubble);
    final handled = await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(handled, false);
    expect(find.text(TvStrings.movieUnavailable), findsOneWidget);
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
  });
}

class _Observer extends NavigatorObserver {
  _Observer(this.pushed);
  final List<Route<dynamic>> pushed;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => pushed.add(route);
}
