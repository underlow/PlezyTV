import 'dart:async';
import 'package:plezy/plezytv/tv_ui/tv_tinted_background.dart';
import 'package:plezy/utils/deletion_notifier.dart';
import 'package:plezy/media/ids.dart';
import 'package:plezy/widgets/media_context_menu.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_hub.dart';
import 'package:plezy/media/media_role.dart';
import 'package:plezy/plezytv/tv_ui/tv_focusable.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_horizontal_row.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/library_query.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_button.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_cards.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_hero.dart';
import 'package:plezy/plezytv/tv_ui/components/tv_tabs.dart';
import 'package:plezy/plezytv/tv_ui/show/tv_show_controller.dart';
import 'package:plezy/plezytv/tv_ui/show/tv_show_screen.dart';
import '../tv_theme_test_helper.dart';
import 'fake_media_server_client.dart';

MediaItem media(String id, MediaKind kind, {int? number, int? watched, int? offset}) => MediaItem(
  id: id,
  backend: MediaBackend.jellyfin,
  kind: kind,
  title: id,
  serverId: 'server',
  index: number,
  durationMs: 3600000,
).copyWith(parentIndex: 1, viewCount: watched, viewOffsetMs: offset);

FakeShowClient fixture() => FakeShowClient()
  ..show = media('The show', MediaKind.show).copyWith(leafCount: 5, viewedLeafCount: 2)
  ..onDeck = media('e3', MediaKind.episode, number: 3, offset: 1500000)
  ..seasons = [
    media('Season 1', MediaKind.season, number: 1).copyWith(leafCount: 4, viewedLeafCount: 2),
    media('Season 2', MediaKind.season, number: 2).copyWith(leafCount: 1, viewedLeafCount: 0),
  ]
  ..episodes = {
    'Season 1': [
      media('e1', MediaKind.episode, number: 1, watched: 1),
      media('e2', MediaKind.episode, number: 2, watched: 1),
      media('e3', MediaKind.episode, number: 3),
      media('e4', MediaKind.episode, number: 4),
    ],
    'Season 2': [media('second', MediaKind.episode, number: 1)],
  };

Future<TvShowController> mount(
  WidgetTester tester,
  FakeShowClient client, {
  String? seasonId,
  String? episodeId,
  Future<void> Function(BuildContext, MediaItem, bool)? play,
  int pageSize = 50,
}) async {
  final c = TvShowController(client: client, metadata: client.show, pageSize: pageSize);
  addTearDown(c.dispose);
  await pumpTvWidget(
    tester,
    TvShowScreen(
      metadata: client.show,
      controller: c,
      initialSeasonId: seasonId,
      initialEpisodeId: episodeId,
      playEpisode: play,
    ),
  );
  await tester.pumpAndSettle();
  return c;
}

TvTabs tabs(WidgetTester tester) => tester.widget<TvTabs>(find.byType(TvTabs));
String focusedEpisode(WidgetTester tester) =>
    tester.widgetList<TvEpisode>(find.byType(TvEpisode)).firstWhere((e) => e.focusNode!.hasFocus).item.id;

void main() {
  testWidgets('R9 multiple seasons use ordinary posters and raw season titles', (tester) async {
    final client = fixture();
    client.seasons[0] = client.seasons[0].copyWith(title: 'The show', parentTitle: 'The show');
    client.seasons[1] = client.seasons[1].copyWith(title: 'Spooks', parentTitle: 'The show');
    await mount(tester, client);
    expect(tabs(tester).tabs.map((tab) => tab.label), ['Show', 'Season 1', 'Spooks']);
    final posters = tester.widgetList<TvPoster>(find.byType(TvPoster)).toList();
    expect(posters.map((poster) => poster.title), ['Season 1', 'Spooks']);
    for (final poster in posters) {
      expect(poster.size.dimensions, const Size(216, 324));
    }
  });

  testWidgets('R9 single season shares episode rail and playback, keeps season tab and S22 navigation', (tester) async {
    final client = fixture();
    client.seasons = [client.seasons.first.copyWith(title: 'The show', index: 6)];
    client.episodes[client.show.id] = client.episodes['Season 1']!;
    client.show = client.show.copyWith(
      roles: [const MediaRole(id: '1', tag: 'Actor')],
    );
    final played = <String>[];
    await mount(
      tester,
      client,
      play: (_, episode, _) async {
        played.add(episode.id);
      },
    );
    expect(tabs(tester).tabs.map((tab) => tab.label), ['Show', 'Season 6']);
    expect(find.byType(TvPoster), findsNothing);
    final showItems = tester.widgetList<TvEpisode>(find.byType(TvEpisode)).map((card) => card.item.id).toList();
    expect(showItems, ['e1', 'e2', 'e3', 'e4']);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(focusedEpisode(tester), 'e1');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus!.context!.findAncestorWidgetOfExactType<TvHorizontalRow>()!.title,
      'Cast',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(played, ['e1']);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus!.debugLabel, 'Show primary');
    tabs(tester).onSelected(1);
    await tester.pumpAndSettle();
    expect(tester.widgetList<TvEpisode>(find.byType(TvEpisode)).map((card) => card.item.id), showItems);
    expect(tester.takeException(), isNull);
  });

  testWidgets('B1 season header uses episode title rather than series title', (tester) async {
    final client = fixture();
    client.episodes['Season 1']![2] = client.episodes['Season 1']![2].copyWith(
      title: 'Daddy Issues',
      grandparentTitle: 'Slow Horses',
    );
    await mount(tester, client, seasonId: 'Season 1', episodeId: 'e3');
    expect(find.text('S1 E3 · Daddy Issues'), findsNWidgets(2));
    expect(find.text('S1 E3 · The show'), findsNothing);
  });

  for (final flattened in [false, true]) {
    for (final cast in [false, true]) {
      testWidgets('B2 overview row navigation flattened=$flattened cast=$cast', (tester) async {
        final client = fixture();
        if (flattened) {
          client.seasons = [client.seasons.first];
          client.episodes[client.show.id] = client.episodes['Season 1']!;
        }
        if (cast) {
          client.show = client.show.copyWith(
            roles: [const MediaRole(id: 'actor', tag: 'Actor')],
          );
        }
        client.extras = [media('Extra', MediaKind.clip)];
        client.relatedHubs = [
          MediaHub(id: 'similar', title: 'Similar', type: 'show', items: [client.show]),
        ];
        await mount(tester, client);
        final rows = tester.stateList<TvHorizontalRowState>(find.byType(TvHorizontalRow)).toList();
        Future<void> key(LogicalKeyboardKey key) async {
          await tester.sendKeyEvent(key);
          await tester.pumpAndSettle();
        }

        final page = tester
            .widgetList<SingleChildScrollView>(find.byType(SingleChildScrollView))
            .firstWhere((view) => view.controller != null)
            .controller!;
        expect(page.offset, 0);
        await key(LogicalKeyboardKey.arrowRight);
        expect(FocusManager.instance.primaryFocus!.debugLabel, isNot('Show primary'));
        expect(page.offset, 0, reason: 'Moving between actions must retain the show header');
        await key(LogicalKeyboardKey.arrowLeft);
        expect(FocusManager.instance.primaryFocus!.debugLabel, 'Show primary');

        void focused(TvHorizontalRowState row) {
          expect(row.focusInside.value, true);
          final box = FocusManager.instance.primaryFocus!.context!.findRenderObject()! as RenderBox;
          expect(box.localToGlobal(Offset.zero).dy, greaterThanOrEqualTo(0));
          expect(box.localToGlobal(Offset(0, box.size.height)).dy, lessThanOrEqualTo(1080));
        }

        for (final row in rows) {
          await key(LogicalKeyboardKey.arrowDown);
          focused(row);
        }
        await key(LogicalKeyboardKey.arrowDown);
        focused(rows.last);
        for (final row in rows.reversed.skip(1)) {
          await key(LogicalKeyboardKey.arrowUp);
          focused(row);
        }
        await key(LogicalKeyboardKey.arrowUp);
        expect(FocusManager.instance.primaryFocus!.debugLabel, 'Show primary');
        expect(page.offset, 0, reason: 'Returning from the first lower row must restore the show header');
        await key(LogicalKeyboardKey.arrowUp);
        expect(FocusManager.instance.primaryFocus!.context!.findAncestorWidgetOfExactType<TvTabs>(), isNotNull);
      });
    }
  }

  testWidgets('season refresh remains coherent through hero timer and rebuild', (tester) async {
    final client = fixture();
    client.episodes['Season 2']!.add(media('third', MediaKind.episode, number: 2));
    final c = await mount(tester, client, seasonId: 'Season 2');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    client.seasons = [client.seasons.last, client.seasons.first];
    final pending = Completer<LibraryPage<MediaItem>>();
    client.onPage = (key, start, size) => pending.future;
    final refresh = c.refresh();
    await tester.pump(const Duration(milliseconds: 400));
    expect(c.seasons.first.id, 'Season 1');
    expect(focusedEpisode(tester), 'third');
    expect(tester.takeException(), null);
    pending.complete(LibraryPage(items: client.episodes['Season 2']!, totalCount: 2));
    await refresh;
    await tester.pumpAndSettle();
    expect(tabs(tester).selectedIndex, 1);
    expect(focusedEpisode(tester), 'third');
  });

  testWidgets('flattening change retains old row until refreshed cache is ready', (tester) async {
    final client = fixture();
    final c = await mount(tester, client, seasonId: 'Season 2');
    client.seasons = [client.seasons.first];
    final pending = Completer<LibraryPage<MediaItem>>();
    client.onPage = (_, _, _) => pending.future;
    final refresh = c.refresh();
    await tester.pump(const Duration(milliseconds: 400));
    expect(c.flattened, false);
    expect(focusedEpisode(tester), 'second');
    expect(tester.takeException(), null);
    pending.complete(LibraryPage(items: client.episodes['Season 1']!, totalCount: 4));
    await refresh;
    await tester.pumpAndSettle();
    expect(c.flattened, true);
    expect(tabs(tester).selectedIndex, 0);
    expect(tester.takeException(), null);
  });

  testWidgets('refresh under dialog restores deleted episode by its old index', (tester) async {
    final client = fixture();
    final c = await mount(tester, client, seasonId: 'Season 1', episodeId: 'e3');
    final context = tester.element(find.byType(TvShowScreen));
    unawaited(
      showDialog<void>(
        context: context,
        builder: (_) => const AlertDialog(content: Text('Confirm')),
      ),
    );
    await tester.pumpAndSettle();
    client.episodes['Season 1']!.removeWhere((e) => e.id == 'e3');
    await c.refresh();
    await tester.pumpAndSettle();
    expect(find.text('Confirm'), findsOneWidget);
    Navigator.of(context).pop();
    await tester.pumpAndSettle();
    expect(focusedEpisode(tester), 'e4');
    expect(tester.takeException(), null);
  });

  testWidgets('deleted remembered episode uses adjacent loaded item without scanning season', (tester) async {
    final client = fixture();
    client.episodes['Season 1'] = [for (var i = 0; i < 100; i++) media('ep$i', MediaKind.episode, number: i + 1)];
    final c = await mount(tester, client, seasonId: 'Season 1', episodeId: 'ep2', pageSize: 10);
    client.episodes['Season 1']!.removeAt(2);
    client.calls.clear();
    await c.refresh();
    await tester.pumpAndSettle();
    expect(focusedEpisode(tester), 'ep3');
    expect(client.calls.where((call) => call.startsWith('page:')), ['page:Season 1:0']);
  });

  testWidgets('focus near row end during refresh retries paging after replacement', (tester) async {
    final client = fixture();
    client.episodes['Season 1'] = [for (var i = 0; i < 30; i++) media('ep$i', MediaKind.episode, number: i + 1)];
    final c = await mount(tester, client, seasonId: 'Season 1', episodeId: 'ep3', pageSize: 10);
    final pending = Completer<LibraryPage<MediaItem>>();
    client.onPage = (key, start, size) => pending.future;
    final refresh = c.refresh();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(focusedEpisode(tester), 'ep5');
    client.onPage = null;
    pending.complete(LibraryPage(items: client.episodes['Season 1']!.take(10).toList(), totalCount: 30));
    await refresh;
    await tester.pumpAndSettle();
    expect(c.episodesFor('Season 1'), hasLength(20));
    expect(focusedEpisode(tester), 'ep5');
  });

  testWidgets('menu and deletion refresh preserve focused episode while replacement is pending', (tester) async {
    final client = fixture();
    final c = await mount(tester, client, seasonId: 'Season 1', episodeId: 'e3');
    for (final deletion in [false, true]) {
      final pending = Completer<LibraryPage<MediaItem>>();
      client.onPage = (_, _, _) => pending.future;
      if (deletion) {
        DeletionNotifier().notify(
          DeletionEvent(
            itemId: 'other',
            serverId: ServerId('server'),
            parentChain: [client.show.id],
            mediaType: 'episode',
          ),
        );
      } else {
        final menu = tester
            .widgetList<MediaContextMenu>(find.byType(MediaContextMenu))
            .firstWhere((m) => (m.item as MediaItem).id == 'e3');
        menu.onRefresh!(menu.item as MediaItem);
      }
      await tester.pump();
      expect(c.loading, true);
      expect(focusedEpisode(tester), 'e3');
      expect(c.episodesFor('Season 1'), hasLength(4));
      pending.complete(LibraryPage(items: client.episodes['Season 1']!, totalCount: 4));
      await tester.pumpAndSettle();
      expect(focusedEpisode(tester), 'e3');
      client.onPage = null;
    }
  });

  testWidgets('refresh remaps selected season by id and falls back when removed', (tester) async {
    final client = fixture();
    client.seasons.add(media('Season 3', MediaKind.season, number: 3));
    final c = await mount(tester, client, seasonId: 'Season 2');
    client.seasons = [client.seasons[1], client.seasons.first];
    await c.refresh();
    await tester.pumpAndSettle();
    expect(tabs(tester).selectedIndex, 1);
    expect(focusedEpisode(tester), 'second');
    client.seasons = [client.seasons.last, media('Season 3', MediaKind.season, number: 3)];
    await c.refresh();
    await tester.pumpAndSettle();
    expect(tabs(tester).selectedIndex, 0);
    expect(tester.takeException(), null);
  });

  testWidgets('refresh failure shows feedback and retains episodes and focus', (tester) async {
    final client = fixture();
    final c = await mount(tester, client, seasonId: 'Season 1', episodeId: 'e3');
    client.onFetch = () => Future.error(StateError('offline'));
    await c.refresh();
    await tester.pump();
    await tester.pump();
    expect(find.text('Unable to refresh. Check your connection.'), findsOneWidget);
    expect(focusedEpisode(tester), 'e3');
    expect(c.episodesFor('Season 1'), hasLength(4));
    await tester.pumpAndSettle();
  });

  testWidgets('episode backdrop waits for focus to settle with the hero', (tester) async {
    await mount(tester, fixture(), seasonId: 'Season 1', episodeId: 'e3');
    String background() => tester.widget<TvTintedBackground>(find.byType(TvTintedBackground)).source.item.id;
    expect(background(), 'e3');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(focusedEpisode(tester), 'e4');
    await tester.pump(const Duration(milliseconds: 299));
    expect(background(), 'e3');
    await tester.pump(const Duration(milliseconds: 1));
    expect(background(), 'e4');
    await tester.pumpAndSettle();
  });

  testWidgets('show deletion removes its own route while leaving an open dialog', (tester) async {
    final client = fixture();
    final c = TvShowController(client: client, metadata: client.show);
    addTearDown(c.dispose);
    await pumpTvWidget(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => TvShowScreen(metadata: client.show, controller: c),
            ),
          ),
          child: const Text('Open show'),
        ),
      ),
    );
    await tester.tap(find.text('Open show'));
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(TvShowScreen));
    unawaited(
      showDialog<void>(
        context: context,
        builder: (_) => const AlertDialog(content: Text('Dialog stays')),
      ),
    );
    await tester.pumpAndSettle();
    DeletionNotifier().notify(
      DeletionEvent(itemId: client.show.id, serverId: ServerId('server'), parentChain: [], mediaType: 'show'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Dialog stays'), findsOneWidget);
    expect(find.byType(TvShowScreen), findsNothing);
    expect(tester.takeException(), null);
  });

  testWidgets('A3 primary resumes on-deck with remaining time and initial focus', (tester) async {
    MediaItem? played;
    bool? restarted;
    await mount(
      tester,
      fixture(),
      play: (_, e, restart) async {
        played = e;
        restarted = restart;
      },
    );
    final button = tester.widget<TvButton>(find.byType(TvButton).first);
    expect(button.label, contains('Continue S1 E3'));
    expect(button.label, contains('35'));
    expect(button.focusNode!.hasFocus, true);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(played!.id, 'e3');
    expect(restarted, false);
  });

  testWidgets('A6 season poster enters at first unwatched; Up and Down remember episode', (tester) async {
    await mount(tester, fixture());
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(tabs(tester).selectedIndex, 1);
    expect(focusedEpisode(tester), 'e3');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(focusedEpisode(tester), 'e4');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(focusedEpisode(tester), 'e4');
  });

  testWidgets('A7 tabs debounce content for 300ms; A9 Back returns to main action', (tester) async {
    await mount(tester, fixture());
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 299));
    expect(tabs(tester).selectedIndex, 0);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pumpAndSettle();
    expect(tabs(tester).selectedIndex, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(tabs(tester).selectedIndex, 0);
    expect(tester.widget<TvButton>(find.byType(TvButton).first).focusNode!.hasFocus, true);
  });

  testWidgets('A10 explicit episode beyond page one is revealed; A11 playback advances after completion', (
    tester,
  ) async {
    final client = fixture();
    await mount(
      tester,
      client,
      seasonId: 'Season 1',
      episodeId: 'e3',
      pageSize: 1,
      play: (_, episode, restart) async {
        client.episodes['Season 1'] = [
          for (final e in client.episodes['Season 1']!)
            if (e.id == episode.id) e.copyWith(viewCount: 1, viewOffsetMs: 0) else e,
        ];
        client.onDeck = client.episodes['Season 1']!.last;
      },
    );
    expect(tabs(tester).selectedIndex, 1);
    expect(focusedEpisode(tester), 'e3');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(focusedEpisode(tester), 'e4');
    expect(
      tester.widgetList<TvEpisode>(find.byType(TvEpisode)).firstWhere((e) => e.item.id == 'e3').item.isWatched,
      true,
    );
  });

  testWidgets('R9 flattened single season retains named season tab and no season posters', (tester) async {
    final client = fixture()..seasons = [media('Season 1', MediaKind.season, number: 1)];
    client.episodes[client.show.id] = client.episodes['Season 1']!;
    await mount(tester, client);
    expect(tabs(tester).tabs.map((t) => t.label), ['Show', 'Season 1']);
    expect(find.byType(TvPoster), findsNothing);
  });

  testWidgets('H2 static skeleton appears only after 300ms; A14 retry recovers with primary focus', (tester) async {
    final client = fixture();
    final pending = Completer<({MediaItem? item, MediaItem? onDeckEpisode})>();
    client.onFetch = () => pending.future;
    final c = TvShowController(client: client, metadata: client.show);
    addTearDown(c.dispose);
    await pumpTvWidget(tester, TvShowScreen(metadata: client.show, controller: c));
    await tester.pump(const Duration(milliseconds: 299));
    expect(find.byType(TvHeroSkeleton), findsNothing);
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.byType(TvHeroSkeleton), findsOneWidget);
    pending.completeError(StateError('offline'));
    await tester.pumpAndSettle();
    final retry = tester.widget<TvButton>(find.byType(TvButton));
    expect(retry.label, 'Retry');
    expect(retry.focusNode!.hasFocus, true);
    client.onFetch = null;
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(TvTabs), findsOneWidget);
    expect(tester.widget<TvButton>(find.byType(TvButton).first).focusNode!.hasFocus, true);
  });
  testWidgets('A9 second Back pops with watch-state result', (tester) async {
    final client = fixture();
    final c = TvShowController(client: client, metadata: client.show);
    addTearDown(c.dispose);
    bool? result;
    await pumpTvWidget(
      tester,
      Builder(
        builder: (context) => TextButton(
          child: const Text('Open show'),
          onPressed: () async {
            result = await Navigator.of(context).push<bool>(
              MaterialPageRoute(
                builder: (_) => TvShowScreen(metadata: client.show, controller: c, initialSeasonId: 'Season 1'),
              ),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('Open show'));
    await tester.pumpAndSettle();
    c.watchStateChanged = true;
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(tabs(tester).selectedIndex, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(TvShowScreen), findsNothing);
    expect(result, true);
  });

  testWidgets('R10/A21 player removed under post-play: focus stays on top, card rereads on return', (tester) async {
    final client = fixture();
    final c = TvShowController(client: client, metadata: client.show);
    addTearDown(c.dispose);
    final top = FocusNode();
    addTearDown(top.dispose);
    bool? result;
    await pumpTvWidget(
      tester,
      Builder(
        builder: (context) => TextButton(
          child: const Text('Open show'),
          onPressed: () async {
            result = await Navigator.of(context).push<bool>(
              MaterialPageRoute(
                builder: (_) => TvShowScreen(
                  metadata: client.show,
                  controller: c,
                  playEpisode: (context, episode, restart) async {
                    // Post-play covers the card; the removed player returns null.
                    unawaited(
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => Scaffold(
                            body: Focus(focusNode: top, autofocus: true, child: const Text('post-play')),
                          ),
                        ),
                      ),
                    );
                    await tester.pump();
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('Open show'));
    await tester.pumpAndSettle();
    final primary = tester.widget<TvButton>(find.byType(TvButton).first);
    expect(primary.focusNode!.hasFocus, true);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(top.hasFocus, true);
    // Plezy reports progress on exit, after the launcher returned.
    client.onDeck = client.onDeck!.copyWith(viewOffsetMs: 3000000);
    final calls = client.calls.where((call) => call == 'metadata').length;
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    expect(client.calls.where((call) => call == 'metadata').length, greaterThan(calls));
    expect(c.onDeckEpisode!.viewOffsetMs, 3000000);
    expect(tester.widget<TvButton>(find.byType(TvButton).first).focusNode!.hasFocus, true);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(TvShowScreen), findsNothing);
    expect(result, true);
  });

  testWidgets('R10 episode from a season tab under post-play: focus stays on top, season focus on return', (
    tester,
  ) async {
    final client = fixture();
    final top = FocusNode();
    addTearDown(top.dispose);
    final c = await mount(
      tester,
      client,
      seasonId: 'Season 1',
      episodeId: 'e3',
      play: (context, episode, restart) async {
        // Post-play covers the card; the removed player returns null.
        unawaited(
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => Scaffold(
                body: Focus(focusNode: top, autofocus: true, child: const Text('post-play')),
              ),
            ),
          ),
        );
        await tester.pump();
      },
    );
    expect(focusedEpisode(tester), 'e3');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(top.hasFocus, true, reason: 'the covered card does not take focus');
    client.episodes['Season 1'] = [
      for (final e in client.episodes['Season 1']!)
        if (e.id == 'e3') e.copyWith(viewCount: 1, viewOffsetMs: 0) else e,
    ];
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    expect(c.episodesFor('Season 1').firstWhere((e) => e.id == 'e3').isWatched, true, reason: 'reread on return');
    expect(tabs(tester).selectedIndex, 1);
    expect(tester.widgetList<TvEpisode>(find.byType(TvEpisode)).any((e) => e.focusNode!.hasFocus), true);
  });

  testWidgets('Down while season page is pending enters episodes when ready', (tester) async {
    final client = fixture();
    final pending = Completer<LibraryPage<MediaItem>>();
    client.onPage = (key, start, size) async {
      if (key == 'Season 2') return pending.future;
      final items = client.episodes[key]!;
      return LibraryPage(items: items, totalCount: items.length);
    };
    await mount(tester, client);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(tabs(tester).selectedIndex, 2);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    pending.complete(LibraryPage(items: client.episodes['Season 2']!, totalCount: 1));
    await tester.pumpAndSettle();
    expect(focusedEpisode(tester), 'second');
  });

  testWidgets('long season tab strip reveals the focused tab', (tester) async {
    final client = fixture()..seasons = [for (var i = 1; i <= 15; i++) media('Season $i', MediaKind.season, number: i)];
    await mount(tester, client);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    for (var i = 0; i < 15; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
    }
    expect(tabs(tester).selectedIndex, 15);
    final box = FocusManager.instance.primaryFocus!.context!.findRenderObject()! as RenderBox;
    expect(box.localToGlobal(Offset(box.size.width, 0)).dx, lessThanOrEqualTo(1920));
  });
  testWidgets('H6 empty lower rows hidden; flattened Down reveals cast and Up returns to actions', (tester) async {
    final client = fixture()..seasons = [media('Season 1', MediaKind.season, number: 1)];
    final c = await mount(tester, client);
    expect(find.byType(TvHorizontalRow), findsNothing);
    client.show = client.show.copyWith(
      roles: [const MediaRole(id: 'actor', tag: 'Actor', role: 'Character')],
    );
    client.extras = [media('Extra', MediaKind.clip)];
    client.relatedHubs = [
      MediaHub(id: 'similar', title: 'Similar shows', type: 'show', items: [client.show]),
    ];
    await c.refresh();
    await tester.pumpAndSettle();
    expect(find.byType(TvHorizontalRow), findsNWidgets(3));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    final cast = tester.widgetList<TvFocusable>(find.byType(TvFocusable)).firstWhere((w) => w.semanticLabel == 'Actor');
    expect(cast.focusNode!.hasFocus, true);
    final box = cast.focusNode!.context!.findRenderObject()! as RenderBox;
    expect(box.localToGlobal(Offset(0, box.size.height)).dy, lessThanOrEqualTo(1080));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(tabs(tester).selectedIndex, 0);
    expect(FocusManager.instance.primaryFocus!.debugLabel, 'Show primary');
  });
}
